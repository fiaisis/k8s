# Define required providers
terraform {
required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.48.0"
    }
  }
}

# You need to set up the openstack environment following this guide:
# https://stfc-cloud-docs.readthedocs.io/en/latest/howto/CreateVMFromCommandLine.html#setting-up-the-environment-to-select-project
provider "openstack" {
  
}