resource "azurerm_key_vault_secret" "app_secret" {
  name         = "terraform-client-secret"
  value        = "secret_value_from_app_resgistrstion" 
  key_vault_id = azurerm_key_vault.prod.id
}


resource "azurerm_key_vault_secret" "db_password" {
  name         = "database-password"
  value        = "1234!@#$" 
  key_vault_id = azurerm_key_vault.prod.id

}

