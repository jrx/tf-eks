variable "cluster_name" {
  type        = string
  description = "Name of the cluster."
  default     = "myexample"
}

variable "owner" {
  type        = string
  description = "Owner tag on all resources."
  default     = "myuser"
}

variable "region" {
  description = "AWS region in which to deploy the cluster."
  type        = string
  default     = "eu-north-1"
}

variable "autoscaling_role" {
  description = "ARN of the deployment account's existing default Auto Scaling service-linked role."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:[a-z0-9-]+:iam::[0-9]{12}:role/aws-service-role/autoscaling[.]amazonaws[.]com/AWSServiceRoleForAutoScaling$", var.autoscaling_role))
    error_message = "Supply the ARN of the default AWSServiceRoleForAutoScaling service-linked role, not a custom-suffix role."
  }
}

variable "iam_role" {
  description = "ARN of the existing IAM role that EKS assumes to manage the control plane."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:[a-z0-9-]+:iam::[0-9]{12}:role/([!-~]+/)?[A-Za-z0-9_+=,.@-]{1,64}$", var.iam_role))
    error_message = "Supply the permanent IAM role ARN for the EKS control plane, including its path if present."
  }
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "IPv4 networks allowed to reach the public Kubernetes API endpoint. An empty list disables public access."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([for cidr in var.cluster_endpoint_public_access_cidrs : try(
      cidrnetmask(cidr) != "0.0.0.0" && cidrhost(cidr, 0) == split("/", cidr)[0], false
    )])
    error_message = "Use IPv4 network addresses narrower than /0. Use your public address with /32 for one laptop, a network address such as 203.0.113.0/24 for a range, or [] for private-only access."
  }
}

variable "cluster_operator_principal_arn" {
  description = "Permanent IAM user or role ARN to grant Kubernetes cluster-admin instead of the Terraform deployment identity."
  type        = string
  default     = null

  validation {
    condition = var.cluster_operator_principal_arn == null ? true : (
      can(regex("^arn:[a-z0-9-]+:iam::[0-9]{12}:(user|role)/([!-~]+/)?[A-Za-z0-9_+=,.@-]{1,64}$", var.cluster_operator_principal_arn)) &&
      !can(regex(":role/aws-service-role/", var.cluster_operator_principal_arn))
    )
    error_message = "Supply a permanent IAM user or role ARN, not an STS session or service-linked role ARN, or omit it for creator admin."
  }
}