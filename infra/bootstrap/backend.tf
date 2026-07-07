# Added after the first (local-state) apply created the bucket, then migrated
# with: terraform init -migrate-state
terraform {
  backend "s3" {
    bucket       = "makanlah-tfstate-022440376627"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
