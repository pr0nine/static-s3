terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
# The required alias provider for the us-east-1 certificate
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}
