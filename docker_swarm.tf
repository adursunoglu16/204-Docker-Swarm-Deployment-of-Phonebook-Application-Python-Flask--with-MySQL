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
    github-file-url =""
}