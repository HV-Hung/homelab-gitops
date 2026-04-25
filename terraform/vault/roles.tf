resource "vault_kubernetes_auth_backend_role" "databases" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "databases"
  bound_service_account_names      = ["vso-sa"]
  bound_service_account_namespaces = ["databases"]
  token_policies                   = [vault_policy.databases.name]
  token_ttl                        = 3600
}

resource "vault_kubernetes_auth_backend_role" "dev" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "dev"
  bound_service_account_names      = ["vso-sa"]
  bound_service_account_namespaces = ["dev"]
  token_policies                   = [vault_policy.dev.name]
  token_ttl                        = 3600
}

resource "vault_kubernetes_auth_backend_role" "prod" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "prod"
  bound_service_account_names      = ["vso-sa"]
  bound_service_account_namespaces = ["prod"]
  token_policies                   = [vault_policy.prod.name]
  token_ttl                        = 1800
}

resource "vault_kubernetes_auth_backend_role" "cloudflare" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "cloudflare"
  bound_service_account_names      = ["vso-sa"]
  bound_service_account_namespaces = ["cloudflare"]
  token_policies                   = [vault_policy.cloudflare.name]
  token_ttl                        = 3600
}
