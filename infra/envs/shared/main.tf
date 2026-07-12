# Persistent layer: resources that must survive `make nuke` of an environment.
# Just ECR — images live here so CI pushes work whether or not dev exists.
# Steady-state cost: ~$0.05/month of image storage.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "makanlah-tfstate-022440376627"
    key          = "envs/shared/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = "shared"
      ManagedBy   = "terraform"
    }
  }
}

variable "project" {
  type    = string
  default = "makanlah"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

module "ecr" {
  source = "../../modules/ecr"

  name_prefix  = var.project
  repositories = ["menu-service", "order-service", "notify-worker"]
}

output "repository_urls" {
  value = module.ecr.repository_urls
}
