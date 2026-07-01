# GENERAL

subscription_id = null # TODO: Put the Azure Subscription ID here only in case you cannot use an environment variable!

region              = "North Europe"
resource_group_name = "example-transit-vnet-common" # Must match the resource group deployed by LB-Sandwich-infra
name_prefix         = "example-"
tags = {
  "createdBy"   = "Palo Alto Networks"
  "createdWith" = "Terraform"
}

# NETWORK REFERENCES
# Provide the Azure resource IDs of your existing subnets and LB backend pools.
# These can come from any deployment — Terraform outputs, Azure Portal, or az CLI:
#   Subnets:          az network vnet subnet list --resource-group <rg> --vnet-name <vnet> --query "[].id"
#   LB backend pools: az network lb address-pool list --resource-group <rg> --lb-name <lb> --query "[].id"

subnet_ids = {
  management = "" # TODO: Resource ID of your management subnet
  public     = "" # TODO: Resource ID of your public (untrust) subnet
  private    = "" # TODO: Resource ID of your private (trust) subnet
}

# LOAD BALANCING

load_balancers = {
  "public" = {
    name = "public-lb"
    nsg_auto_rules_settings = {
      nsg_name   = "example-public-nsg" # TODO: Name of the public NSG created by LB-Sandwich-infra
      source_ips = ["1.1.1.1/32"]       # TODO: Whitelist public IP addresses that will be used to access LB
    }
    health_probes = {
      http = {
        name         = "http-probe"
        protocol     = "Http"
        request_path = "/unauth/php/health.php"
      }
    }
    frontend_ips = {
      "app1" = {
        name             = "app1"
        public_ip_name   = "public-lb-app1-pip"
        create_public_ip = true
        in_rules = {
          "balanceHttp" = {
            name             = "HTTP"
            protocol         = "Tcp"
            port             = 80
            health_probe_key = "http"
          }
        }
      }
    }
  }
  "private" = {
    name = "private-lb"
    health_probes = {
      http = {
        name         = "http-probe"
        protocol     = "Http"
        request_path = "/unauth/php/health.php"
      }
    }
    frontend_ips = {
      "ha-ports" = {
        name               = "private-vmseries"
        subnet_key         = "private"
        private_ip_address = "10.0.0.46"
        in_rules = {
          HA_PORTS = {
            name             = "HA-ports"
            port             = 0
            protocol         = "All"
            health_probe_key = "http"
          }
        }
      }
    }
  }
}

# VM-SERIES

# All options under `vmseries_universal` can be overridden on a per-firewall basis under `vmseries`
vmseries_universal = {
  version = "11.2.8"
  size    = "Standard_DS3_v2"

  # This example uses basic user-data bootstrap by default
  bootstrap_options = {
    type               = "dhcp-client"
    plugin-op-commands = "advance-routing:enable"
  }

  /* Uncomment to use Panorama Software Firewall License (sw_fw_license) plugin bootstrap
  bootstrap_options = {
    type               = "dhcp-client"
    plugin-op-commands = "advance-routing:enable,panorama-licensing-mode-on"
    panorama-server    = "" # TODO: Insert Panorama IP address from sw_fw_license plugin
    tplname            = "" # TODO: Insert Panorama Template Stack name from sw_fw_license plugin
    dgname             = "" # TODO: Insert Panorama Device Group name from sw_fw_license plugin
    auth-key           = "" # TODO: Insert authentication key from sw_fw_license plugin
  }
  */

  /* Uncomment to use Strata Cloud Manager (SCM) bootstrap (PAN-OS 11.0+)
  bootstrap_options = {
    type                                  = "dhcp-client"
    plugin-op-commands                    = "advance-routing:enable"
    panorama-server                       = "cloud"
    tplname                               = "" # TODO: Insert SCM device label name
    dgname                                = "" # TODO: Insert SCM Folder name
    vm-series-auto-registration-pin-id    = "" # TODO: Insert Device Certificate Registration PIN ID
    vm-series-auto-registration-pin-value = "" # TODO: Insert Device Certificate Registration PIN value
    authcodes                             = "" # TODO: Insert license authorization code
  }
  */
}

vmseries = {
  "fw-1" = {
    name = "firewall01"
    virtual_machine = {
      zone = 1
    }
    interfaces = [
      {
        name       = "vm01-mgmt"
        subnet_key = "management"
        ip_configurations = {
          primary-ip = {
            name             = "primary-ip"
            primary          = true
            create_public_ip = true
          }
        }
      },
      {
        name       = "vm01-public"
        subnet_key = "public"
        ip_configurations = {
          primary-ip = {
            name             = "primary-ip"
            primary          = true
            create_public_ip = true
          }
        }
        load_balancer_key = "public"
      },
      {
        name       = "vm01-private"
        subnet_key = "private"
        ip_configurations = {
          primary-ip = {
            name             = "primary-ip"
            primary          = true
            create_public_ip = false
          }
        }
        load_balancer_key = "private"
      }
    ]
  }
  "fw-2" = {
    name = "firewall02"
    virtual_machine = {
      zone = 2
    }
    interfaces = [
      {
        name       = "vm02-mgmt"
        subnet_key = "management"
        ip_configurations = {
          primary-ip = {
            name             = "primary-ip"
            primary          = true
            create_public_ip = true
          }
        }
      },
      {
        name       = "vm02-public"
        subnet_key = "public"
        ip_configurations = {
          primary-ip = {
            name             = "primary-ip"
            primary          = true
            create_public_ip = true
          }
        }
        load_balancer_key = "public"
      },
      {
        name       = "vm02-private"
        subnet_key = "private"
        ip_configurations = {
          primary-ip = {
            name             = "primary-ip"
            primary          = true
            create_public_ip = false
          }
        }
        load_balancer_key = "private"
      }
    ]
  }
}
