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
  depends_on            = [azurerm_storage_account.service311storage]
}

resource "azurerm_storage_container" "silver" {
  name                  = "silver"
  storage_account_id    = azurerm_storage_account.service311storage.id
  container_access_type = "private"
  depends_on            = [azurerm_storage_account.service311storage]
}


# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "service311server" {
  name                          = "service311server"
  resource_group_name           = azurerm_resource_group.service_requests.name
  location                      = "Canada Central"
  version                       = "16"
  administrator_login           = var.user
  administrator_password        = var.pg_pass
  zone                          = "1"
  public_network_access_enabled = true

  storage_mb   = 32768

  sku_name    = "GP_Standard_D4s_v3"
  create_mode = "Default"

  depends_on = [azurerm_resource_group.service_requests]

}

resource "azurerm_postgresql_flexible_server_database" "service_311_db" {
  name      = "service_311_db"
  server_id = azurerm_postgresql_flexible_server.service311server.id
  collation = "en_US.utf8"
  charset   = "UTF8"

  # prevent the possibility of accidental data loss
  lifecycle {
    prevent_destroy = false
  }
}

# Data Factory with linked services (blob storage and parquet dataset)
data "azurerm_storage_account" "service311storage" {
  name                = "service311storage"
  resource_group_name = azurerm_resource_group.service_requests.name

  depends_on = [ azurerm_storage_account.service311storage ]
}

resource "azurerm_data_factory" "service311factory" {
  name                = "service311factory"
  location            = "East US"
  resource_group_name = azurerm_resource_group.service_requests.name
}

resource "azurerm_data_factory_linked_service_azure_blob_storage" "blob_storage_ls" {
  name              = "blob_storage_ls"
  data_factory_id   = azurerm_data_factory.service311factory.id
  connection_string = data.azurerm_storage_account.service311storage.primary_connection_string
}

resource "azurerm_data_factory_dataset_parquet" "service_311_dataset" {
  name                = "service_311_dataset"
  data_factory_id     = azurerm_data_factory.service311factory.id
  linked_service_name = azurerm_data_factory_linked_service_azure_blob_storage.blob_storage_ls.name

  compression_codec = "snappy"

  azure_blob_storage_location {
    container = "silver"
    filename = "urban_service_requests.parquet"
  }
}

# PostgreSQL Linked Service for data factory
resource "azurerm_data_factory_linked_custom_service" "linkedservicepostgresql" {
  name              = "linkedservicepostgresql"
  data_factory_id   = azurerm_data_factory.service311factory.id
  type            = "PostgreSqlV2"

  type_properties_json = jsonencode({
    server         = azurerm_postgresql_flexible_server.service311server.fqdn
    port           = 5432
    database       = azurerm_postgresql_flexible_server_database.service_311_db.name
    username       = var.user
    sslMode        = 2 # corresponds to Require / SSL enabled
    trustServerCertificate = true
    password = {
      type  = "SecureString"
      value = var.pg_pass
    }
  })
}

# PostgreSQL output dataset in data factory 
resource "azurerm_data_factory_custom_dataset" "postgresql_dataset" {
    name                = "postgresql_dataset"
    data_factory_id     = azurerm_data_factory.service311factory.id
    type                = "PostgreSqlV2Table"
    linked_service {
        name = azurerm_data_factory_linked_custom_service.linkedservicepostgresql.name
    }

    type_properties_json = jsonencode({
        table  = "urban_city_requests"
        schema = "gold"
    })
}

# Data factory Copy Pipeline
resource "azurerm_data_factory_pipeline" "silver_to_gold_pipeline" {
  name            = "silver_to_gold_pipeline"
  data_factory_id = azurerm_data_factory.service311factory.id

  activities_json = jsonencode([
    {
      name = "Silver_Parquet_To_Gold_Postgres"
      type = "Copy"
      typeProperties = {
        source = {
          type = "ParquetSource"
          storeSettings = {
            type      = "AzureBlobStorageReadSettings"
            recursive = true
          }
        }
        sink = {
          type           = "AzurePostgreSQLSink"
          writeBatchSize = 10000
          preCopyScript  = "TRUNCATE TABLE gold.urban_city_requests;"
        }
      }
      inputs = [
        {
          referenceName = azurerm_data_factory_dataset_parquet.service_311_dataset.name
          type          = "DatasetReference"
        }
      ]
      outputs = [
        {
          referenceName = azurerm_data_factory_custom_dataset.postgresql_dataset.name
          type          = "DatasetReference"
        }
      ]
    }
  ])
}