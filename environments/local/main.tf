terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  region                      = "eu-west-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2 = "http://localhost:4566"
    iam = "http://localhost:4566"
    sqs = "http://localhost:4566"
  }
}

locals {
  ami_id = "ami-12345678"
}

module "vpc" {
  source = "../../modules/vpc"
  env    = "local"
}

module "sqs" {
  source = "../../modules/sqs"
  env    = "local"
}

module "ec2_db" {
  source    = "../../modules/ec2-db"
  env       = "local"
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.private_subnet_ids[0]
  ami_id    = local.ami_id
}

module "ec2_keycloak" {
  source    = "../../modules/ec2-keycloak"
  env       = "local"
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.public_subnet_ids[0]
  ami_id    = local.ami_id
}

module "ec2_app" {
  source       = "../../modules/ec2-app"
  env          = "local"
  vpc_id       = module.vpc.vpc_id
  subnet_id    = module.vpc.public_subnet_ids[0]
  ami_id       = local.ami_id
  docker_image = "ilyesabidi/spring-secure-api:latest"
  db_url       = module.ec2_db.db_url
  jwk_set_uri  = module.ec2_keycloak.jwk_set_uri
  sqs_endpoint = "http://localhost:4566"
}

output "app_url"         { value = module.ec2_app.app_url }
output "keycloak_url"    { value = "http://${module.ec2_keycloak.public_ip}:9090" }
output "sqs_api_logs"    { value = module.sqs.api_logs_queue_url }
output "sqs_sec_alerts"  { value = module.sqs.security_alerts_queue_url }
