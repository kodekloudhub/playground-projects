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
