terraform {
  backend "s3" {
    bucket         = "vineeth-s3-snake-game"
    key            = "eks/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-lock-table"
    encrypt        = true
  }
}

