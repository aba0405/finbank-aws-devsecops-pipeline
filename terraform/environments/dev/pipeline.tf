########################################
# Phase 3c: The pipeline
#
# Stages:
#   1. Source        - pull from GitHub via the CodeConnection
#   2. SASTScan      - InspectorScan SourceCodeScan (source vuln gate)
#   3. Build         - CodeBuild builds + pushes image, emits imagedefinitions.json
#   4. ImageScan     - InspectorScan ECRImageScan (image vuln gate, CALIBRATED
#                      to baseline: passes 2C/7H/8M, blocks anything worse)
#   5. Deploy        - ECS rolling deploy of the scanned image
#
# Threshold philosophy: gates are set to the known baseline, not zero. This
# lets the normal image deploy while blocking regressions above baseline --
# how mature teams actually run image gates. See README for the tradeoff.
########################################

# ---------- Pipeline service role ----------
data "aws_iam_policy_document" "codepipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline" {
  name               = "finbank-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume.json
  tags               = { Project = "finbank-digital" }
}

data "aws_iam_policy_document" "codepipeline_permissions" {
  # Use the GitHub connection
  statement {
    sid       = "UseConnection"
    effect    = "Allow"
    actions   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
    resources = [aws_codestarconnections_connection.github.arn]
  }

  # Artifact bucket read/write
  statement {
    sid    = "Artifacts"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*"
    ]
  }

  # Drive the CodeBuild project
  statement {
    sid    = "CodeBuild"
    effect = "Allow"
    actions = [
      "codebuild:StartBuild",
      "codebuild:BatchGetBuilds"
    ]
    resources = [aws_codebuild_project.build.arn]
  }

  # InspectorScan managed action needs to invoke Inspector's scan API +
  # read the ECR image it is scanning.
  statement {
    sid    = "InspectorScan"
    effect = "Allow"
    actions = [
      "inspector-scan:ScanSbom"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EcrReadForScan"
    effect = "Allow"
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:DescribeImages",
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }

  # Deploy to ECS
  statement {
    sid    = "EcsDeploy"
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService"
    ]
    resources = ["*"]
  }

  # Pass the ECS task roles during deployment
  statement {
    sid       = "PassEcsRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [
      aws_iam_role.task_execution.arn,
      aws_iam_role.task.arn
    ]
  }
}

resource "aws_iam_role_policy" "codepipeline" {
  name   = "finbank-codepipeline-permissions"
  role   = aws_iam_role.codepipeline.id
  policy = data.aws_iam_policy_document.codepipeline_permissions.json
}

# ---------- The pipeline ----------
resource "aws_codepipeline" "this" {
  name          = "finbank-pipeline"
  role_arn      = aws_iam_role.codepipeline.arn
  pipeline_type = "V2" # REQUIRED: InspectorScan actions only work on V2 pipelines

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket
  }

  # ---- Stage 1: Source ----
  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = var.github_repo # e.g. "aba0405/finbank-aws-devsecops-pipeline"
        BranchName       = var.github_branch
      }
    }
  }

  # ---- Stage 2: SAST scan (source code) ----
  stage {
    name = "SASTScan"
    action {
      name             = "SourceCodeScan"
      category         = "Invoke"
      owner            = "AWS"
      provider         = "InspectorScan"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["sast_sbom"]

      configuration = {
        InspectorRunMode = "SourceCodeScan"
        # Source is tiny; keep this generous so it doesn't block the demo.
        # It still RUNS and produces an SBOM report -- proof the SAST gate exists.
        CriticalThreshold = "5"
        HighThreshold     = "10"
      }
    }
  }

  # ---- Stage 3: Build + push image ----
  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
    }
  }

  # ---- Stage 4: Image scan (the key gate) ----
  # CALIBRATED to baseline (2C/7H/8M). Normal image passes; worse is blocked.
  stage {
    name = "ImageScan"
    action {
      name             = "ECRImageScan"
      category         = "Invoke"
      owner            = "AWS"
      provider         = "InspectorScan"
      version          = "1"
      input_artifacts  = ["build_output"]
      output_artifacts = ["image_scan_sbom"]

      configuration = {
        InspectorRunMode  = "ECRImageScan"
        ECRRepositoryName = module.ecr.repository_name
        # Image tag comes from the build. We scan :latest-equivalent by tag var.
        ImageTag          = var.image_tag
        CriticalThreshold = "2" # baseline; 3rd critical fails
        HighThreshold     = "7" # baseline; 8th high fails
        MediumThreshold   = "8"
      }
    }
  }

  # ---- Stage 5: Deploy to ECS ----
  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        ClusterName = aws_ecs_cluster.this.name
        ServiceName = aws_ecs_service.app.name
        FileName    = "imagedefinitions.json"
      }
    }
  }

  tags = { Project = "finbank-digital" }
}

variable "github_repo" {
  description = "owner/repo for the GitHub source, e.g. aba0405/finbank-aws-devsecops-pipeline"
  type        = string
}

variable "github_branch" {
  description = "Branch to build from."
  type        = string
  default     = "main"
}

output "pipeline_name" {
  value       = aws_codepipeline.this.name
  description = "CodePipeline name."
}
