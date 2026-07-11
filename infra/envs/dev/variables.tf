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
