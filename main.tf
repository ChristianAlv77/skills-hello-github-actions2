provider "aws" {
  region = "us-west-2"  # Puedes cambiar la región según tus necesidades
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "example-vpc"
  }
}

resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-a"
  }
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-west-2b"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-b"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id  = aws_vpc.example.id
}

resource "aws_route_table" "r" {
  vpc_id  = aws_vpc.example.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "main"
  }
}

resource "aws_main_route_table_association" "a" {
  vpc_id  = aws_vpc.example.id
  route_table_id = aws_route_table.r.id
}

resource "aws_ecs_cluster" "cluster" {
  name = "example"
}

resource "aws_ecs_task_definition" "task" {
  family                   = "example"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE","EC2"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name  = "example"
    image = "nginx:latest"
    portMappings = [{
      containerPort = 80
      hostPort      = 80
      protocol      = "tcp"
    }]
  }])
}

resource "aws_lb" "test" {
  name               = "test-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
}

resource "aws_lb_target_group" "test" {
  name     = "tf-example"
  port     = 80
  protocol = "HTTP"
  vpc_id  = aws_vpc.example.id
  target_type = "ip"
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.test.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test.arn
  }
}

resource "aws_ecs_service" "service" {
  name            = "example"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets            = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
    assign_public_ip = true
    security_groups  = [aws_security_group.lb_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.test.arn
    container_name   = "example"
    container_port   = 80
  }

}

resource "aws_security_group" "lb_sg" {
  name        = "lb_sg"
  description = "Allow all inbound traffic"
  vpc_id = aws_vpc.example.id
  
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
#================ fin del ejercicio back ===============
#================ Inicio Ejercicio Front ===============

resource "aws_s3_bucket" "bucket" {
  bucket = "my-bucket-from-terraform"
  #acl    = "private"
}

resource "aws_s3_bucket_object" "object" {
  bucket = aws_s3_bucket.bucket.id
  key    = "index.html"
  source = "index.html"
  content_type = "text/html"
}

resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "My OAI"
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.oai.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "confundus-policy" {
  bucket = aws_s3_bucket.bucket.id
  policy = data.aws_iam_policy_document.s3_policy.json
}

resource "aws_cloudfront_distribution" "distribution" {
  origin {
    domain_name = aws_s3_bucket.bucket.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.bucket.id
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "My distribution"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = aws_s3_bucket.bucket.id

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}