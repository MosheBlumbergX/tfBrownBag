# --- Networking: hub and spoke ----------------------------------------------
# Two VPCs, joined by a Transit Gateway (tgw.tf):
#
#   spoke VPC  10.42.0.0/16   EKS (the clients)
#        |                    (the only VPC with a NAT gateway)
#       TGW
#        |
#   hub VPC    10.40.0.0/16   the Confluent Cloud PrivateLink endpoint
#                             + the Route53 private zone that resolves it
#
# This is the "centralised PrivateLink" pattern: one endpoint in a shared
# services VPC, every spoke reaches Confluent Cloud through it. Add a second
# spoke later and it costs you one TGW attachment, not another endpoint.
#
# Brownbag topic 2: "Terraform configuration". Note that we never write a
# subnet, route table or NAT gateway by hand: a module does it. A module is
# just a folder of .tf files, here pulled from the public registry and pinned
# to a major version.

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

# --- Hub ---------------------------------------------------------------------

module "hub_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.name}-hub"
  cidr = var.hub_vpc_cidr
  azs  = local.azs

  # Private subnets only: nothing in the hub needs to reach the internet, it
  # only hosts the interface endpoint's ENIs.
  private_subnets = [for i, _ in local.azs : cidrsubnet(var.hub_vpc_cidr, 8, i)]

  enable_nat_gateway = false

  # Required for the Route53 private hosted zone to resolve inside the VPC.
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# --- Spoke -------------------------------------------------------------------

module "spoke_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.name}-spoke"
  cidr = var.spoke_vpc_cidr
  azs  = local.azs

  private_subnets = [for i, _ in local.azs : cidrsubnet(var.spoke_vpc_cidr, 4, i)]
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.spoke_vpc_cidr, 8, 48 + i)]

  # One NAT gateway keeps the demo cheap. The nodes need it to pull
  # container images.
  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags EKS looks for when it places load balancers.
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}
