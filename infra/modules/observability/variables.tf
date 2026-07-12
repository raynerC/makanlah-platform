variable "name" {
  description = "Prefix for topic, alarms, and dashboard name"
  type        = string
}

variable "alert_email" {
  description = "Where alarm notifications go (subscription requires email confirmation)"
  type        = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "queue_name" {
  type = string
}

variable "dlq_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "service_names" {
  description = "ECS service names to watch for crash-loops and chart"
  type        = list(string)
}

variable "p95_threshold_seconds" {
  description = "Latency SLO used by the p95 alarm and dashboard annotation"
  type        = number
  default     = 0.8
}
