# Kubernetes deployment for IR

Requirements:
-------------

- [Install k0sctl](https://github.com/k0sproject/k0sctl#installation)
- Access to the STFC cloud openstack account
- Install conda (recommend mambaforge) for managing the k8s repo or install python-kubernetes, ansible, and all of the kubernetes management software (kubernetes-client, kuberentes-server, etc) into your system/distro.
- [Install Cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli)
- [Install hubble Client](https://docs.cilium.io/en/v1.10/gettingstarted/hubble_setup/#install-the-hubble-client)

Conda env setup
---------------
To create a conda environment that can sustain development of this repository (excluding k0sctl and setup of k0s itself) you can run the following command, whilst in the repository:

```shell
conda env create -f k8s-conda-env.yml
```

Recommended installs:
------------

After installing the conda env, activate it and install this plugin to helm.

```shell
helm plugin install https://github.com/databus23/helm-diff
```

Cloud setup:
----------
Setup the VMs if they don't exist already

- 2 control nodes size c3.small
- 3 application work nodes size c3.medium
- 2 queue work nodes size l2.small

Create a load balancer for TCP forwarding to the 3 controllers. To achieve this you will need to forward all traffic from these ports:

- 6443 (for Kubernetes API)
- 8132 (for Konnectivity)
- 9443 (for controller join API)

Adding new nodes or changing the config
---------------------------------------

There are two places you need to change IP addresses:

- k0sctl.yaml
- ansible/inventory.yaml

Using k0sctl to setup the kubernetes cluster
--------------------------------------------

- Setup an ssh-agent for connecting to the cluster with k0sctl

```shell
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa
```

- Ensure that the k0sctl.yaml file uses your FedId for the user on each host
- Run k0sctl apply with the config

```shell
k0sctl apply --config k0sctl.yaml --no-wait
```

- Export the kubeconfig

```shell
k0sctl kubeconfig > kubeconfig
```

- Export KUBECONFIG

```shell
export KUBECONFIG=/path/to/kubeconfig
```

Add the k8s componenets needed for IR
-------------------------------------

Navigate to the ansible playbook directory and run the playbook for deploying K8s tools such as Traefik, Cilium etc.

```shell
ansible-playbook deploy-k8s-services.yml 
```

Gotchas
-------

- Kube-proxy is turned off so that Cilium can handle networking for us with better performance, the great the Linux Kernel version the more functionality this can provide so we should be as up to date in terms of kernel as possible. Minimum versions are: v4.19.57, v5.1.16, v5.2.0 it's based on the socket-LB feature. Details [here](https://docs.cilium.io/en/v1.12/gettingstarted/kubeproxy-free/)