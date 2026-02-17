variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "staging"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be 'staging' or 'production'."
  }
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "jwt_secret" {
  type      = string
  sensitive = true
}

variable "apple_team_id" {
  type      = string
  sensitive = true
}

variable "google_client_id" {
  type      = string
  sensitive = true
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for HTTPS on ALB"
}
