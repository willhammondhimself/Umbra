terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "umbra-terraform-state"
    key    = "backend/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "umbra"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ---------- VPC ----------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "umbra-${var.environment}"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = var.environment != "production"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# ---------- Security Groups ----------

resource "aws_security_group" "alb" {
  name_prefix = "umbra-alb-"
  vpc_id      = module.vpc.vpc_id

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
}

resource "aws_security_group" "ecs" {
  name_prefix = "umbra-ecs-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 8000
    to_port         = 8000
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

resource "aws_security_group" "rds" {
  name_prefix = "umbra-rds-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }
}

resource "aws_security_group" "redis" {
  name_prefix = "umbra-redis-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }
}

# ---------- RDS (Postgres 15) ----------

resource "aws_db_subnet_group" "main" {
  name       = "umbra-${var.environment}"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_rds_cluster" "postgres" {
  cluster_identifier = "umbra-${var.environment}"
  engine             = "aurora-postgresql"
  engine_version     = "15.4"
  database_name      = "umbra"
  master_username    = "umbra_admin"
  master_password    = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  storage_encrypted   = true
  deletion_protection = var.environment == "production"
  skip_final_snapshot = var.environment != "production"

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = var.environment == "production" ? 8 : 2
  }
}

resource "aws_rds_cluster_instance" "postgres" {
  count              = var.environment == "production" ? 2 : 1
  cluster_identifier = aws_rds_cluster.postgres.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.postgres.engine
  engine_version     = aws_rds_cluster.postgres.engine_version
}

# ---------- ElastiCache (Redis 7) ----------

resource "aws_elasticache_subnet_group" "main" {
  name       = "umbra-${var.environment}"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "umbra-${var.environment}"
  description          = "Umbra Redis cluster"
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = var.environment == "production" ? "cache.r7g.large" : "cache.t4g.micro"
  num_cache_clusters   = var.environment == "production" ? 2 : 1

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  automatic_failover_enabled = var.environment == "production"
}

# ---------- ECR ----------

resource "aws_ecr_repository" "api" {
  name                 = "umbra-api"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ---------- ECS Fargate ----------

resource "aws_ecs_cluster" "main" {
  name = "umbra-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_iam_role" "ecs_execution" {
  name = "umbra-ecs-execution-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name = "umbra-ecs-task-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/umbra-api-${var.environment}"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "api" {
  family                   = "umbra-api-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.environment == "production" ? 1024 : 512
  memory                   = var.environment == "production" ? 2048 : 1024
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name  = "api"
    image = "${aws_ecr_repository.api.repository_url}:latest"

    portMappings = [{
      containerPort = 8000
      protocol      = "tcp"
    }]

    environment = [
      { name = "DATABASE_URL", value = "postgresql+asyncpg://${aws_rds_cluster.postgres.master_username}:${var.db_password}@${aws_rds_cluster.postgres.endpoint}:5432/${aws_rds_cluster.postgres.database_name}" },
      { name = "REDIS_URL", value = "rediss://${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379/0" },
      { name = "ENVIRONMENT", value = var.environment },
    ]

    secrets = [
      { name = "JWT_SECRET", valueFrom = aws_ssm_parameter.jwt_secret.arn },
      { name = "APPLE_TEAM_ID", valueFrom = aws_ssm_parameter.apple_team_id.arn },
      { name = "GOOGLE_CLIENT_ID", valueFrom = aws_ssm_parameter.google_client_id.arn },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.api.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "api"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8000/health')\""]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }
  }])
}

resource "aws_ecs_service" "api" {
  name            = "umbra-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.environment == "production" ? 2 : 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.ecs.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 8000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.https]
}

# ---------- ALB ----------

resource "aws_lb" "main" {
  name               = "umbra-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_target_group" "api" {
  name        = "umbra-api-${var.environment}"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# ---------- SSM Parameters (secrets) ----------

resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/umbra/${var.environment}/jwt-secret"
  type  = "SecureString"
  value = var.jwt_secret
}

resource "aws_ssm_parameter" "apple_team_id" {
  name  = "/umbra/${var.environment}/apple-team-id"
  type  = "SecureString"
  value = var.apple_team_id
}

resource "aws_ssm_parameter" "google_client_id" {
  name  = "/umbra/${var.environment}/google-client-id"
  type  = "SecureString"
  value = var.google_client_id
}

# ---------- Outputs ----------

output "api_url" {
  value = "https://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "rds_endpoint" {
  value     = aws_rds_cluster.postgres.endpoint
  sensitive = true
}

output "redis_endpoint" {
  value     = aws_elasticache_replication_group.redis.primary_endpoint_address
  sensitive = true
}
