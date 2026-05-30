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
    set -e
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

    # ── Attendre que Keycloak soit prêt (localhost bypass ssl_required=EXTERNAL) ──
    echo "[KC] Waiting for Keycloak..."
    until curl -sf http://localhost:9090/realms/master > /dev/null 2>&1; do
      sleep 5
    done
    sleep 15
    echo "[KC] Keycloak is up."

    # ── Helper : récupérer un token admin ──
    get_token() {
      curl -s -X POST http://localhost:9090/realms/master/protocol/openid-connect/token \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=admin-cli&username=admin&password=admin&grant_type=password" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])"
    }

    TOKEN=$(get_token)

    # ── 1. Désactiver ssl_required sur master realm ──
    curl -s -X PUT http://localhost:9090/admin/realms/master \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"sslRequired":"NONE"}'
    echo "[KC] ssl_required disabled on master."

    # ── 2. Créer ilyes-realm ──
    TOKEN=$(get_token)
    curl -s -X POST http://localhost:9090/admin/realms \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"realm":"ilyes-realm","enabled":true,"sslRequired":"NONE"}'
    echo "[KC] ilyes-realm created."

    # ── 3. Créer demo-client ──
    TOKEN=$(get_token)
    curl -s -X POST http://localhost:9090/admin/realms/ilyes-realm/clients \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"clientId":"demo-client","enabled":true,"publicClient":true,"directAccessGrantsEnabled":true,"standardFlowEnabled":true}'
    echo "[KC] demo-client created."

    # ── 4. Créer les rôles ADMIN, DEV, QA ──
    TOKEN=$(get_token)
    for ROLE in ADMIN DEV QA; do
      curl -s -X POST http://localhost:9090/admin/realms/ilyes-realm/roles \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$ROLE\"}"
      echo "[KC] Role $ROLE created."
    done

    # ── 5. Créer les users avec email/firstName/lastName (requis par KC24) ──
    TOKEN=$(get_token)
    create_user() {
      local USERNAME=$1
      local PASSWORD=$2
      local ROLE=$3
      local EMAIL=$4
      local FIRSTNAME=$5
      local LASTNAME=$6

      curl -s -X POST http://localhost:9090/admin/realms/ilyes-realm/users \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$USERNAME\",\"email\":\"$EMAIL\",\"firstName\":\"$FIRSTNAME\",\"lastName\":\"$LASTNAME\",\"enabled\":true,\"emailVerified\":true,\"requiredActions\":[]}"

      USER_ID=$(curl -s "http://localhost:9090/admin/realms/ilyes-realm/users?username=$USERNAME" \
        -H "Authorization: Bearer $TOKEN" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

      curl -s -X PUT "http://localhost:9090/admin/realms/ilyes-realm/users/$USER_ID/reset-password" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"password\",\"value\":\"$PASSWORD\",\"temporary\":false}"

      ROLE_DATA=$(curl -s "http://localhost:9090/admin/realms/ilyes-realm/roles/$ROLE" \
        -H "Authorization: Bearer $TOKEN")

      curl -s -X POST "http://localhost:9090/admin/realms/ilyes-realm/users/$USER_ID/role-mappings/realm" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "[$ROLE_DATA]"

      echo "[KC] User $USERNAME ($ROLE) created."
    }

    create_user alice   alice1234   ADMIN alice@demo.com   Alice   Admin
    create_user bob     bob1234     DEV   bob@demo.com     Bob     Dev
    create_user charlie charlie1234 QA    charlie@demo.com Charlie QA

    echo "[KC] Setup complete."
  EOF

  tags = { Name = "ec2-keycloak-${var.env}" }
}

output "private_ip" { value = aws_instance.keycloak.private_ip }
output "public_ip" { value = aws_instance.keycloak.public_ip }
output "jwk_set_uri" {
  value = "http://${aws_instance.keycloak.public_ip}:9090/realms/ilyes-realm/protocol/openid-connect/certs"
}
