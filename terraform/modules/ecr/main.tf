########################################
# ECR repository for the FinBank image
########################################
resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  # Basic scan-on-push is a repo-level setting. We ALSO turn on enhanced
  # scanning at the registry level below -- enhanced (Inspector) supersedes
  # basic, but leaving this here documents intent and is harmless.
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

########################################
# Enhanced scanning (Amazon Inspector)
#
# IMPORTANT: scan *type* is a REGISTRY-level setting, not per-repository.
# Setting scan_type = "ENHANCED" turns on Inspector-powered scanning for
# ECR across this whole account+region. That's why it's a separate resource
# from the repo above. This is the single most-confused point in ECR scanning.
########################################
resource "aws_ecr_registry_scanning_configuration" "this" {
  scan_type = "ENHANCED"

  rule {
    scan_frequency = "SCAN_ON_PUSH"
    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }
}
