terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  cloud {
    organization = "alexcrh"

    workspaces {
      tags = ["cicd-enterprise"]
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "cicd-enterprise"
      Environment = local.environment
      ManagedBy   = "terraform"
      Owner       = "alex2020global"
    }
  }
}

locals {
  environment = terraform.workspace

  instance_config = {
    dev     = { instance_type = "t2.micro", instance_count = 1 }
    staging = { instance_type = "t2.micro", instance_count = 1 }
    prod    = { instance_type = "t2.small", instance_count = 2 }
  }

  config = lookup(
    local.instance_config,
    local.environment,
    local.instance_config["dev"]
  )
}

module "ec2" {
  source         = "./modules/ec2"
  environment    = local.environment
  instance_type  = local.config.instance_type
  instance_count = local.config.instance_count
  aws_region     = var.aws_region
}
