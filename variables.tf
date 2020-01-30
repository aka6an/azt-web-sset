# These variables are assigned values based on ENV variables set via .bashrc
variable  "subscription_id" {}
variable  "tenant_id" {}
variable  "client_id" {}
variable  "client_secret" {}

variable "locations" {
    type = map(string)
    default = {
        NC = "northcentralus"
        SC = "southcentralus"
        WC = "westcentralus"
    }
}

variable "prefixes" {
    type = map(string)
    default = {
        TF = "TF-"
        NC = "TF-NC-"
        SC = "TF-SC-"
        WC = "TF-WC-"
    }
}

variable "nc_address_space" {
    default = "10.0.0.0/22"
} 

variable "nc_ws_subnets" {
    type = list(string)
    default = ["10.0.1.0/24","10.0.2.0/24"]
}

variable "sc_address_space" {
    default = "10.1.0.0/22"
} 

variable "sc_ws_subnets" {
    type = list(string)
    default = ["10.1.1.0/24","10.1.2.0/24"]
}


variable "nc_ws_address_prefix" {
    default = "10.0.1.0/24"
}

variable "ws_name" {
    default = "ws"
}

variable "environment" {
    default = "production"
}

variable "ws_count"{
    default = 2
}

variable "tf_script_version" {
    default = "1.00"
}

variable "domain_name_label" {
    default = "tf-afk-web"
}
