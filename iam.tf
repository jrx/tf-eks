data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Vault

resource "aws_iam_role" "vault_kms_unseal_role" {
  name               = "${var.cluster_name}-vault-kms-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "vault-kms-unseal" {
  statement {
    sid       = "VaultKMSUnseal"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
      "ec2:DescribeInstances",
      "iam:GetRole",
    ]
  }
}

resource "aws_iam_policy" "vault-policy" {
  name   = "${var.cluster_name}-vault-policy"
  policy = data.aws_iam_policy_document.vault-kms-unseal.json
}
