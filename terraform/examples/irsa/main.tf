# The same transcoder role, wired with IRSA instead of Pod Identity.
# Use this on Fargate, or anywhere Pod Identity is not available.

terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

variable "cluster_name" {
  type = string
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "tls_certificate" "oidc" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# Once per cluster: tell IAM to trust tokens signed by this cluster.
resource "aws_iam_openid_connect_provider" "eks" {
  url             = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}

locals {
  oidc_host = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

# The trust policy names this cluster's OIDC provider. A second cluster
# means a second provider and another statement here.
data "aws_iam_policy_document" "irsa_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:video:transcoder"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "transcoder" {
  name               = "video-pipeline-transcoder-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust.json
}

# Then annotate the service account (not managed by Terraform here):
#   eks.amazonaws.com/role-arn: <aws_iam_role.transcoder.arn>
output "service_account_annotation" {
  value = "eks.amazonaws.com/role-arn: ${aws_iam_role.transcoder.arn}"
}
