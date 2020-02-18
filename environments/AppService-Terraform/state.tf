
provider "azurerm" {
  use_msi = true
}

terraform {
  backend "azurerm" {
    storage_account_name = "statestorerbest"
    container_name       = "tstate"
    key                  = "prod100.terraform.tfstate"
    use_msi              = true
    resource_group_name  = "AAATerraform"
  }
}