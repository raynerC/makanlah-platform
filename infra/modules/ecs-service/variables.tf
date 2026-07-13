variable "name" {
  description = "Service name (also used for roles, SG, log group)"
  type        = string
}

variable "cluster_arn" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "image" {
  description = "Full image URI incl. tag"
  type        = string
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "max_count" {
  description = "Autoscaling ceiling"
  type        = number
  default     = 4
}

variable "container_port" {
  type    = number
  default = 8000
}

variable "environment" {
  description = "Plain environment variables"
  type        = map(string)
  default     = {}
}

variable "task_policy_json" {
  description = "Least-privilege IAM policy JSON for the application (task role)"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "target_group_arn" {
  description = "ALB target group; null for background workers"
  type        = string
  default     = null
}

variable "enable_request_scaling" {
  description = "Scale on ALB requests-per-target (primary signal for exposed services). Must be a literal bool, not a computed value"
  type        = bool
  default     = false
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix — required when enable_request_scaling"
  type        = string
  default     = null
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix — required when enable_request_scaling"
  type        = string
  default     = null
}

variable "requests_per_target" {
  description = "Target requests/minute per task before scaling out"
  type        = number
  default     = 600
}

variable "alb_security_group_id" {
  description = "Required when target_group_arn is set"
  type        = string
  default     = null
}

variable "log_retention_days" {
  type    = number
  default = 7
}
