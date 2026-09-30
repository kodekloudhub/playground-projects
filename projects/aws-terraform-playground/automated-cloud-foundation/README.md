# Automated Cloud Foundation

**Level:** intermediate  ·  **Playground:** AWS Terraform Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-terraform-aws)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
A media company has been manually deploying infrastructure for their core web applications. As they prepare to standardize their deployments, the manual provisioning process has become a bottleneck, leading to configuration drift and deployment errors. The Lead Cloud Architect has mandated a shift to declarative infrastructure. You must completely automate the provisioning of a Highly Available, multi-AZ environment using Infrastructure as Code (IaC) so it can be deployed consistently, audited, and destroyed with a single command.

## What you'll build
You will author Terraform configuration files to deploy a secure, 2-AZ True 3-Tier network topology. This architecture includes a custom Virtual Private Cloud (VPC), six subnets distributed across two Availability Zones, an Internet Gateway, and highly available NAT Gateways. Crucially, you will deploy an Application Load Balancer in the public subnets to serve as the definitive point of contact for external routing, seamlessly passing traffic down through strictly chained Security Groups to your isolated database tier.

## Learning objectives
By the end you will be able to:
- Provision a True 3-Tier AWS VPC architecture with public, application, and isolated database subnets.
- Deploy an Application Load Balancer and highly available NAT Gateways across multiple Availability Zones.
- Configure specific route tables to manage internet access securely per tier.
- Chain AWS Security Groups (ALB -> App -> DB) to enforce least-privilege internal network access.

## Prerequisites
- Playground: **Terraform + AWS** (open it before starting)

## Steps

### Task 1 — Define Providers and Variables
Create a file named `providers.tf` and add the following content:
```terraform
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

Next, create a file named `variables.tf` and add the following content:
```terraform
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "media-app"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnets" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "isolated_db_subnets" {
  type    = list(string)
  default = ["10.0.20.0/24", "10.0.21.0/24"]
}
```
> **Why:** These files initialize Terraform with the correct AWS provider version and establish variables to prevent hardcoding values, making the configuration reusable across environments.

### Task 2 — Configure Main Resources and Outputs
Create a file named `main.tf` and add the following content:
```terraform
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-vpc" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-igw" })
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-public-${count.index + 1}" })
}

resource "aws_subnet" "private_app" {
  count                   = length(var.private_app_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_app_subnets[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags                    = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-app-${count.index + 1}" })
}

resource "aws_subnet" "isolated_db" {
  count                   = length(var.isolated_db_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.isolated_db_subnets[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags                    = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-db-${count.index + 1}" })
}

# --- HA NAT Gateways (One per Public Subnet) ---
resource "aws_eip" "nat_eip" {
  count  = length(var.public_subnets)
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-nat-eip-${count.index + 1}" })

  # Explicit dependency to ensure the IGW exists before requesting EIPs
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  count         = length(var.public_subnets)
  allocation_id = aws_eip.nat_eip[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags       = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-nat-${count.index + 1}" })
  depends_on = [aws_internet_gateway.igw]
}

# --- Route Tables ---
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-public-rt" })
}

# Create ONE App Route Table per AZ to map to the respective NAT Gateway
resource "aws_route_table" "app_rt" {
  count  = length(var.private_app_subnets)
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-app-rt-${count.index + 1}" })
}

resource "aws_route_table" "db_rt" {
  vpc_id = aws_vpc.main.id
  # No outbound internet route for isolated DB layer
  tags   = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-db-rt" })
}

# --- Route Table Associations ---
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "app" {
  count          = length(var.private_app_subnets)
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.app_rt[count.index].id
}

resource "aws_route_table_association" "db" {
  count          = length(var.isolated_db_subnets)
  subnet_id      = aws_subnet.isolated_db[count.index].id
  route_table_id = aws_route_table.db_rt.id
}

# --- 3-Tier Chained Security Groups ---
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "ALB point of contact - allow HTTP/HTTPS inbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-alb-sg" })
}

resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-${var.environment}-app-sg"
  description = "App tier - accepts traffic ONLY from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-app-sg" })
}

resource "aws_security_group" "db_sg" {
  name        = "${var.project_name}-${var.environment}-db-sg"
  description = "Database tier - accepts traffic ONLY from App tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-db-sg" })
}

# --- Application Load Balancer ---
resource "aws_lb" "app_alb" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id

  tags = merge(local.common_tags, { Name = "${var.project_name}-${var.environment}-alb" })
}
```

Then, create a file named `outputs.tf` and add the following content:
```terraform
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  value = aws_subnet.private_app[*].id
}

output "db_subnet_ids" {
  value = aws_subnet.isolated_db[*].id
}

output "alb_security_group_id" {
  value = aws_security_group.alb_sg.id
}

output "app_security_group_id" {
  value = aws_security_group.app_sg.id
}

output "db_security_group_id" {
  value = aws_security_group.db_sg.id
}

output "alb_dns_name" {
  description = "The publicly accessible DNS name of the Load Balancer"
  value       = aws_lb.app_alb.dns_name
}
```
> **Why:** The main logic orchestrates the 6 subnets, multi-AZ NAT gateways, route tables, the physical Load Balancer, and the strictly chained 3-tier security groups. The outputs expose essential resource IDs for verification.

### Task 3 — Initialize and Deploy (Apply)
Execute the following commands to provision the infrastructure:
```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```
> **Why:** This workflow initializes the working directory, calculates the execution plan, and then securely applies the changes to AWS.

### Task 4 — Verify
Extract the IDs created by Terraform and query the AWS API to verify the HA architecture:
```bash
# 1. Store Outputs for Querying
export VPC_ID=$(terraform output -raw vpc_id)
export ALB_SG_ID=$(terraform output -raw alb_security_group_id)
export APP_SG_ID=$(terraform output -raw app_security_group_id)
export DB_SG_ID=$(terraform output -raw db_security_group_id)

# 2. Verify the Load Balancer Provisioning
aws elbv2 describe-load-balancers \
  --names media-app-prod-alb \
  --query "LoadBalancers[*].{Name:LoadBalancerName, Scheme:Scheme, State:State.Code, AZs:join(', ', AvailabilityZones[*].ZoneName)}" \
  --output table

# 3. Verify VPC DNS Properties
aws ec2 describe-vpcs --vpc-ids $VPC_ID --query "Vpcs[0].{Name:Tags[?Key=='Name'].Value | [0], CidrBlock:CidrBlock, DnsSupport:EnableDnsSupport}"
aws ec2 describe-vpc-attribute --vpc-id $VPC_ID --attribute enableDnsHostnames --query "EnableDnsHostnames.Value"

# 4. Verify Subnets & AZ Distribution
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].{Name:Tags[?Key=='Name'].Value | [0], SubnetId:SubnetId, CidrBlock:CidrBlock, AZ:AvailabilityZone, MapPublicIp:MapPublicIpOnLaunch}" \
  --output table

# 5. Verify Routing Paths (IGW, Multi-NAT, and Isolated)
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "RouteTables[*].{Name:Tags[?Key=='Name'].Value | [0], Routes:Routes}" \
  --output json

# 6. Verify 3-Tier Chained Security Groups
# Check ALB SG
aws ec2 describe-security-groups --group-ids $ALB_SG_ID \
  --query "SecurityGroups[0].IpPermissions[*].{FromPort:FromPort, ToPort:ToPort, IpProtocol:IpProtocol, IpRanges:IpRanges[*].CidrIp}" \
  --output table

# Check App SG
aws ec2 describe-security-groups --group-ids $APP_SG_ID \
  --query "SecurityGroups[0].IpPermissions[*].{FromPort:FromPort, ToPort:ToPort, IpProtocol:IpProtocol, AllowedSourceGroup:UserIdGroupPairs[*].GroupId}" \
  --output table

# Check DB SG
aws ec2 describe-security-groups --group-ids $DB_SG_ID \
  --query "SecurityGroups[0].IpPermissions[*].{FromPort:FromPort, ToPort:ToPort, IpProtocol:IpProtocol, AllowedSourceGroup:UserIdGroupPairs[*].GroupId}" \
  --output table
```
> **Why:** Directly querying the AWS API confirms that the resources deployed into the cloud environment match the declarative code.

## Validation
To definitively prove that your infrastructure is successfully deployed and perfectly matches your declarative code (testing for idempotency), run a final plan check:

```bash
terraform plan
```

Expected result:
- [ ] The command outputs `No changes. Your infrastructure matches the configuration.`, confirming the deployment is fully synchronized and complete.
- [ ] The Application Load Balancer is successfully provisioned across the public subnets and established as the entry point.
- [ ] Instances in the Private App Subnets can route outbound traffic through their respective NAT gateways, while Isolated Database subnets lack internet routes entirely.
- [ ] The security groups are strictly chained together (ALB -> App -> DB) rather than relying on open CIDR blocks.

## References & further learning
- HashiCorp Terraform AWS Provider Documentation: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- AWS VPC Architecture Guide: https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html
- KodeKloud course: Terraform Basics Training Course: https://kodekloud.com/courses/terraform-basics-training-course/
