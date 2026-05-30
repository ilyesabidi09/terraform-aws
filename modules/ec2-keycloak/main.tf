variable "env" {}
variable "vpc_id" {}
variable "subnet_id" {}
variable "ami_id" {}
variable "db_host" {}
variable "db_password" { default = "keycloak" }

# ─── Security Group ────────────────────────────────────────
resource "aws_security_group" "keycloak" {
  name   = "secgrp-keycloak-${var.env}"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 9090
    to_port     = 9090
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

  tags = { Name = "secgrp-keycloak-${var.env}" }
}

# ─── EC2 with Keycloak ─────────────────────────────────────
resource "aws_instance" "keycloak" {
  ami                         = var.ami_id
  instance_type               = "t2.micro"
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.keycloak.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io curl jq
    systemctl start docker
    systemctl enable docker
    docker run -d \
      --name keycloak \
      --restart always \
      -e KEYCLOAK_ADMIN=admin \
      -e KEYCLOAK_ADMIN_PASSWORD=admin \
      -e KC_HTTP_PORT=9090 \
      -e KC_HTTP_ENABLED=true \
      -e KC_HOSTNAME_STRICT=false \
      -e KC_HOSTNAME_STRICT_HTTPS=false \
      -e KC_DB=postgres \
      -e KC_DB_URL="jdbc:postgresql://${var.db_host}:5432/keycloak" \
      -e KC_DB_USERNAME=keycloak \
      -e KC_DB_PASSWORD=${var.db_password} \
      -p 9090:9090 \
      quay.io/keycloak/keycloak:24.0 start-dev

    # Wait for Keycloak using HOST curl (curl is on the host, not inside the container)
    echo "Waiting for Keycloak to start..."
    until curl -sf http://localhost:9090/realms/master > /dev/null 2>&1; do
      sleep 5
    done
    sleep 10
    echo "Keycloak is up. Disabling SSL requirement via kcadm..."

    # kcadm.sh runs inside container and connects to container localhost (bypasses ssl_required=EXTERNAL)
    docker exec keycloak /opt/keycloak/bin/kcadm.sh config credentials \
      --server http://localhost:9090 \
      --realm master \
      --user admin \
      --password admin

    docker exec keycloak /opt/keycloak/bin/kcadm.sh update realms/master \
      -s sslRequired=NONE

    echo "Done. SSL requirement disabled on master realm."
  EOF

  tags = { Name = "ec2-keycloak-${var.env}" }
}

output "private_ip" { value = aws_instance.keycloak.private_ip }
output "public_ip" { value = aws_instance.keycloak.public_ip }
output "jwk_set_uri" {
  value = "http://${aws_instance.keycloak.public_ip}:9090/realms/ilyes-realm/protocol/openid-connect/certs"
}
