variable "name" {
  type        = string
  description = "Log Analytics workspace name."
}

variable "location" {
  type        = string
  description = "Azure region for the workspace."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name."
}

variable "retention_in_days" {
  type        = number
  description = "Log retention in days."
  default     = 30
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources."
  default     = {}
}
