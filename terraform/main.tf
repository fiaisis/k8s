variable "image" {
    default = "ubuntu-focal-20.04-nogui"
}

variable "controller_flavour" {
    default = "c3.medium"
}

variable "app_worker_flavour" {
    default = "c3.medium"
}

variable "queue_worker_flavour" {
    default = "l2.small"
}

variable "controller_count" {
    default = 3 # Need to update to load balancer definitions below when this changes to include the extra ips as they are not dynamic
}

variable "app_worker_count" {
    default = 3
}

variable "queue_worker_count" {
    default = 2
}

variable "security_groups" {
    default = ["use-host-firewall"]
}

######################################################################################################
# SSH Keys
######################################################################################################

resource "openstack_compute_keypair_v2" "keypair" {
  name = "vxw59196" # Use fedID as this is reused in the k0sctl definition at the bottom
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDE973x4riglYeO/8QRF2Pbr0rb7W4Q40apqJf1UUnBnKZ04wPmPq9R+20JDt/YpX4i+Nfxv8peFu6+wqrdHLbNWTnQoUq+jWGass5MzadWhaW8Bc8BRuMgCx3dBxLnHKAH9Lrr9PKhY99w2573B8sb5SdJKDJQMCqjpVlQKtgOaJEHZ3iE9eBKDj0z+FveIpA/huLFPXeLmYc3u/DpGgkc59x5xnLPuh4Va0IJ+9DEsru5NYFLVACVW8QsNozWYONs/2xUjO4uL1Ue5wfFoRWU87lgJ8YZNXj1aszrJD4i51cD8Zar1dbHc2CHMDF0oyJBpXd6IfN4F5R4MUVizmtD samuel.jones@stfc.ac.uk"
}

######################################################################################################
# Nodes
######################################################################################################

resource "openstack_compute_instance_v2" "k0s-controllers" {
  name = "k0s-controller-${count.index+1}"
  image_name = var.image
  flavor_name = var.controller_flavour
  key_pair = "${openstack_compute_keypair_v2.keypair.name}"
  security_groups = var.security_groups
  count = var.controller_count
}

resource "openstack_compute_instance_v2" "k0s-app-workers" {
  name = "k0s-app-worker-${count.index+1}"
  image_name = var.image
  flavor_name = var.app_worker_flavour
  key_pair = "${openstack_compute_keypair_v2.keypair.name}"
  security_groups = var.security_groups
  count = var.app_worker_count
}

resource "openstack_compute_instance_v2" "k0s-queue-workers" {
  name = "k0s-queue-worker-${count.index+1}"
  image_name = var.image
  flavor_name = var.queue_worker_flavour
  key_pair = "${openstack_compute_keypair_v2.keypair.name}"
  security_groups = var.security_groups
  count = var.queue_worker_count
}

######################################################################################################
# Load balancer
######################################################################################################

resource "openstack_lb_loadbalancer_v2" "k0s-load-balancer" {
    name = "k0s-load-balancer"
    vip_subnet_id = "78c7fbcc-b76e-4ff3-8e56-e979209032cc"
    admin_state_up = "true"
}

# Konnectivity listener + pool + monitor + members
# ----------------------------------------------------------------------------------------------------

resource "openstack_lb_listener_v2" "Konnectivity" {
    name = "Konnectivity"
    protocol = "TCP"
    protocol_port = 8132
    loadbalancer_id = openstack_lb_loadbalancer_v2.k0s-load-balancer.id
}

resource "openstack_lb_pool_v2" "Konnectivity" {
    name            = "Konnectivity"
    protocol        = "TCP"
    lb_method       = "SOURCE_IP"
    listener_id = openstack_lb_listener_v2.Konnectivity.id

    persistence {
        type = "SOURCE_IP"
    }
}

resource "openstack_lb_monitor_v2" "Konnectivity" {
    pool_id     = openstack_lb_pool_v2.Konnectivity.id
    type        = "TCP"
    delay       = 20
    timeout     = 10
    max_retries = 5
}

resource "openstack_lb_members_v2" "Konnectivity" {
    pool_id = openstack_lb_pool_v2.Konnectivity.id

    member {
        name = openstack_compute_instance_v2.k0s-controllers[0].name
        address = openstack_compute_instance_v2.k0s-controllers[0].access_ip_v4
        protocol_port = 8132
    }

    member {
        name = openstack_compute_instance_v2.k0s-controllers[1].name
        address = openstack_compute_instance_v2.k0s-controllers[1].access_ip_v4
        protocol_port = 8132
    }

    member {
        name = openstack_compute_instance_v2.k0s-controllers[2].name
        address = openstack_compute_instance_v2.k0s-controllers[2].access_ip_v4
        protocol_port = 8132
    }
}

# Controller join API listener + pool + monitor + members
# ----------------------------------------------------------------------------------------------------

resource "openstack_lb_listener_v2" "Controller_join_API" {
    name = "Controller join API"
    protocol = "TCP"
    protocol_port = 9443
    loadbalancer_id = openstack_lb_loadbalancer_v2.k0s-load-balancer.id
}

resource "openstack_lb_pool_v2" "Controller_join_API" {
    name            = "Controller join API"
    protocol        = "TCP"
    lb_method       = "SOURCE_IP"
    listener_id = openstack_lb_listener_v2.Controller_join_API.id

    persistence {
        type = "SOURCE_IP"
    }
}

resource "openstack_lb_monitor_v2" "Controller_join_API" {
    pool_id     = openstack_lb_pool_v2.Controller_join_API.id
    type        = "TCP"
    delay       = 20
    timeout     = 10
    max_retries = 5
}

resource "openstack_lb_members_v2" "Controller_join_API" {
    pool_id = openstack_lb_pool_v2.Controller_join_API.id

    member {
        name = openstack_compute_instance_v2.k0s-controllers[0].name
        address = openstack_compute_instance_v2.k0s-controllers[0].access_ip_v4
        protocol_port = 9443
    }

    member {
        name = openstack_compute_instance_v2.k0s-controllers[1].name
        address = openstack_compute_instance_v2.k0s-controllers[1].access_ip_v4
        protocol_port = 9443
    }

    member {
        name = openstack_compute_instance_v2.k0s-controllers[2].name
        address = openstack_compute_instance_v2.k0s-controllers[2].access_ip_v4
        protocol_port = 9443
    }
}

# Kubernetes API listener + pool + monitor + members
# ----------------------------------------------------------------------------------------------------

resource "openstack_lb_listener_v2" "Kubernetes_API" {
    name = "Kubernetes API"
    protocol = "TCP"
    protocol_port = 6443
    loadbalancer_id = openstack_lb_loadbalancer_v2.k0s-load-balancer.id
}

resource "openstack_lb_pool_v2" "Kubernetes_API" {
    name            = "Kubernetes API"
    protocol        = "TCP"
    lb_method       = "SOURCE_IP"
    listener_id = openstack_lb_listener_v2.Kubernetes_API.id

    persistence {
        type = "SOURCE_IP"
    }
}

resource "openstack_lb_monitor_v2" "Kubernetes_API" {
    pool_id     = openstack_lb_pool_v2.Kubernetes_API.id
    type        = "TCP"
    delay       = 20
    timeout     = 10
    max_retries = 5
}

resource "openstack_lb_members_v2" "Kubernetes_API" {
    pool_id = openstack_lb_pool_v2.Kubernetes_API.id

    member {
        name = openstack_compute_instance_v2.k0s-controllers[0].name
        address = openstack_compute_instance_v2.k0s-controllers[0].access_ip_v4
        protocol_port = 6443
    }

    member {
        name = openstack_compute_instance_v2.k0s-controllers[1].name
        address = openstack_compute_instance_v2.k0s-controllers[1].access_ip_v4
        protocol_port = 6443
    }

    member {
        name = openstack_compute_instance_v2.k0s-controllers[2].name
        address = openstack_compute_instance_v2.k0s-controllers[2].access_ip_v4
        protocol_port = 6443
    }
}

######################################################################################################
# output
######################################################################################################

locals {
    k0s_tmpl = {
        apiVersion = "k0sctl.k0sproject.io/v1beta1"
        kind = "cluster"
        metadata = {
            name = "k0s-cluster"
        }
        spec = {
            hosts = [
                for host in concat(openstack_compute_instance_v2.k0s-controllers, openstack_compute_instance_v2.k0s-app-workers, openstack_compute_instance_v2.k0s-queue-workers) : {
                    ssh = {
                        address = host.access_ip_v4
                        user = openstack_compute_keypair_v2.keypair.name
                        port = 22
                    }
                    role = "${length(regexall("controller", host.name)) > 0 ? "controller" : "worker" }"
                }
            ]
            k0s = {
                version = "1.24.7+k0s.0"
                dynamicConfig = false
                config = {
                    apiVersion = "k0s.k0sproject.io/v1beta1"
                    kind = "cluster"
                    metadata = {
                        name = "k0s"
                    }
                    spec = {
                        api = {
                            externalAddress = openstack_lb_loadbalancer_v2.k0s-load-balancer.vip_address
                            sans = openstack_lb_loadbalancer_v2.k0s-load-balancer.vip_address
                        }
                        network = {
                            provider = "custom"
                        }
                    }
                }
            }
        }
    }
}

output "k0s_cluster" {
  value = yamlencode(local.k0s_tmpl)
}

output "ansible_inventory" {
  value = templatefile(
    "${path.module}/templates/ansible-inventory.tftpl",
    {
        user = openstack_compute_keypair_v2.keypair.name,
        controllers = openstack_compute_instance_v2.k0s-controllers.*.access_ip_v4,
        workers = concat(openstack_compute_instance_v2.k0s-app-workers.*.access_ip_v4, openstack_compute_instance_v2.k0s-queue-workers.*.access_ip_v4)
    }
  )
}