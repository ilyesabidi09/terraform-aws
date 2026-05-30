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
    apt-get install -y docker.io curl
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

    # Wait for Keycloak (localhost bypasses ssl_required=EXTERNAL)
    echo "Waiting for Keycloak..."
    until curl -sf http://localhost:9090/realms/master > /dev/null 2>&1; do
      sleep 5
    done
    sleep 15
    echo "Keycloak ready. Getting admin token via localhost..."

    # Get admin token — python3 is always available on Ubuntu, no jq needed
    TOKEN=$(curl -s -X POST http://localhost:9090/realms/master/protocol/openid-connect/token \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "client_id=admin-cli&username=admin&password=admin&grant_type=password" \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token','ERROR'))")

    echo "Token: $${TOKEN:0:20}..."

    # Disable ssl_required on master realm via Admin REST API
    curl -s -X PUT http://localhost:9090/admin/realms/master \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"sslRequired":"NONE"}'

    echo "Done. ssl_required set to NONE."
  EOF

  tags = { Name = "ec2-keycloak-${var.env}" }
}

output "private_ip" { value = aws_instance.keycloak.private_ip }
output "public_ip" { value = aws_instance.keycloak.public_ip }
output "jwk_set_uri" {
  value = "http://${aws_instance.keycloak.public_ip}:9090/realms/ilyes-realm/protocol/openid-connect/certs"
}
