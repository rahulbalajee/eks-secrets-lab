variable "region" {
  description = "AWS region of the EKS cluster."
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "Name of an existing EKS cluster (Kubernetes 1.28 or later)."
  type        = string
}

variable "environment" {
  description = "Environment name, used in resource names and parameter paths."
  type        = string
  default     = "prod"
}

variable "app_namespace" {
  description = "Kubernetes namespace of the transcoder."
  type        = string
  default     = "video"
}

variable "app_service_account" {
  description = "Kubernetes service account of the transcoder."
  type        = string
  default     = "transcoder"
}

variable "eso_namespace" {
  description = "Namespace the External Secrets Operator runs in."
  type        = string
  default     = "external-secrets"
}

variable "eso_service_account" {
  description = "Service account of the External Secrets Operator controller."
  type        = string
  default     = "external-secrets"
}

variable "db_password_version" {
  description = "Increase to write a new database password to Secrets Manager."
  type        = number
  default     = 1
}
