terraform {
  backend "s3" {
    bucket       = "makanlah-tfstate-022440376627"
    key          = "envs/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
