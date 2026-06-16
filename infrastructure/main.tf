terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket       = "secure-aws-iac-tfstate-2026"
    key          = "infrastructure/terraform.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "secure-aws-iac"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Extra provider for CLoudFront
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "networking" {
  source = "./modules/networking"

  aws_region           = var.aws_region
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "security" {
  source = "./modules/security"

  environment            = var.environment
  aws_region             = var.aws_region
  vpc_id                 = module.networking.vpc_id
  vpc_cidr               = var.vpc_cidr
  private_subnet_ids     = module.networking.private_subnet_ids
  private_route_table_id = module.networking.private_route_table_id
}

module "database" {
  source = "./modules/database"

  environment        = var.environment
  aws_region         = var.aws_region
  private_subnet_ids = module.networking.private_subnet_ids
  rds_sg_id          = module.security.rds_sg_id
}

module "compute" {
  source = "./modules/compute"

  environment               = var.environment
  aws_region                = var.aws_region
  vpc_id                    = module.networking.vpc_id
  private_subnet_ids        = module.networking.private_subnet_ids
  alb_sg_id                 = module.security.alb_sg_id
  ec2_sg_id                 = module.security.ec2_sg_id
  ec2_instance_profile_name = module.security.ec2_instance_profile_name
}

module "cdn" {
  source = "./modules/cdn"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  environment  = var.environment
  alb_arn      = module.compute.alb_arn
  alb_dns_name = module.compute.alb_dns_name
}

data "aws_caller_identity" "current" {}

module "monitoring" {
  source = "./modules/monitoring"

  environment = var.environment
  aws_region  = var.aws_region
  account_id  = data.aws_caller_identity.current.account_id
}