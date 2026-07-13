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

variable "public_subnet_tags" {
  description = "Extra tags (e.g. kubernetes.io/role/elb for the AWS Load Balancer Controller)"
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Extra tags (e.g. kubernetes.io/role/internal-elb)"
  type        = map(string)
  default     = {}
}
