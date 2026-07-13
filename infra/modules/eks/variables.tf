variable "name" {
  description = "Cluster name"
  type        = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.33"
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "instance_types" {
  type    = list(string)
  default = ["t3.small", "t3a.small"] # multiple types = better spot availability
}

variable "node_count" {
  type    = number
  default = 2
}
