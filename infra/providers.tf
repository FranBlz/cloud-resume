terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive",
      version = "~> 2.7"
    }
  }

  backend "s3" {
    bucket       = "tfstate-976550610911-us-east-1"
    key          = "cloud-resume/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "cloud-resume",
      ManagedBy = "terraform"
    }
  }
}