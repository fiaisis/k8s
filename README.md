# Kubernetes deployment for IR

Requirements
-------------

- [Install k0sctl](https://github.com/k0sproject/k0sctl#installation)
- Access to the STFC cloud via an openstack account, with [setup environment variables](https://stfc-cloud-docs.readthedocs.io/en/latest/howto/CreateVMFromCommandLine.html#setting-up-the-environment-to-select-project) on the terminal of choice.
- Install conda (recommend mambaforge) for managing the k8s repo or install python-kubernetes, ansible, and all of the kubernetes management software (kubernetes-client, kuberentes-server, etc) into your system/distro.

Optional (Recommended for debugging and evaluating the cluster)
----------------------------------------------------------------

- [Install Cilium CLI (networking)](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli)
- [Install hubble Client (networking webapp)](https://docs.cilium.io/en/v1.10/gettingstarted/hubble_setup/#install-the-hubble-client)
- [K9s (K8s management in a terminal)](https://k9scli.io/topics/install/)

Conda env setup
---------------

To create a conda environment that can sustain development of this repository (excluding k0sctl and setup of k0s itself) you can run the following command, whilst in the repository:

```shell
conda env create -f k8s-conda-env.yml
```

Recommended installs
---------------------

After installing the conda env, activate it and install this plugin to helm.

```shell
helm plugin install https://github.com/databus23/helm-diff
```

Cloud setup and deploy k0s via k0sctl in terraform
---------------------------------------------------

You can achieve this by using terraform (included in the conda environment) from inside the terraform directory. `terraform apply` can fail due to cloud instability, if it does, just run it again. You need to have setup the environment variables for openstack listed in the requirements at the top of this file.

Ensure that the `terraform/main.tf` file uses your FedId for the SSH Key name, and the key is up to date with yours.

```shell
terraform init
terraform apply
```

Setup an ssh-agent for connecting to the cluster with k0sctl. Example:

```shell
eval "$(ssh-agent -c)"
ssh-add ~/.ssh/id_rsa
```

Use terraform to output the ansible inventory into your ansible directory

```shell
terraform output -raw ansible_inventory > ../ansible/inventory.ini
```

Use terraform to output the haproxy.cfg

```shell
terraform output -raw haproxy_config > ../ansible/haproxy.cfg
```

Use ansible to activate the firewall and create the load balancer required for the k0s cluster (It is recommended to run these repeatedly until they execute with no errors):

```shell
cd ../ansible; ansible-playbook setup-nodes.yml --ask-vault-password; cd ../terraform
```

Use terraform to output the data and then apply that to construct the k0s cluster.

```shell
terraform output -raw k0s_cluster | k0sctl apply --no-wait --config -
```

Export the kubeconfig to the top of the repository, whilst in the terraform directory

```shell
terraform output -raw k0s_cluster | k0sctl kubeconfig --config - > ../kubeconfig
```

Export KUBECONFIG as an environment variable so that ansible can pick it up

```shell
export KUBECONFIG=/path/to/repository/kubeconfig
```

Run the playbook for deploying K8s tools such as Traefik, Cilium, Longhorn, Prometheus, Promtail etc.

```shell
cd ../ansible; ansible-playbook deploy-k8s-services.yml --ask-vault-password ; cd ../terraform
```

Gotchas
-------

- `terraform apply` struggles with creating all the openstack VMs, this happens when doing it manually and is not related to terraform, it is due to cloud instability as far as we can tell.

Updating different parts of the cluster
---------------------------------------

In order to update the container versions on the cluster, for each of the containers that we produce, the following commands will be useful:

RunDetection:

```shell
kubectl set image -n ir deployment/rundetection rundetection=ghcr.io/interactivereduction/rundetection@sha256:commit-number
```

JobController:

```shell
kubectl set image -n ir deployment/jobcontroller jobcontroller=ghcr.io/interactivereduction/jobcontroller@sha256:commit-number
```

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

Creating a kafka producer for connecting to the cluster and sending things to a topic
-------------------------------------------------------------------------------------

With the aim of sending data directly to the kafka topics with a producer in your terminal, first of all you will need the kubeconfig variable set and secondly you will need kafka installed from:

Then you will need some variables set by running these commands, the only caveat is that k0s-app-worker-5 may not have any of the kafka brokers on it, so you need to ensure that it is pointing at a node that has one, you can do this by checking k9s or looking at where the kafka pods are running using kubectl:

```shell
set KAFKA_NODE_PORT $(kubectl get service -n kafka kafka-cluster-kafka-external-bootstrap -o=jsonpath='{.spec.ports[0].nodePort}{"\n"}')
set KAFKA_NODE_IP $(kubectl get node k0s-app-worker-5 -o=jsonpath='{range .status.addresses[*]}{.type}{"\t"}{.address}{"\n"}')
```

Then you can actually connect to the kafka topic as a producer:

```shell
~/kafka/bin/kafka-console-producer.sh --bootstrap-server $KAFKA_NODE_IP:$KAFKA_NODE_PORT --topic detected-runs
```

Once connected anything you type and then hit enter on will be sent to the kafka topic as a message!
