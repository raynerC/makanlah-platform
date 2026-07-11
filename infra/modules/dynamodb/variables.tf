variable "name" {
  description = "Table name"
  type        = string
}

variable "hash_key" {
  description = "Partition key attribute (type S)"
  type        = string
}

variable "range_key" {
  description = "Optional sort key attribute (type S)"
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Protect the table from deletion (off in dev so `make nuke` works)"
  type        = bool
  default     = false
}
