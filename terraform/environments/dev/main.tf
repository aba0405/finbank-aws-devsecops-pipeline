terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Bumped from ~> 5.0 in Phase 2: the terraform-aws-modules/vpc v6 module
      # requires provider v6. Provider v6 is backward-compatible with the ECR
      # resources from Phase 1, so this is a safe in-place bump.
      version = "~> 6.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # NOTE: state is local for now (a terraform.tfstate file on your machine).
  # That's fine for a solo practice project. In Phase 2 or the writeup we can
  # discuss an S3 + DynamoDB remote backend as the "what I'd do on a team" note.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "finbank-digital"
      ManagedBy = "terraform"
      Env       = "dev"
    }
  }
}

variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

########################################
# Phase 1: ECR + enhanced scanning
########################################
module "ecr" {
  source          = "../../modules/ecr"
  repository_name = "finbank-digital"
}

output "ecr_repository_url" {
  description = "Push images here."
  value       = module.ecr.repository_url
}
