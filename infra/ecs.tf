# ==========================================
# 1. BACKEND: ECS cluster
# ==========================================


# 1. Define the core cluster shell
resource "aws_ecs_cluster" "watcher_cluster" {
  name = "research-watcher-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled" # 
  }
}

# 2. Map the Fargate Capacity Providers to the cluster shell explicitly
resource "aws_ecs_cluster_capacity_providers" "watcher_providers" {
  cluster_name = aws_ecs_cluster.watcher_cluster.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

}

# ==========================================
# 2. BACKEND: ECR repository and image
# ==========================================

# repository for scraper
resource "aws_ecr_repository" "rw_scraper" {
  name                 = "rw-scraper"
  image_tag_mutability = "IMMUTABLE"

}

# repository for processor
resource "aws_ecr_repository" "rw_processor" {
  name                 = "rw-processor"
  image_tag_mutability = "IMMUTABLE"

}



# ==========================================
# 3. BACKEND: SECRETS for api key
# ==========================================

variable "llm_api_key" {
  type        = string
  description = "The secret API key value"
  sensitive   = true
}   


resource "aws_secretsmanager_secret" "api_key_container" {
  name                    = "staging/llm_api_key"
  description             = "staging third-party service API key"
  recovery_window_in_days = 0
}

# 2. Define the sensitive value version inside the container
resource "aws_secretsmanager_secret_version" "api_key_value" {
  secret_id     = aws_secretsmanager_secret.api_key_container.id
  secret_string = jsonencode({
    grok_api_key = var.llm_api_key
  })
}

# ==========================================
# 4. BACKEND: ECS task execution_role
# ==========================================

resource "aws_iam_role_policy" "ecs_execution_policy" {
  name = "rw-ecs-execution-policy"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # A. Let ECS read your logs and authenticate with ECR
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      # B. Let ECS fetch the environment file from S3
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "${aws_s3_bucket.research-watcher-config.arn}",
          "${aws_s3_bucket.research-watcher-config.arn}/*"
        ]
      },
      # C. Let ECS decrypt secrets from Secrets Manager
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.db_secret_metadata.arn,
          aws_secretsmanager_secret.api_key_container.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "rw-scraper-ecs-execution-role"

  # The Trust Policy: Tells AWS who can "wear" this hat.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowECSTasksToAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = "staging"
    Project     = "research-watcher"
  }
}

# ==========================================
# 5. BACKEND: ECS task definitions
# ==========================================
resource "aws_ecs_task_definition" "scraper-task" {
  family                   = "rw-scraper-task"
  network_mode             = "awsvpc"       # Required for Fargate
  requires_compatibilities = ["FARGATE"]    # Declares launch type compatibility
  cpu                      = "256"          # 0.25 vCPU
  memory                   = "512"          # 512 MiB
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  # Define container configurations inside a valid JSON array
  container_definitions = jsonencode([
    {
      name      = "scraper-app"
      image     = "${aws_ecr_repository.rw_scraper.repository_url}:latest"
      essential = true
      
      # Pulling the .env file from S3
      environmentFiles = [
        {
          value = "${aws_s3_bucket.research-watcher-config.arn}/scraper-aws.env"
          type  = "s3"
        }
      ]

      # Pulling individual protected variables from Secrets Manager
      secrets = [
        {
          name      = "DATABASE_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.db_secret_metadata.arn}:password::" # 
        },
        {
          name      = "PROXY_API_KEY"
          valueFrom = "${aws_secretsmanager_secret.api_key_container.arn}:grok_api_key::" 
        }
      ]

      environment = [
        { name = "PYTHONPATH", value = "/app/src" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/awslogs-research-watcher"
          "awslogs-region"        = "us-east-2"
          "awslogs-stream-prefix" = "scraper"
        }
      }
    }
  ])
}


# ==========================================
# 5. BACKEND: Scheduler triggering task
# ==========================================
# scraper for weekly
resource "aws_cloudwatch_event_rule" "weekly_scraper_schedule" {
  name        = "rw-scraper-weekly-noon"
  description = "Triggers the research watcher scraper ECS task every Sunday at noon UTC"
  
  # Cron format: (Minutes Hours Day-of-Month Month Day-of-Week Year)
  # 0 12 * * 1 * means: 00 minutes, 12 hours (Noon), every day of month, every month, Day 1 (Sunday in AWS Cron), every year.
  schedule_expression = "cron(0 12 * * 1 *)"
}

#permisison 

resource "aws_iam_role" "scheduler_execution_role" {
  name = "rw-eventbridge-ecs-trigger-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_ecs_policy" {
  name = "rw-eventbridge-ecs-trigger-policy"
  role = aws_iam_role.scheduler_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask"
        ]
        # Restrict it to running your specific scraper task definition family
        Resource = [
          "${replace(aws_ecs_task_definition.scraper-task.arn, "/:\\d+$/", ":*")}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        # EventBridge needs to pass your ECS execution role to the ECS service agent
        Resource = [
          aws_iam_role.ecs_execution_role.arn
        ]
      }
    ]
  })
}


# scheduler that triggers ecs task
resource "aws_cloudwatch_event_target" "scraper_target" {
  rule      = aws_cloudwatch_event_rule.weekly_scraper_schedule.name
  target_id = "TriggerWeeklyScraperTask"
  arn       = aws_ecs_cluster.watcher_cluster.arn
  role_arn  = aws_iam_role.scheduler_execution_role.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.scraper-task.arn
    launch_type         = "FARGATE"
    platform_version    = "LATEST"

    # Because Fargate requires the awsvpc network mode, 
    # we must explicitly pass the subnet and security group topology targets here
    network_configuration {
      subnets          = [aws_subnet.public_a.id] 
      security_groups  = [aws_security_group.vpc_internal.id]       # 🟢 Reuses your default/app SG
      assign_public_ip = true                                 # Required if running in a public subnet to pull ECR images
    }
  }
}