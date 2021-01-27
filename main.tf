// Basic setup (provider, version, credentials)
provider "azurerm" {
//  version = ">=2.00.0"
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret
 }

locals {
    ws_name = var.environment != "production" ? "${var.ws_name}-dev" : var.ws_name

    common_tags = {
        ct1-Application = "WebApp-01"
        ct2-Department = "ITSM"
        ct3-Cost = "999"
        ct4-Owner = "John Doe"
    }
    
    extra_tags = {
        et1-ENV = var.environment != "production" ? "DEV" : "PROD"
        et2-BUILD = var.tf_script_version
    }
}

module "location_nc" {
    source = "./location"
    tf_script_version = var.tf_script_version
    environment = var.environment
    prefixes = var.prefixes.NC
    locations = var.locations.NC
    ws_name = var.ws_name
    ws_count = var.ws_count
    address_space = var.nc_address_space
    ws_subnets = var.nc_ws_subnets
    domain_name_label = var.domain_name_label
}

module "location_sc" {
    source = "./location"
    tf_script_version = var.tf_script_version
    environment = var.environment
    prefixes = var.prefixes.SC
    locations = var.locations.SC
    ws_name = var.ws_name
    ws_count = var.ws_count
    address_space = var.sc_address_space
    ws_subnets = var.sc_ws_subnets
    domain_name_label = var.domain_name_label
}

// ****************************************************************************************
//  Traffic Manager Resource Group 
// ****************************************************************************************

// Create Resource Group (RG) for Traffic Manager
 resource "azurerm_resource_group" "tfm_rg" {
     name = "${var.prefixes.TF}TFM-RG"
     location = var.locations.NC
     tags = merge(local.common_tags,local.extra_tags) 
 }     

// ****************************************************************************************
//  Traffic Manager configuration
// ****************************************************************************************

resource "azurerm_traffic_manager_profile" "tfm" {
    name = "${var.prefixes.TF}traffic-manager"
    resource_group_name = azurerm_resource_group.tfm_rg.name
    traffic_routing_method = "Weighted"

    dns_config {
        relative_name = var.domain_name_label
        ttl = 100
    }

    monitor_config {
        protocol = "http"
        port = 80
        path = "/"
    }
}

resource "azurerm_traffic_manager_endpoint" "tfm_nc" {
        name = "${var.prefixes.TF}tfm-nc"
        resource_group_name = azurerm_resource_group.tfm_rg.name
        profile_name = azurerm_traffic_manager_profile.tfm.name
        target_resource_id = module.location_nc.ws_public_ip_id
        type = "azureEndpoints"
        weight = 100
}

resource "azurerm_traffic_manager_endpoint" "tfm_sc" {
        name = "${var.prefixes.TF}tfm-sc"
        resource_group_name = azurerm_resource_group.tfm_rg.name
        profile_name = azurerm_traffic_manager_profile.tfm.name
        target_resource_id = module.location_sc.ws_public_ip_id
        type = "azureEndpoints"
        weight = 100
}

// ****************************************************************************************
//  Jump Host Resource Group 
// ****************************************************************************************

// Create Resource Group (RG) for Jump Host
 resource "azurerm_resource_group" "jh_rg" {
     name = "${var.prefixes.TF}JH-RG"
     location = var.locations.NC
     tags = merge(local.common_tags,local.extra_tags) 
 }     

// ****************************************************************************************
//  Jump Host virtual network, subnet and peering configuration
// ****************************************************************************************

resource "azurerm_virtual_network" "jh_vnet" {
     name = "${var.prefixes.TF}JH-vnet"
     location = var.locations.NC
     resource_group_name = azurerm_resource_group.jh_rg.name
     address_space = ["10.3.0.0/24"]
}
 
resource "azurerm_subnet" "jh_snet" {
     name = "${var.prefixes.TF}JH-snet"
     resource_group_name = azurerm_resource_group.jh_rg.name
     virtual_network_name = azurerm_virtual_network.jh_vnet.name
     address_prefixes = ["10.3.0.0/24"]
}

resource "azurerm_virtual_network_peering" "jh_nc_peer" {
    name = "jh-nc-peer"
    resource_group_name = azurerm_resource_group.jh_rg.name
    virtual_network_name = azurerm_virtual_network.jh_vnet.name
    remote_virtual_network_id = module.location_nc.ws_vnet_id
    allow_virtual_network_access = true
    depends_on = [azurerm_subnet.jh_snet]
}

resource "azurerm_virtual_network_peering" "nc_jh_peer" {
    name = "nc-jh-peer"
    resource_group_name = module.location_nc.ws_rg_name
    virtual_network_name = module.location_nc.ws_vnet_name
    remote_virtual_network_id = azurerm_virtual_network.jh_vnet.id
    allow_virtual_network_access = true
    depends_on = [azurerm_subnet.jh_snet]
}

resource "azurerm_virtual_network_peering" "jh_sc_peer" {
    name = "jh-sc-peer"
    resource_group_name = azurerm_resource_group.jh_rg.name
    virtual_network_name = azurerm_virtual_network.jh_vnet.name
    remote_virtual_network_id = module.location_sc.ws_vnet_id
    allow_virtual_network_access = true
    depends_on = [azurerm_subnet.jh_snet]
}

resource "azurerm_virtual_network_peering" "sc_jh_peer" {
    name = "sc-jh-peer"
    resource_group_name = module.location_sc.ws_rg_name
    virtual_network_name = module.location_sc.ws_vnet_name
    remote_virtual_network_id = azurerm_virtual_network.jh_vnet.id
    allow_virtual_network_access = true
    depends_on = [azurerm_subnet.jh_snet]
}

// ****************************************************************************************
//  Jump Host virtual machine configuration
// ****************************************************************************************

resource "azurerm_network_interface" "jh_nic" {
    name = "${var.prefixes.TF}jh-nic"
    location = var.locations.NC
    resource_group_name = azurerm_resource_group.jh_rg.name
    network_security_group_id = azurerm_network_security_group.jh_nsg.id

    ip_configuration {
        name = "${var.prefixes.TF}jh-ip"
        subnet_id = azurerm_subnet.jh_snet.id
        private_ip_address_allocation = "dynamic"
        public_ip_address_id = azurerm_public_ip.jh_public_ip.id
  }
}

resource "azurerm_public_ip" "jh_public_ip" {
    name = "${var.prefixes.TF}jh-public-ip"
    location = var.locations.NC
    resource_group_name = azurerm_resource_group.jh_rg.name
    allocation_method = var.environment == "production" ? "Static" : "Dynamic"
}

resource "azurerm_network_security_group" "jh_nsg" {
    name = "${var.prefixes.TF}jh-nsg"
    location = var.locations.NC
    resource_group_name = azurerm_resource_group.jh_rg.name
}

resource "azurerm_network_security_rule" "jh_nsg_rule_rdp" {
  name                        = "RDP Inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefix       = "72.66.122.162/32"
  destination_address_prefix  = "*"
  resource_group_name = azurerm_resource_group.jh_rg.name
  network_security_group_name = azurerm_network_security_group.jh_nsg.name 
}

resource "azurerm_virtual_machine" "jh_server" {
    name = "${var.prefixes.TF}jh-01"
    location = var.locations.NC
    resource_group_name = azurerm_resource_group.jh_rg.name
    network_interface_ids        = [azurerm_network_interface.jh_nic.id]
    vm_size                      = "Standard_B2s"

    storage_image_reference {
        publisher = "MicrosoftWindowsServer"
        offer = "WindowsServer"
        sku = "2016-Datacenter"
        version = "latest"
  }

    storage_os_disk {
        name              = "${var.prefixes.TF}jh-01-os"    
        caching           = "ReadWrite"
        create_option     = "FromImage"
        managed_disk_type = "Standard_LRS"
  }
  
    os_profile {
        computer_name      = "${var.prefixes.TF}jh-01" 
        admin_username     = "PTI-Admin"
        admin_password     = "lg6%MDN28K)Y;0]2*w2x28SC"
  }

    os_profile_windows_config {
  }

}
