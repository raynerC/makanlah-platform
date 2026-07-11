variable "name" {
  description = "Prefix for all network resource names"
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones (public+private subnet pair per AZ)"
  type        = number
  default     = 2
}
