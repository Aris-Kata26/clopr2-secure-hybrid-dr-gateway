# providers/aws/secrets — AWS Secrets Manager
# =============================================
# STATUS: SCAFFOLD — NOT DEPLOYED
# Equivalent to: providers/azure → azurerm_key_vault + azurerm_key_vault_secret
# Implements: shared/secrets-interface
#
# Access model:
#   Azure: Managed Identity + Key Vault Secrets User RBAC role
#   AWS:   EC2 IAM Role + secretsmanager:GetSecretValue IAM policy

# terraform {
#   required_providers {
#     aws = {
#       source  = "hashicorp/aws"
#       version = "~> 5.0"
#     }
#   }
# }

# ── Secret — PostgreSQL replication password ──────────────────────────────────

# resource "aws_secretsmanager_secret" "pg_replication" {
#   name                    = "${var.secret_name_prefix}/pg-replication-password"
#   description             = "PostgreSQL replication user password for CLOPR2 DR"
#   recovery_window_in_days = var.soft_delete_retention_days
#   tags                    = var.tags
# }

# resource "aws_secretsmanager_secret_version" "pg_replication" {
#   secret_id     = aws_secretsmanager_secret.pg_replication.id
#   secret_string = var.pg_replication_password
# }

# ── IAM Policy — read-only access for EC2 role ───────────────────────────────
# Equivalent to: azurerm_role_assignment → Key Vault Secrets User

# data "aws_iam_policy_document" "pg_dr_secrets" {
#   statement {
#     effect = "Allow"
#     actions = [
#       "secretsmanager:GetSecretValue",
#       "secretsmanager:DescribeSecret"
#     ]
#     resources = [aws_secretsmanager_secret.pg_replication.arn]
#   }
# }

# resource "aws_iam_policy" "pg_dr_secrets" {
#   name        = "clopr2-pg-dr-secrets-read-${var.env_name}"
#   description = "Allow pg-dr EC2 instance to read replication password"
#   policy      = data.aws_iam_policy_document.pg_dr_secrets.json
#   tags        = var.tags
# }

# resource "aws_iam_role_policy_attachment" "pg_dr_secrets" {
#   role       = var.consumer_iam_role_name
#   policy_arn = aws_iam_policy.pg_dr_secrets.arn
# }
