# Elastic Kubernetes Service

This Terraform root deploys a **new** Amazon EKS Kubernetes 1.37 cluster with `terraform-aws-modules/eks/aws` 21.30.2 and `terraform-aws-modules/kms/aws` 4.2.2. Use an empty deployment workspace, not an existing cluster's state. This release does not provide an in-place upgrade path.

## Before deployment

- Use Terraform 1.5.7 or newer and the HashiCorp AWS provider 6.59 or newer. Configure this root's `remote` backend for your deployment workspace. Use `terraform init -upgrade` in your fresh deployment if an old local provider lock selects AWS 5.x.
- Grant the deployment workspace read access to the **separate** HCP Terraform workspace `jrxhc/net` on `app.terraform.io`. Its `aws_vpc_id`, `aws_private_subnets`, and `aws_public_subnets` outputs must refer to an EKS-ready VPC in the deployment region (default `eu-north-1`). Workers use the private subnets. The public subnets host the EKS control-plane interfaces; this alone does not make the API public.
- Supply `iam_role`, an existing [EKS control-plane role](https://docs.aws.amazon.com/eks/latest/userguide/cluster-iam-role.html) that trusts `eks.amazonaws.com` and has cluster permissions. Terraform does not create this role or attach its policies.
- Supply `autoscaling_role`, the deployment account's default `AWSServiceRoleForAutoScaling`. Ensure the role exists **before** Terraform creates the node-volume key. A custom-suffix role will not work: the node group uses the default role to [launch instances with encrypted volumes](https://docs.aws.amazon.com/autoscaling/ec2/userguide/key-policy-requirements-EBS-encryption.html).
- The Terraform deployment identity needs provisioning permissions, including `iam:PassRole` for the cluster role and `kms:DescribeKey` and `kms:CreateGrant` for [cluster creation with KMS encryption](https://docs.aws.amazon.com/eks/latest/userguide/enable-kms.html). These are prerequisites, not a complete provisioning policy. Its permanent IAM identity administers the separate node-volume key.

Copy [`terraform.tfvars.example`](terraform.tfvars.example) to `terraform.tfvars` for a local run, or set the equivalent Terraform variables in the deployment workspace. Replace the example account, roles, and address. Keep credentials out of variable files.

## Administer the cluster from a laptop

1. Select the AWS CLI profile you will use with `kubectl`. Run `aws sts get-caller-identity --profile my-profile --query Arn --output text`. For an IAM user, use the returned ARN. For an STS assumed-role session, obtain the **permanent IAM role ARN**, including its path, from IAM or your administrator. Do not paste the STS ARN or guess an Identity Center role's path.
2. Set `cluster_operator_principal_arn` to that IAM ARN. Everyone who can assume the named role receives **cluster-wide Kubernetes admin**. The module does not also grant creator admin. If you omit this variable, the Terraform deployment identity receives cluster-admin instead; that may not be your laptop profile. Kubernetes admin does not grant AWS permissions. Your laptop profile separately needs IAM `eks:DescribeCluster`.
3. Set `cluster_endpoint_public_access_cidrs` to your network's public egress IPv4 address with `/32`. Update the input and redeploy if your ISP or VPN changes this address. For an intentional range, use the IPv4 network address and prefix. Omitting this input leaves the public endpoint off. The allowlist alone grants no Kubernetes permissions.
4. After deployment, replace the profile, region, and cluster name below with your values. The final command should return `yes` for the configured administrator.

   ```sh
   export AWS_PROFILE=my-profile
   aws eks update-kubeconfig --region eu-north-1 --name myexample
   kubectl auth can-i '*' '*' --all-namespaces
   ```

Private API access stays on. Without public access, your laptop needs a route into the VPC, working private DNS, and security-group access. The cluster and node security groups intentionally allow all protocols from the existing private IPv4 ranges (`10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16`, including the two more specific configured ranges). The public endpoint allowlist does not restrict that private traffic.

## Nodes and add-ons

The self-managed group uses `m5.2xlarge` workers with standard Amazon Linux 2023 bootstrap. It starts with three workers and allows one to seven. Each worker requires IMDSv2 and has a 75 GiB encrypted `gp3` root volume. The EKS module configures secret encryption and API, audit, and authenticator logs. The node-volume key does not by itself grant the EBS CSI driver access to encrypted persistent volumes.

EKS selects the latest compatible VPC CNI, CoreDNS, `kube-proxy`, and EBS CSI add-ons. VPC CNI does not wait for the node group; this ordering does not guarantee network readiness.

## License

[Mozilla Public License v2.0](./LICENSE)
