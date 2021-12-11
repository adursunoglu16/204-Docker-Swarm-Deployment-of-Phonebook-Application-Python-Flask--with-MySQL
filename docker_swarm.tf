terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "3.68.0"
    }
  }
}
provider "aws" {
  region = "us-east-1"
  //  access_key = ""
  //  secret_key = ""
  //  If you have entered your credentials in AWS CLI before, you do not need to use these arguments.
}

locals {
    github-repo ="https://github.com/adursunoglu16/204-Docker-Swarm-Deployment-of-Phonebook-Application-Python-Flask--with-MySQL.git"
    github-file-url ="https://raw.githubusercontent.com/adursunoglu16/204-Docker-Swarm-Deployment-of-Phonebook-Application-Python-Flask--with-MySQL/master/"
}
data "aws_caller_identity" "current" {}

data "aws_region" "current" {
    name = "us-east-1"
}

data "template_file" "leader-master" {
    template = <<EOF
        #! /bin/bash
        yum update -y
        hostnamectl set-hostname Grand-Master
        amazon-linux-extras install docker -y
        systemctl start docker
        systemctl enable docker
        usermod -a -G docker ec2-user
        curl -L "https://github.com/docker/compose/releases/download/1.26.2/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        docker swarm init
        aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.ecr-repo.repository_url}
        docker service create \
          --name=viz \
          --publish=8080:8080/tcp \
          --constraint=node.role==manager \
          --mount=type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
          dockersamples/visualizer
        yum install git -y
        # uninstall aws cli version 1
        rm -rf /bin/aws
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        ./aws/install
        docker build --force-rm -t "${aws_ecr_repository.ecr-repo.repository_url}:latest" ${local.github-repo} 
        docker push "${aws_ecr_repository.ecr-repo.repository_url}:latest"
        mkdir -p /home/ec2-user/phonebook
        cd /home/ec2-user/phonebook && echo "ECR_REPO=${aws_ecr_repository.ecr-repo.repository_url} > .env
        curl -o "docker-compose.yml" -L ${local.github-file-url}docker-compose.yml
        curl -o "init.sql" -L ${local.github-file-url}init.sql
        docker-compose config | docker stack deploy --with-registry-auth -c - phonebook
    EOF    
}
data "template_file" "manager" {
    template = <<EOF
        #! /bin/bash
        yum update -y
        amazon-linux-extras install docker -y
        systemctl start docker
        systemctl enable docker
        usermod -a -G docker ec2-user
        curl -L "https://github.com/docker/compose/releases/download/1.26.2/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        yum install python3 -y
        amazon-linux-extras install epel -y
        yum install python-pip -y
        pip install ec2instanceconnectcli
        eval "$(mssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  \
        --region ${data.aws_region.current.name} ${aws_instance.docker-machine-leader-manager.id} docker swarm join-token manager | grep -i 'docker')"
        # uninstall aws cli version 1
        rm -rf /bin/aws
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        ./aws/install
    EOF
}

data "template_file" "worker" {
    template = <<EOF
        #! /bin/bash
        yum update -y
        amazon-linux-extras install docker -y
        systemctl start docker
        systemctl enable docker
        usermod -a -G docker ec2-user
        curl -L "https://github.com/docker/compose/releases/download/1.26.2/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        yum install python3 -y
        amazon-linux-extras install epel -y
        yum install python-pip -y
        pip install ec2instanceconnectcli
        eval "$(mssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  \
        --region ${data.aws_region.current.name} ${aws_instance.docker-machine-leader-manager.id} docker swarm join-token worker | grep -i 'docker')"
        # uninstall aws cli version 1
        rm -rf /bin/aws
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        ./aws/install
    EOF
}

resource "aws_ecr_repository" "ecr-repo" {
  name = "abdullah-repo/phonebook-app"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
  
}
## terraformda instance resource icinde role direkt olusturamiyoruz once role olusturcaz ardindan bu role u aws_iam_instance_profile a
## bagla ve sonra instance olustururken bunu instance a bagla.
resource "aws_iam_role" "ec2connectrole" {
  name = "ec2connectrole"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
  inline_policy {
    name   = "my_inline_policy"
    policy = jsonencode({
      "Version":"2012-10-17",
      "Statement":[ 
      { 
         "Effect":"Allow",
         "Action":"ec2-instance-connect:SendSSHPublicKey",
         "Resource": "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account.id}:instance/*",
         "Condition":{ 
            "StringEquals":{ 
               "ec2:osuser":"ec2-user"
            }
         }
      },
      {
        "Effect": "Allow",
        "Action": "ec2:DescribeInstances",
        "Resource": "*"
      }
   ]
    })
  }
    managed_policy_arns = ["arn:aws:iam:policy/AmazonEC2ContainerRegistryFullAccess"] 
}

resource "aws_iam_instance_profile" "ec2ecr-profile" {
  name = "swarmprofile"
  role = "aws_iam_role.ec2connectrole.name"
}

resource "aws_instance" "docker-machine-leader-manager" {
  ami = "xxxxxxxxxx"
  instance_type = "t2.micro"
  key_name = "pablokeys"
  root_block_device {
    volume_size = 16
  }
  security_groups = ["docker-swarm-sec-gr"]
  iam_instance_profile = aws_iam_instance_profile.ec2ecr-profile.name
  user_data = data.template_file.leader-master.rendered
  tags = {
    Name = "Docker-Swarm-Leader-Manager"
  }  
}

resource "aws_instance" "docker-machine-managers" {
  ami = "xxxxxxxxxx"
  instance_type = "t2.micro"
  key_name = "pablokeys"
  security_groups = ["docker-swarm-sec-gr"]
  iam_instance_profile = aws_iam_instance_profile.ec2ecr-profile.name
  count = 2
  user_data = data.template_file.manager.rendered
  tags = {
    Name = "Docker-Swarm-Manager-${count.index + 1}"
  }
  dependsdepends_on = [aws_instance.docker-machine-leader-manager]  
}

resource "aws_instance" "docker-machine-workers" {
  ami = "xxxxxxxxxx"
  instance_type = "t2.micro"
  key_name = "pablokeys"
  security_groups = ["docker-swarm-sec-gr"]
  iam_instance_profile = aws_iam_instance_profile.ec2ecr-profile.name
  count = 2
  user_data = data.template_file.worker.rendered
  tags = {
    Name = "Docker-Swarm-Worker-${count.index + 1}"
  }
  depends_on = [aws_instance.docker-machine-leader-manager]  
}

variable "sg-ports" {
  default = [80, 22, 2377, 7946, 8080]
}
resource "aws_security_group" "tf-docker-sec-gr" {
  name = "docker-swarm-sec-gr"
  tags = {
    Name = "swarm-sec-gr"
  }
  dynamic "ingress" {
    for_each = var.sg-ports
    content {
      from_port = ingress.value
      to_port = ingress.value
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  ingress {
    from_port = 7946
    protocol = "udp"
    to_port = 7946
    cidr_blocks = ["0.0.0.0/0"]
  } 

  ingress {
    from_port = 4789
    protocol = "udp"
    to_port = 4789
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  
}

output "leader-manager-public-ip" {
  value = aws_instance.docker-machine-leader-manager.public_ip
}

output "website-url" {
  value = "http://${aws_instance.docker-machine-leader-manager.public_ip}"
}

output "viz-url" {
  value = "http://${aws_instance.docker-machine-leader-manager.public_ip}:8080"
}

output "manager-public-ip" {
  value = aws_instance.docker-machine-managers.*.public_ip
}

output "worker-public-ip" {
  value = aws_instance.docker-machine-workers.*.public_ip
}

output "ecr-repo-url" {
  value = aws_ecr_repository.ecr-repo.repository_url
}