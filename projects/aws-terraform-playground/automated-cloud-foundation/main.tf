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
