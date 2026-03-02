# Backend configuration is provided via backend.hcl file
# This allows multiple POVs to use different state buckets
# See backend.hcl.example for configuration options
terraform {
  backend "s3" {
    key = "eks/terraform.tfstate"
  }
}
