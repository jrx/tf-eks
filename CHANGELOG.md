# Changelog

## Unreleased

### Breaking changes

- Target fresh deployments of EKS Kubernetes 1.37 with EKS module 21.30.2 and KMS module 4.2.2. Use a new workspace and a `cluster_name` that no earlier deployment in the same AWS account uses. IAM names conflict across regions. This release does not support upgrading an existing cluster in place. Keep the earlier deployment and its Vault unseal key until the new cluster is verified. See [Replace an existing deployment](README.md#replace-an-existing-deployment).
- Require Terraform 1.7.0 or newer and AWS provider 6.x, version 6.59 or newer. Commit the provider lock file. Remove the unused Kubernetes provider and deployment token lookup.
- Require the existing control-plane role ARN (`iam_role`) and the deployment account's default Auto Scaling service-linked role ARN (`autoscaling_role`). Both roles must be in the deployment account and partition.
- Disable the public Kubernetes API endpoint by default. Set `cluster_endpoint_public_access_cidrs` to allow specific IPv4 sources. Private access stays enabled.
- Set `cluster_operator_principal_arn` to grant a permanent IAM user or role cluster-wide Kubernetes admin **instead of** the deployment identity. Omit it to keep creator admin.

Workers use the standard Amazon Linux 2023 bootstrap without the old example shell commands. VPC CNI can start installing before the self-managed node group. See the [deployment and laptop access instructions](README.md).
