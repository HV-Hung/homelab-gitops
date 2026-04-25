output "azure_tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "azure_client_id" {
  value = azuread_application.vault.client_id
}

output "azure_client_secret" {
  value     = azuread_application_password.vault.value
  sensitive = true
}

output "key_vault_name" {
  value = azurerm_key_vault.vault.name
}

output "key_name" {
  value = azurerm_key_vault_key.unseal.name
}
