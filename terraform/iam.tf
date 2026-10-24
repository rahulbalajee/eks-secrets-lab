# ---------------------------------------------------------------------------
# EKS Pod Identity. The agent runs on every node and hands short-lived
# credentials to pods whose service account has an association.
# ---------------------------------------------------------------------------

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = var.cluster_name
  addon_name   = "eks-pod-identity-agent"
}

# One trust policy works for every cluster: the principal is the EKS Pod
# Identity service, not a per-cluster OIDC provider. The conditions use the
# session tags Pod Identity adds, so the role only works for the service
# account it was made for, even if someone associates it elsewhere.
data "aws_iam_policy_document" "pod_identity_trust" {
  for_each = {
    eso        = { namespace = var.eso_namespace, service_account = var.eso_service_account }
    transcoder = { namespace = var.app_namespace, service_account = var.app_service_account }
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-namespace"
      values   = [each.value.namespace]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-service-account"
      values   = [each.value.service_account]
    }
  }
}

# --- External Secrets Operator: read this app's parameters and secret only.

resource "aws_iam_role" "eso" {
  name               = "${local.name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust["eso"].json
}

data "aws_iam_policy_document" "eso" {
  statement {
    sid     = "ReadPipelineParameters"
    actions = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.param_path}/*",
    ]
  }

  statement {
    sid       = "ReadPipelineSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.db.arn]
  }
}

resource "aws_iam_role_policy" "eso" {
  name   = "read-video-pipeline-config"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso.json
}

resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = var.cluster_name
  namespace       = var.eso_namespace
  service_account = var.eso_service_account
  role_arn        = aws_iam_role.eso.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

# --- The transcoder: work the queue and write to the output bucket.

resource "aws_iam_role" "transcoder" {
  name               = "${local.name}-transcoder"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust["transcoder"].json
}

data "aws_iam_policy_document" "transcoder" {
  statement {
    sid       = "WorkTheQueue"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.transcode.arn]
  }

  statement {
    sid       = "WriteOutput"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.output.arn}/*"]
  }
}

resource "aws_iam_role_policy" "transcoder" {
  name   = "transcode"
  role   = aws_iam_role.transcoder.id
  policy = data.aws_iam_policy_document.transcoder.json
}

resource "aws_eks_pod_identity_association" "transcoder" {
  cluster_name    = var.cluster_name
  namespace       = var.app_namespace
  service_account = var.app_service_account
  role_arn        = aws_iam_role.transcoder.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}
