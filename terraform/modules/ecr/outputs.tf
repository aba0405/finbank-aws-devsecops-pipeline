output "repository_url" {
  description = "Full URI to use when tagging/pushing images (e.g. <acct>.dkr.ecr.<region>.amazonaws.com/finbank-digital)."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_name" {
  description = "Repository name."
  value       = aws_ecr_repository.this.name
}

output "repository_arn" {
  description = "Repository ARN (used later for least-privilege IAM policies)."
  value       = aws_ecr_repository.this.arn
}
