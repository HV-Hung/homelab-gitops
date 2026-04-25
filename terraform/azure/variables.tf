variable "resource_group_name" {
  type        = string
  description = "The name of the resource group to deploy the Key Vault in."
  default     = "vault-rg"
}

variable "location" {
  type        = string
  description = "The Azure region to deploy to."
  default     = "southeastasia"
}

variable "key_vault_name" {
  type        = string
  description = "Name for the Azure Key Vault."
  default     = "homelab-vault-kv"
}
