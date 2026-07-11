variable "name" {
  description = "Load balancer name prefix"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "services" {
  description = "Routed services: key -> target group + listener rule settings"
  type = map(object({
    port          = number
    health_path   = string
    path_patterns = list(string)
    priority      = number
  }))
}

variable "waf_rate_limit" {
  description = "Max requests per IP per 5-minute window before blocking"
  type        = number
  default     = 500
}
