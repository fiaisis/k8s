# Redpanda deployment

Requirements
------------
- Access to the STFC cloud via an openstack account
- Ansible
- Terraform

If you do have not setup the keypair in the terrafrom file `redpanda.tf` then please do so, and ensure the nodes are using that keypair.

In the terraform dir execute
```
terraform apply
terraform output ansible_inventory > ../ansible/ansible-inventory.ini
```

Run the ansible playbook to setup redpanda from the ansible directory
```
ansible-playbook redpanda.yml -i ansible-inventory.ini
```

Ensure the redpanda console in the kubernetes cluster points at these brokers, this changes happens in the relevant app in the gitops repository.


# Kubernetes deployment for FIA

Requirements
-------------

- Access to the STFC cloud via an openstack account

Optional (Recommended for debugging and evaluating the cluster)
----------------------------------------------------------------

- [K9s (K8s management in a terminal)](https://k9scli.io/topics/install/)
- Helm diff plugin:
```shell
helm plugin install https://github.com/databus23/helm-diff
```

Setup ArgoCD
------------

This section assumes that you have the context setup appropriately in the Kubeconfigs and you are currently managing the management cluster

Install ArgoCD:
```shell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Setup ArgoCD CLI: https://argo-cd.readthedocs.io/en/stable/getting_started/#2-download-argo-cd-cli

Create the Service type load balancer:
```shell
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

Get the initial password:
```
argocd admin initial-password -n argocd
```

Login to the UI using the IP of the worker node running the ArgoCD server, and the port defined in the service for ArgoCD as a URL in your web browser. The username is admin, and the password you already have.

Change the password using the user settings to the one in Keeper so everyone who needs the password has it availiable.

Go follow the GitOps repo [README](https://github.com/interactivereduction/gitops) now.

Developing using a local cluster
--------------------------------

It is recommended HEAVILY that you do not develop using the production cluster. Please use a local cluster using minikube, so install minikube using this guide: <https://minikube.sigs.k8s.io/docs/start/>

You will need the archive mounted locally follow these instructions (you may need to get on the work VPN or log in for this): <https://stfc365.sharepoint.com/sites/isiscomputingdivision-staffsite/Shared%20Documents/Mantid/MountISISArchiveLinux.txt>

or run the following playbook to setup the archive and ceph locally on debian/ubuntu based linux operating systems, you need to replace the all caps words with the actual inputs:
```shell
ansible-playbook setup-local-machine.yml -K --extra-vars '{ "isis_archive": { "username": "FEDID", "password": "FEDID_PASSWORD", "domain": "ARCHIVE_DOMAIN"}, "isis_ceph" {"key": "CEPH_KEY"}}'
```

Start minkube by running this command (ensure kubernetes is the correct version):

```shell
minikube start --kubernetes-version='1.25.6'
minikube mount /archive:/archive &
minikube mount /ceph:/ceph &
```

To deploy services to your cluster:
```shell
ansible-playbook deploy-dev-k8s-services.yml
```

That's it! you have Interactive reduction running on a local Kubernetes cluster!

