# ==========================================
# BACKEND: CODEBUILD
# ==========================================


# CodeBuild IAM Role
resource "aws_iam_role" "codebuild_role" {
  name = "codebuild-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
    }]
  })
}

# Attach basic execution policies to CodeBuild (Logs, S3, etc.)
resource "aws_iam_role_policy" "codebuild_policy" {
  name = "codebuild-policy"
  role = aws_iam_role.codebuild_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = ["*"]
      },
      {
        Effect  = "Allow"
        Action  = [
                "codebuild:CreateReportGroup",
                "codebuild:CreateReport",
                "codebuild:UpdateReport",
                "codebuild:BatchPutTestCases",
                "codebuild:BatchPutCodeCoverages"
            ]
        Resource = ["*"]
      },
      {
        Effect  = "Allow"
        Action  = [
                "ecr:GetAuthorizationToken",
                "ecr:CompleteLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:InitiateLayerUpload",
                "ecr:BatchCheckLayerAvailability",
                "ecr:PutImage"
            ]
        Resource = [
            aws_ecr_repository.rw_scraper.arn,
            aws_ecr_repository.rw_processor.arn
        ] 
      },
      {
        Effect  = "Allow"
        Action  = [
                "ecs:RunTask",
                "ecs:ListTasks",
                "ecs:RegisterTaskDefinition",
                "ecs:DescribeTaskDefinition",
                "ecs:DescribeTasks",
            ]
        Resource = [
             "${replace(aws_ecs_cluster.watcher_cluster.arn, ":cluster/", ":task/")}/*",
             "${aws_ecs_task_definition.scraper-task.arn}",
             "${aws_ecs_task_definition.processor-task.arn}"
        ] 
      },
      {
        Effect  = "Allow"
        Action  = [ 
                "events:PutTargets",
                "events:DescribeRule"
                ]
        Resource= [
            aws_cloudwatch_event_rule.weekly_scraper_schedule.arn,
            aws_cloudwatch_event_rule.daily_processor_schedule.arn
        ]
      },
       {
        Effect  = "Allow"
        Action  = [ "iam:PassRole"]
        Resource= [
            aws_iam_role.ecs_execution_role.arn,
             aws_iam_role.scheduler_execution_role.arn
        ]
      },
      {
        Effect  = "Allow"
        Action  = ["secretsmanager:GetSecretValue"]
        Resource= [
            aws_secretsmanager_secret.db_secret_metadata.arn,
            aws_secretsmanager_secret.api_key_container.arn
        ]
      }
    ]
  })
}

# build scraper

resource "aws_codebuild_project" "buildscraper" {
  name          = "build_scraper"
  build_timeout = "5"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE" # Must be CODEPIPELINE when used inside a pipeline
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type = "CODEPIPELINE" # CodePipeline will feed the source files here
  }
}



resource "aws_codebuild_project" "buildprocessor" {
  name          = "build_processor"
  build_timeout = "5"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE" # Must be CODEPIPELINE when used inside a pipeline
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type = "CODEPIPELINE" # CodePipeline will feed the source files here
    buildspec = "buildspec_processor.yml" 
  }
  
}


resource "aws_codebuild_project" "buildapi" {
  name          = "build_api"
  build_timeout = "5"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE" # Must be CODEPIPELINE when used inside a pipeline
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type = "CODEPIPELINE" # CodePipeline will feed the source files here
    buildspec = "buildspec_api.yml" 
  }
  
}







# CodePipeline IAM Role
resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
    }]
  })
}


# Attach basic execution policies to codepipeline (Logs, S3, etc.)
resource "aws_iam_role_policy" "codepipelinepolicy" {
  name = "codepipeline-policy"
  role = aws_iam_role.codepipeline_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = [
                    "s3:GetBucketVersioning","s3:GetBucketAcl","s3:GetBucketLocation",
                    "s3:GetObject", "s3:GetObjectVersion", "s3:PutObject","s3:PutObjectAcl"]
        Resource = [
                    aws_s3_bucket.pipeline-bucket.arn,
                    "${aws_s3_bucket.pipeline-bucket.arn}/*"]
      },
      {
        Effect  = "Allow"
        Action  = [
                "codebuild:BatchGetBuilds",
                "codebuild:StartBuild",
                "codebuild:BatchGetBuildBatches",
                "codebuild:StartBuildBatch",
                "codebuild:CreateReportGroup",
                "codebuild:CreateReport",
                "codebuild:UpdateReport",
                "codebuild:BatchPutTestCases",
                "codebuild:BatchPutCodeCoverages"
            ]
        Resource = ["*"]
      },
      {
        Effect  = "Allow"
        Action  = [
                "codeconnections:UseConnection",
                "codestar-connections:UseConnection"
            ]
        Resource = [
            aws_codestarconnections_connection.github.arn
        ] 
      }
      
    ]
  })
}





# 1. Create the CodeStar Connection to GitHub
resource "aws_codestarconnections_connection" "github" {
  name          = "github-connection"
  provider_type = "GitHub"
}

# 2. Update CodePipeline to use the GitHub Connection
resource "aws_codepipeline" "app_pipeline" {
  name     = "app-deployment-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline-bucket.bucket
    type     = "S3"
  }

  # Stage 1: GitHub Source Integration
  stage {
    name = "Source"

    action {
      name             = "GitHub_Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection" # Updated Provider
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = "rmvpaps/vton-research-watcher" # Format: org/repo or user/repo
        BranchName       = "staging"
        
        # Automatically trigger the pipeline on git push
        DetectChanges    = "true" 
      }
    }
  }

  # Stage 2: Build Stage (Stays the same as before)
  stage {
    name = "Build"
    action {
      name             = "BuildScraper"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]

      configuration = {
        ProjectName = aws_codebuild_project.buildscraper.name
      }
    }

    action {
      name             = "BuildProcessor"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]


      configuration = {
        ProjectName = aws_codebuild_project.buildprocessor.name
      }
    }

    action {
      name             = "BuildAPI"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.buildapi.name
      }
    }
  }

  # Stage 3: Deploy Stage (Stays the same as before)
  stage {
    name = "Deploy"
    action {
      name            = "DeployAction"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "Lambda"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        FunctionName = aws_lambda_function.fastapi.id
      }
    }
  }
}