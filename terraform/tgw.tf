# --- Transit Gateway ---------------------------------------------------------
# The TGW is the router between the spoke (EKS) and the hub (PrivateLink
# endpoint). Both attachments land in the TGW's default route table and
# propagate their CIDRs into it, so the TGW itself needs no static routes;
# we only have to point each VPC's subnets at the TGW for the other's CIDR.
#
# Worth saying out loud in the session: Confluent Cloud *Enterprise* clusters
# are private-only over PrivateLink (or PNI). A native Confluent Cloud
# "Transit Gateway network" is a Dedicated-cluster feature and a different
# resource set (confluent_network + confluent_transit_gateway_attachment + an
# AWS RAM share). What we build here is the shape most customers actually run:
# their own TGW fabric, with Confluent reached through one PrivateLink hub.

resource "aws_ec2_transit_gateway" "this" {
  description                     = "${var.name} hub/spoke fabric"
  amazon_side_asn                 = 64512
  auto_accept_shared_attachments  = "disable" # both VPCs are in this account
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"

  tags = { Name = var.name }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = module.hub_vpc.vpc_id
  subnet_ids         = module.hub_vpc.private_subnets

  dns_support = "enable"

  tags = { Name = "${var.name}-hub" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = module.spoke_vpc.vpc_id
  subnet_ids         = module.spoke_vpc.private_subnets

  dns_support = "enable"

  tags = { Name = "${var.name}-spoke" }
}

# --- VPC route tables --------------------------------------------------------
# One route per private route table in each VPC, pointing at the other VPC's
# CIDR via the TGW.
#
# Worth a minute in the session, because everyone hits this once:
# `for_each = toset(module.spoke_vpc.private_route_table_ids)` looks obvious
# and fails at plan time with
#
#   The "for_each" set includes values derived from resource attributes that
#   cannot be determined until apply
#
# Route table IDs do not exist until apply, and for_each keys have to be known
# at plan time - they are how Terraform addresses each instance in state.
# The fix is the one the error message suggests: build a map whose KEYS are
# static (the index, known because the AZ list is known at plan time) and
# whose VALUES are the apply-time IDs.

resource "aws_route" "spoke_to_hub" {
  for_each = {
    for i, rt in module.spoke_vpc.private_route_table_ids : tostring(i) => rt
  }

  route_table_id         = each.value
  destination_cidr_block = var.hub_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke]
}

resource "aws_route" "hub_to_spoke" {
  for_each = {
    for i, rt in module.hub_vpc.private_route_table_ids : tostring(i) => rt
  }

  route_table_id         = each.value
  destination_cidr_block = var.spoke_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.hub]
}
