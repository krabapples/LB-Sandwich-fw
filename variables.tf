# GENERAL

variable "subscription_id" {
  description = <<-EOF
  Azure Subscription ID is a required argument since AzureRM provider v4.

  **Note!** \
  Instead of putting the Subscription ID directly in the code, it's recommended to use an environment variable. Create an
  environment variable named `ARM_SUBSCRIPTION_ID` with your Subscription ID as value and leave this variable set to `null`.
  EOF
  type        = string
}

variable "name_prefix" {
  description = <<-EOF
  A prefix that will be added to all created resources.
  There is no default delimiter applied between the prefix and the resource name.
  Please include the delimiter in the actual prefix.

  Example:
  ```
  name_prefix = "test-"
  ```
  EOF
  default     = ""
  type        = string
}

variable "resource_group_name" {
  description = "Name of the existing Resource Group that hosts the network infrastructure (deployed by LB-Sandwich-infra)."
  type        = string
}

variable "region" {
  description = "The Azure region to use."
  type        = string
}

variable "tags" {
  description = "Map of tags to assign to all created resources."
  default     = {}
  nullable    = false
  type        = map(string)
}

# NETWORK REFERENCES
# Supply the Azure resource IDs of your existing subnets and load balancer backend pools.
# These can come from any deployment — Terraform outputs, the Azure Portal, or az CLI:
#   az network vnet subnet show --ids <id> --query id
#   az network lb address-pool show --ids <id> --query id

variable "subnet_ids" {
  description = <<-EOF
  Map of logical subnet keys to Azure subnet resource IDs.
  The keys are referenced by name in the `vmseries` interfaces via `subnet_key`.
  Values can be sourced from any existing Azure deployment — not just LB-Sandwich-infra.

  Example:
  ```
  subnet_ids = {
    management = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/mgmt-snet"
    public     = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/public-snet"
    private    = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/private-snet"
  }
  ```
  EOF
  type        = map(string)
}

variable "lb_backend_pool_ids" {
  description = <<-EOF
  Map of logical load balancer keys to Azure LB backend pool resource IDs.
  The keys are referenced by name in the `vmseries` interfaces via `load_balancer_key`.
  Values can be sourced from any existing Azure deployment — not just LB-Sandwich-infra.

  Example:
  ```
  lb_backend_pool_ids = {
    public  = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/loadBalancers/<lb>/backendAddressPools/<pool>"
    private = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/loadBalancers/<lb>/backendAddressPools/<pool>"
  }
  ```
  EOF
  type        = map(string)
}

# VM-SERIES

variable "availability_sets" {
  description = <<-EOF
  A map defining availability sets. Can be used to provide infrastructure high availability when zones cannot be used.

  Following properties are supported:

  - `name`                - (`string`, required) name of the Availability Set.
  - `update_domain_count` - (`number`, optional, defaults to Azure default) specifies the number of update domains that are used.
  - `fault_domain_count`  - (`number`, optional, defaults to Azure default) specifies the number of fault domains that are used.
  EOF
  default     = {}
  nullable    = false
  type = map(object({
    name                = string
    update_domain_count = optional(number)
    fault_domain_count  = optional(number)
  }))
}

variable "ngfw_metrics" {
  description = <<-EOF
  A map controlling metrics-related resources.

  When set to explicit `null` (default) it will disable any metrics resources in this deployment.

  When defined it will either create or source a Log Analytics Workspace and create Application Insights instances (one per
  each firewall). All instances will be automatically connected to the workspace.

  Following properties are available:

  - `name`                      - (`string`, required) name of the Log Analytics Workspace.
  - `create_workspace`          - (`bool`, optional, defaults to `true`) controls whether we create or source an existing workspace.
  - `resource_group_name`       - (`string`, optional, defaults to `var.resource_group_name`) name of the Resource Group hosting
                                  the Log Analytics Workspace.
  - `sku`                       - (`string`, optional, defaults to module default) the SKU of the Log Analytics Workspace.
  - `metrics_retention_in_days` - (`number`, optional, defaults to module default) workspace and insights data retention in days.
  EOF
  default     = null
  type = object({
    name                      = string
    create_workspace          = optional(bool, true)
    resource_group_name       = optional(string)
    sku                       = optional(string)
    metrics_retention_in_days = optional(number)
  })
}

variable "bootstrap_storages" {
  description = <<-EOF
  A map defining Azure Storage Accounts used to host file shares for bootstrapping VM-Series.

  Following properties are supported:

  - `name`                      - (`string`, required) name of the Storage Account (globally unique, 3-63 chars, lowercase only).
  - `resource_group_name`       - (`string`, optional, defaults to `var.resource_group_name`) Resource Group hosting the account.
  - `storage_account`           - (`map`, optional, defaults to `{}`) basic Storage Account configuration.
  - `storage_network_security`  - (`map`, optional, defaults to `{}`) network security settings for a new storage account.
    - `min_tls_version`    - (`string`, optional) minimum TLS version.
    - `allowed_public_ips` - (`list`, optional) public IPs allowed to access the storage account.
    - `allowed_subnet_ids` - (`list`, optional) subnet resource IDs allowed to access the storage account.
  - `file_shares_configuration` - (`map`, optional, defaults to `{}`) common File Share settings.
  - `file_shares`               - (`map`, optional, defaults to `{}`) File Shares and bootstrap package configuration.
  EOF
  default     = {}
  nullable    = false
  type = map(object({
    name                = string
    resource_group_name = optional(string)
    storage_account = optional(object({
      create           = optional(bool)
      replication_type = optional(string)
      kind             = optional(string)
      tier             = optional(string)
      blob_retention   = optional(number)
    }), {})
    storage_network_security = optional(object({
      min_tls_version    = optional(string)
      allowed_public_ips = optional(list(string))
      allowed_subnet_ids = optional(list(string), [])
    }), {})
    file_shares_configuration = optional(object({
      create_file_shares            = optional(bool)
      disable_package_dirs_creation = optional(bool)
      quota                         = optional(number)
      access_tier                   = optional(string)
    }), {})
    file_shares = optional(map(object({
      name                   = string
      bootstrap_package_path = optional(string)
      bootstrap_files        = optional(map(string))
      bootstrap_files_md5    = optional(map(string))
      quota                  = optional(number)
      access_tier            = optional(string)
    })), {})
  }))
}

variable "vmseries_universal" {
  description = <<-EOF
  A map defining common settings for all created VM-Series instances. Values here can be overridden per-firewall in `var.vmseries`.

  Following properties are supported:

  - `use_airs`          - (`bool`, optional, defaults to `false`) when `true`, uses the AI Runtime Security VM image.
  - `version`           - (`string`, optional) PAN-OS image version from Azure Marketplace.
  - `size`              - (`string`, optional) Azure VM size. Consult the VM-Series Deployment Guide for supported sizes.
  - `bootstrap_options` - (`map`, optional, mutually exclusive with `bootstrap_package`) bootstrap options passed to PAN-OS.
  - `bootstrap_package` - (`map`, optional, mutually exclusive with `bootstrap_options`) bootstrap package configuration.
  EOF
  default     = {}
  type = object({
    use_airs = optional(bool)
    version  = optional(string)
    size     = optional(string)
    bootstrap_options = optional(object({
      type                                  = optional(string)
      ip-address                            = optional(string)
      default-gateway                       = optional(string)
      netmask                               = optional(string)
      ipv6-address                          = optional(string)
      ipv6-default-gateway                  = optional(string)
      hostname                              = optional(string)
      panorama-server                       = optional(string)
      panorama-server-2                     = optional(string)
      tplname                               = optional(string)
      dgname                                = optional(string)
      cgname                                = optional(string)
      dns-primary                           = optional(string)
      dns-secondary                         = optional(string)
      vm-auth-key                           = optional(string)
      op-command-modes                      = optional(string)
      op-cmd-dpdk-pkt-io                    = optional(string)
      plugin-op-commands                    = optional(string)
      dhcp-send-hostname                    = optional(string)
      dhcp-send-client-id                   = optional(string)
      dhcp-accept-server-hostname           = optional(string)
      dhcp-accept-server-domain             = optional(string)
      vm-series-auto-registration-pin-id    = optional(string)
      vm-series-auto-registration-pin-value = optional(string)
      auth-key                              = optional(string)
      authcodes                             = optional(string)
    }))
    bootstrap_package = optional(object({
      bootstrap_storage_key  = string
      static_files           = optional(map(string), {})
      bootstrap_package_path = optional(string)
      bootstrap_xml_template = optional(string)
      ai_update_interval     = optional(number, 5)
      intranet_cidr          = optional(string)
    }))
  })
  validation {
    condition = alltrue([
      var.vmseries_universal.bootstrap_options != null && var.vmseries_universal.bootstrap_package == null ||
      var.vmseries_universal.bootstrap_options == null && var.vmseries_universal.bootstrap_package != null ||
      var.vmseries_universal.bootstrap_options == null && var.vmseries_universal.bootstrap_package == null
    ])
    error_message = "Either `bootstrap_options` or `bootstrap_package` can be set, not both."
  }
}

variable "vmseries" {
  description = <<-EOF
  A map defining Azure Virtual Machines based on Palo Alto Networks VM-Series NGFW image.

  The most important properties are as follows:

  - `name`            - (`string`, required) name of the VM, will be prefixed with `var.name_prefix`.
  - `authentication`  - (`map`, optional) firewall admin credentials. Defaults to username `panadmin` with auto-generated password.
  - `image`           - (`map`, optional) base image settings. Set `version` or `custom_id`. Falls back to `vmseries_universal`.
  - `virtual_machine` - (`map`, required) VM configuration:
    - `zone`              - (`string`, required) Availability Zone for the VM and its public IPs.
    - `size`              - (`string`, optional) Azure VM size.
    - `bootstrap_options` - (`map`, optional, mutually exclusive with `bootstrap_package`) PAN-OS bootstrap key-value options.
    - `bootstrap_package` - (`map`, optional, mutually exclusive with `bootstrap_options`) bootstrap package from Storage Account.
  - `interfaces`      - (`list`, required) ordered list of network interfaces (first = management):
    - `name`              - (`string`, required) interface name (prefixed with `var.name_prefix`).
    - `subnet_key`        - (`string`, required) key into `var.subnet_ids` for the subnet to attach this interface to.
    - `ip_configurations` - (`map`, required) IP configuration(s) for the interface.
    - `load_balancer_key` - (`string`, optional) key into `var.lb_backend_pool_ids` to register with a load balancer backend pool.
  - `logging_disks`   - (`map`, optional) additional data disks for VM-Series logging.
  EOF
  default     = {}
  nullable    = false
  type = map(object({
    name = string
    authentication = optional(object({
      username                        = optional(string, "panadmin")
      password                        = optional(string)
      disable_password_authentication = optional(bool, false)
      ssh_keys                        = optional(list(string), [])
    }), {})
    image = optional(object({
      use_airs                = optional(bool)
      version                 = optional(string)
      publisher               = optional(string)
      offer                   = optional(string)
      sku                     = optional(string)
      enable_marketplace_plan = optional(bool)
      custom_id               = optional(string)
    }))
    virtual_machine = object({
      size = optional(string)
      bootstrap_options = optional(object({
        type                                  = optional(string)
        ip-address                            = optional(string)
        default-gateway                       = optional(string)
        netmask                               = optional(string)
        ipv6-address                          = optional(string)
        ipv6-default-gateway                  = optional(string)
        hostname                              = optional(string)
        panorama-server                       = optional(string)
        panorama-server-2                     = optional(string)
        tplname                               = optional(string)
        dgname                                = optional(string)
        cgname                                = optional(string)
        dns-primary                           = optional(string)
        dns-secondary                         = optional(string)
        vm-auth-key                           = optional(string)
        op-command-modes                      = optional(string)
        op-cmd-dpdk-pkt-io                    = optional(string)
        plugin-op-commands                    = optional(string)
        dhcp-send-hostname                    = optional(string)
        dhcp-send-client-id                   = optional(string)
        dhcp-accept-server-hostname           = optional(string)
        dhcp-accept-server-domain             = optional(string)
        vm-series-auto-registration-pin-id    = optional(string)
        vm-series-auto-registration-pin-value = optional(string)
        auth-key                              = optional(string)
        authcodes                             = optional(string)
      }))
      bootstrap_package = optional(object({
        bootstrap_storage_key  = string
        static_files           = optional(map(string), {})
        bootstrap_package_path = optional(string)
        bootstrap_xml_template = optional(string)
        ai_update_interval     = optional(number, 5)
        intranet_cidr          = optional(string)
      }))
      zone                          = string
      disk_type                     = optional(string)
      disk_name                     = optional(string)
      avset_key                     = optional(string)
      capacity_reservation_group_id = optional(string)
      accelerated_networking        = optional(bool)
      allow_extension_operations    = optional(bool)
      encryption_at_host_enabled    = optional(bool)
      disk_encryption_set_id        = optional(string)
      enable_boot_diagnostics       = optional(bool, true)
      boot_diagnostics_storage_uri  = optional(string)
      identity_type                 = optional(string)
      identity_ids                  = optional(list(string))
    })
    interfaces = list(object({
      name       = string
      subnet_key = string
      ip_configurations = map(object({
        name                          = optional(string)
        primary                       = optional(bool, true)
        create_public_ip              = optional(bool, false)
        public_ip_name                = optional(string)
        public_ip_resource_group_name = optional(string)
        private_ip_address            = optional(string)
      }))
      load_balancer_key = optional(string)
    }))
    logging_disks = optional(map(object({
      name      = string
      size      = optional(string)
      lun       = string
      disk_type = optional(string)
    })), {})
  }))
  validation {
    condition = alltrue([
      for _, v in var.vmseries :
      v.virtual_machine.bootstrap_options != null && v.virtual_machine.bootstrap_package == null ||
      v.virtual_machine.bootstrap_options == null && v.virtual_machine.bootstrap_package != null ||
      v.virtual_machine.bootstrap_options == null && v.virtual_machine.bootstrap_package == null
    ])
    error_message = "Either `bootstrap_options` or `bootstrap_package` can be set per VM, not both."
  }
}
