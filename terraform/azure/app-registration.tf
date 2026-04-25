resource "azuread_application" "vault" {
  display_name = "homelab-vault-unseal"
}

resource "azuread_service_principal" "vault" {
  client_id = azuread_application.vault.client_id
}

resource "azuread_application_password" "vault" {
  application_id = azuread_application.vault.id
  display_name   = "vault-auto-unseal"
  end_date       = "2030-01-01T00:00:00Z"
}
