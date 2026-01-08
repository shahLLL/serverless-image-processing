# Variables that are essential for the project.
variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-west-2"
}

variable "email_endpoint" {
  description = "Email address for SNS notifications"
  type        = string
  default     = "shahLLL@yahoo.com"
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "ServerlessImageProcessing"
}