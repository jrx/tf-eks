mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:sts::123456789012:assumed-role/Deployment/test"
    }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_iam_session_context" {
    defaults = { issuer_arn = "arn:aws:iam::123456789012:role/Deployment" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
mock_provider "terraform" {}
mock_provider "cloudinit" {}
mock_provider "tls" {}
mock_provider "time" {}
mock_provider "random" {}
mock_provider "local" {}
mock_provider "null" {}

override_data {
  target = data.terraform_remote_state.vpc
  values = {
    outputs = {
      aws_vpc_id          = "vpc-00000000000000001"
      aws_private_subnets = ["subnet-00000000000000001", "subnet-00000000000000002"]
      aws_public_subnets  = ["subnet-00000000000000003", "subnet-00000000000000004"]
    }
  }
}

variables {
  iam_role         = "arn:aws:iam::123456789012:role/platform/EksControlPlane"
  autoscaling_role = "arn:aws:iam::123456789012:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
}

run "private_defaults" {
  command = plan
  assert {
    condition = (
      module.eks.cluster_version == "1.37" &&
      one(keys(module.eks.access_entries)) == "cluster_creator" &&
      module.eks.access_entries["cluster_creator"].principal_arn == "arn:aws:iam::123456789012:role/Deployment" &&
      module.eks.access_policy_associations["cluster_creator_admin"].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" &&
      one(module.eks.access_policy_associations["cluster_creator_admin"].access_scope).type == "cluster"
    )
    error_message = "A fresh cluster should use Kubernetes 1.37 and grant the deployment identity admin by default."
  }
}

run "laptop_admin" {
  command = plan
  variables {
    cluster_endpoint_public_access_cidrs = ["203.0.113.7/32"]
    cluster_operator_principal_arn       = "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/eu-north-1/AWSReservedSSO_Admin_1234"
  }
  assert {
    condition = (
      one(keys(module.eks.access_entries)) == "operator" &&
      module.eks.access_entries["operator"].principal_arn == var.cluster_operator_principal_arn &&
      module.eks.access_policy_associations["operator_admin"].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" &&
      one(module.eks.access_policy_associations["operator_admin"].access_scope).type == "cluster"
    )
    error_message = "The named IAM role should receive cluster-wide admin instead of the creator."
  }
}

run "network_only" {
  command = plan
  variables { cluster_endpoint_public_access_cidrs = ["203.0.113.0/24"] }
  assert {
    condition     = one(keys(module.eks.access_entries)) == "cluster_creator"
    error_message = "Allowlisting a network must not grant an operator access entry."
  }
}

run "identity_only" {
  command = plan
  variables { cluster_operator_principal_arn = "arn:aws:iam::123456789012:user/platform/Operator" }
  assert {
    condition     = one(keys(module.eks.access_entries)) == "operator" && module.eks.access_entries["operator"].principal_arn == var.cluster_operator_principal_arn
    error_message = "An IAM user can be the operator of a private cluster."
  }
}

run "invalid_control_plane_role" {
  command = plan
  variables { iam_role = "not-a-role" }
  expect_failures = [var.iam_role]
}

run "custom_autoscaling_role" {
  command = plan
  variables { autoscaling_role = "arn:aws:iam::123456789012:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling_custom" }
  expect_failures = [var.autoscaling_role]
}

run "wrong_autoscaling_account" {
  command = plan
  variables { autoscaling_role = "arn:aws:iam::987654321098:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling" }
  expect_failures = [data.aws_iam_session_context.deployment]
}

run "wrong_control_plane_account" {
  command = plan
  variables { iam_role = "arn:aws:iam::987654321098:role/platform/EksControlPlane" }
  expect_failures = [data.aws_iam_session_context.deployment]
}

run "session_operator" {
  command = plan
  variables { cluster_operator_principal_arn = "arn:aws:sts::123456789012:assumed-role/Operator/session" }
  expect_failures = [var.cluster_operator_principal_arn]
}

run "service_linked_operator" {
  command = plan
  variables { cluster_operator_principal_arn = "arn:aws:iam::123456789012:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling" }
  expect_failures = [var.cluster_operator_principal_arn]
}

run "malformed_cidr" {
  command = plan
  variables { cluster_endpoint_public_access_cidrs = ["203.0.113.7"] }
  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}

run "ipv6_cidr" {
  command = plan
  variables { cluster_endpoint_public_access_cidrs = ["2001:db8::/64"] }
  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}

run "unrestricted_cidr" {
  command = plan
  variables { cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"] }
  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}

run "cidr_has_host_bits" {
  command = plan
  variables { cluster_endpoint_public_access_cidrs = ["203.0.113.7/24"] }
  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}
