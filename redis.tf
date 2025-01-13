variable "aws-region" {
  type        = string
  description = "AWS Region"
  default     = "sa-east-1"
}

terraform {
  backend "s3" {
    bucket  = "6soat-tfstate"
    key     = "terraform-redis/video2framestatus-redis/terraform.tfstate"
    region  = "sa-east-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws-region
}

resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "video2framestatus-redis-subnet-group"
  subnet_ids = [data.aws_subnet.subnet1.id, data.aws_subnet.subnet2.id]

  tags = {
    Name        = "video2framestatus Redis Subnet Group"
    Environment = "production"
    Service     = "video2framestatus"
  }
}

resource "aws_elasticache_replication_group" "redis_replication_group" {
  replication_group_id        = "video2framestatus-redis"
  description                 = "Redis Replication Group for video2framestatus"
  engine                      = "redis"
  engine_version              = "7.0"
  node_type                   = "cache.t3.micro"
  num_cache_clusters          = 2
  automatic_failover_enabled  = true
  multi_az_enabled            = true
  preferred_cache_cluster_azs = ["sa-east-1a", "sa-east-1b"]
  parameter_group_name        = "default.redis7"
  subnet_group_name           = aws_elasticache_subnet_group.redis_subnet_group.id
  security_group_ids          = [aws_security_group.redis_sg.id]

  tags = {
    Name        = "video2framestatus Redis Replication Group"
    Environment = "production"
    Service     = "video2framestatus"
  }
}

resource "aws_security_group" "redis_sg" {
  name        = "video2framestatus-redis-sg"
  description = "Security group for video2framestatus Redis"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "video2framestatus Redis Security Group"
    Environment = "production"
    Service     = "video2framestatus"
  }
}

output "redis_primary_endpoint" {
  value = aws_elasticache_replication_group.redis_replication_group.primary_endpoint_address
}

output "redis_port" {
  value = aws_elasticache_replication_group.redis_replication_group.port
}

resource "aws_iam_policy" "secretsPolicy" {
  name = "podsecret-deployment-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [aws_secretsmanager_secret.db_credentials.arn]
      },
    ]
  })
}

output "secrets_policy" {
  value = aws_iam_policy.secretsPolicy.arn
}

output "secrets_id" {
  value = aws_secretsmanager_secret.db_credentials.id
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "video2framestatus-dbcredential-redis"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    redis_host     = aws_elasticache_replication_group.redis_replication_group.primary_endpoint_address
    redis_port     = aws_elasticache_replication_group.redis_replication_group.port
    redis_password = ""
  })
}
