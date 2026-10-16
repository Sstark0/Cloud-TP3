terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }

    andom = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}
