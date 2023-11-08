terraform {
  required_version = ">= 0.12.0"
  backend "remote" {}
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
  depends_on = [
    module.eks.cluster_endpoint
  ]
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  token = data.aws_eks_cluster_auth.cluster.token
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
  source                          = "terraform-aws-modules/eks/aws"
  version                         = "19.19.0"
  cluster_version                 = "1.28"
  cluster_name                    = var.cluster_name
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  vpc_id     = data.terraform_remote_state.vpc.outputs.aws_vpc_id
  subnet_ids = data.terraform_remote_state.vpc.outputs.aws_private_subnets

  # Self managed node groups will not automatically create the aws-auth configmap so we need to
  create_aws_auth_configmap = true
  manage_aws_auth_configmap = true
  create_iam_role           = false
  iam_role_arn              = var.iam_role

  cluster_security_group_additional_rules = {
    ingress = {
      description = "inter-cluster connections"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = [
        "10.0.0.0/8",
        "172.16.0.0/12",
        "172.20.0.0/16",
        "172.25.16.0/20",
        "192.168.0.0/16",
      ]
      type = "ingress"
    }
  }

  node_security_group_enable_recommended_rules = true
  node_security_group_additional_rules = {
    ingress = {
      description = "inter-cluster connections"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = [
        "10.0.0.0/8",
        "172.16.0.0/12",
        "172.20.0.0/16",
        "172.25.16.0/20",
        "192.168.0.0/16",
      ]
      type = "ingress"
    }
  }

  tags = {
    Owner = var.owner
    # Keep = ""
  }

  self_managed_node_groups = {
    complete = {
      name            = "${var.cluster_name}-eks-node"
      use_name_prefix = false

      subnet_ids = data.terraform_remote_state.vpc.outputs.aws_private_subnets

      min_size     = 1
      max_size     = 7
      desired_size = 3

      pre_bootstrap_user_data = <<-EOT
        export FOO=bar
      EOT

      post_bootstrap_user_data = <<-EOT
        echo "you are free little kubelet!"
      EOT

      instance_type = "m5.2xlarge"

      launch_template_name            = "self-managed-ex"
      launch_template_use_name_prefix = true
      launch_template_description     = "Self managed node group example launch template"

      ebs_optimized     = true
      enable_monitoring = true

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 75
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 150
            encrypted             = true
            kms_key_id            = module.ebs_kms_key.key_arn
            delete_on_termination = true
          }
        }
      }

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
        instance_metadata_tags      = "disabled"
      }

      create_iam_role          = true
      iam_role_name            = "${var.cluster_name}-eks-node"
      iam_role_use_name_prefix = false
      iam_role_description     = "Self managed node group complete example role"
      iam_role_tags = {
        Purpose = "Protector of the kubelet"
      }
      iam_role_additional_policies = {
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        AmazonEBSCSIDriverPolicy           = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
        additional                         = aws_iam_policy.vault-policy.arn
      }

      timeouts = {
        create = "80m"
        update = "80m"
        delete = "80m"
      }

      tags = {
        ExtraTag = "Self managed node group complete example"
      }
    }

  }
}

module "ebs_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 1.5"

  description = "Customer managed key to encrypt EKS managed node group volumes"

  # Policy
  key_administrators = [
    data.aws_caller_identity.current.arn
  ]

  key_service_roles_for_autoscaling = [
    # required for the ASG to manage encrypted volumes for nodes
    var.autoscaling_role,
    # required for the cluster / persistentvolume-controller to create encrypted PVCs
    var.iam_role
  ]

  # Aliases
  aliases = ["eks/${var.cluster_name}/ebs"]

  tags = {
    Owner = var.owner
    # Keep = ""
  }
}