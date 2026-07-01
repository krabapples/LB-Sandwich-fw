# Generate a random password

# https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password
resource "random_password" "this" {
  count = anytrue([for _, v in var.vmseries : v.authentication.password == null]) ? 1 : 0

  length           = 16
  min_lower        = 16 - 4
  min_numeric      = 1
  min_special      = 1
  min_upper        = 1
  override_special = "_%@"
}

locals {
  authentication = {
    for k, v in var.vmseries : k =>
    merge(
      v.authentication,
      {
        ssh_keys = [for ssh_key in v.authentication.ssh_keys : file(ssh_key)]
        password = coalesce(v.authentication.password, try(random_password.this[0].result, null))
      }
    )
  }
}

# Source the existing Resource Group created by LB-Sandwich-infra

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group
data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

# Create VM-Series metrics resources

module "ngfw_metrics" {
  source = "github.com/PaloAltoNetworks/terraform-azurerm-swfw-modules//modules/ngfw_metrics?ref=v3.5.1"

  count = var.ngfw_metrics != null ? 1 : 0

  create_workspace = var.ngfw_metrics.create_workspace

  name = "${var.ngfw_metrics.create_workspace ? var.name_prefix : ""}${var.ngfw_metrics.name}"
  resource_group_name = var.ngfw_metrics.create_workspace ? data.azurerm_resource_group.this.name : (
    coalesce(var.ngfw_metrics.resource_group_name, data.azurerm_resource_group.this.name)
  )
  region = var.region

  log_analytics_workspace = {
    sku                       = var.ngfw_metrics.sku
    metrics_retention_in_days = var.ngfw_metrics.metrics_retention_in_days
  }

  application_insights = { for k, v in var.vmseries : k => { name = "${var.name_prefix}${v.name}-ai" } }

  tags = var.tags
}

# Bootstrap storage accounts

locals {
  bootstrap_file_shares_flat = flatten([
    for k, v in var.vmseries :
    merge(try(coalesce(v.virtual_machine.bootstrap_package, var.vmseries_universal.bootstrap_package), null), { vm_key = k })
    if try(v.virtual_machine.bootstrap_package != null || var.vmseries_universal.bootstrap_package != null, false)
  ])

  bootstrap_file_shares = { for k, v in var.bootstrap_storages : k => {
    for file_share in local.bootstrap_file_shares_flat : file_share.vm_key => {
      name                   = file_share.vm_key
      bootstrap_package_path = file_share.bootstrap_package_path
      bootstrap_files        = file_share.static_files
      bootstrap_files_md5    = {}
    } if file_share.bootstrap_storage_key == k }
  }
}

module "bootstrap" {
  source = "github.com/PaloAltoNetworks/terraform-azurerm-swfw-modules//modules/bootstrap?ref=v3.5.1"

  for_each = var.bootstrap_storages

  storage_account     = each.value.storage_account
  name                = each.value.name
  resource_group_name = coalesce(each.value.resource_group_name, data.azurerm_resource_group.this.name)
  region              = var.region

  storage_network_security = {
    min_tls_version    = each.value.storage_network_security.min_tls_version
    allowed_public_ips = each.value.storage_network_security.allowed_public_ips
    allowed_subnet_ids = each.value.storage_network_security.allowed_subnet_ids
  }
  file_shares_configuration = each.value.file_shares_configuration
  file_shares               = local.bootstrap_file_shares[each.key]

  tags = var.tags
}

# Availability Sets

# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/availability_set
resource "azurerm_availability_set" "this" {
  for_each = var.availability_sets

  name                         = "${var.name_prefix}${each.value.name}"
  resource_group_name          = data.azurerm_resource_group.this.name
  location                     = var.region
  platform_update_domain_count = each.value.update_domain_count
  platform_fault_domain_count  = each.value.fault_domain_count

  tags = var.tags
}

# Deploy VM-Series firewalls

module "vmseries" {
  source = "github.com/PaloAltoNetworks/terraform-azurerm-swfw-modules//modules/vmseries?ref=v3.5.1"

  for_each = var.vmseries

  name                = "${var.name_prefix}${each.value.name}"
  region              = var.region
  resource_group_name = data.azurerm_resource_group.this.name

  authentication = local.authentication[each.key]
  image = merge(
    each.value.image,
    {
      use_airs = try(each.value.image.use_airs, var.vmseries_universal.use_airs, false)
      version  = try(each.value.image.version, var.vmseries_universal.version, null)
    }
  )
  virtual_machine = merge(
    each.value.virtual_machine,
    {
      disk_name = "${var.name_prefix}${coalesce(each.value.virtual_machine.disk_name, "${each.value.name}-osdisk")}"
      avset_id  = try(azurerm_availability_set.this[each.value.virtual_machine.avset_key].id, null)
      size      = try(coalesce(each.value.virtual_machine.size, var.vmseries_universal.size), null)
      bootstrap_options = try(
        join(";", [for k, v in each.value.virtual_machine.bootstrap_options : "${k}=${v}" if v != null]),
        join(";", [for k, v in var.vmseries_universal.bootstrap_options : "${k}=${v}" if v != null]),
        join(";", [
          "storage-account=${module.bootstrap[
          each.value.virtual_machine.bootstrap_package.bootstrap_storage_key].storage_account_name}",
          "access-key=${module.bootstrap[
          each.value.virtual_machine.bootstrap_package.bootstrap_storage_key].storage_account_primary_access_key}",
          "file-share=${each.key}",
          "share-directory=None"
        ]),
        join(";", [
          "storage-account=${module.bootstrap[
          var.vmseries_universal.bootstrap_package.bootstrap_storage_key].storage_account_name}",
          "access-key=${module.bootstrap[
          var.vmseries_universal.bootstrap_package.bootstrap_storage_key].storage_account_primary_access_key}",
          "file-share=${each.key}",
          "share-directory=None"
        ]),
        null
      )
      bootstrap_package = try(
        coalesce(each.value.virtual_machine.bootstrap_package, var.vmseries_universal.bootstrap_package),
        null
      )
    }
  )

  interfaces = [for v in each.value.interfaces : {
    name      = "${var.name_prefix}${v.name}"
    subnet_id = var.subnet_ids[v.subnet_key]
    ip_configurations = { for vk, vv in v.ip_configurations : vk => {
      name                          = coalesce(vv.name, "primary")
      create_public_ip              = vv.create_public_ip
      public_ip_name                = vv.create_public_ip ? "${var.name_prefix}${coalesce(vv.public_ip_name, "${v.name}-${vk}-pip")}" : vv.public_ip_name
      primary                       = vv.primary
      public_ip_resource_group_name = vv.public_ip_resource_group_name
      public_ip_id                  = null
      private_ip_address            = vv.private_ip_address
    } }
    attach_to_lb_backend_pool    = v.load_balancer_key != null
    lb_backend_pool_id           = try(var.lb_backend_pool_ids[v.load_balancer_key], null)
    attach_to_appgw_backend_pool = false
    appgw_backend_pool_id        = null
  }]

  logging_disks = { for k, v in each.value.logging_disks : k => merge(v, { name = "${var.name_prefix}${v.name}" }) }

  tags = var.tags
  depends_on = [
    azurerm_availability_set.this,
    module.bootstrap,
  ]
}
