terraform {
  required_version = ">= 0.12.0"
  backend "remote" {}
}

provider "aws" {
  region = var.region
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}

data "aws_availability_zones" "available" {
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

resource "aws_kms_key" "vault" {
  description             = "Vault unseal key"
  deletion_window_in_days = 10

  tags = {
    Name = "${var.cluster_name}-vault-key"
  }
}

data "terraform_remote_state" "vpc" {
  backend = "remote"
  config = {
    workspaces = {
      name = "net-dev"
    }
    hostname     = "app.terraform.io"
    organization = "jrx"
  }
}

module "eks" {
  source                       = "terraform-aws-modules/eks/aws"
  version                      = "16.0.0"
  cluster_version              = "1.19"
  cluster_name                 = var.cluster_name
  subnets                      = data.terraform_remote_state.vpc.outputs.aws_private_subnets
  manage_cluster_iam_resources = false
  cluster_iam_role_name        = "jrx-consul-eks"

  tags = {
    Owner = var.owner
    # Keep = ""
  }

  vpc_id = data.terraform_remote_state.vpc.outputs.aws_vpc_id

  worker_groups = [
    {
      name                          = "worker-group-1"
      instance_type                 = "m5.2xlarge"
      additional_userdata           = "echo foo bar"
      asg_desired_capacity          = 3
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_one.id]
    },
    # {
    #   name                          = "worker-group-2"
    #   instance_type                 = "t3.medium"
    #   additional_userdata           = "echo foo bar"
    #   additional_security_group_ids = [aws_security_group.worker_group_mgmt_two.id]
    #   asg_desired_capacity          = 1
    # },
  ]

  worker_additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]
  map_roles                            = var.map_roles
  map_users                            = var.map_users
  map_accounts                         = var.map_accounts
}