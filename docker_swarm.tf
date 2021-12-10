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
data "template_file" "manager"