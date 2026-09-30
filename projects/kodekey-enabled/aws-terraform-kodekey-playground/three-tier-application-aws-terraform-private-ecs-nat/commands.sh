#!/usr/bin/env bash
set -euo pipefail

export AWS_REGION="us-east-1"
aws configure set region "$AWS_REGION"

export KODEKEY_BASE_URL="paste-the-kodekey-base-url-here"
read -rsp "KodeKey API key: " KODEKEY_API_KEY
echo

mkdir -p "$HOME/code/terraform-3tier"
cd "$HOME/code/terraform-3tier"



docker pull egglou/nova:searxng
docker pull egglou/nova:latest

export DB_PASSWORD="$(openssl rand -hex 24)"
export SEARXNG_SECRET_KEY="$(openssl rand -hex 24)"

aws iam list-roles \
  --query 'Roles[?starts_with(RoleName, `iam_role_`)].RoleName' \
  --output table

terraform fmt -recursive
terraform validate
terraform plan
terraform apply -auto-approve

aws ecs update-service \
  --cluster prod-ecs-cluster \
  --service prod-ecs-service \
  --force-new-deployment

aws ecs wait services-stable \
  --cluster prod-ecs-cluster \
  --services prod-ecs-service

ALB_DNS=$(terraform output -raw alb_dns_name)
curl -I "http://$ALB_DNS"

aws ecs list-tasks \
  --cluster prod-ecs-cluster \
  --service-name prod-ecs-service

aws ecs describe-services \
  --cluster prod-ecs-cluster \
  --services prod-ecs-service \
  --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}'

aws secretsmanager list-secrets \
  --query 'SecretList[?starts_with(Name, `prod/nova/`)].Name' \
  --output table

aws secretsmanager get-secret-value \
  --secret-id prod/nova/database-url \
  --query SecretString \
  --output text | grep 'sslmode=require'

RDS_HOST=$(terraform output -raw rds_endpoint | cut -d: -f1)
getent hosts "$RDS_HOST"

aws logs tail /ecs/prod-nova --since 10m

terraform validate
terraform output -raw alb_dns_name
curl -fsS -o /dev/null -w '%{http_code}\n' "http://$(terraform output -raw alb_dns_name)"
aws ecs describe-services \
  --cluster prod-ecs-cluster \
  --services prod-ecs-service \
  --query 'services[0].runningCount'
aws ecr describe-images --repository-name prod-app-repo --query 'imageDetails[0].imageTags'
aws ecr describe-images --repository-name prod-search-repo --query 'imageDetails[0].imageTags'
