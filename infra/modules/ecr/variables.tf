variable "name_prefix" {
  description = "Registry namespace, e.g. makanlah"
  type        = string
}

variable "repositories" {
  description = "Repository names to create under the prefix"
  type        = list(string)
}

variable "keep_last_images" {
  description = "Lifecycle policy: number of images to retain per repo"
  type        = number
  default     = 10
}
