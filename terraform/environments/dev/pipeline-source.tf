########################################
# Phase 3a: Source connection + pipeline artifact store
#
#  - CodeStar/CodeConnections connection to GitHub. Terraform creates it in
#    PENDING status; you MUST finish the OAuth handshake in the AWS console
#    (Developer Tools > Connections > Update pending connection). This is an
#    auth grant and cannot be automated -- by design.
#  - S3 artifact bucket: every CodePipeline stores stage artifacts (zipped
#    source, build output) in an S3 bucket. We harden it: block all public
#    access, enable versioning, and enforce encryption. A pipeline artifact
#    bucket can hold source code, so treating it as sensitive is correct.
########################################

# ---- GitHub connection (finish auth in the console) ----
resource "aws_codestarconnections_connection" "github" {
  name          = "finbank-github"
  provider_type = "GitHub"

  tags = { Project = "finbank-digital" }
}

# ---- Artifact bucket ----
# Random suffix: S3 bucket names are globally unique. This avoids collisions.
resource "random_id" "artifact_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "finbank-pipeline-artifacts-${random_id.artifact_suffix.hex}"
  force_destroy = true # lets `terraform destroy` empty+delete it on a practice account

  tags = { Project = "finbank-digital" }
}

# Block ALL public access -- this bucket may contain source code.
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy      = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning: recover from accidental overwrites; also an audit trail.
resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption at rest (SSE-S3/AES256).
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

output "github_connection_arn" {
  description = "ARN of the GitHub connection (must be AVAILABLE before the pipeline runs)."
  value       = aws_codestarconnections_connection.github.arn
}

output "artifact_bucket_name" {
  description = "S3 bucket CodePipeline uses for stage artifacts."
  value       = aws_s3_bucket.artifacts.id
}
