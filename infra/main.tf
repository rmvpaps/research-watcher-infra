provider "aws" {
  region = "us-east-2"
  profile = "terraform"
}    


# ==========================================
# 1. FRONTEND: S3 Static Website Hosting
# ==========================================
resource "aws_s3_bucket" "frontend" {
  bucket = "app-researchwatcher-staging-hosting"
}

resource "aws_s3_bucket_website_configuration" "frontend_hosting" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend_public_override" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "allow_public_access" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.allow_access_from_public.json
depends_on = [aws_s3_bucket_public_access_block.frontend_public_override]
}

data "aws_iam_policy_document" "allow_access_from_public" {
  statement {
            principals {
              type        = "AWS"
              identifiers = ["*"]
            }
            actions = [
              "s3:GetObject",
            ]
            resources = [
              "${aws_s3_bucket.frontend.arn}/*",
            ]
        }
    
}


# ==========================================
# 2. BACKEND: S3 environmentFiles
# ==========================================

resource "aws_s3_bucket" "research-watcher-config" {
  bucket = "app-researchwatcher-staging-backendconfig"
}


# ==========================================
# CICD: S3 artifact bucket
# ==========================================

resource "aws_s3_bucket" "pipeline-bucket" {
  bucket = "app-researchwatcher-pipeline-bucket"
}