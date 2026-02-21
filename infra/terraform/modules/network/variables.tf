variable "name" {
  type        = string
  description = "Virtual network name."
}

variable "location" {
  type        = string
  description = "Azure region for the network resources."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name."
}

variable "address_space" {
  type        = list(string)
  description = "Address space for the virtual network."
}

variable "subnets" {
  type = map(object({
    address_prefixes = list(string)
    nsg_name         = string
  }))
  description = "Subnet map with address prefixes and NSG names."
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources."
  default     = {}
}
