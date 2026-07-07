variable "aws_region" {
  description = "Home region for all MakanLah infrastructure (see ADR-006)"
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "GitHub <owner>/<repo> allowed to assume the CI roles via OIDC"
  type        = string
  default     = "raynerC/makanlah-platform"
}

variable "project" {
  description = "Project slug used to prefix resource names"
  type        = string
  default     = "makanlah"
}
