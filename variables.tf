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
  default = "eu-north-1"
}

variable "iam_role" {
  default = "arn:aws:iam::996575707302:role/jrx-consul-eks"
}