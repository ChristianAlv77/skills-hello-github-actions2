terraform {
  backend "s3" {
    bucket = "pruebachrisbucket"
    key    = "infra.tfstate"
    region = "us-east-1"
    
  }
}