provider "aws" {
}

terraform {
  backend "s3" {
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  state_bucket_name = format("terraform-state-%s", sha1("${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"))
}

# This is state bucket used above
module "state_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "1.17.0"

  bucket = local.state_bucket_name
  acl    = "private"

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  // S3 bucket-level Public Access Block configuration
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}