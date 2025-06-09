# variables.tf

variable "project" {
  description = "The name of the project."
  type        = string
  default     = "mystore"
}

variable "environment" {
  description = "The deployment environment (e.g., staging, production)."
  type        = string
  default     = "staging"
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "backend_container_image" {
  description = "The full URI of the backend container image in ECR."
  type        = string
}

variable "owner" {
  description = "The owner of the resources."
  type        = string
}