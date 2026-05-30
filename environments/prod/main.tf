terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket  = "ilyesabidi-terraform-state"
    key     = "prod/terraform.tfstate"
    region  = "eu-west-1"
    encrypt = true
  }
}

provider "aws" {
  region = "eu-west-1"
}

# Latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

module "vpc" {
  source = "../../modules/vpc"
  env    = "prod"
}

module "sqs" {
  source = "../../modules/sqs"
  env    = "prod"
}

module "ec2_db" {
  source      = "../../modules/ec2-db"
  env         = "prod"
  vpc_id      = module.vpc.vpc_id
  subnet_id   = module.vpc.public_subnet_ids[1]
  ami_id      = data.aws_ami.ubuntu.id
  db_password = var.db_password
}

module "ec2_keycloak" {
  source      = "../../modules/ec2-keycloak"
  env         = "prod"
  vpc_id      = module.vpc.vpc_id
  subnet_id   = module.vpc.public_subnet_ids[0]
  ami_id      = data.aws_ami.ubuntu.id
  db_host     = module.ec2_db.private_ip
  db_password = "keycloak"
}

module "ec2_app" {
  source               = "../../modules/ec2-app"
  env                  = "prod"
  vpc_id               = module.vpc.vpc_id
  subnet_id            = module.vpc.public_subnet_ids[0]
  ami_id               = data.aws_ami.ubuntu.id
  docker_image         = "ilyesabidi/spring-secure-api:latest"
  db_url               = module.ec2_db.db_url
  db_password          = var.db_password
  jwk_set_uri          = module.ec2_keycloak.jwk_set_uri
  aws_region           = "eu-west-1"
  keycloak_instance_id = module.ec2_keycloak.instance_id
}

output "app_url" { value = module.ec2_app.app_url }
output "keycloak_url" { value = "http://${module.ec2_keycloak.public_ip}:9090" }
output "pgadmin_url" { value = "http://${module.ec2_db.elastic_ip}:5050" }
