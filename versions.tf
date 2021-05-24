terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 2.28.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 1.11"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 1.2"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 2.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 2.1"
    }
  }
  required_version = ">= 0.13"
}
