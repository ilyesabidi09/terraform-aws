variable "env" {}
variable "vpc_id" {}
variable "subnet_id" {}
variable "ami_id" {}
variable "docker_image" {}
variable "db_url" {}
variable "db_username" { default = "demo" }
variable "db_password" { default = "demo1234" }
variable "jwk_set_uri" {}
variable "aws_region" { default = "eu-west-1" }
variable "sqs_endpoint" { default = "" }
variable "sqs_queue_api_logs" { default = "" }
variable "sqs_queue_security_alerts" { default = "" }
variable "keycloak_instance_id" { default = "" }

# ─── IAM Role for SQS access ───────────────────────────────
resource "aws_iam_role" "app" {
  name = "ec2-app-role-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "sqs_access" {
  name = "sqs-access-${var.env}"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:*"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "ec2-app-profile-${var.env}"
  role = aws_iam_role.app.name
}

# ─── Security Group ────────────────────────────────────────
resource "aws_security_group" "app" {
  name   = "secgrp-app-${var.env}"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "secgrp-app-${var.env}" }
}

# ─── EC2 with Spring Boot ──────────────────────────────────
resource "aws_instance" "app" {
  ami                         = var.ami_id
  instance_type               = "t2.micro"
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io
    systemctl start docker
    systemctl enable docker
    docker run -d \
      --name spring-secure-api \
      --restart always \
      -e SPRING_DATASOURCE_URL="${var.db_url}" \
      -e SPRING_DATASOURCE_USERNAME="${var.db_username}" \
      -e SPRING_DATASOURCE_PASSWORD="${var.db_password}" \
      -e JWK_SET_URI="${var.jwk_set_uri}" \
      -e AWS_REGION="${var.aws_region}" \
      -e SQS_ENDPOINT="${var.sqs_endpoint}" \
      -e SQS_QUEUE_API_LOGS="${var.sqs_queue_api_logs}" \
      -e SQS_QUEUE_SECURITY_ALERTS="${var.sqs_queue_security_alerts}" \
      -p 8080:8080 \
      ${var.docker_image}
  EOF

  tags = { Name = "ec2-app-${var.env}" }

  lifecycle {
    replace_triggered_by = [terraform_data.keycloak_instance_id]
  }
}

# Sentinel resource — change quand keycloak_instance_id change → force recréation de l'app
resource "terraform_data" "keycloak_instance_id" {
  input = var.keycloak_instance_id
}

output "public_ip" { value = aws_instance.app.public_ip }
output "app_url" { value = "http://${aws_instance.app.public_ip}:8080" }
