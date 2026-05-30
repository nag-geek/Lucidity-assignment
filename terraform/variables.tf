variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "cicd_iam_user" {
  description = "IAM user name used by CI/CD pipeline"
  type        = string
}
