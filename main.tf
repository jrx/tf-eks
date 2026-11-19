terraform {
  backend "remote" {}
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_iam_session_context" "deployment" {
  arn = data.aws_caller_identity.current.arn

  lifecycle {
    precondition {
      condition     = startswith(var.autoscaling_role, "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:")
      error_message = "Supply the default Auto Scaling service-linked role from the same AWS account and partition as the deployment."
    }
  }
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
      name = "net"
    }
    hostname     = "app.terraform.io"
    organization = "jrxhc"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.30.2"

  name                         = var.cluster_name
  kubernetes_version           = "1.37"
  endpoint_private_access      = true
  endpoint_public_access       = length(var.cluster_endpoint_public_access_cidrs) > 0
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  enable_cluster_creator_admin_permissions = var.cluster_operator_principal_arn == null
  access_entries = var.cluster_operator_principal_arn == null ? {} : {
    operator = {
      principal_arn = var.cluster_operator_principal_arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      before_compute = true
      most_recent    = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  vpc_id                   = data.terraform_remote_state.vpc.outputs.aws_vpc_id
  subnet_ids               = data.terraform_remote_state.vpc.outputs.aws_private_subnets
  control_plane_subnet_ids = data.terraform_remote_state.vpc.outputs.aws_public_subnets

  create_iam_role = false
  iam_role_arn    = var.iam_role

  security_group_additional_rules = {
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

      autoscaling_group_tags = {
        "k8s.io/cluster-autoscaler/enabled"             = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      }

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

      create_iam_instance_profile = true
      iam_role_name               = "${var.cluster_name}-eks-node"
      iam_role_use_name_prefix    = false
      iam_role_description        = "Self managed node group complete example role"
      iam_role_tags = {
        Purpose = "Protector of the kubelet"
      }
      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
        additional               = aws_iam_policy.vault-policy.arn
      }

      timeouts = {
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
  version = "4.2.2"

  description = "Customer managed key to encrypt EKS self-managed node volumes"

  # Policy
  key_administrators = [
    data.aws_iam_session_context.deployment.issuer_arn
  ]

  key_service_roles_for_autoscaling = [
    # required for the ASG to manage encrypted volumes for nodes
    var.autoscaling_role,
    var.iam_role
  ]

  # Aliases
  aliases = ["eks/${var.cluster_name}/ebs"]

  tags = {
    Owner = var.owner
    # Keep = ""
  }
}
