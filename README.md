# Kubernetes deployment for IR

Requirements:
-------------

- [Install k0sctl](https://github.com/k0sproject/k0sctl#installation)
- Access to the STFC cloud openstack account
- Install conda (recommend mambaforge) for managing the k8s repo or install python-kubernetes, ansible, and all of the kubernetes management software (kubernetes-client, kuberentes-server, etc) into your system/distro.

Cloud VMs:
----------
Setup the VMs if they don't exist already

- 2 control nodes size c3.medium
- 3 application work nodes size c3.medium
- 2 queue work nodes size l2.small

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
k0sctl apply --config k0sctl.yaml
```

- Export the kubeconfig

```shell
k0sctl kubeconfig > kubeconfig
```

Conda env setup
---------------
To create a conda environment that can sustain development of this repository (excluding k0sctl and setup of k0s itself) you can run the following command, whilst in the repository:

```shell
conda env create -f k8s-conda-env.yml
```

Add the k8s componenets needed for IR
-------------------------------------

....
