#  vpc -> subnets } -> autoscaling group -> launch template -> instance 
#  while it is not recommended to store the keys here . I'm adding to testing  
#  there are lot of for each and modularizations possible however I chose to do thisin the restricted env
#  further refinements can be done with actual deployments 

provider "aws" {
  region = "us-east-1"
  #access_key = "AKIAW3MEAXQE6M46ZIUG"
  #secret_key = "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"
}


resource "aws_vpc" "webvpc" {
  cidr_block = var.vpccidr

  tags = {
    Name = "demovpc"
  }
}


data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public_subnet_1" {
    vpc_id = aws_vpc.webvpc.id
    availability_zone = "us-east-1a"
    cidr_block = var.subnet1acidr

    tags = {
      Name = "public_subnet_1a"
    }

}
resource "aws_subnet" "public_subnet_2" {
    vpc_id = aws_vpc.webvpc.id
    availability_zone = "us-east-1b"
    cidr_block = var.subnet1bcidr

    tags = {
      Name = "public_subnet_1b"
    }
}

resource "aws_internet_gateway" "myigw" {
    vpc_id = aws_vpc.webvpc.id
    
    tags = {
      Name = "igw"
    }
}

resource "aws_route_table" "igwroutetable" {
    vpc_id = aws_vpc.webvpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.myigw.id
    }
}

resource "aws_launch_template" "webseverlaunchtemplate" {
  name_prefix = "Webserver"
  image_id = data.aws_ami.ubuntu.id
  instance_type = "t3.micro" # for free tier friendly
  security_group_names = [aws_security_group.allow_instance_access.id]
}

resource "aws_autoscaling_group" "webserverautoscalingrp" {
    availability_zones = ["us-east-1a","us-east-1b"]
    desired_capacity   = 2
    max_size           = 2
    min_size           = 2

    launch_template {
        id      = aws_launch_template.webseverlaunchtemplate.id
        version = "$Latest"
    }
  
}

# I'll let it be manual and skip auto scaling policy  

##loadbalancer
resource "aws_lb" "Webserver_alb" {
  name               = "webserver-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_website_access.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  enable_deletion_protection = true

}


##loadbalancer listner
resource "aws_lb_listener" "Webserver" {
    load_balancer_arn = aws_lb.Webserver_alb.arn
    port              = "80"
    protocol          = "HTTP"
    default_action {
        type             = "forward"
        target_group_arn = aws_lb_target_group.webservertg.arn
    }
}
 ## TG
resource "aws_lb_target_group" "webservertg" {
  name     = "webservertg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.webvpc.id
}

## TG attachment
resource "aws_lb_target_group_attachment" "wedserverattach" {
 depends_on = [aws_instance.webserver]
  target_group_arn = aws_lb_target_group.webservertg.arn
  target_id        = aws_instance.webserver.id  
  port             = 8080
}
## instance 
resource "aws_instance" "webserver" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro" #freetier friendly
  security_groups = [aws_security_group.allow_instance_access.id]
  tags = {
    Name = "Webserver"
  }
}

## AMI For instance
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

## security Groups for Instance 
resource "aws_security_group" "allow_instance_access" {
  name        = "allow_instance_access"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.webvpc.id

  tags = {
    Name = "allow_instance_access"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4_inst" {
  security_group_id = aws_security_group.allow_instance_access.id
  cidr_ipv4         = aws_vpc.webvpc.cidr_block
  from_port         = 8080
  ip_protocol       = "tcp"
  to_port           = 8080
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4_inst" {
  security_group_id = aws_security_group.allow_instance_access.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

## security Groups for ALB 

resource "aws_security_group" "allow_website_access" {
  name        = "allow_website_access"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.webvpc.id
  tags = {
    Name = "allow_instance_access"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4_alb" {
  security_group_id = aws_security_group.allow_website_access.id
  cidr_ipv4         = "0.0.0.0/0"  ## assumingthere is no firewall etc as per scenario
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "allow_all_ipv4_alb" {
  security_group_id = aws_security_group.allow_website_access.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}



#iam user 

resource "aws_iam_user" "imarestarter" {
  name = "InstanceRestarteer"

  tags = {
    tag-key = "tag-value"
  }
}

data "aws_iam_policy_document" "ec2_restart" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:rebootInstances*"]
    resources = [aws_instance.webserver]
  }
}

resource "aws_iam_user_policy" "iam_policyattach" {
  name   = "test"
  user   = aws_iam_user.imarestarter.name
  policy = data.aws_iam_policy_document.ec2_restart.json
}




