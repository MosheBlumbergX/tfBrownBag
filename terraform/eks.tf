# --- EKS ---------------------------------------------------------------------
# The spoke cluster: where your workloads would run. Here it is the "client" end
# of the private path to Confluent Cloud. Nothing stateful, so deliberately small.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  # Public API endpoint so kubectl on this laptop works without a
  # bastion. The data plane stays in private subnets.
  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true

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
