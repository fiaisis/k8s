# These directories contain the deployments for our clusters

This document is a highly specific reinterpretation of this [documentation](https://stfc-cloud-docs.readthedocs.io/en/latest/Kubernetes/CapiSetup.html) from the STFC Cloud. If you need a more generic set of instructions please look at that documentation.

Before setting up our clusters you need to aquire your clouds.yaml file, follow these [instructions](https://stfc-cloud-docs.readthedocs.io/en/latest/Keystone/ApplicationCredentials.html#create-credential-from-the-web-interface). Please place your clouds.yaml file in each of the cluster folders, there should be one in management, staging, and prod cluster folders (They should be identical). Don't forget to add a `project_id: "c191dbba0d1c4bd6a23414a1bd024de3"` to the auth section of the clouds.yaml file.

You'd also need to setup a local cluster. For the purposes of these instructions we will use [minikube](https://minikube.sigs.k8s.io/docs/), you can also use [kind](https://kind.sigs.k8s.io/) if you prefer.

We also require [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl), [helm](https://helm.sh/docs/intro/install/), and [clusterctl](https://cluster-api.sigs.k8s.io/user/quick-start.html#install-clusterctl).

You need a floating ip manually created for each cluster, this has already been done and has been saved to the values.yaml files.

It's also possible you run into GitHub rate limiting if so you need to add the following to your environment:

```bash
export GITHUB_TOKEN=<your token>
```

## Setup local cluster for management

Start minikube

```bash
minikube start
```

Configure local cluster to create management cluster

```bash
clusterctl init --infrastructure openstack

cd management-cluster
export CLUSTER_NAME="k8s-management"

kubectl create namespace clusters

helm repo add capi https://stackhpc.github.io/capi-helm-charts
helm repo add capi-addons https://stackhpc.github.io/cluster-api-addon-provider
helm repo update

helm upgrade cluster-api-addon-provider capi-addons/cluster-api-addon-provider --install --version ">=0.1.0-dev.0.main.0,<0.1.0-dev.0.main.9999999999" --wait -n clusters

helm upgrade $CLUSTER_NAME capi/openstack-cluster --install -f values.yaml -f clouds.yaml -f user-values.yaml -f flavors.yaml -n clusters
cd ..
```

Wait for the above to finish by running this command and waiting for the cluster to report as "Ready: True":

```bash
watch clusterctl describe cluster -n clusters $CLUSTER_NAME
```

## Migrate to management cluster from local

Now that the manegement cluster exists we should ensure that it is managed by itself and not a local cluster on our dev machine. Run the following:

```bash
clusterctl get kubeconfig $CLUSTER_NAME -n clusters > "kubeconfig-$CLUSTER_NAME"
clusterctl init --infrastructure openstack --kubeconfig="kubeconfig-$CLUSTER_NAME"
clusterctl move --to-kubeconfig "kubeconfig-$CLUSTER_NAME"
```

This management cluster will also need the cluster-api-addon-provider so install that now.

```bash
kubectl create namespace clusters --kubeconfig "kubeconfig-$CLUSTER_NAME"
helm upgrade cluster-api-addon-provider capi-addons/cluster-api-addon-provider --install --version ">=0.1.0-dev.0.main.0,<0.1.0-dev.0.main.9999999999" --wait -n clusters --kubeconfig "kubeconfig-$CLUSTER_NAME"
```

Wait for the migration to complete by waiting for the following to report as complete:

```bash
kubectl get kubeadmcontrolplane --kubeconfig=kubeconfig-$CLUSTER_NAME
```

Now that we are done with that migration you probably want to run the following command to change your kubeconfig file:

```bash
export KUBECONFIG="<path/to/kubeconfig-$CLUSTER_NAME>"
```

## Staging cluster setup using management

Now that we have the management cluster setup what we need to do is create our first "workload" cluster and that will be staging.

To do this run the following commands:
```bash
cd staging-cluster
export CLUSTER_NAME="k8s-staging"
helm upgrade $CLUSTER_NAME capi/openstack-cluster --install -f values.yaml -f clouds.yaml -f user-values.yaml -f flavors.yaml -n clusters --wait
cd ..
clusterctl get kubeconfig $CLUSTER_NAME -n clusters > "kubeconfig-$CLUSTER_NAME"
```

## Production cluster setup using management

Now do the same but for production:
```bash
cd prod-cluster
export CLUSTER_NAME="k8s-prod"
helm upgrade $CLUSTER_NAME capi/openstack-cluster --install -f values.yaml -f clouds.yaml -f user-values.yaml -f flavors.yaml -n clusters --wait
cd ..
clusterctl get kubeconfig $CLUSTER_NAME -n clusters > "kubeconfig-$CLUSTER_NAME"
```

## Go merge your kubeconfigs together

There is a kubectl plugin for this called: [konfig](https://github.com/corneliusweig/konfig)

Install it with [Krew](https://krew.sigs.k8s.io/) (Like brew but for kubectl plugins):

```shell
kubectl krew install konfig
```

Use it like this:
```shell
konfig merge kubeconfig-k8s-management kubeconfig-k8s-prod kubeconfig-k8s-staging > kubeconfig-all 
```

Set your new kubeconfig as the active one
```shell
export KUBECONFIG="<path/to/kubeconfig-all>"
```

## Setup ArgoCD on management

This section assumes that you have the context setup appropriately in the Kubeconfigs, set your context equal to k8s-management.

```shell
kubectl config use-context k8s-management
```

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
```shell
argocd admin initial-password -n argocd
```

Login to the UI using the IP provided by the ArgoCD load balancer this will be an IP inside the firewall. The username is admin, and the password you already have.

Change the password using the user settings to the one in Keeper so everyone who needs the password has it available.

Add the ArgoCD github pat token in the settings of ArgoCD. Navigate to the repository settings, Use these settings:
- Connection Method: Via HTTPS
- Type: git
- Project: default
- Repository URL: https://github.com/interactivereduction/gitops
- Username: interactivereduction
- Password: <GIT TOKEN>

After that we need to go back to the command line:

Login to the ArgoCD CLI:

```bash
argocd --port-forward --port-forward-namespace=argocd login --username=admin --password="ARGOCD_ADMIN_PASSWORD"
```

Add cluster using CLI for staging:

```bash
argocd --port-forward --port-forward-namespace=argocd cluster add k8s-staging-admin@k8s-staging --yes
```

Add cluster using CLI for prod

```bash
argocd --port-forward --port-forward-namespace=argocd cluster add k8s-prod-admin@k8s-prod --yes
```

Then follow the rest of the instructions in the gitops repo for adding the app of apps. These can be found [here](https://github.com/interactivereduction/gitops/blob/main/README.md#how-to-deploy-the-app-of-apps).

Don't forget to update the sealed secrets in for every app for the new clusters! 