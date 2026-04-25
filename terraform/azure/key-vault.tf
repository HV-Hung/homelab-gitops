resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_key_vault" "vault" {
  name                = var.key_vault_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  purge_protection_enabled = true

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Create", "Get", "List", "Purge", "Recover", "Delete", "WrapKey", "UnwrapKey", "Update"
    ]
  }
}

resource "azurerm_key_vault_key" "unseal" {
  name         = "vault-unseal-key"
  key_vault_id = azurerm_key_vault.vault.id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["wrapKey", "unwrapKey"]

  depends_on = [
    azurerm_key_vault.vault
  ]
}

resource "azurerm_role_assignment" "vault_unseal" {
  scope                = azurerm_key_vault.vault.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azuread_service_principal.vault.object_id
}
