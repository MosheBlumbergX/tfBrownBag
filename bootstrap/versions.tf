terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      owner_email     = var.owner_email
      owner_name      = var.owner_name
      cflt_service    = var.cflt_service
      cflt_managed_by = var.cflt_managed_by
      cflt_managed_id = var.cflt_managed_id
      cflt_keep_until = var.cflt_keep_until
    }
  }
}
