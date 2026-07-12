variable "project" {
  type    = string
  default = "makanlah"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "image_tag" {
  description = "Image tag deployed for all services"
  type        = string
  default     = "dev"
}

variable "alert_email" {
  description = "Recipient for CloudWatch alarm notifications"
  type        = string
  default     = "raynerc.sm18@gmail.com"
}
