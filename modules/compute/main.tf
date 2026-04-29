locals {
  acr_name      = lower(replace("${var.name_prefix}${var.unique_suffix}acr", "-", ""))
  plan_name     = "${var.name_prefix}-plan"
  api_app_name  = "${var.name_prefix}-api"
  site_app_name = "${var.name_prefix}-site"
}

resource "azurerm_container_registry" "main" {
  name                = local.acr_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = var.common_tags
}

resource "azurerm_service_plan" "main" {
  name                = local.plan_name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku
  tags                = var.common_tags
}

resource "azurerm_linux_web_app" "api" {
  name                = local.api_app_name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.main.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      docker_image_name   = "api:latest"
      docker_registry_url = "https://${azurerm_container_registry.main.login_server}"
    }
  }

  app_settings = {
    "ASPNETCORE_ENVIRONMENT"              = "Production"
    "DB_CONNECTION_STRING"                = "@Microsoft.KeyVault(VaultName=${var.key_vault_name};SecretName=db-connection-string)"
    "acrUseManagedIdentityCreds"          = "true"
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
  }

  tags = var.common_tags
}

resource "azurerm_linux_web_app" "site" {
  name                = local.site_app_name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.main.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      docker_image_name   = "site:latest"
      docker_registry_url = "https://${azurerm_container_registry.main.login_server}"
    }
  }

  app_settings = {
    "ASPNETCORE_ENVIRONMENT"              = "Production"
    "REDIS_CONNECTION_STRING"             = "@Microsoft.KeyVault(VaultName=${var.key_vault_name};SecretName=redis-connection-string)"
    "MarketingApi__BaseUrl"               = "https://${local.api_app_name}.azurewebsites.net"
    "acrUseManagedIdentityCreds"          = "true"
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
  }

  tags = var.common_tags
}

resource "azurerm_role_assignment" "api_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.api.identity[0].principal_id
}

resource "azurerm_role_assignment" "site_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.site.identity[0].principal_id
}

resource "azurerm_monitor_autoscale_setting" "main" {
  name                = "${var.name_prefix}-autoscale"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.main.id

  profile {
    name = "default"

    capacity {
      default = 1
      minimum = 1
      maximum = 5
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 50
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
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
        cooldown  = "PT5M"
      }
    }
  }

  tags = var.common_tags
}
