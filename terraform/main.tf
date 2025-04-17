data "azurerm_client_config" "current" {}

terraform {
  required_providers {
    azurerm = {
        source = "hashicorp/azurerm"
        version = "4.14.0"
    }
  }
}

provider "azurerm" {
    features{
      key_vault {
        purge_soft_delete_on_destroy    = true
        recover_soft_deleted_key_vaults = true
    }
    }
    subscription_id = "016ff014-d7ea-4ce9-8cd5-c220328da9f2"
    tenant_id = "3bd7d319-1f84-4baf-9245-9515a4cf3cef"
    client_id = "8c117aaa-99d6-41ac-ab7c-0b4650b7e77b" 
    client_secret = "<<secret_value_from_app_resgistrstion>>"
}


resource "azurerm_resource_group" "uv_test" {
  name     = "Uv_test"
  location = "Central India"
}

resource "azurerm_key_vault" "prod" {
  name                        = "prodkeyvault"
  location                    = azurerm_resource_group.uv_test.location
  resource_group_name         = azurerm_resource_group.uv_test.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
    ]

    secret_permissions = [
      "Get",
    ]

    storage_permissions = [
      "Get",
    ]
  }
}

data "azurerm_key_vault" "prod" {
  name                = azurerm_key_vault.prod.name 
  resource_group_name = azurerm_resource_group.uv_test.name
  depends_on          = [azurerm_key_vault.prod]
}

data "azurerm_key_vault_secret" "app_secret" {
  name         = "terraform-client-secret"
  key_vault_id = data.azurerm_key_vault.prod.id
}


resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-network"
  resource_group_name = azurerm_resource_group.uv_test.name
  location            = azurerm_resource_group.uv_test.location
  address_space       = ["10.254.0.0/16"]
}

resource "azurerm_subnet" "sub1" {
  name                 = "sub1"
  resource_group_name  = azurerm_resource_group.uv_test.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.254.0.0/24"]
}

resource "azurerm_public_ip" "outside" {
  name                = "outside-pip"
  resource_group_name = azurerm_resource_group.uv_test.name
  location            = azurerm_resource_group.uv_test.location
  allocation_method   = "Static"
}


locals {
  backend_address_pool_name      = "${azurerm_virtual_network.vnet.name}-beap"
  frontend_port_name             = "${azurerm_virtual_network.vnet.name}-feport"
  frontend_ip_configuration_name = "${azurerm_virtual_network.vnet.name}-feip"
  http_setting_name              = "${azurerm_virtual_network.vnet.name}-be-htst"
  listener_name                  = "${azurerm_virtual_network.vnet.name}-httplstn"
  request_routing_rule_name      = "${azurerm_virtual_network.vnet.name}-rqrt"
  redirect_configuration_name    = "${azurerm_virtual_network.vnet.name}-rdrcfg"
}

resource "azurerm_application_gateway" "network" {
  name                = "example-appgateway"
  resource_group_name = azurerm_resource_group.uv_test.name
  location            = azurerm_resource_group.uv_test.location

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "my-gateway-ip-configuration"
    subnet_id = azurerm_subnet.sub1.id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.outside.id
  }

  backend_address_pool {
    name = local.backend_address_pool_name
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    path                  = "/path1/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    priority                   = 9
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
  }
}

resource "azurerm_api_management" "inter1" {
  name                = "inter1-apim"
  location            = azurerm_resource_group.uv_test.location
  resource_group_name = azurerm_resource_group.uv_test.name
  publisher_name      = "Anonymous pulisher"
  publisher_email     = "uvendhan001@outlook.com"
  sku_name = "Standard_1"
}

data "azurerm_key_vault_secret" "db_password" {
  name         = "database-password"
  key_vault_id = azurerm_key_vault.prod.id
}

resource "azurerm_mssql_server" "testing" {
  name                         = "testing-sqlserver"
  resource_group_name          = azurerm_resource_group.uv_test.name
  location                     = azurerm_resource_group.uv_test.location
  version                      = "12.0"
  administrator_login          = "admin"
  administrator_login_password = data.azurerm_key_vault_secret.db_password.value

}

resource "azurerm_service_plan" "testing" {
  name                = "testing-appserviceplan"
  location            = azurerm_resource_group.uv_test.location
  resource_group_name = azurerm_resource_group.uv_test.name
  sku_name            = "P2v2" 
  os_type             = "Linux"

}
resource "azurerm_linux_web_app" "testing1" {
  name                = "testing1-app-service"
  location            = azurerm_resource_group.uv_test.location
  resource_group_name = azurerm_resource_group.uv_test.name
  service_plan_id     = azurerm_service_plan.testing.id 

  site_config {
    always_on = true 
  }
   connection_string {
    name  = "Database"
    type  = "SQLServer"
    value = "Server=some-server.mydomain.com;Integrated Security=SSPI"
  }
}


resource "azurerm_monitor_autoscale_setting" "autoscale" {
  name                = "myAutoscaleSetting"
  resource_group_name = azurerm_resource_group.uv_test.name
  location            = azurerm_resource_group.uv_test.location
  target_resource_id  = azurerm_service_plan.testing.id

  profile {
    name = "defaultProfile"

    capacity {
      default = 2
      minimum = 1
      maximum = 10
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_service_plan.testing.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 1000
        metric_namespace   = "microsoft.compute/virtualmachinescalesets"
        dimensions {
          name     = "AppName"
          operator = "Equals"
          values   = ["App1"]
        }
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_service_plan.testing.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }
  }

  predictive {
    scale_mode      = "Enabled"
    look_ahead_time = "PT5M"
  }

  notification {
    email {
      send_to_subscription_administrator    = true
      send_to_subscription_co_administrator = true
      custom_emails                         = ["uvendhan001@outlook.com"]
    }
  }
}