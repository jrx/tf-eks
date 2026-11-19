# Elastic Kubernetes Service

This Terraform root deploys a **new** Amazon EKS Kubernetes 1.37 cluster with `terraform-aws-modules/eks/aws` 21.30.2 and `terraform-aws-modules/kms/aws` 4.2.2. Use an empty deployment workspace, not an existing cluster's state. This release does not provide an in-place upgrade path.

## Before deployment

- Use Terraform 1.7.0 or newer and the HashiCorp AWS provider 6.x, version 6.59 or newer. The committed `.terraform.lock.hcl` selects the tested provider versions. Configure this root's `remote` backend for your deployment workspace.
- Grant the deployment workspace read access to the **separate** HCP Terraform workspace `jrxhc/net` on `app.terraform.io`. Its `aws_vpc_id`, `aws_private_subnets`, and `aws_public_subnets` outputs must refer to an EKS-ready VPC in the deployment region (default `eu-north-1`). Workers use the private subnets. The public subnets host the EKS control-plane interfaces; this alone does not make the API public.
- Supply `iam_role`, an existing [EKS control-plane role](https://docs.aws.amazon.com/eks/latest/userguide/cluster-iam-role.html) that trusts `eks.amazonaws.com` and has cluster permissions. Terraform does not create this role or attach its policies.
- Supply `autoscaling_role`, the deployment account's default `AWSServiceRoleForAutoScaling`. Ensure the role exists **before** Terraform creates the node-volume key. A custom-suffix role will not work: the node group uses the default role to [launch instances with encrypted volumes](https://docs.aws.amazon.com/autoscaling/ec2/userguide/key-policy-requirements-EBS-encryption.html).
- The Terraform deployment identity needs provisioning permissions, including `iam:PassRole` for the cluster role and `kms:DescribeKey` and `kms:CreateGrant` for [cluster creation with KMS encryption](https://docs.aws.amazon.com/eks/latest/userguide/enable-kms.html). These are prerequisites, not a complete provisioning policy. Its permanent IAM identity administers the separate node-volume key.

## Replace an existing deployment

A new workspace has its own state, but AWS names are not. Several names derive from `cluster_name` and do not use a random prefix:

- Unique in the whole AWS account, in every region: the node IAM role and instance profile (`<cluster_name>-eks-node`), and the Vault role and policy (`<cluster_name>-vault-kms-role`, `<cluster_name>-vault-policy`).
- Unique per region: the EKS cluster, the Auto Scaling group (`<cluster_name>-eks-node`), the KMS aliases under `alias/eks/<cluster_name>`, and the log group `/aws/eks/<cluster_name>/cluster`.

If an earlier deployment uses the same `cluster_name` in the same account, apply fails because these names already exist. A different region does not avoid the IAM name conflicts.

1. Set a `cluster_name` that no earlier deployment in the account uses, so both deployments can run side by side.
2. Do not point this release at the earlier deployment's workspace or state.
3. Keep the earlier workspace, its Vault unseal key, and its workloads until you have moved and verified everything on the new cluster. The new deployment creates a new Vault unseal key, which cannot decrypt data sealed with the old key. Keep the old key enabled until you have verified recovery from every Vault backup you need. Once [deletion is scheduled](https://docs.aws.amazon.com/kms/latest/developerguide/deleting-keys.html), the key can no longer unseal Vault, and it is deleted after its 10-day waiting period.
4. To retire the earlier deployment, check out the commit it was deployed from and start a destroy run in its workspace. Review the full destroy plan in that run and get approval before you apply the same run.

Copy [`terraform.tfvars.example`](terraform.tfvars.example) to `terraform.tfvars` for a local run, or set the equivalent Terraform variables in the deployment workspace. Replace the example account, roles, and address. Keep credentials out of variable files.

## Administer the cluster from a laptop

1. Select the AWS CLI profile you will use with `kubectl`. Run `aws sts get-caller-identity --profile my-profile --query Arn --output text`. For an IAM user, use the returned ARN. For an STS assumed-role session, obtain the **permanent IAM role ARN**, including its path, from IAM or your administrator. Do not paste the STS ARN or guess an Identity Center role's path.
2. Set `cluster_operator_principal_arn` to that IAM ARN. Everyone who can assume the named role receives **cluster-wide Kubernetes admin**. The module does not also grant creator admin. If you omit this variable, the Terraform deployment identity receives cluster-admin instead; that may not be your laptop profile. Kubernetes admin does not grant AWS permissions. Your laptop profile separately needs IAM `eks:DescribeCluster` on the cluster. For an operator in another AWS account, see step 4.
3. Set `cluster_endpoint_public_access_cidrs` to your network's public egress IPv4 address with `/32`. Update the input and redeploy if your ISP or VPN changes this address. For an intentional range, use the IPv4 network address and prefix. Omitting this input leaves the public endpoint off. The allowlist alone grants no Kubernetes permissions.
4. After deployment, replace the profile, region, and cluster name below with your values. The final command should return `yes` for the configured administrator. If the operator IAM identity is in a different AWS account than the cluster, `update-kubeconfig` looks up the cluster in the profile's own account. Add `--assume-role-arn` with a role in the cluster account that allows `eks:DescribeCluster`. In that case the laptop profile needs permission to assume that role, not `eks:DescribeCluster` itself. The kubeconfig still authenticates to Kubernetes as the operator profile.

   ```sh
   export AWS_PROFILE=my-profile
   aws eks update-kubeconfig --region eu-north-1 --name myexample
   kubectl auth can-i '*' '*' --all-namespaces
   ```

Private API access stays on. Without public access, your laptop needs a route into the VPC, working private DNS, and security-group access. The cluster and node security groups intentionally allow all protocols from the existing private IPv4 ranges (`10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16`, including the two more specific configured ranges). The public endpoint allowlist does not restrict that private traffic.

## Nodes and add-ons

The self-managed group uses `m5.2xlarge` workers with standard Amazon Linux 2023 bootstrap. It starts with three workers and allows one to seven. Each worker requires IMDSv2 and has a 75 GiB encrypted `gp3` root volume. The EKS module configures secret encryption and API, audit, and authenticator logs. The node-volume key does not by itself grant the EBS CSI driver access to encrypted persistent volumes.

EKS selects the latest compatible VPC CNI, CoreDNS, `kube-proxy`, and EBS CSI add-ons. VPC CNI does not wait for the node group; this ordering does not guarantee network readiness.

## Test

The tests in `tests/` run in plan mode against mocked providers. They need Terraform 1.7.0 or newer and no AWS credentials. They check module logic, not real AWS behavior.

`terraform test` also loads `terraform.tfvars`, `*.auto.tfvars`, and `TF_VAR_*` environment variables. The test file overrides only `iam_role` and `autoscaling_role`. Run the tests in a clean checkout without deployment variable files or `TF_VAR_*` values. Otherwise, values such as `cluster_operator_principal_arn` leak into the default runs, and the tests no longer check the defaults.

The upstream EKS module does not output the endpoint access flags, so `tests/endpoints.jq` checks the planned `aws_eks_cluster` resource. Run both checks with one command so a failure in either one fails the pipeline:

```sh
terraform init -backend=false
set -o pipefail
terraform test -filter=tests/upgrade.tftest.hcl -json -verbose | jq -es -f tests/endpoints.jq
```

The final output must be `true`.

## License

[Mozilla Public License v2.0](./LICENSE)
