# AWS Three Tier Application with Terraform

## Project info

- **ID:** three-tier-application-aws-terraform-private-ecs-nat
- **Title:** Secure Three-Tier AI Application on AWS with Private ECS and NAT Gateway
- **Playground:** AWS Cloud Sandbox
- **Playground link:** [https://kodekloud.com/playgrounds/playground-terraform-aws](https://kodekloud.com/playgrounds/playground-terraform-aws)
- **Difficulty:** advanced
- **Estimated minutes:** 120
- **Tags:**
  - aws
  - terraform
  - ecs
  - ecr
  - fargate
  - docker
  - security
- **Skills:**
  - provisioning AWS networking with Terraform
  - building and publishing Docker images to Amazon ECR
  - deploying multi-container ECS Fargate tasks
  - injecting credentials from AWS Secrets Manager
  - validating ALB, ECS, RDS, and security-group connectivity
- **Prerequisites:**
  - Basic Terraform and HCL knowledge
  - Basic AWS CLI and IAM knowledge
  - Basic Docker commands
  - Familiarity with container networking

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

> 📄 **[`script.sh`](./script.sh)**

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
```

> 📄 **[`.gitignore`](./.gitignore)**

```bash
docker pull kodekloud/nova:latest
docker pull kodekloud/nova:searxng
```

### Task 3 — Define Terraform providers, variables, secrets, and the public/private network

Create the foundational Terraform files. The generated `terraform.tfvars` stays local and is ignored by Git.

> 📄 **[`providers.tf`](./providers.tf)**

> 📄 **[`variables.tf`](./variables.tf)**

```bash
export DB_PASSWORD="$(openssl rand -hex 24)"
export SEARXNG_SECRET_KEY="$(openssl rand -hex 24)"

aws iam list-roles \
  --query 'Roles[?starts_with(RoleName, `iam_role_`)].RoleName' \
  --output table
```

> 📄 **[`terraform.tfvars`](./terraform.tfvars)**

> 📄 **[`vpc.tf`](./vpc.tf)**

> 📄 **[`secrets.tf`](./secrets.tf)**

### Task 4 — Create ECR, IAM, security groups, ALB, RDS, ECS, and outputs

Add the remaining Terraform resources. This stage defines the full AWS dependency graph but does not yet build or publish images.

> 📄 **[`security_groups.tf`](./security_groups.tf)**

> 📄 **[`storage_registry.tf`](./storage_registry.tf)**

> 📄 **[`iam.tf`](./iam.tf)**

> 📄 **[`database.tf`](./database.tf)**

> 📄 **[`alb.tf`](./alb.tf)**

### Task 5 — Initialize ECR, retag both images, and push them

Create the ECR repositories first, then authenticate Docker to the AWS account. Retag the two published Docker Hub images and push them to ECR. Do not rebuild the images locally.

> 📄 **[`script-2.sh`](./script-2.sh)**

### Task 6 — Define the ECS task and deploy the three-tier stack

Create the ECS resources and connect the pushed images to the task definition. ECS runs in the dedicated private application subnets without public IPs; the public ALB reaches it internally, and the NAT Gateway provides outbound access. The task definition injects sensitive values with Secrets Manager ARNs and keeps model routing values as ordinary configuration.

Use the required `iam_role_` prefix for the ECS execution and task roles. Attach the standard ECS execution policy, the AWS-managed `AWSSecretsManagerClientReadOnlyAccess` policy, and the S3 task policy.

> 📄 **[`ecs.tf`](./ecs.tf)**

> 📄 **[`outputs.tf`](./outputs.tf)**

```bash
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

```

---

## Files in this folder

The steps above reference these ready-to-use files (copy them onto the playground):

- [`.gitignore`](./.gitignore)
- [`README.md`](./README.md)
- [`alb.tf`](./alb.tf)
- [`database.tf`](./database.tf)
- [`ecs.tf`](./ecs.tf)
- [`iam.tf`](./iam.tf)
- [`outputs.tf`](./outputs.tf)
- [`providers.tf`](./providers.tf)
- [`script-2.sh`](./script-2.sh)
- [`script.sh`](./script.sh)
- [`secrets.tf`](./secrets.tf)
- [`security_groups.tf`](./security_groups.tf)
- [`storage_registry.tf`](./storage_registry.tf)
- [`terraform.tfvars`](./terraform.tfvars)
- [`variables.tf`](./variables.tf)
- [`vpc.tf`](./vpc.tf)
