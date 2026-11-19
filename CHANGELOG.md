# Changelog

## Unreleased

### Breaking changes

- Target fresh deployments of EKS Kubernetes 1.37 with EKS module 21.30.2 and KMS module 4.2.2. Use a new workspace. This release does not support upgrading an existing cluster in place.
- Require Terraform 1.5.7 or newer and AWS provider 6.59 or newer. Remove the unused Kubernetes provider and deployment token lookup.
- Require the existing control-plane role ARN (`iam_role`) and the deployment account's default Auto Scaling service-linked role ARN (`autoscaling_role`).
- Disable the public Kubernetes API endpoint by default. Set `cluster_endpoint_public_access_cidrs` to allow specific IPv4 sources. Private access stays enabled.
- Set `cluster_operator_principal_arn` to grant a permanent IAM user or role cluster-wide Kubernetes admin **instead of** the deployment identity. Omit it to keep creator admin.

Workers use the standard Amazon Linux 2023 bootstrap without the old example shell commands. VPC CNI can start installing before the self-managed node group. See the [deployment and laptop access instructions](README.md).
