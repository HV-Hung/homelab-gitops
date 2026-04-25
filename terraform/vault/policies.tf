resource "vault_policy" "databases" {
  name   = "databases-policy"
  policy = <<-EOT
    path "secret/data/admin" { capabilities = ["read"] }
    path "secret/data/dev"   { capabilities = ["read"] }
    path "secret/data/prod"  { capabilities = ["read"] }
  EOT
}

resource "vault_policy" "dev" {
  name   = "dev-policy"
  policy = <<-EOT
    path "secret/data/dev" { capabilities = ["read"] }
  EOT
}

resource "vault_policy" "prod" {
  name   = "prod-policy"
  policy = <<-EOT
    path "secret/data/prod" { capabilities = ["read"] }
  EOT
}

resource "vault_policy" "cloudflare" {
  name   = "cloudflare-policy"
  policy = <<-EOT
    path "secret/data/cloudflare" { capabilities = ["read"] }
  EOT
}
