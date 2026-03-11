variable "environment" {
  type        = string
  description = "Environment label used in tags."
  default     = "dev"
}

variable "aks_resource_group_name" {
  type        = string
  description = "Dedicated resource group for the AKS demo cluster (created by this module)."
  default     = "rg-b2clc-katar-aks-swe"
}

variable "acr_resource_group_name" {
  type        = string
  description = "Resource group containing the existing ACR in germanywestcentral (NOT recreated)."
  default     = "rg-clopr2-katar711-gwc"
}

variable "acr_name" {
  type        = string
  description = "Name of the existing ACR in germanywestcentral used for image pulls."
  default     = "acrb2clckatargwc"
}

variable "aks_cluster_name" {
  type        = string
  description = "AKS cluster name. Must include b2clc + katar per project naming convention."
  default     = "aks-b2clc-katar-swe"
}

variable "aks_location" {
  type        = string
  description = "Azure region for the AKS cluster. swedencentral confirmed: B2s_v2 allowed + quota available."
  default     = "swedencentral"
}

variable "aks_node_size" {
  type        = string
  description = "AKS node pool VM size. Standard_B2s_v2 confirmed in AKS allowed list for swedencentral with 0/10 vCPU quota available."
  default     = "Standard_B2s_v2"
}
