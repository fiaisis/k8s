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
  name = "vxw59196" # Use fedID as this is reused in the k0sctl definition at the bottom
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDE973x4riglYeO/8QRF2Pbr0rb7W4Q40apqJf1UUnBnKZ04wPmPq9R+20JDt/YpX4i+Nfxv8peFu6+wqrdHLbNWTnQoUq+jWGass5MzadWhaW8Bc8BRuMgCx3dBxLnHKAH9Lrr9PKhY99w2573B8sb5SdJKDJQMCqjpVlQKtgOaJEHZ3iE9eBKDj0z+FveIpA/huLFPXeLmYc3u/DpGgkc59x5xnLPuh4Va0IJ+9DEsru5NYFLVACVW8QsNozWYONs/2xUjO4uL1Ue5wfFoRWU87lgJ8YZNXj1aszrJD4i51cD8Zar1dbHc2CHMDF0oyJBpXd6IfN4F5R4MUVizmtD samuel.jones@stfc.ac.uk"
}

######################################################################################################
# Server groups
######################################################################################################

resource "openstack_compute_servergroup_v2" "redpanda-group" {
    name = "redpanda-group"
    policies = ["soft-anti-affinity"]
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
    name = "Internal"
  }
  scheduler_hints {
        group = openstack_compute_servergroup_v2.redpanda-group.id 
    }
}

######################################################################################################
# Networking
######################################################################################################

data "openstack_networking_network_v2" "internal" {
  name = "Internal"
  network_id = "5be315b7-7ebd-4254-97fe-18c1df501538"
}

data "openstack_networking_network_v2" "external" {
  name = "External"
  network_id = "5283f642-8bd8-48b6-8608-fa3006ff4539"
}

# This is now correctly linked to the 'Internal' network
data "openstack_networking_subnet_v2" "internal_subnet" {
  name       = "Internal1"
  network_id = data.openstack_networking_network_v2.internal.id
  cidr       = "172.16.100.0/22"
}

resource "openstack_networking_router_v2" "redpanda_router" {
  name = "redpanda-router"
  external_network_id = data.openstack_networking_network_v2.external.id
}

resource "openstack_networking_router_interface_v2" "redpanda_router_interface" {
  router_id = openstack_networking_router_v2.redpanda_router.id
  subnet_id = data.openstack_networking_subnet_v2.internal_subnet.id
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
        redpanda = openstack_compute_instance_v2.redpanda.*.access_ip_v4
    }
  )
}
