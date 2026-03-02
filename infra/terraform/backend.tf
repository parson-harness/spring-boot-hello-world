terraform {
  backend "s3" {
    bucket         = "spring-boot-hello-world-terraform-state-dev"
    key            = "asg/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "spring-boot-hello-world-terraform-locks-dev"
    encrypt        = true
  }
}
