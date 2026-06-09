# 1. Generate a strong cryptographically secure string
resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?" # Removes characters that could break connection strings
}

# 2. Establish the Secret Metadata Shell Container
resource "aws_secretsmanager_secret" "db_secret_metadata" {
  name                    = "researchwatcher/staging/postgres"
  recovery_window_in_days = 0 # Forces complete immediate destruction if you delete the stack
}

# 3. Store the actual password string payload inside that shell
resource "aws_secretsmanager_secret_version" "db_secret_payload" {
  secret_id     = aws_secretsmanager_secret.db_secret_metadata.id
  secret_string = jsonencode({
    username = "postgres"
    password = random_password.db_password.result
    engine   = "postgres"
  })
}

# 4. Map our Subnet Pair into an RDS Target Group Node
resource "aws_db_subnet_group" "rds_subnets" {
  name       = "researchwatcher-db-subnet-group"
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = { Name = "researchwatcher-rds-subnet-group" }
}


# 3. Firewall Protection Blueprint (Security Group)
resource "aws_security_group" "rds_sg" {
  name        = "researchwatcher-rds-sg"
  description = "Controls ingress data streams to the database node"
  vpc_id      = aws_vpc.main.id

  # Inbound Rule: Allow standard Postgres data access patterns
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # ⚠️ Open to web temporarily for initial setup verification
  }

  # Outbound Rule: Allow outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. The Core Managed Postgres DB Node
resource "aws_db_instance" "postgres" {
  identifier           = "researchwatcher-postgres-staging"
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "18.3"
  instance_class       = "db.t4g.micro" # Free-Tier eligible footprint instance
  db_name              = "vton_research"
  # Credentials matching our structural values
  username             = "postgres"
  password             = random_password.db_password.result

  # Networking links
  db_subnet_group_name   = aws_db_subnet_group.rds_subnets.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false # Required to reach it directly over the public subnets
  multi_az               = false   
  availability_zone      = "us-east-2a"                

  # Operational Safeguards
  skip_final_snapshot    = true # Prevents Terraform from hanging indefinitely during deletions
  deletion_protection  = false
}


output "db_endpoint" {
  description = "The connection host for the database"
  value       = "${aws_db_instance.postgres.endpoint}"
}