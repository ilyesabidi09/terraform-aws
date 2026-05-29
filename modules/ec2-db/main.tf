variable "env"       {}
variable "vpc_id"    {}
variable "subnet_id" {}
variable "ami_id"    {}
variable "db_password" { default = "demo1234" }

# ─── Security Group ────────────────────────────────────────
resource "aws_security_group" "db" {
  name   = "secgrp-db-${var.env}"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "secgrp-db-${var.env}" }
}

# ─── EC2 with PostgreSQL ───────────────────────────────────
resource "aws_instance" "db" {
  ami                    = var.ami_id
  instance_type          = "t2.micro"
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.db.id]

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io
    systemctl start docker
    systemctl enable docker
    docker run -d \
      --name postgres \
      --restart always \
      -e POSTGRES_DB=demo \
      -e POSTGRES_USER=demo \
      -e POSTGRES_PASSWORD=${var.db_password} \
      -p 5432:5432 \
      postgres:16
  EOF

  tags = { Name = "ec2-db-${var.env}" }
}

output "private_ip" { value = aws_instance.db.private_ip }
output "db_url"     { value = "jdbc:postgresql://${aws_instance.db.private_ip}:5432/demo" }
