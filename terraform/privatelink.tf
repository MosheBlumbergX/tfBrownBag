# --- PrivateLink: the hub's single door into Confluent Cloud -----------------
# Four resources, in this order:
#
#   1. confluent_gateway      an ingress PrivateLink gateway in Confluent Cloud.
#                             Gives us a VPC endpoint *service* name.
#   2. aws_vpc_endpoint       an interface endpoint to that service, in the HUB
#                             VPC, private DNS switched off.
#   3. confluent_access_point Confluent's record of our endpoint. Hands back the
#                             DNS domain its endpoints will be published under.
#   4. aws_route53_zone       a private zone for that domain, pointing the
#                             wildcard at the endpoint, associated with BOTH
#                             VPCs so the spoke resolves it too.
#
# Notice resources from two different providers referring to each other
# directly. Terraform builds the dependency graph from those references: no
# ordering is declared anywhere, it is derived.

resource "confluent_gateway" "ingress" {
  display_name = "${var.name}-ingress"

  environment {
    id = confluent_environment.demo.id
  }

  aws_ingress_private_link_gateway {
    region = var.region
  }
}

resource "aws_security_group" "ccloud_privatelink" {
  name        = "${var.name}-ccloud-privatelink"
  description = "Confluent Cloud PrivateLink endpoint (hub)"
  vpc_id      = module.hub_vpc.vpc_id

  # Reachable from the hub itself and from every spoke across the TGW.
  dynamic "ingress" {
    for_each = [80, 443, 9092]

    content {
      description = "Confluent Cloud port ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [var.hub_vpc_cidr, var.spoke_vpc_cidr]
    }
  }

  egress {
    description = "all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-ccloud-privatelink" }
}

resource "aws_vpc_endpoint" "ccloud" {
  vpc_id            = module.hub_vpc.vpc_id
  service_name      = confluent_gateway.ingress.aws_ingress_private_link_gateway[0].vpc_endpoint_service_name
  vpc_endpoint_type = "Interface"
  subnet_ids        = module.hub_vpc.private_subnets

  security_group_ids = [aws_security_group.ccloud_privatelink.id]

  # Confluent publishes many hostnames under one domain; we point the whole
  # domain at this endpoint ourselves via Route53 below.
  private_dns_enabled = false

  tags = { Name = "${var.name}-ccloud" }
}

resource "confluent_access_point" "hub" {
  display_name = "${var.name}-hub"

  environment {
    id = confluent_environment.demo.id
  }

  gateway {
    id = confluent_gateway.ingress.id
  }

  aws_ingress_private_link_endpoint {
    vpc_endpoint_id = aws_vpc_endpoint.ccloud.id
  }
}

locals {
  # e.g. ap-abc123.us-east-1.aws.accesspoint.confluent.cloud
  ccloud_dns_domain = confluent_access_point.hub.aws_ingress_private_link_endpoint[0].dns_domain

  # Confluent publishes cluster endpoints under the ".glb." variant, which
  # resolves publicly to a CNAME inside the domain above - and our private zone
  # takes it from there.
  ccloud_glb_domain = replace(local.ccloud_dns_domain, ".accesspoint.confluent.cloud", ".accesspoint.glb.confluent.cloud")
}

resource "aws_route53_zone" "ccloud" {
  name    = local.ccloud_dns_domain
  comment = "Confluent Cloud PrivateLink (${var.name})"

  # Associated with both VPCs: the endpoint lives in the hub, the pods that
  # resolve it live in the spoke.
  vpc {
    vpc_id = module.hub_vpc.vpc_id
  }

  vpc {
    vpc_id = module.spoke_vpc.vpc_id
  }
}

resource "aws_route53_record" "ccloud_wildcard" {
  zone_id = aws_route53_zone.ccloud.zone_id
  name    = "*.${local.ccloud_dns_domain}"
  type    = "CNAME"
  ttl     = 60

  # The endpoint's regional DNS name. It resolves to the ENIs in the hub's
  # private subnets; the spoke gets there over the Transit Gateway.
  records = [aws_vpc_endpoint.ccloud.dns_entry[0].dns_name]
}
