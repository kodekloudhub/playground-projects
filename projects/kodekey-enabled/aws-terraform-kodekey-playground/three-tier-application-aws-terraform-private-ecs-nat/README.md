# Secure Three-Tier AI Application on AWS with Private ECS and NAT Gateway

**Level:** advanced  ·  **Playground:** AWS Terraform | KodeKey Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-terraform-aws)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

```powershell
---
# ─── Metadata (read by the playground for listing & filtering) ───
id: three-tier-application-aws-terraform-private-ecs-nat
title: Secure Three-Tier AI Application on AWS with Private ECS and NAT Gateway
playground: AWS Cloud Sandbox
playground_link: https://kodekloud.com/playgrounds/playground-terraform-aws
difficulty: advanced
estimated_minutes: 120
tags:
  - aws
  - terraform
  - ecs
  - ecr
  - fargate
  - docker
  - security
skills:
  - provisioning AWS networking with Terraform
  - building and publishing Docker images to Amazon ECR
  - deploying multi-container ECS Fargate tasks
  - injecting credentials from AWS Secrets Manager
  - validating ALB, ECS, RDS, and security-group connectivity
prerequisites:
  - Basic Terraform and HCL knowledge
  - Basic AWS CLI and IAM knowledge
  - Basic Docker commands
  - Familiarity with container networking
---

# AWS Three Tier Application with Terraform

## Scenario

Nova is an AI business-validation platform that coordinates several agents, searches the web through SearXNG, and stores application data in PostgreSQL. The previous deployment placed services and credentials on manually configured hosts, creating drift and exposing secrets. You must produce a repeatable AWS deployment with Terraform, container images in ECR, an ECS Fargate task behind an Application Load Balancer, and a private RDS database.

## What you'll build

You will create a two-AZ VPC with public ALB subnets, dedicated private ECS application subnets, private RDS subnets, and a NAT Gateway, ECR repositories, Secrets Manager entries, IAM task roles, an S3 bucket, an ECS cluster, and a two-container Fargate task. You will pull the published SearXNG and application images from Docker Hub, push both to ECR, then validate the public ALB endpoint and private database boundaries.

## Learning objectives

By the end you will be able to:

- Install and use Docker to pull, tag, and push the published images to ECR.
- Provision a multi-AZ AWS network and application stack with Terraform.
- Run an ECS Fargate task with an application container and SearXNG sidecar.
- Inject KodeKey and database credentials through Secrets Manager references.
- Restrict RDS access to the ECS security group and validate the public/private boundary.

## Prerequisites

- Playground: **{{ playground }}** ([open it before starting](https://kodekloud.com/cloud-playgrounds/aws))
- AWS CLI configured with credentials and a default region
- Basic Terraform, Docker, AWS IAM, and networking knowledge

## Steps

### Task 1 — Prepare Terraform, AWS CLI, and Docker

Confirm the AWS identity and install the Docker Engine package required for pulling Docker Hub images and pushing them to ECR. The playground may already contain Terraform and the AWS CLI; verify them before installing anything.

```bash
terraform version
aws --version

sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER" || true

# Refresh the shell's group membership for this session.
newgrp docker <<'DOCKER_CHECK'
docker version
docker run --rm hello-world
DOCKER_CHECK

aws sts get-caller-identity
aws configure get region
```

If `newgrp` starts a subshell, continue the remaining lab commands inside that shell. Set a region if the previous command prints nothing:

```bash
export AWS_REGION="us-east-1"
aws configure set region "$AWS_REGION"
```

### Task 2 — Obtain KodeKey credentials and prepare the published images

Open [KodeKey](https://kodekloud.com/ai-playgrounds/kodekey), choose **Launch now**, then **Start Playground**. Copy the displayed **Base URL** and **API Key**. Keep the key in a shell variable and do not paste it into a public source file.

```bash
export KODEKEY_BASE_URL="paste-the-kodekey-base-url-here"
read -rsp "KodeKey API key: " KODEKEY_API_KEY
echo

mkdir -p "$HOME/code/terraform-3tier"
cd "$HOME/code/terraform-3tier"

cat << 'EOF' > .gitignore
terraform.tfvars
.terraform/
*.tfstate
*.tfstate.*
EOF

docker pull egglou/nova:searxng
docker pull egglou/nova:latest
```

### Task 3 — Define Terraform providers, variables, secrets, and the public/private network

Create the foundational Terraform files. The generated `terraform.tfvars` stays local and is ignored by Git.

```bash
cat << 'EOF' > providers.tf
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
EOF

cat << 'EOF' > variables.tf
variable "aws_region" {
  type = string
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "db_name" {
  type    = string
  default = "nova"
}

variable "db_user" {
  type    = string
  default = "postgres"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "kodekey_base_url" {
  type = string
}

variable "kodekey_api_key" {
  type      = string
  sensitive = true
}

variable "searxng_secret_key" {
  type      = string
  sensitive = true
}

variable "openrouter_model" {
  type    = string
  default = "openai/gpt-5-mini"
}

variable "model_planner" {
  type    = string
  default = "gpt-5.4-mini"
}

variable "model_research" {
  type    = string
  default = "gpt-5.4-mini"
}

variable "model_competitor" {
  type    = string
  default = "claude-haiku-4-5-20251001"
}

variable "model_market" {
  type    = string
  default = "qwen/qwen3.7-plus"
}

variable "model_customer" {
  type    = string
  default = "gpt-5.4-mini"
}

variable "model_pricing" {
  type    = string
  default = "gpt-5.4-mini"
}

variable "model_advisor" {
  type    = string
  default = "claude-sonnet-5"
}

variable "model_chat" {
  type    = string
  default = "gpt-5.4-mini"
}
EOF

export DB_PASSWORD="$(openssl rand -hex 24)"
export SEARXNG_SECRET_KEY="$(openssl rand -hex 24)"

aws iam list-roles \
  --query 'Roles[?starts_with(RoleName, `iam_role_`)].RoleName' \
  --output table

cat << EOF > terraform.tfvars
aws_region         = "$AWS_REGION"
environment        = "prod"
vpc_cidr           = "10.0.0.0/16"
db_name            = "nova"
db_user            = "postgres"
db_password        = "$DB_PASSWORD"
kodekey_base_url   = "$KODEKEY_BASE_URL"
kodekey_api_key    = "$KODEKEY_API_KEY"
searxng_secret_key = "$SEARXNG_SECRET_KEY"
EOF

cat << 'EOF' > vpc.tf
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.environment}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.environment}-igw" }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.environment}-public-1" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.environment}-public-2" }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "${var.environment}-private-1" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags              = { Name = "${var.environment}-private-2" }
}

resource "aws_subnet" "app_private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.30.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "${var.environment}-app-private-1" }
}

resource "aws_subnet" "app_private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.40.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags              = { Name = "${var.environment}-app-private-2" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.environment}-public-rt" }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.environment}-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id
  depends_on    = [aws_internet_gateway.main]
  tags          = { Name = "${var.environment}-nat" }
}

resource "aws_route_table" "app_private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "${var.environment}-app-private-rt" }
}

resource "aws_route_table_association" "app_private_1" {
  subnet_id      = aws_subnet.app_private_1.id
  route_table_id = aws_route_table.app_private.id
}

resource "aws_route_table_association" "app_private_2" {
  subnet_id      = aws_subnet.app_private_2.id
  route_table_id = aws_route_table.app_private.id
}
EOF

cat << 'EOF' > secrets.tf
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.environment}/nova/db-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}

resource "aws_secretsmanager_secret" "kodekey_api_key" {
  name                    = "${var.environment}/nova/kodekey-api-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "kodekey_api_key" {
  secret_id     = aws_secretsmanager_secret.kodekey_api_key.id
  secret_string = var.kodekey_api_key
}

resource "aws_secretsmanager_secret" "searxng_secret_key" {
  name                    = "${var.environment}/nova/searxng-secret-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "searxng_secret_key" {
  secret_id     = aws_secretsmanager_secret.searxng_secret_key.id
  secret_string = var.searxng_secret_key
}

resource "aws_secretsmanager_secret" "database_url" {
  name                    = "${var.environment}/nova/database-url"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = "postgres://${var.db_user}:${var.db_password}@${aws_db_instance.rds_db.address}:5432/${var.db_name}?sslmode=require"
}
EOF
```

### Task 4 — Create ECR, IAM, security groups, ALB, RDS, ECS, and outputs

Add the remaining Terraform resources. This stage defines the full AWS dependency graph but does not yet build or publish images.

```bash
cat << 'EOF' > security_groups.tf
resource "aws_security_group" "alb" {
  name   = "${var.environment}-alb-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs" {
  name   = "${var.environment}-ecs-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name   = "${var.environment}-db-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
EOF

cat << 'EOF' > storage_registry.tf
resource "aws_ecr_repository" "app" {
  name                 = "${var.environment}-app-repo"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "search" {
  name                 = "${var.environment}-search-repo"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_s3_bucket" "assets" {
  bucket        = "${var.environment}-assets-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
EOF

cat << 'EOF' > iam.tf
resource "aws_iam_role" "execution" {
  name = "iam_role_ecs_execution"

  lifecycle {
    ignore_changes = [description]
  }

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "execution_secrets_readonly" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/AWSSecretsManagerClientReadOnlyAccess"
}

resource "aws_iam_role" "task" {
  name = "iam_role_ecs_task"

  lifecycle {
    ignore_changes = [description]
  }

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_s3" {
  role       = aws_iam_role.task.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
EOF

cat << 'EOF' > database.tf
resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

resource "aws_db_instance" "rds_db" {
  identifier             = "${var.environment}-nova-db"
  allocated_storage      = 20
  max_allocated_storage  = 100
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  db_name                = var.db_name
  username               = var.db_user
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}
EOF

cat << 'EOF' > alb.tf
resource "aws_lb" "main" {
  name               = "${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

resource "aws_lb_target_group" "app" {
  name        = "${var.environment}-app-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path    = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
EOF
```

### Task 5 — Initialize ECR, retag both images, and push them

Create the ECR repositories first, then authenticate Docker to the AWS account. Retag the two published Docker Hub images and push them to ECR. Do not rebuild the images locally.

```bash
terraform init
terraform apply \
  -target=aws_ecr_repository.app \
  -target=aws_ecr_repository.search \
  -auto-approve

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
  echo "AWS region is not configured. Set AWS_REGION and run: aws configure set region \"$AWS_REGION\""
  exit 1
fi
ENVIRONMENT="prod"
ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

aws ecr get-login-password --region "$AWS_REGION" |
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

APP_REPOSITORY="$ECR_REGISTRY/${ENVIRONMENT}-app-repo"
SEARCH_REPOSITORY="$ECR_REGISTRY/${ENVIRONMENT}-search-repo"

docker tag egglou/nova:searxng "$SEARCH_REPOSITORY:latest"
docker push "$SEARCH_REPOSITORY:latest"

docker tag egglou/nova:latest "$APP_REPOSITORY:latest"
docker push "$APP_REPOSITORY:latest"

aws ecr describe-images --repository-name prod-app-repo --region "$AWS_REGION"
aws ecr describe-images --repository-name prod-search-repo --region "$AWS_REGION"
```

### Task 6 — Define the ECS task and deploy the three-tier stack

Create the ECS resources and connect the pushed images to the task definition. ECS runs in the dedicated private application subnets without public IPs; the public ALB reaches it internally, and the NAT Gateway provides outbound access. The task definition injects sensitive values with Secrets Manager ARNs and keeps model routing values as ordinary configuration.

Use the required `iam_role_` prefix for the ECS execution and task roles. Attach the standard ECS execution policy, the AWS-managed `AWSSecretsManagerClientReadOnlyAccess` policy, and the S3 task policy.

```bash
cat << 'EOF' > ecs.tf
resource "aws_ecs_cluster" "main" {
  name = "${var.environment}-ecs-cluster"
}

resource "aws_cloudwatch_log_group" "main" {
  name              = "/ecs/${var.environment}-nova"

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_ecs_task_definition" "main" {
  family                   = "${var.environment}-nova-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "nova-app"
      image     = "${aws_ecr_repository.app.repository_url}:latest"
      essential = true
      portMappings = [{ containerPort = 3000, hostPort = 3000 }]
      environment = [
        { name = "KODEKEY_BASE_URL", value = var.kodekey_base_url },
        { name = "OPENROUTER_MODEL", value = var.openrouter_model },
        { name = "SEARXNG_URL", value = "http://localhost:8080" },
        { name = "POSTGRES_DB", value = var.db_name },
        { name = "POSTGRES_USER", value = var.db_user },
        { name = "MODEL_PLANNER", value = var.model_planner },
        { name = "MODEL_RESEARCH", value = var.model_research },
        { name = "MODEL_COMPETITOR", value = var.model_competitor },
        { name = "MODEL_MARKET", value = var.model_market },
        { name = "MODEL_CUSTOMER", value = var.model_customer },
        { name = "MODEL_PRICING", value = var.model_pricing },
        { name = "MODEL_ADVISOR", value = var.model_advisor },
        { name = "MODEL_CHAT", value = var.model_chat }
      ]
      secrets = [
        { name = "KODEKEY_API_KEY", valueFrom = aws_secretsmanager_secret.kodekey_api_key.arn },
        { name = "DATABASE_URL", valueFrom = aws_secretsmanager_secret.database_url.arn },
        { name = "POSTGRES_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
        { name = "SEARXNG_SECRET", valueFrom = aws_secretsmanager_secret.searxng_secret_key.arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }
    },
    {
      name      = "nova-searxng"
      image     = "${aws_ecr_repository.search.repository_url}:latest"
      essential = true
      portMappings = [{ containerPort = 8080, hostPort = 8080 }]
      secrets = [
        { name = "SEARXNG_SECRET", valueFrom = aws_secretsmanager_secret.searxng_secret_key.arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "searxng"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "main" {
  name            = "${var.environment}-ecs-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.app_private_1.id, aws_subnet.app_private_2.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "nova-app"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.http]
}
EOF

cat << 'EOF' > outputs.tf
output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "ecr_app_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "ecr_search_repository_url" {
  value = aws_ecr_repository.search.repository_url
}

output "s3_bucket_name" {
  value = aws_s3_bucket.assets.id
}

output "rds_endpoint" {
  value = aws_db_instance.rds_db.endpoint
}
EOF

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
```

### Task 7 — Validate the deployment and security boundaries

Wait for the ECS service to become stable, then test the public endpoint, registry state, secret names, and private database DNS record.

```bash
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
```

Expected result:

- [ ] The ALB returns an HTTP response from the application image.
- [ ] The ECS service has one desired and one running task in a private application subnet.
- [ ] Both ECR repositories contain a `latest` image.
- [ ] Secrets Manager contains the database, KodeKey, and SearXNG secrets.
- [ ] The RDS endpoint resolves privately and is not publicly accessible.
- [ ] The RDS security group allows port 5432 only from the ECS security group.
- [ ] The ECS application subnets route `0.0.0.0/0` through the NAT Gateway.
- [ ] ECS tasks have no public IP address.

## Validation

```bash
terraform validate
terraform output -raw alb_dns_name
curl -fsS -o /dev/null -w '%{http_code}\n' "http://$(terraform output -raw alb_dns_name)"
aws ecs describe-services \
  --cluster prod-ecs-cluster \
  --services prod-ecs-service \
  --query 'services[0].runningCount'
aws ecr describe-images --repository-name prod-app-repo --query 'imageDetails[0].imageTags'
aws ecr describe-images --repository-name prod-search-repo --query 'imageDetails[0].imageTags'
```

Expected result:

- [ ] `terraform validate` completes successfully.
- [ ] The ALB responds with an HTTP status code.
- [ ] ECS reports one running task.
- [ ] Both ECR repositories report the `latest` tag.
- [ ] Terraform state contains Secrets Manager references rather than plaintext secret environment values in the ECS task definition.

## References & further learning

- [Docker Engine installation](https://docs.docker.com/engine/install/)
- [Amazon ECR: push an image](https://docs.aws.amazon.com/AmazonECR/latest/userguide/getting-started-cli.html)
- [Amazon ECS task definition parameters](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html)
- [Amazon ECS task execution IAM role](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html)
- [Amazon RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)
- [Terraform AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [KodeKloud KodeKey](https://kodekloud.com/ai-playgrounds/kodekey)
```
