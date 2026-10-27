# AGENTS.md

Guidance for coding agents working in this repository.

## What this repo is (OpenStack cluster & Redpanda provisioning, pre-GitOps)

`k8s` is the **underlying cloud-infrastructure and cluster-bootstrap repository** for the Flexible
Interactive Automation (FIA) service on the STFC OpenStack Cloud (see root `README.md` and
`c-api/README.md`). It is **not** a software application and does not deploy individual FIA
microservices — instead, it provisions the virtual machines and Kubernetes clusters that `../gitops`
subsequently populates via ArgoCD:

1. **Cluster API Kubernetes clusters (`c-api/`)**: Provisions and upgrades the active FIA Kubernetes
   clusters (`management-cluster`, `staging-cluster`, and `prod-cluster`; note that
   `messaging-cluster` and `initial_cluster` are legacy/unused) on the STFC Cloud via the
   `capi/openstack-cluster` Helm chart and `clusterctl`, then bootstraps ArgoCD on `management` and
   registers `staging` and `prod` so `../gitops` can deploy the App of Apps.
2. **Redpanda & local host playbooks (`terraform/` + `ansible/`)**:
   - `terraform/` provisions the OpenStack compute instances, dedicated `redpanda` network/router,
     floating IPs, and load balancer (`:31092`) for the Redpanda cluster, and outputs
     `ansible/ansible-inventory.ini`.
   - `ansible/redpanda.yml` configures the Redpanda brokers (`roles/redpanda`) on those VMs.
   - `ansible/setup-local-machine.yml` configures `/archive` (`roles/isis-archive`) and `/ceph`
     (`roles/isis-ceph`) mounts on a local Linux machine for local/Minikube development.

## Position in the FIA service

### Overarching FIA architecture

FIA is a multi-repository system (all checked out as siblings under the same parent workspace
directory) that automatically reduces instrument data, and also lets users browse, plot, and rerun
that data interactively:

```text
[ISIS Instrument Archive (/archive, /imat) & lastrun.txt]
        │
        ▼
  file-watcher (Kopf Operator + Per-Instrument Watcher Pods)
        │  publishes file path to RabbitMQ: `watched-files`
        ▼
  run-detection ◄──── fetches instrument rules (`GET /instrument/{inst}/specification`) ────► FIA-API
        │  ingests .nxs metadata, verifies rules, publishes JobRequest JSON
        │  to RabbitMQ: `scheduled-jobs` (or retries via `failed-watched-files`)
        ▼
  jobcontroller (job_creator) ◄──── requests PreScript (`GET /script/{inst}`) & posts Job ──► FIA-API ◄──► autoreduction-scripts
        │  spawns Kubernetes Job in cluster:
        ├──► Main container: runners (`ghcr.io/fiaisis/mantid` or `mantid-imaging`) -> writes reduced data to `/ceph`
        └──► Sidecar container: jobcontroller (job_watcher) -> updates job status/outputs in FIA-API (`PATCH /job/{id}`)

[Interactive / Web & Live Data Paths]
  scigateway (Host App) ──► frontend (FIA React Plugin)
                                ├──► fia-auth (UOWS login, JWT verify/refresh, `/experiments` RB lookup)
                                ├──► FIA-API (runs, jobs, scripts, specifications, reruns -> `watched-files` / `scheduled-jobs`)
                                └──► plotting-service (h5grove NeXus/HDF5 & IMAT image serving from `/ceph` & `/imat`)

  Kafka (`<INST>_events`, `<INST>_sampleEnv`, `<INST>_runInfo`)
        └──► live-data (Live Data Operator + Mantid Live Data Processor fetching `/live-data/{inst}/script` from FIA-API)

  LLSP (Long Lived Script Processors: `LLSP-API` + RabbitMQ + Celery `LLSP-Worker` built on `ghcr.io/fiaisis/mantid`)

[Infrastructure & Deployment]
  k8s (THIS REPO) (Terraform + Ansible for OpenStack clusters, Redpanda, local Minikube)
  gitops (ArgoCD App-of-Apps & Kustomize `base`/`envs`/`variants` manifests for all FIA services)
```

### This repository's location (upstream, downstream & siblings)

- **Role**: Bottom layer of the FIA stack — turns STFC OpenStack cloud quota into running Kubernetes
  clusters (`management`, `staging`, `prod`) and Redpanda brokers, then hands off cluster workload
  management to `../gitops`.
- **Upstream inputs**: STFC OpenStack Cloud (`openstack.stfc.ac.uk`), CAPI Ubuntu Kubernetes machine
  images (`capi-ubuntu-2204-kube-v<version>`), and StackHPC `capi/openstack-cluster` Helm charts.
- **Downstream consumers**:
  - `gitops` (`../gitops`) — once `c-api/` has provisioned the clusters and bootstrapped ArgoCD on
    `management`, `../gitops/apps/app_of_apps/deployment.yml` reconciles all FIA services onto
    `management`, `staging`, and `prod`. (Also, the Redpanda Console app in `../gitops` points at
    the Redpanda brokers provisioned by `terraform/` + `ansible/`.)
  - `jobcontroller` (`../jobcontroller`) — schedules GPU jobs onto the `gpu-worker` node group
    defined in `c-api/*/flavors.yaml`.

---

## Strict security & credential rules — DO NOT READ `clouds.yaml` or `OS_*` env vars

**Never read `clouds.yaml` files anywhere on the machine** (including `c-api/*/clouds.yaml` or
`~/.config/openstack/clouds.yaml`), **never inspect or print `OS_*` OpenStack environment variables**
(`OS_PASSWORD`, `OS_APPLICATION_CREDENTIAL_SECRET`, `OS_TOKEN`, `env | grep OS_`, `printenv`, etc.),
**never read `kubeconfig*` files** (`kubeconfig-production`, `c-api/kubeconfig-*`), **never read
`terraform/terraform.tfstate*`**, and **never read `ansible/vars/vault.yml`**.

- These files and `OS_*` environment variables contain live OpenStack application credentials,
  cluster admin certificates/tokens, or infrastructure state secrets, and reading or echoing them
  will either expose credentials or trigger permission/security frameworks that reject the tool
  call.
- Likewise, never attempt to read Kubernetes `Secret` objects on any cluster
  (`kubectl get secret`, `kubectl describe secret`, etc.).
- If a task requires updating `clouds.yaml`, `OS_*` environment variables, or a kubeconfig, give the
  user the exact instructions or placeholder snippet to apply themselves rather than reading the
  file or environment.

---

## Repository structure

```
c-api/                       Cluster API (CAPI) Helm values for STFC OpenStack Kubernetes clusters.
                              Active clusters are `management-cluster/`, `staging-cluster/`, and
                              `prod-cluster/` (`messaging-cluster/` and `initial_cluster/` are
                              legacy/unused). Each active cluster directory has:
                              - `values.yaml`: OpenStack CA bundle, pod/service/node CIDRs, STFC
                                registry mirror, Cinder CSI storage class
                              - `user-values.yaml`: API server floating IP, control-plane size and
                                flavor, `kubernetesVersion`, `machineImage`, SSH key name, and
                                CAPI addon toggles
                              - `flavors.yaml`: Worker `nodeGroups` (e.g. `workers`, `gpu-worker`)
                                and node healthcheck timeouts
                              - `clouds.yaml`: OpenStack credentials (DO NOT READ)
terraform/                   OpenStack Terraform configuration (`redpanda.tf`, `providers.tf`,
                              `templates/ansible-inventory.tftpl`) provisioning the 3-node Redpanda
                              VMs, dedicated `redpanda` network/subnet/router, floating IPs, and
                              `:31092` load balancer
ansible/                     Ansible inventory (`ansible-inventory.ini`), playbooks (`redpanda.yml`,
                              `setup-local-machine.yml`), and roles (`roles/redpanda`,
                              `roles/isis-archive`, `roles/isis-ceph`)
README.md, c-api/README.md   Instructions for Redpanda Terraform/Ansible rollout, CAPI cluster
                              creation/upgrade, kubeconfig merging (`kubectl konfig`), ArgoCD
                              bootstrap, and local Minikube setup
```

---

## Common operational workflows

### 1. Upgrading a CAPI Kubernetes cluster (`c-api/`) — check available OpenStack images first!

You **cannot** upgrade a cluster's Kubernetes version simply by guessing a version number — the
corresponding `capi-*` machine image must actually exist on the STFC OpenStack Cloud, and
**Kubernetes versions must only be incremented one minor/major step at a time** (e.g. `1.34.x` ->
`1.35.x`, never skipping a version):

1. **Check available CAPI machine images in OpenStack** using the `openstack` CLI (pointing
   `OS_CLIENT_CONFIG_FILE` at a `clouds.yaml` path **without reading `clouds.yaml` itself**):
   ```shell
   OS_CLIENT_CONFIG_FILE=c-api/staging-cluster/clouds.yaml openstack --os-cloud openstack image list -f value -c Name | grep -i capi
   ```
2. **Determine the target version (one version step at a time)**:
   - Increment `kubernetesVersion` and `machineImage` in `c-api/<cluster>/user-values.yaml` by
     **one** Kubernetes version step at a time (e.g. `1.34.x` -> `1.35.x`), using the exact image
     name returned by `openstack image list` (e.g. `capi-ubuntu-2204-kube-v1.35.8`).
   - **If the image currently configured in `user-values.yaml` no longer exists in OpenStack**:
     check what Kubernetes version the live nodes in that cluster are actually running:
     ```shell
     kubectl get nodes --context <cluster-context>
     ```
     Then update `kubernetesVersion` and `machineImage` in `user-values.yaml` to the available
     OpenStack image that is **one version higher than what the cluster's nodes are currently
     running**.
3. **Do not run `helm upgrade ... capi/openstack-cluster` or `terraform apply` against live
   OpenStack clusters without explicit user confirmation**, as these mutate live control planes,
   worker nodes, or VMs.
4. When running `helm` or `kubectl` commands, always inspect available contexts first with
   `kubectl config get-contexts` and pass `--context <context-name>` (or `--kube-context`)
   explicitly at the **end** of the command:
   ```shell
   kubectl get clusters -n clusters --context <management-context>
   kubectl get machines -n clusters --context <management-context>
   ```

### 2. Provisioning or updating Redpanda (`terraform/` + `ansible/`)
Per `README.md`:
1. In `terraform/`:
   ```shell
   terraform init
   terraform plan
   # Only after user confirmation:
   terraform apply
   terraform output ansible_inventory > ../ansible/ansible-inventory.ini
   ```
   *(Note from `terraform/redpanda.tf`: Redpanda VMs must use the dedicated `redpanda` network,
   never the shared OpenStack `Internal` network.)*
2. In `ansible/`:
   ```shell
   ansible-playbook redpanda.yml -i ansible-inventory.ini --check
   # Only after user confirmation:
   ansible-playbook redpanda.yml -i ansible-inventory.ini
   ```

### 3. Local `/archive` and `/ceph` mount setup (`ansible/setup-local-machine.yml`)

`ansible/setup-local-machine.yml` runs the `isis-archive` (`/archive` CIFS mount via `/archive.creds`)
and `isis-ceph` (`/ceph` CephFS mount via `/etc/ceph/deneb.key` and the `autoreduce` user/group)
roles against `localhost`, and references `vars/vault.yml` (`ansible/vars/vault.yml`, which is
gitignored via `.gitignore`).

Agents **must never read `ansible/vars/vault.yml`**. Instead, instruct the user to provide the
credentials in one of two ways before running the playbook:

- **Option A — Local `ansible/vars/vault.yml` file (gitignored)**:
  Ask the user to create `ansible/vars/vault.yml` locally with:
  ```yaml
  isis_archive:
    username: "<FEDID>"
    password: "<FEDID_PASSWORD>"
    domain: "<ARCHIVE_DOMAIN>"
  isis_ceph:
    uid: <AUTOREDUCE_UID>
    key: "<CEPH_KEY>"
  ```
  Then run from `ansible/`:
  ```shell
  ansible-playbook setup-local-machine.yml -K
  ```

- **Option B — Passing `--extra-vars` at runtime (as in `README.md`)**:
  ```shell
  ansible-playbook setup-local-machine.yml -K --extra-vars '{ "isis_archive": { "username": "FEDID", "password": "FEDID_PASSWORD", "domain": "ARCHIVE_DOMAIN" }, "isis_ceph": { "uid": "AUTOREDUCE_UID", "key": "CEPH_KEY" } }'
  ```

---

## Requirements for infrastructure changes (validation & "testing")

There are no unit tests, coverage reports, or CI workflows in this repository — **OpenStack image
verification, dry-run / syntax validation, and cross-cluster diffing are your verification steps**.
Only run these checks when `.yaml`, `.tf`, or `.yml` infrastructure files are actually changed (skip
validation for `.md`-only documentation changes). Before considering an infrastructure change
complete:

1. **For `c-api/` Helm values changes**:
   - Confirm via `openstack image list` that the target `machineImage` actually exists in OpenStack,
     that `kubernetesVersion` matches the version in `machineImage`, and that the version bump is at
     most **one** version step above the cluster's current node version.
   - Validate YAML syntax and diff `user-values.yaml` / `flavors.yaml` / `values.yaml` across the
     active clusters (`management-cluster`, `staging-cluster`, `prod-cluster`) so unintended drift
     is caught.
   - If the `capi/openstack-cluster` chart and cluster access are available, render or dry-run with
     `helm template` / `helm diff` (mentioned in `README.md`) without reading `clouds.yaml` into
     agent context.
2. **For `terraform/` changes**:
   - Run `terraform fmt -check` and `terraform validate` inside `terraform/` (without reading
     `terraform.tfstate`).
3. **For `ansible/` changes**:
   - Run `ansible-playbook --syntax-check redpanda.yml -i ansible-inventory.ini` inside `ansible/`.

---

## Managing issues, branches, commits & pull requests

- **Issues**: Use the org-wide default template from `fiaisis/.github`:
  ```shell
  gh issue create --template Issue
  ```
  Check `gh issue list` / `gh issue view <number>` first to avoid duplicates.
- **Branch naming**: Use `snake_case` descriptions of the work without prefixes (`feature/`,
  `fix/`), e.g. `fix_redpanda`, `update_k8s_version`.
- **Commit messages**: Write clear, imperative-mood commit summaries (e.g. `Update to latest minor
  patch of k8s`, `Ensure that the kafka messages are big enough for big detspecmaps`). Never stage
  or commit `clouds.yaml`, `kubeconfig*`, or `terraform.tfstate*` files.
- **Pull request process**:
  1. When infrastructure files are changed (skip for `.md`-only changes), run the relevant checks
     from "Requirements for infrastructure changes" above, and always confirm `git status` shows no
     credential or state files staged.
  2. **PR title**: normal grammar/sentence case (no `snake_case`).
  3. **PR description**: use the org-wide default template from `fiaisis/.github`
     (`Closes # <Issue Number>` + `## Description`; ask the user if no issue number is evident).
  4. **AI-assistance label**: attach a label to the PR indicating that it was made with the
     assistance of AI. Check existing labels first with `gh label list` (e.g. `AI` or `AI_code` in
     this org) and apply the matching label via `gh pr create --label <label>` or
     `gh pr edit <number> --add-label <label>`; if the repo does not have an AI label yet, create
     one first (`gh label create "AI" --description "Created with the assistance of AI"`).

## General working practices

- Prefer the `read` tool (with `offset`/`limit`) over `sed -n`, `cat`, or similar shell one-liners
  when inspecting safe configuration files, and prefer the `write` and `edit` tools over `bash`
  (`cat <<EOF`, `sed -i`, `echo >`), Python one-liners, or other non-tool-based commands whenever
  creating or modifying files.
- **Never read `clouds.yaml`, `OS_*` environment variables, `kubeconfig*`, `terraform.tfstate*`,
  `ansible/vars/vault.yml`, or cluster `Secret` resources.**
- Ask the user a clarifying question whenever a task is ambiguous — especially which cluster
  (`management-cluster`, `staging-cluster`, `prod-cluster`) a change targets, or before running any
  command that mutates live OpenStack or Kubernetes state.

## Keeping this document up to date

If a change you make would make any information in this `AGENTS.md` inaccurate or incomplete —
e.g. a changed cluster directory under `c-api/`, a changed Terraform/Ansible layout, or updated
bootstrap instructions in `README.md` / `c-api/README.md` — update the relevant section of this file
as part of the same change. Treat it the same way you would treat `README.md`: documentation that
goes stale is worse than no documentation, so don't leave it to a future agent or PR to notice the
drift.
