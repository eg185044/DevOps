variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "erez-cv-devops"
}

variable "owner" {
  description = "Owner tag"
  type        = string
  default     = "Erez Glik"
}

variable "ami_id" {
  description = "Optional Ubuntu AMI ID. If empty, latest Ubuntu 22.04 LTS is used."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type for all Linux servers"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Existing AWS EC2 key pair name"
  type        = string
  default     = "erezg01"
}

variable "allowed_ssh_cidr" {
  description = "Your public IP CIDR for SSH, for example 1.2.3.4/32"
  type        = string
}

variable "db_name" {
  description = "RDS database name"
  type        = string
  default     = "erezcv"
}

variable "db_username" {
  description = "RDS database username"
  type        = string
  default     = "erezadmin"
}

variable "db_password" {
  description = "RDS database password. Keep this out of Git."
  type        = string
  sensitive   = true
}

variable "sns_email" {
  description = "Email address for SNS subscription"
  type        = string
}

variable "create_rds" {
  description = "Create RDS PostgreSQL for the microservice demo"
  type        = bool
  default     = true
}
