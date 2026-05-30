terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "lucidity-tf-state-yourname-1234" # Ensure this bucket is created FIRST
    key            = "eks/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-state-lock"            # Create a DynamoDB table with Partition Key 'LockID'
    encrypt        = true                              # Encrypts state file at rest in S3
  }
}

provider "aws" {
  region = var.region
}

resource "aws_ecr_repository" "hello_world" {
  name                 = "hello-world"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
