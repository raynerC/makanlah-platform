variable "name" {
  description = "Queue name (DLQ becomes <name>-dlq)"
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "How long a received message stays invisible before retry"
  type        = number
  default     = 30
}

variable "max_receive_count" {
  description = "Receives before a message is moved to the DLQ"
  type        = number
  default     = 3
}
