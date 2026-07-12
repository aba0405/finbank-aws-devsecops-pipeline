########################################
# Phase 3b: CodeBuild project + its service role
#
#  - CodeBuild assumes its OWN role (not your user's). That role needs: pull
#    source from the artifact bucket, push images to ECR, write CloudWatch logs.
#  - privileged_mode = true is REQUIRED to run `docker build` inside CodeBuild
#    (Docker-in-Docker needs the privileged container).
#  - The project only builds+pushes; scanning is separate native pipeline actions.
########################################

# ---- Trust policy: CodeBuild service can assume this role ----
data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "finbank-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
  tags               = { Project = "finbank-digital" }
}

# ---- Scoped permissions for the CodeBuild role ----
data "aws_iam_policy_document" "codebuild_permissions" {
  # CloudWatch logs for the build
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.region}:*:log-group:/aws/codebuild/finbank-*"]
  }

  # Pull source / write artifacts in the pipeline bucket
  statement {
    sid    = "Artifacts"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:GetBucketLocation"
    ]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*"
    ]
  }

  # ECR auth token is account-wide (no per-repo ARN)
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push/pull to the specific repo only
  statement {
    sid    = "EcrPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload"
    ]
    resources = [module.ecr.repository_arn]
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name   = "finbank-codebuild-permissions"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild_permissions.json
}

# ---- The CodeBuild project ----
resource "aws_codebuild_project" "build" {
  name         = "finbank-build"
  description  = "Builds the FinBank container image and pushes to ECR"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true # REQUIRED for docker build

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = "649966626634"
    }
    environment_variable {
      name  = "AWS_REGION"
      value = var.region
    }
    environment_variable {
      name  = "ECR_REPO_URL"
      value = module.ecr.repository_url
    }
    environment_variable {
      name  = "CONTAINER_NAME"
      value = "finbank-app" # must match the ECS task definition
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec/buildspec.yml"
  }

  tags = { Project = "finbank-digital" }
}

output "codebuild_project_name" {
  value       = aws_codebuild_project.build.name
  description = "CodeBuild project name, referenced by the pipeline."
}
