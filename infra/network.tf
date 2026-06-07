# 1. Core VPC Container
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "researchwatcher-vpc-staging" }
}

# 2. Internet Gateway (The Web Portal)
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "researchwatcher-igw" }
}

# 3. Public Subnet A (Zone us-east-2a)
resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-2a"
  map_public_ip_on_launch = true # Ensures instances running here get a public IP

  tags = { Name = "researchwatcher-public-2a" }
}

# 4. Public Subnet B (Zone us-east-2b - Required by RDS)
resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-2b"
  map_public_ip_on_launch = true

  tags = { Name = "researchwatcher-public-2b" }
}

# 5. Route Table (The Network Navigation Maps)
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id # Directs outbound traffic out via the IGW
  }

  tags = { Name = "researchwatcher-public-rt" }
}

# 6. Bind the Navigation Maps to Both Subnet Nodes
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}




# 3. Firewall Protection Blueprint for intra vpc communication (Security Group)
resource "aws_security_group" "vpc_internal" {
  name        = "researchwatcher-internal-sg"
  description = "allows data across machines in vpc"
  vpc_id      = aws_vpc.main.id
}

# inbound
resource "aws_vpc_security_group_ingress_rule" "allow_self" {
  security_group_id = aws_security_group.vpc_internal.id

  # This makes it self-referencing
  referenced_security_group_id = aws_security_group.vpc_internal.id
  
  ip_protocol = "-1" 

}

  # Outbound Rule: Allow outbound traffic
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.vpc_internal.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # Allow all outbound traffic
}