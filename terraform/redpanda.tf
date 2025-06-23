variable "image" {
    default = "ubuntu-noble-24.04-nogui"
}

# Used by the load balancer too
variable "redpanda_flavour" {
    default = "l3.tiny"
}

variable "redpanda_count" {
    default = 3 
}

variable "security_groups" {
    default = ["All"]
}

variable "redpanda_floating_ips" {
  type    = list(string)
  default = ["130.246.81.45", "130.246.81.166", "130.246.81.188"]
}

######################################################################################################
# SSH Keys
######################################################################################################

resource "openstack_compute_keypair_v2" "keypair" {
  name = "service-key" # Use fedID as this is reused in the k0sctl definition at the bottom
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC2xwcH2xtljOH20tzornv5J5oezBs7/co0GSLZiXpldx4Zhp9kwHQ+/exFoCBMmQQ0DvNSKHBt3KunIOWyJSmPl3+4wRQAqoL/uaUWYZbVfNjG4gQzVxf8TXutsw6DhrKpwBRduzYU9OGvYFRtvS59PKkEyj2UJf3BGkOKAYU2MR8UdE6Stxu5FcnATMCgyrLc1RkPPvSuKvF3a7+TuKKzhRP3zT+ysHAp5scCc8tIjq5+mjS+s538VW8z/hMORWADLOMmJMceOyWTYScZE0tFZc0Jdn8LrnRDYHp36RFZziFCHpfNwrMg+uXOCsmObx425dNcDPVkkMCiT/a7Tp09 Generated-by-Nova"
}

######################################################################################################
# Server groups
######################################################################################################

resource "openstack_compute_servergroup_v2" "redpanda-group" {
    name = "redpanda-group"
    policies = ["soft-anti-affinity"]
}

######################################################################################################
# Networking
######################################################################################################

data "openstack_networking_network_v2" "external" {
  name = "External"
  network_id = "5283f642-8bd8-48b6-8608-fa3006ff4539"
}

resource "openstack_networking_network_v2" "redpanda" {
  name           = "redpanda"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "redpanda" {
  name       = "redpanda"
  network_id = openstack_networking_network_v2.redpanda.id
  cidr       = "192.168.199.0/24"
  ip_version = 4
}


resource "openstack_networking_router_v2" "redpanda_router" {
  name = "redpanda-router"
  external_network_id = data.openstack_networking_network_v2.external.id
}

resource "openstack_networking_router_interface_v2" "redpanda_router_interface" {
  router_id = openstack_networking_router_v2.redpanda_router.id
  subnet_id = openstack_networking_subnet_v2.redpanda.id
}

######################################################################################################
# Nodes - Redpanda
######################################################################################################

resource "openstack_compute_instance_v2" "redpanda" {
  name = "redpanda-${count.index+1}"
  image_name = var.image
  flavor_name = var.redpanda_flavour
  key_pair = "${openstack_compute_keypair_v2.keypair.name}"
  security_groups = var.security_groups
  count = var.redpanda_count
  network {
    # DO NOT USE "Internal"
    name = "redpanda"
  }
  scheduler_hints {
        group = openstack_compute_servergroup_v2.redpanda-group.id 
    }
}

######################################################################################################
# Floating IPs
######################################################################################################

resource "openstack_compute_floatingip_associate_v2" "redpanda_fip_assoc" {
  count       = var.redpanda_count
  floating_ip = var.redpanda_floating_ips[count.index]
  instance_id = openstack_compute_instance_v2.redpanda[count.index].id
}

######################################################################################################
# Output
######################################################################################################

output "ansible_inventory" {
  value = templatefile(
    "${path.module}/templates/ansible-inventory.tftpl",
    {
        user = openstack_compute_keypair_v2.keypair.name,
        redpanda = var.redpanda_floating_ips.*
    }
  )
}
