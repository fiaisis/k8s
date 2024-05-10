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

Follow this:
https://stfc.atlassian.net/wiki/spaces/CLOUDKB/pages/211878034/Cluster+API+Setup#Moving-the-control-plane

## Staging cluster setup using management

Now that we have the management cluster setup what we need to do is create our first "workload" cluster and that will be staging.

To do this run the following commands:
```bash
cd staging-cluster
export CLUSTER_NAME="staging"
helm upgrade $CLUSTER_NAME capi/openstack-cluster --install -f values.yaml -f clouds.yaml -f user-values.yaml -f flavors.yaml -n clusters --wait
cd ..
clusterctl get kubeconfig $CLUSTER_NAME -n clusters > "kubeconfig-$CLUSTER_NAME"
```

## Production cluster setup using management

Now do the same but for production:
```bash
cd prod-cluster
export CLUSTER_NAME="production"
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
kubectl konfig merge kubeconfig-management kubeconfig-production kubeconfig-staging > kubeconfig-all 
```

Set your new kubeconfig as the active one
```shell
export KUBECONFIG="<path/to/kubeconfig-all>"
```

## Setup ArgoCD on management

This section assumes that you have the context setup appropriately in the Kubeconfigs, set your context equal to k8s-management.

```shell
kubectl config use-context management
```

Install ArgoCD:
```shell
kubectl create namespace argocd
helm install argocd argo/argo-cd --version 6.7.18 --namespace argocd
```

Setup ArgoCD CLI: https://argo-cd.readthedocs.io/en/stable/getting_started/#2-download-argo-cd-cli

Get the initial password:
```shell
argocd admin initial-password -n argocd
```

Portforward the UI to port 8080 using this command, allowing temporary access on http://localhost:8080:
```shell
kubectl port-forward service/argocd-server 80:8080 --namespace=argocd
```

Login to the UI, the username is admin, and the password you already have.

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
argocd --port-forward --port-forward-namespace=argocd cluster add staging --yes
```

Once you've done this, change the name of the cluster in the UI to just `staging` instead of the long context name.

Add cluster using CLI for prod

```bash
argocd --port-forward --port-forward-namespace=argocd cluster add prod --yes
```

Once you've done this, change the name of the cluster in the UI to just `prod` instead of the long context name.

Then follow the rest of the instructions in the gitops repo for adding the app of apps. These can be found [here](https://github.com/fiaisis/gitops/blob/main/README.md#how-to-deploy-the-app-of-apps).

Don't forget to update the sealed secrets in for every app for the new clusters! 