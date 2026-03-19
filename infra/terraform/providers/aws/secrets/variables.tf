# providers/aws/secrets — Variables
# STATUS: SCAFFOLD — NOT DEPLOYED

variable "env_name" {
  type        = string
  description = "Logical environment name"
}

variable "secret_name_prefix" {
  type        = string
  description = "Path prefix for secrets (e.g. clopr2/dr-aws-euc1)"
  default     = "clopr2"
}

variable "pg_replication_password" {
  type        = string
  description = "PostgreSQL replication password to store in Secrets Manager"
  sensitive   = true
}

variable "consumer_iam_role_name" {
  type        = string
  description = "IAM role name of the EC2 instance that needs secret read access"
  default     = null
}

variable "soft_delete_retention_days" {
  type        = number
  description = "Recovery window in days (AWS minimum: 7)"
  default     = 7
}

variable "tags" {
  type        = map(string)
  description = "AWS resource tags"
  default     = {}
}
