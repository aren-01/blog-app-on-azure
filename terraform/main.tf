terraform {
  required_version = ">= 1.6.0"

  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatearen007"
    container_name       = "tfstate"
    key                  = "blog-app-on-azure.tfstate"
    use_oidc             = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}

  use_oidc = true
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "centralus"
}

variable "client_ip_address" {
  description = "Your client public IP address for PostgreSQL firewall access."
  type        = string
}

variable "postgres_admin_username" {
  description = "PostgreSQL admin username. Do not hardcode this in Terraform."
  type        = string
  sensitive   = true
}

variable "postgres_admin_password" {
  description = "PostgreSQL admin password. Do not hardcode this in Terraform."
  type        = string
  sensitive   = true
}

resource "azurerm_resource_group" "main" {
  name     = "sampleblogapp01"
  location = var.location
}

resource "azurerm_storage_account" "blog_static_site" {
  name                     = "myblogappazure007"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  static_website {
    index_document = "index.html"
  }
}

resource "azurerm_postgresql_flexible_server" "blog_db" {
  name                = "sampleappblog"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  version = "16"

  administrator_login    = var.postgres_admin_username
  administrator_password = var.postgres_admin_password

  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }

  sku_name   = "B_Standard_B1ms"
  storage_mb = 32768

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  zone                         = "1"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "client_ip" {
  name             = "AllowClientIPAddress"
  server_id        = azurerm_postgresql_flexible_server.blog_db.id
  start_ip_address = var.client_ip_address
  end_ip_address   = var.client_ip_address
}

resource "azurerm_service_plan" "function_plan" {
  name                = "myblogappazure007-consumption-plan"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  os_type  = "Windows"
  sku_name = "Y1"
}

resource "azurerm_windows_function_app" "blog_function" {
  name                = "myblogappazure007"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  service_plan_id = azurerm_service_plan.function_plan.id

  storage_account_name       = azurerm_storage_account.blog_static_site.name
  storage_account_access_key = azurerm_storage_account.blog_static_site.primary_access_key

  functions_extension_version = "~4"

app_settings = {
  AzureWebJobsStorage          = azurerm_storage_account.blog_static_site.primary_connection_string
  FUNCTIONS_WORKER_RUNTIME     = "node"
  WEBSITE_NODE_DEFAULT_VERSION = "~22"
  WEBSITE_RUN_FROM_PACKAGE     = "1"

  DB_HOST     = azurerm_postgresql_flexible_server.blog_db.fqdn
  DB_PORT     = "5432"
  DB_NAME     = azurerm_postgresql_flexible_server_database.posts.name
  DB_USER     = var.postgres_admin_username
  DB_PASSWORD = var.postgres_admin_password
  DB_SSL      = "true"
}

  site_config {
  application_stack {
    node_version = "~22"
  }
}
}

output "website_url" {
  value = azurerm_storage_account.blog_static_site.primary_web_endpoint
}

output "storage_connection_string" {
  value     = azurerm_storage_account.blog_static_site.primary_connection_string
  sensitive = true
}

output "function_app_default_hostname" {
  value = azurerm_windows_function_app.blog_function.default_hostname
}

output "function_app_url" {
  value = "https://${azurerm_windows_function_app.blog_function.default_hostname}"
}

output "postgresql_server_fqdn" {
  value = azurerm_postgresql_flexible_server.blog_db.fqdn
}
