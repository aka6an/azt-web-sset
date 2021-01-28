variable "tf_script_version" {}
variable "environment" {}
variable "prefixes" {}
variable "locations" {}
variable "ws_name" {}
variable "ws_count" {}
variable "address_space" {}
variable "ws_subnets" {}
variable "domain_name_label" {}

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

// Create Resource Group (RG)
 resource "azurerm_resource_group" "ws_rg" {
     name = "${var.prefixes}Web-RG"
     location = var.locations
     tags = merge(local.common_tags,local.extra_tags) 
 }     

// Create Virtual Network (VNet)
 resource "azurerm_virtual_network" "ws_vnet" {
     name = "${var.prefixes}vnet"
     location = var.locations
     resource_group_name = azurerm_resource_group.ws_rg.name
     address_space = [var.address_space]
 }

// Create Subnets
 resource "azurerm_subnet" "ws_subnet" {
     name = "${var.prefixes}${var.ws_name}-${substr(var.ws_subnets[count.index],0,length(var.ws_subnets[count.index])-3)}-subnet"
     resource_group_name = azurerm_resource_group.ws_rg.name
     virtual_network_name = azurerm_virtual_network.ws_vnet.name
     address_prefixes = [var.ws_subnets[count.index]]
// [DEPRECATED] Use the `azurerm_subnet_network_security_group_association`, see line 83
//     network_security_group_id = "${count.index == 0 ? "${azurerm_network_security_group.ws_nsg.id}" : ""}"
     count = length(var.ws_subnets)
 }

// Create Public IP (dynamic), it will be assigned to LB associated with Scale Set
 resource "azurerm_public_ip" "ws_public_ip" {
     name = "${var.prefixes}lb-public-ip"
     location = var.locations
     resource_group_name = azurerm_resource_group.ws_rg.name
     allocation_method = var.environment != "production" ? "Static" : "Dynamic" 
     domain_name_label = var.domain_name_label
 }

// Create Network Security Group (NSG)
 resource "azurerm_network_security_group" "ws_nsg"{
     name = "${var.prefixes}nsg"
     location = var.locations
     resource_group_name = azurerm_resource_group.ws_rg.name 
 } 

// Create NSG Rule (Inbound HTTP, TCP/80)
 resource "azurerm_network_security_rule" "ws_nsg_http" {
     name = "HTTP Inbound"
     priority = 100
     direction = "Inbound"
     access = "Allow"
     protocol = "TCP"
     source_port_range = "*"
     destination_port_range = "80"
     source_address_prefix = "*"
     destination_address_prefix = "*"
     network_security_group_name = azurerm_network_security_group.ws_nsg.name
     resource_group_name = azurerm_resource_group.ws_rg.name 
 }

 resource "azurerm_subnet_network_security_group_association" "snet_nsg" {
     subnet_id = azurerm_subnet.ws_subnet[0].id
     network_security_group_id = azurerm_network_security_group.ws_nsg.id
 }

// Create scale set (web server)
 resource "azurerm_virtual_machine_scale_set" "ws_ss" {
     name = "${var.prefixes}${local.ws_name}-sset"
     location = var.locations
     resource_group_name = azurerm_resource_group.ws_rg.name
     upgrade_policy_mode = "manual"

     sku {
         name = "Standard_B1s"
         tier = "Standard"
         capacity = var.ws_count

     }

     storage_profile_image_reference {
         publisher = "MicrosoftWindowsServer"
         offer = "WindowsServer"
         sku = "2016-Datacenter-Server-Core-smalldisk"
         version = "latest"
     }

     storage_profile_os_disk {
         name = ""
         caching = "ReadWrite"
         create_option = "FromImage"
         managed_disk_type = "Standard_LRS"
     }

     os_profile {
         computer_name_prefix = "${var.prefixes}${local.ws_name}"
         admin_username = "PTI-Admin"
         admin_password = "lg6%MDN28K)Y;0]2*w2x28SC"
     }

     os_profile_windows_config{
         provision_vm_agent = true
     }

     network_profile {
         name = "ws-network-profile"
         primary = true

         ip_configuration {
             name = "${var.prefixes}${local.ws_name}"
             primary = true
             subnet_id = azurerm_subnet.ws_subnet.*.id[0]
             load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.ws_lb_backend_pool.id]
         }
     }

     extension {
         name = "${var.prefixes}${local.ws_name}-ext"
         publisher = "Microsoft.Compute"
         type = "CustomScriptExtension"
         type_handler_version = "1.9"

         settings = <<SETTINGS
         {
             "fileUris": ["https://raw.githubusercontent.com/eltimmo/learning/master/azureInstallWebServer.ps1"],
             "commandToExecute": "start powershell -ExecutionPolicy Unrestricted -File azureInstallWebServer.ps1"
         }
         SETTINGS

     }
 }

// Create load balancer
 resource "azurerm_lb" "ws_lb"{
     name = "${var.prefixes}lb"
     location = var.locations
     resource_group_name = azurerm_resource_group.ws_rg.name   

     frontend_ip_configuration {
         name = "${var.prefixes}lb-frontend-ip"
         public_ip_address_id = azurerm_public_ip.ws_public_ip.id
     }
 }

// Create load balancer back-end pool
 resource "azurerm_lb_backend_address_pool" "ws_lb_backend_pool" {
     name = "${var.prefixes}lb-backend-pool"
     resource_group_name = azurerm_resource_group.ws_rg.name
     loadbalancer_id = azurerm_lb.ws_lb.id   
 }

// Create load balancer health probe
 resource "azurerm_lb_probe" "ws_lb_probe" {
     name = "${var.prefixes}lb-probe"
     resource_group_name = azurerm_resource_group.ws_rg.name
     loadbalancer_id = azurerm_lb.ws_lb.id   
     protocol = "tcp"
     port = "80"
 }

// Create load balancer rule
 resource "azurerm_lb_rule" "ws_lb_rule" {
     name = "${var.prefixes}lb-rule"
     resource_group_name = azurerm_resource_group.ws_rg.name
     loadbalancer_id = azurerm_lb.ws_lb.id   
     protocol = "tcp"
     frontend_port = "80"
     backend_port = "80"
     frontend_ip_configuration_name = "${var.prefixes}lb-frontend-ip"
     probe_id = azurerm_lb_probe.ws_lb_probe.id
     backend_address_pool_id = azurerm_lb_backend_address_pool.ws_lb_backend_pool.id
 }
