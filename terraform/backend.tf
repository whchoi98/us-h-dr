terraform {
  backend "s3" {
    bucket         = "us-h-dr-terraform-state"
    key            = "multi-region-dr/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
