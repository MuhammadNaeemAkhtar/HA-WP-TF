terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "eu-west-1"
}

/*=====================================
VPC, Subnets, Internet and NAT Gateways
=======================================/*
By default this module will provision new Elastic IPs for the VPC's NAT Gateways.
This means that when creating a new VPC, new IPs are allocated, and 
when that VPC is destroyed those IPs are released.
*/
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "wordpress-workshop"
  cidr = "192.168.0.0/16"

  azs             = ["eu-west-1a", "eu-west-1b"]
  public_subnets  = ["192.168.0.0/24", "192.168.1.0/24"] #public subnets A, B
  private_subnets = ["192.168.2.0/24", "192.168.3.0/24"] #Application subnets A, B
  intra_subnets   = ["192.168.4.0/24", "192.168.5.0/24"] #Data subnets A, B

  enable_vpn_gateway = true
  
  #One NAT Gateway per availability zone
  enable_nat_gateway = true
  single_nat_gateway = false
  one_nat_gateway_per_az = true

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}

/*======================
LAB2: Set up your RDS DB
=======================*/
resource "aws_security_group" "wordpress-db-client-SG" {
  name = "wordpress-db-client-SG"

  vpc_id = module.vpc.vpc_id
  tags = {
    Name = "WP DB Client SG"
  }
}

resource "aws_security_group" "wordpress-db-SG" {
  name = "wordpress-db-SG"
    
  description = "Allow TCP connection on 3306 for RDS"
  vpc_id = module.vpc.vpc_id
  
  # Only MySQL in
  ingress {
      from_port = 3306
      to_port = 3306
      protocol = "tcp"
      security_groups = [aws_security_group.wordpress-db-client-SG.id]
  }
  
  #Allow all outbounded traffic
  egress {
      from_port = 0
      to_port = 0
      protocol = "-1"
  }
  tags = {
    Name = "WP DB SG"
  }
}
################################################################################
# Subnet Group
################################################################################
resource "aws_db_subnet_group" "wordpress-aurora" {
  name        = "wordpress-aurora"
  subnet_ids  = module.vpc.intra_subnets
  description = "Subnet group used by Aurora DB"

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
################################################################################
# RDS Database
################################################################################
resource "aws_rds_cluster" "wordpress-rds-cluster" {
  cluster_identifier     = "wordpress-workshop"
  engine                 = "aurora-mysql"
  engine_version         = "5.7.mysql_aurora.2.07.2"
  availability_zones     = ["eu-west-1a", "eu-west-1b"]
  database_name          = "wordpress"
  db_subnet_group_name   = aws_db_subnet_group.wordpress-aurora.name
  master_username        = "wordpressadmin"
  master_password        = "wordpressadminn"
  vpc_security_group_ids = [aws_security_group.wordpress-db-SG.id]
  skip_final_snapshot    = true
  #backup_retention_period = 5
  #preferred_backup_window = "07:00-09:00"
  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
#RDS Cluster Instance
resource "aws_rds_cluster_instance" "wordpress-rds-instances" {
  count                = 2
  identifier           = "database-1-instance-${count.index}"
  db_subnet_group_name = aws_db_subnet_group.wordpress-aurora.name
  cluster_identifier   = aws_rds_cluster.wordpress-rds-cluster.id
  instance_class       = "db.r5.large"
  engine               = aws_rds_cluster.wordpress-rds-cluster.engine
  engine_version       = aws_rds_cluster.wordpress-rds-cluster.engine_version
  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
/*=====================================
LAB 3: Set up Elasticache for memcached
=====================================*/
resource "aws_security_group" "wordpress-cache-client-SG" {
  name = "wordpress-cache-client-SG"

  vpc_id = module.vpc.vpc_id
  tags = {
      Name = "WP Cache Client SG"
  }
}

resource "aws_security_group" "wordpress-cache-SG" {
  name = "wordpress-cache-SG"
    
  description = "Allow TCP connection on 3306 for RDS"
  vpc_id = module.vpc.vpc_id
  
  # Only MySQL in
  ingress {
      from_port = 11211
      to_port = 11211
      protocol = "tcp"
      security_groups = [aws_security_group.wordpress-cache-client-SG.id]
  }
  
  #Allow all outbounded traffic
  egress {
      from_port = 0
      to_port = 0
      protocol = "-1"
  }
  tags = {
      Name = "WP Cache SG"
  }
}
################################################################################
# Elasticache Memcached
################################################################################
resource "aws_elasticache_cluster" "wordpress-memcached" {
  cluster_id           = "wordpress-memcached"
  engine_version       = "1.5.16"
  subnet_group_name    = aws_elasticache_subnet_group.wordpress-elasticache.name
  security_group_ids   = [aws_security_group.wordpress-cache-SG.id]
  engine               = "memcached"
  node_type            = "cache.t2.small"
  num_cache_nodes      = 1
  parameter_group_name = "default.memcached1.5"
  port                 = 11211

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
################################################################################
# Subnet Group
################################################################################
resource "aws_elasticache_subnet_group" "wordpress-elasticache" {
  name        = "wordpress-elasticache"
  description = "Subnet group used by elasticache"
  subnet_ids  = module.vpc.intra_subnets

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

/*===================================
LAB 4: Create the shared filesystem
===================================*/
resource "aws_security_group" "wordpress-fs-client-SG" {
  name = "wordpress-fs-client-SG"

  vpc_id = module.vpc.vpc_id
  tags = {
      Name = "WP FS Client SG"
  }
}

resource "aws_security_group" "wordpress-fs-SG" {
  name = "wp-cache-SG"
    
  description = "Allow TCP connection on 3306 for RDS"
  vpc_id = module.vpc.vpc_id
  
  # Only MySQL in
  ingress {
      from_port = 2049
      to_port = 2049
      protocol = "tcp"
      security_groups = [aws_security_group.wordpress-fs-client-SG.id]
  }
  
  #Allow all outbounded traffic
  egress {
      from_port = 0
      to_port = 0
      protocol = "-1"
  }
  tags = {
      Name = "WP FS SG"
  }
}
################################################################################
# Elastic File System
################################################################################
resource "aws_efs_file_system" "wordpress-efs" {
  creation_token = "wordpress-efs"

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_efs_mount_target" "wordpress-mount-targets" {
  count           = length(module.vpc.private_subnets)
  file_system_id  = aws_efs_file_system.wordpress-efs.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.wordpress-fs-SG.id]
}

/*===================== Application Tier =======================
/*=============================
Lab 5: Create the Load Balancer
==============================*/
resource "aws_security_group" "wordpress-lb-SG" {
  name = "wordpress-lb-SG"
    
  description = "Allow HTTP connection from everywhere"
  vpc_id = module.vpc.vpc_id
  
  # Accept from everywhere
  ingress {
      from_port = 80
      to_port = 80
      protocol  = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
  }
  
  #Allow all outbounded traffic
  egress {
      from_port = 80
      to_port = 80
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
      Name = "WP Load Balancer SG"
  }
}
################################################################################
# Load Balancer
################################################################################
/* module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 6.0"

  name = "wordpress-loadbalancer"

  load_balancer_type = "application"

  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnets
  security_groups = [aws_security_group.wordpress-lb-SG.id]

  target_groups = [
    {
      name_prefix      = "wp-tg-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
    }
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
} */
resource "aws_lb" "wordpress-loadbalancer" {

  name               = "wordpress-loadbalancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.wordpress-lb-SG.id]
  subnets            = module.vpc.public_subnets
  tags = {
      Terraform = "true"
      Environment = "dev"
    }
}

resource "aws_lb_listener" "wordpress-lb-listener" {
  load_balancer_arn = aws_lb.wordpress-loadbalancer.arn
  port              = 80
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress-lb-target-group.arn
  }
}

resource "aws_lb_target_group" "wordpress-lb-target-group" {
  name     = "wordpress-lb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
  /* health_check {    
    target              = "HTTP:80/"
    healthy_threshold   = 3    
    unhealthy_threshold = 10    
    timeout             = 5    
    interval            = 10    
    port                = 80 
  } */
  tags = {
      Terraform = "true"
      Environment = "dev"
    }
}

/*==================================
Lab 6: Create a launch configuration
====================================*/
resource "aws_security_group" "wp-wordpress-SG" {
  name = "wp-wordpress-SG"
  description = "Allow HTTP connection from Load Balancer"
  vpc_id = module.vpc.vpc_id

  # Only lb in
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
  }

  # Allow all outbound traffic
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
  }

  tags = {
    Name = "WP Wordpress SG" 
  }
}

data "template_file" "user_data" {
  template = file("${path.module}/user_data.tpl")
  vars = {
    EFS_MOUNT   = aws_efs_mount_target.wordpress-mount-targets[0].dns_name
    DB_NAME     = aws_rds_cluster.wordpress-rds-cluster.database_name
    DB_HOSTNAME = aws_rds_cluster.wordpress-rds-cluster.endpoint
    DB_USERNAME = aws_rds_cluster.wordpress-rds-cluster.master_username
    DB_PASSWORD = aws_rds_cluster.wordpress-rds-cluster.master_password
    LB_HOSTNAME = aws_lb.wordpress-loadbalancer.dns_name
  }
}

resource "aws_launch_configuration" "launch-conf" {
  name_prefix = "launch-conf"
  image_id = "ami-0eab41619a08cc289"
  instance_type = "t2.small"
  security_groups = [aws_security_group.wordpress-db-client-SG.id,
                      aws_security_group.wordpress-db-SG.id,
                      aws_security_group.wp-wordpress-SG.id, 
                      aws_security_group.wordpress-cache-SG.id] 
                                          
  user_data = data.template_file.user_data.rendered
  lifecycle {
    create_before_destroy = true
  }
}