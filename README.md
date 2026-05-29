# Terraform AWS Infrastructure

Infrastructure as Code for `spring-secure-api` — deploys on AWS (or locally with LocalStack).

## Structure

```
terraform-aws/
├── modules/
│   ├── vpc/          # VPC, subnets, internet gateway
│   ├── database/     # RDS PostgreSQL
│   ├── messaging/    # Amazon MQ (ActiveMQ)
│   └── app/          # ECS Fargate (Spring Boot container)
└── environments/
    ├── local/        # Points to LocalStack (free, no AWS needed)
    └── prod/         # Points to real AWS
```

## Test locally with LocalStack

```bash
# 1. Start LocalStack
cd ../infrastructure
docker compose up -d localstack

# 2. Init and apply
cd ../terraform-aws/environments/local
terraform init
terraform plan
terraform apply
```

## Deploy to real AWS

```bash
# Set credentials
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret

cd environments/prod
terraform init
terraform plan
terraform apply
```

## What gets created

| Resource | AWS Service |
|----------|------------|
| Network | VPC + Subnets + IGW |
| Database | RDS PostgreSQL 16 |
| Messaging | Amazon MQ (ActiveMQ 5.18) |
| App | ECS Fargate (Spring Boot) |
| Logs | CloudWatch Log Group |
