# envs/gcp-proof — Variables

variable "project_id" {
  type        = string
  description = "GCP project ID"
  default     = "aris-project-490607"
}

variable "region" {
  type        = string
  description = "GCP region — EU to match project location"
  default     = "europe-west3"
}

variable "subnet_cidr" {
  type        = string
  description = "Subnet CIDR — isolated, does not overlap Azure (10.20.0.0/16) or on-prem (10.0.0.0/16) or AWS proof (10.21.0.0/16)"
  default     = "10.22.1.0/24"
}

variable "vm_size" {
  type        = string
  description = "GCP machine type — e2-micro maps to Azure Standard_B1s (smallest viable)"
  default     = "e2-micro"
}

variable "disk_size_gb" {
  type        = number
  description = "Boot disk size in GB"
  default     = 20
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key (stored in GCP instance metadata)"
  sensitive   = true
}

variable "ssh_username" {
  type        = string
  description = "SSH username for the VM"
  default     = "adminuser"
}

variable "labels" {
  type        = map(string)
  description = "GCP resource labels applied to all resources"
  default = {
    project = "clopr2"
    env     = "gcp-proof"
    sprint  = "s5"
    team    = "bclc24"
  }
}
