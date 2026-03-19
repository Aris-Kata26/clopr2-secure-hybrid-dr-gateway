# envs/aws-proof — Variables

variable "region" {
  type        = string
  description = "AWS region for proof-of-portability deployment"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR — isolated, does not overlap Azure (10.20.0.0/16) or on-prem (10.0.0.0/16)"
  default     = "10.21.0.0/16"
}

variable "subnet_cidr" {
  type        = string
  description = "Subnet CIDR within the proof VPC"
  default     = "10.21.1.0/24"
}

variable "vm_size" {
  type        = string
  description = "EC2 instance type — maps to Azure Standard_B2ats_v2"
  default     = "t3.micro"
}

variable "disk_size_gb" {
  type        = number
  description = "Root EBS volume size in GB"
  default     = 20
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for operator access (stored as AWS key pair)"
  sensitive   = true
}

variable "tags" {
  type        = map(string)
  description = "AWS resource tags applied to all resources"
  default = {
    project = "clopr2"
    env     = "aws-proof"
    sprint  = "S5"
    team    = "BCLC24"
  }
}
