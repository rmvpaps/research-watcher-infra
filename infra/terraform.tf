terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }

    random = {
      source = "hashicorp/random"
      version = "~> 3.9.0"
    }

    archive = {
      source = "hashicorp/archive"
      version = "~> 2.8.0"
    }
  }

  required_version = ">= 1.2"
}
