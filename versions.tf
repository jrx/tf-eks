terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 2.28.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.21.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5.1"
    }
  }
  required_version = ">= 0.13"
}