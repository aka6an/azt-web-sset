output "ws_rg_name" {
    value = "${azurerm_resource_group.ws_rg.name}"
}

output "ws_public_ip_id" {
    value = "${azurerm_public_ip.ws_public_ip.id}"
}

output "ws_vnet_id" {
    value = "${azurerm_virtual_network.ws_vnet.id}"
}

output "ws_vnet_name" {
    value = "${azurerm_virtual_network.ws_vnet.name}"
}
