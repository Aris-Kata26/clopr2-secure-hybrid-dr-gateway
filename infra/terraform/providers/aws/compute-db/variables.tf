# providers/aws/compute-db — Variables
# STATUS: SCAFFOLD — NOT DEPLOYED
# Mirrors shared/compute-db interface with AWS-specific additions.

variable "env_name" {
  type        = string
  description = "Logical environment name (e.g. dr-aws-euc1)"
}

variable "region" {
  type        = string
  description = "AWS region (e.g. eu-central-1)"
  default     = "eu-central-1"
}

variable "vpc_id" {
  type        = string
  description = "AWS VPC ID (from providers/aws/core-network outputs)"
}

variable "subnet_id" {
  type        = string
  description = "AWS subnet ID for the DB VM"
}

variable "private_ip" {
  type        = string
  description = "Static private IP for the EC2 instance (optional)"
  default     = null
}

variable "vm_size" {
  type        = string
  description = "EC2 instance type (e.g. t3.small — maps to Azure Standard_B2ats_v2)"
  default     = "t3.small"
}

variable "disk_size_gb" {
  type        = number
  description = "EBS root volume size in GB"
  default     = 30
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key (stored as AWS Key Pair)"
  sensitive   = true
}

variable "admin_username" {
  type        = string
  description = "SSH username (Ubuntu default: ubuntu)"
  default     = "ubuntu"
}

variable "postgres_version" {
  type        = string
  description = "PostgreSQL major version"
  default     = "16"
}

variable "pg_replication_password" {
  type        = string
  description = "PostgreSQL replication password"
  sensitive   = true
  default     = null
}

variable "wg_tunnel_ip" {
  type        = string
  description = "WireGuard tunnel IP for this VM (e.g. 10.200.0.6/30)"
  default     = "10.200.0.6/30"
}

variable "wg_private_key" {
  type        = string
  description = "WireGuard private key for wg0 interface"
  sensitive   = true
}

variable "wg_peer_public_key" {
  type        = string
  description = "WireGuard public key of on-prem peer (pg-primary)"
  sensitive   = true
}

variable "wg_onprem_public_ip" {
  type        = string
  description = "On-prem public IP for WireGuard endpoint"
}

variable "wg_listen_port" {
  type        = number
  description = "WireGuard UDP listen port"
  default     = 51820
}

variable "secret_store_id" {
  type        = string
  description = "AWS Secrets Manager secret ARN to grant EC2 role read access"
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "AWS resource tags"
  default     = {}
}
