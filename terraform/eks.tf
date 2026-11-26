# --- EKS ---------------------------------------------------------------------
# The spoke cluster: where your workloads would run. Here it is the "client" end
# of the private path to Confluent Cloud. Nothing stateful, so deliberately small.

# Who administers the cluster: the SSO role you run Terraform with on a laptop,
# and the role GitHub Actions assumes (created by ../bootstrap). Both are looked
# up, so no account ID is written in this repo.
data "aws_iam_roles" "sso_admin" {
  name_regex  = "^AWSReservedSSO_${var.eks_admin_sso_permission_set}_"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

data "aws_iam_role" "ci" {
  name = var.ci_role_name
}

locals {
  eks_admin_principals = {
    sso = one(data.aws_iam_roles.sso_admin.arns)
    ci  = data.aws_iam_role.ci.arn
  }
}

# The CI role already holds the old "cluster_creator" entry. Keep it under its new
# name, or Terraform would try to create a second entry for the same principal
# before deleting the first, and EKS would refuse.
moved {
  from = module.eks.aws_eks_access_entry.this["cluster_creator"]
  to   = module.eks.aws_eks_access_entry.this["ci"]
}

moved {
  from = module.eks.aws_eks_access_policy_association.this["cluster_creator_admin"]
  to   = module.eks.aws_eks_access_policy_association.this["ci_admin"]
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  # Public API endpoint so kubectl on this laptop works without a
  # bastion. The data plane stays in private subnets.
  endpoint_public_access = true

  # Cluster admin is granted to named principals, not to "whoever ran the apply".
  # With enable_cluster_creator_admin_permissions the module hands admin (and the
  # KMS key administrator role) to the caller, so the identity that last applied
  # silently locked the other one out: CI took over from the laptop and
  # kubectl returned Unauthorized. Explicit principals make an apply from either
  # place produce the same state.
  enable_cluster_creator_admin_permissions = false

  access_entries = {
    for key, arn in local.eks_admin_principals : key => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  kms_key_administrators = values(local.eks_admin_principals)

  vpc_id     = module.spoke_vpc.vpc_id
  subnet_ids = module.spoke_vpc.private_subnets

  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    aws-ebs-csi-driver = {
      # The provider's default_tags never reach a volume the CSI driver creates
      # on our behalf, so the driver is told to stamp them itself.
      configuration_values = jsonencode({
        controller = { extraVolumeTags = local.tags }
      })
      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs_csi.arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      ami_type       = "AL2023_x86_64_STANDARD"

      min_size     = var.node_count
      max_size     = var.node_count + 1
      desired_size = var.node_count

      disk_size = 50
    }
  }

  # Same story as extraVolumeTags: these get pushed into the launch template so
  # the EC2 instances and their root volumes carry the mandatory tags.
  tags = local.tags
}

# --- IAM for the EBS CSI driver (EKS Pod Identity, no static keys) -----------

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
