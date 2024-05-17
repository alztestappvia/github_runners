locals {
  admin_username = "runneradmin"
}

resource "azurecaf_name" "rg" {
  name          = "github-runner"
  resource_type = "azurerm_resource_group"
  suffixes      = [lower(var.environment)]
  random_length = 4
}

resource "azurecaf_name" "subnet" {
  name          = "github-runner"
  resource_type = "azurerm_subnet"
  suffixes      = [lower(var.environment)]
  random_length = 4
}

resource "azurecaf_name" "nsg" {
  name          = "github-runner"
  resource_type = "azurerm_network_security_group"
  suffixes      = [lower(var.environment)]
  random_length = 4
}

resource "azurecaf_name" "runner" {
  name          = "github-runner"
  resource_type = "azurerm_linux_virtual_machine_scale_set"
  suffixes      = [lower(var.environment)]
  random_length = 4
}

resource "azurerm_resource_group" "runner" {
  name     = azurecaf_name.rg.result
  location = var.location
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_subnet" "runner_subnet" {
  name                 = azurecaf_name.subnet.result
  resource_group_name  = var.vnet_resource_group_name
  virtual_network_name = var.vnet_name
  address_prefixes     = var.address_prefixes
}

resource "azurerm_network_security_group" "runner_subnet" {
  name                = azurecaf_name.nsg.result
  location            = var.location
  resource_group_name = var.vnet_resource_group_name
}

resource "azurerm_subnet_network_security_group_association" "runner_subnet" {
  subnet_id                 = azurerm_subnet.runner_subnet.id
  network_security_group_id = azurerm_network_security_group.runner_subnet.id
}

resource "azurerm_linux_virtual_machine_scale_set" "runner" {
  name                = azurecaf_name.runner.result
  resource_group_name = azurerm_resource_group.runner.name
  location            = var.location
  sku                 = "Standard_D4ds_v4"
  instances           = 5
  overprovision       = false
  upgrade_mode        = "Manual"
  provision_vm_agent  = true
  #checkov:skip=CKV_AZURE_97:Encryption at host is still in preview - this should be changed when GA
  encryption_at_host_enabled = false

  disable_password_authentication = true
  admin_username                  = local.admin_username

  admin_ssh_key {
    username   = local.admin_username
    public_key = trimspace(tls_private_key.ssh.public_key_openssh)
  }

  priority        = "Spot"
  eviction_policy = "Delete"

  identity {
    type = "SystemAssigned"
  }

  source_image_id = var.vmss_image_id

  network_interface {
    name    = "default"
    primary = true

    ip_configuration {
      name      = "default"
      primary   = true
      subnet_id = azurerm_subnet.runner_subnet.id
    }
  }

  os_disk {
    caching              = "ReadOnly"
    storage_account_type = "Standard_LRS"

    diff_disk_settings {
      option    = "Local"
      placement = "CacheDisk"
    }
  }

  boot_diagnostics {
    storage_account_uri = null
  }

  extension {
    name                 = "InstallGitHubRunner"
    publisher            = "Microsoft.Azure.Extensions"
    type                 = "CustomScript"
    type_handler_version = "2.1"

    protected_settings = jsonencode({
      script = base64encode(<<-EOF
        #!/bin/bash
        set -e

        # Create a user for github
        id -u github &>/dev/null || useradd -m github
        usermod -aG docker github

        # get the reg token
        export GH_REG_TOKEN=$(curl -s -L -X POST -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${var.github_pat}" -H "X-GitHub-Api-Version: 2022-11-28" https://api.github.com/orgs/${var.github_org}/actions/runners/registration-token | jq -r ".token")

        # Create a folder
        mkdir -p /usr/local/actions-runner && cd /usr/local/actions-runner

        # Download the latest runner package
        curl -sL $(curl -s https://api.github.com/repos/actions/runner/releases/latest | grep browser_download_url | cut -d\" -f4 | egrep 'linux-x64-[0-9.]+tar.gz$') | tar zx --overwrite

        # Change ownership of the runner to the github user
        chown -R github:github .

        run_github() {
          runuser -l github -c "cd /usr/local/actions-runner && ./config.sh --url https://github.com/${var.github_org} --token $GH_REG_TOKEN --name $(hostname)-$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8) --runnergroup ${var.github_runner_group} --ephemeral --labels alz,test --unattended && ./run.sh"

          export M_NAME=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" | jq -r ".compute.name")
          az login -i
          az vmss reimage -g ${azurecaf_name.rg.result} -n ${azurecaf_name.runner.result} --instance-id $${M_NAME##*_}
        }

        export -f run_github 
        nohup bash -c run_github &
        EOF
      )
    })
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      instances,
      tags
    ]
  }
}

resource "azurerm_role_assignment" "runner" {
  scope                = azurerm_linux_virtual_machine_scale_set.runner.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_linux_virtual_machine_scale_set.runner.identity[0].principal_id
}
