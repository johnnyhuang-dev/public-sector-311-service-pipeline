# Azure Provider source and version being used
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=5.0.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
  subscription_id = file("credentials.txt")
}

# Create a resource group
resource "azurerm_resource_group" "service_requests" {
  name     = "service_requests"
  location = "Canada East"
}

# Create a blob storage account
resource "azurerm_storage_account" "service311storage" {
  name                     = "service311storage"
  resource_group_name      = azurerm_resource_group.service_requests.name
  location                 = "East US"
  account_tier             = "Standard"
  account_replication_type = "GRS"

  tags = {
    environment = "staging"
  }
}

# Create a container in the blob storage
resource "azurerm_storage_container" "bronze" {
  name                  = "bronze"
  storage_account_id    = azurerm_storage_account.service311storage.id
  container_access_type = "private"
  depends_on = [ azurerm_storage_account.service311storage ]
}

resource "azurerm_storage_container" "silver" {
  name                  = "silver"
  storage_account_id    = azurerm_storage_account.service311storage.id
  container_access_type = "private"
  depends_on = [ azurerm_storage_account.service311storage ]
}


# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "service311server" {
  name                          = "service311server"
  resource_group_name           = azurerm_resource_group.service_requests.name
  location                      = "East US"
  version                       = "16"
  administrator_login           = "adminadmin"
  administrator_password        = "H@Sh1CoR3!"
  zone                          = "1"
  public_network_access_enabled = true

  storage_mb   = 32768
  storage_tier = "P30"

  sku_name   = "GP_Standard_D4s_v3"
  depends_on = [azurerm_resource_group.service_requests]

}

resource "azurerm_postgresql_flexible_server_database" "service_311_db" {
  name      = "service_311_db"
  server_id = azurerm_postgresql_flexible_server.service311server.id
  collation = "en_US.utf8"
  charset   = "UTF8"

  # prevent the possibility of accidental data loss
  lifecycle {
    prevent_destroy = true
  }
}

# Data Factory
resource "azurerm_data_factory" "service_311_data_factory" {
  name                = "service_311_data_factory"
  location            = "East Us"
  resource_group_name = azurerm_resource_group.service_requests.name
}

resource "azurerm_data_factory_pipeline" "service_311_df_pipeline" {
  name            = "service_311_df_pipeline"
  data_factory_id = azurerm_data_factory.service_311_data_factory.id
  variables = {
    "bob" = "item1"
  }
  activities_json = <<JSON
[
    {
        "name": "Append variable1",
        "type": "AppendVariable",
        "dependsOn": [],
        "userProperties": [],
        "typeProperties": {
          "variableName": "bob",
          "value": "something"
        }
    }
]
  JSON
}