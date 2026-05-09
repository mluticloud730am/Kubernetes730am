# ☸️ Day 3 — Kubernetes Workloads: Pod, ReplicaSet & Deployment

> **Session Date:** 7th May 2026 | **Batch:** 7:30 AM | **Instructor:** Veera Sir  
> **Platform:** AWS EKS on EC2 (Amazon Linux, t2.medium bootstrap node)  
> **Topics:** EKS Cluster Setup · Pod · ReplicaSet · Deployment · Rolling Updates · etcd Behavior · apiVersion deep-dive

---

## 📋 Table of Contents

1. [What We Cover Today — The Big Picture](#-what-we-cover-today--the-big-picture)
2. [Prerequisites & EKS Cluster Setup](#-prerequisites--eks-cluster-setup)
   - [Step 1 — EC2 Setup & IAM Role](#step-1--ec2-setup--iam-role)
   - [Step 2 — Install kubectl](#step-2--install-kubectl)
   - [Step 3 — Install eksctl](#step-3--install-eksctl)
   - [Step 4 — Create EKS Cluster](#step-4--create-eks-cluster)
3. [Understanding apiVersion — v1 vs apps/v1](#-understanding-apiversion--v1-vs-appsv1)
4. [Kubernetes Workload 1 — Pod](#-kubernetes-workload-1--pod)
   - [What is a Pod?](#what-is-a-pod)
   - [pod.yaml Deep Dive](#podyaml-deep-dive)
   - [Hands-On Lab: Pod Lifecycle](#hands-on-lab-pod-lifecycle)
   - [etcd — The Brain Behind kubectl apply](#etcd--the-brain-behind-kubectl-apply)
   - [Pod Drawbacks](#pod-drawbacks)
5. [Kubernetes Workload 2 — ReplicaSet](#-kubernetes-workload-2--replicaset)
   - [What is a ReplicaSet?](#what-is-a-replicaset)
   - [replicaset.yaml Deep Dive](#replicasetyaml-deep-dive)
   - [Hands-On Lab: Self-Healing Demo](#hands-on-lab-self-healing-demo)
   - [Proving Rolling Updates Do NOT Work in ReplicaSet](#proving-rolling-updates-do-not-work-in-replicaset)
   - [ReplicaSet Drawbacks](#replicaset-drawbacks)
6. [Kubernetes Workload 3 — Deployment](#-kubernetes-workload-3--deployment)
   - [What is a Deployment?](#what-is-a-deployment)
   - [deployment.yaml Deep Dive](#deploymentyaml-deep-dive)
   - [Hands-On Lab: Rolling Update in Action](#hands-on-lab-rolling-update-in-action)
   - [The Layer Architecture — Pod ⊂ ReplicaSet ⊂ Deployment](#the-layer-architecture--pod--replicaset--deployment)
7. [Side-by-Side Comparison](#-side-by-side-comparison)
8. [Real-World Scenarios & Interview Q&A](#-real-world-scenarios--interview-qa)
9. [Quick Reference — All kubectl Commands Used Today](#-quick-reference--all-kubectl-commands-used-today)
10. [Common Mistakes & Gotchas](#-common-mistakes--gotchas)

---

## 🗺️ What We Cover Today — The Big Picture

Before diving in, understand **why** Kubernetes workloads exist as layers:

```
The Problem                        The Kubernetes Solution
─────────────────────────────────────────────────────────────
Container runs on one server   →   Pod (basic wrapper)
App crashes, nobody restarts   →   ReplicaSet (self-healing)
Deploy new version = downtime  →   Deployment (rolling updates)
```

Think of it like a company hierarchy:

```
┌───────────────────────────────────────┐
│            DEPLOYMENT                 │  ← Manager (strategy, upgrades)
│  ┌─────────────────────────────────┐  │
│  │         REPLICASET              │  │  ← Supervisor (count enforcement)
│  │  ┌────────┐ ┌────────┐ ┌─────┐ │  │
│  │  │  POD 1 │ │  POD 2 │ │POD 3│ │  │  ← Workers (actual app)
│  │  └────────┘ └────────┘ └─────┘ │  │
│  └─────────────────────────────────┘  │
└───────────────────────────────────────┘
```

---

## 🏗️ Prerequisites & EKS Cluster Setup

### Step 1 — EC2 Setup & IAM Role

**Create EC2 Instance:**
- Instance type: `t2.medium` (minimum for running eksctl comfortably)
- OS: Amazon Linux 2
- Storage: 20 GB gp2

**Attach IAM Role to EC2** (not an IAM user — this is the recommended approach when your bootstrap system is inside AWS):

The IAM Role must have permissions for:

| AWS Service | Why It's Needed |
|-------------|-----------------|
| IAM | eksctl creates node roles and OIDC providers |
| EC2 | Spinning up worker nodes |
| VPC | Creating subnets, route tables, security groups |
| CloudFormation | eksctl uses CloudFormation stacks under the hood |

> 💡 **For freshers:** IAM Role = a set of permissions attached directly to an EC2 instance. The EC2 "assumes" this role automatically — no access keys needed. If your machine is **outside** AWS (e.g., your laptop), you'd create an IAM User with programmatic access keys instead.

---

### Step 2 — Install kubectl

`kubectl` is the **command-line tool** to communicate with the Kubernetes API server. Think of it as the "remote control" for your cluster.

```bash
# Download the latest stable version
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl

# Make it executable
chmod +x ./kubectl

# Move to system PATH so you can use it from anywhere
sudo mv ./kubectl /usr/local/bin/kubectl

# Verify
kubectl version --client
```

> 💡 **What is `/usr/local/bin`?** It's a standard Linux directory for user-installed executables. Any file placed here is available as a command from any terminal session. `chmod +x` grants the file "execute" permission — without it, the OS refuses to run it.

---

### Step 3 — Install eksctl

`eksctl` is a CLI tool from **Weaveworks** (now maintained by AWS) that simplifies creating and managing EKS clusters. Without it, you'd spend hours configuring VPCs, node groups, and IAM roles manually.

```bash
# Download, extract, and move in one line
curl --silent --location \
  "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" \
  | tar xz -C /tmp

sudo mv /tmp/eksctl /usr/local/bin

# Verify
eksctl version
```

> 💡 **Breaking down the command:**  
> - `$(uname -s)` — dynamically inserts your OS name (e.g., `Linux`)  
> - `tar xz -C /tmp` — extracts the `.tar.gz` archive into `/tmp`  
> - The whole thing is piped (`|`) so download → extract happens in one shot

---

### Step 4 — Create EKS Cluster

```bash
eksctl create cluster \
  --name test \
  --region ap-south-1 \
  --node-type t2.small \
  --nodes-min 2 \
  --nodes-max 2
```

**What happens behind the scenes:**

```
eksctl create cluster
       │
       ├─► Creates CloudFormation Stack (VPC, Subnets, IGW, Route Tables)
       ├─► Creates EKS Control Plane (API Server, etcd, Scheduler, Controller Manager)
       ├─► Creates EC2 Worker Nodes (your t2.small instances)
       ├─► Configures IAM Roles for nodes
       └─► Updates ~/.kube/config so kubectl can talk to this cluster
```

> ⏱️ **This takes ~15–20 minutes.** Go grab a chai ☕ — CloudFormation is doing a LOT of work.

**Verify cluster:**

```bash
kubectl get nodes       # Should show 2 worker nodes
kubectl get pods -A     # Shows all system pods running
```

---

## 🔑 Understanding apiVersion — v1 vs apps/v1

**One of the most asked questions today in class:** *Why does pod.yaml use `v1` but ReplicaSet and Deployment use `apps/v1`?*

Kubernetes organizes its resources into **API groups**:

| API Group | apiVersion | Resources Included |
|-----------|------------|-------------------|
| Core group (no prefix) | `v1` | Pod, Service, ConfigMap, Secret, Namespace, PersistentVolume |
| Apps group | `apps/v1` | Deployment, ReplicaSet, StatefulSet, DaemonSet |
| Batch group | `batch/v1` | Job, CronJob |
| Networking | `networking.k8s.io/v1` | Ingress, NetworkPolicy |

**Think of it like a folder structure:**

```
Kubernetes API
├── v1  (core — existed from day 1)
│   ├── Pod
│   ├── Service
│   └── ConfigMap
│
└── apps/v1  (apps group — added as Kubernetes matured)
    ├── Deployment
    ├── ReplicaSet
    └── StatefulSet
```

**Why the split?** Pods are the most fundamental building block — they existed from Kubernetes v1.0 and belong in the "core" API. Deployments and ReplicaSets were introduced later as higher-level abstractions and were organized into the `apps` group to keep things modular.

> 🎯 **Rule of thumb:** If you see just a version number like `v1`, it's core API. If you see `something/v1`, it's an extended API group.

---

## 📦 Kubernetes Workload 1 — Pod

### What is a Pod?

A **Pod** is the **smallest deployable unit** in Kubernetes. It is a wrapper around one or more containers that share:
- The same network namespace (same IP address)
- The same storage volumes
- The same lifecycle

> 🍱 **Real-world analogy:** If a container is a lunchbox, a Pod is a lunchbox carrier bag. The bag shares one address — your desk. Multiple lunchboxes (containers) can be in the same bag (Pod).

---

### pod.yaml Deep Dive

```yaml
apiVersion: v1          # Core API group — Pod belongs here
kind: Pod               # The type of Kubernetes object
metadata:               # Information ABOUT the Pod (not what runs inside)
  name: nginx-pod       # Unique name within the namespace
  labels:               # Key-value tags — used by selectors to find this Pod
    app: nginx          # Other objects use "app: nginx" to locate this Pod
spec:                   # What SHOULD run inside the Pod
  containers:           # List of containers (can be multiple — called sidecars)
  - name: nginx-container   # Name for the container within the Pod
    image: nginx:latest     # Docker image to pull from registry
    ports:
    - containerPort: 80     # Port the container listens on INSIDE the Pod
```

**Field-by-field explanation:**

| Field | Purpose | Fresher Explanation |
|-------|---------|---------------------|
| `apiVersion: v1` | Tells Kubernetes which API to use | Like specifying which version of a form you're filling |
| `kind: Pod` | Resource type | What kind of object are we creating? |
| `metadata.name` | Unique identifier | The Pod's "name tag" |
| `metadata.labels` | Searchable tags | Like hashtags — other objects use these to find Pods |
| `spec.containers` | What runs inside | The actual application code/image |
| `image: nginx:latest` | Docker image | The packaged application to run |
| `containerPort: 80` | Exposed port | The port the app listens on inside the container |

> ⚠️ **`containerPort` is documentation, not enforcement.** Kubernetes does NOT block traffic to other ports if you don't list them. It's informational — but it's good practice to always declare it.

---

### Hands-On Lab: Pod Lifecycle

**Lab 1: Create and verify a Pod**

```bash
$ kubectl apply -f pod.yaml
pod/nginx-pod created

$ kubectl get pods
NAME                               READY   STATUS    RESTARTS   AGE
nginx-pod                          1/1     Running   0          9s
```

**Lab 2: Inspect Pod details with `kubectl describe`**

```bash
$ kubectl describe pod nginx-pod
Name:             nginx-pod
Namespace:        default
Node:             ip-192-168-58-97.ec2.internal/192.168.58.97
IP:               192.168.45.150
Containers:
  nginx-container:
    Image:          nginx:latest
    Port:           80/TCP
    State:          Running
```

> 💡 **Reading `kubectl describe`:**
> - **Node** — which worker node this Pod landed on (scheduler decided)
> - **IP** — Pod's internal cluster IP (not accessible from internet)
> - **Events** — the step-by-step story of how the Pod was created (Scheduled → Pulling → Pulled → Created → Started)

**Lab 3: Pod has NO self-healing**

```bash
# Delete both a Deployment-managed pod AND the standalone nginx-pod
$ kubectl delete pod my-deployment-np-97bbd86dc-qkhhz nginx-pod
pod "my-deployment-np-97bbd86dc-qkhhz" deleted
pod "nginx-pod" deleted

$ kubectl get pods
NAME                               READY   STATUS    RESTARTS   AGE
my-deployment-np-97bbd86dc-6knjf   1/1     Running   0          6s
# ↑ Deployment-managed pod came back!   ↑ nginx-pod did NOT come back!
```

**Key observation:** The Deployment pod restarted automatically. The standalone Pod is gone forever.

**Lab 4: etcd remembers the resource, not the file**

```bash
# Rename the file on disk
$ sudo mv pod.yaml pod1.yaml

# Try with old name — fails (file doesn't exist on Linux)
$ kubectl apply -f pod.yaml
error: the path "pod.yaml" does not exist

# Pod is still running — etcd stored the resource definition
$ kubectl apply -f pod1.yaml
pod/nginx-pod unchanged    ← "unchanged" because etcd already has this config
```

**Lab 5: Name change = new resource**

```bash
# Change name in pod1.yaml from nginx-pod to nginx-pod1
$ kubectl apply -f pod1.yaml
pod/nginx-pod1 created      ← NEW pod created because the name is different

$ kubectl get pods
NAME        READY   STATUS    RESTARTS   AGE
nginx-pod   1/1     Running   0          5m37s
nginx-pod1  1/1     Running   0          9s
# Both exist now!
```

---

### etcd — The Brain Behind kubectl apply

```
You               kubectl              API Server          etcd
 │                  │                      │                 │
 │  kubectl apply   │                      │                 │
 ├─────────────────►│  HTTP POST /pods     │                 │
 │                  ├─────────────────────►│                 │
 │                  │                      │  Store config   │
 │                  │                      ├────────────────►│
 │                  │                      │                 │
 │                  │                      │  "pod/nginx-pod exists?"
 │                  │                      │◄────────────────┤
 │                  │                      │                 │
 │                  │   "unchanged" / "created"              │
 │◄─────────────────┤◄─────────────────────┤                 │
```

> 🧠 **Key insight about etcd:**
> - `kubectl apply` compares what you send vs what's stored in **etcd** (Kubernetes' database)
> - If the **name** matches and config is identical → `unchanged`
> - If the **name** matches but config differs → `configured` (updated)
> - If the **name** is new → `created`
> - **`rm -rf pod.yaml`** deletes the file from Linux — etcd still has the config. The Pod keeps running.
> - Only `kubectl delete -f pod.yaml` or `kubectl delete pod nginx-pod` removes it from etcd and terminates the Pod.

---

### Pod Drawbacks

| Problem | Impact |
|---------|--------|
| No self-healing | Pod dies → stays dead. No restart. |
| No replication | Only 1 Pod — single point of failure |
| No rolling updates | Can't update image without downtime |
| No load balancing | One IP, one instance |

> 🏭 **Real-world implication:** You would NEVER run a production workload as a standalone Pod. It's like deploying your app on a single server with no monitoring and no auto-restart.

---

## 🔁 Kubernetes Workload 2 — ReplicaSet

### What is a ReplicaSet?

A **ReplicaSet** is a controller that ensures a **specified number of identical Pods** are always running. If a Pod dies, it creates a new one. If too many Pods exist (matching the label selector), it deletes the extras.

> 🏭 **Real-world analogy:** A ReplicaSet is like a factory floor manager who says: *"We must always have 3 workers at station A. If one leaves, hire immediately. If 4 show up, send one home."*

**The role of Labels is CRITICAL here:**

```
ReplicaSet selector:              Pod labels:
  matchLabels:                      labels:
    app: nginx          ←──────────   app: nginx
                        MUST MATCH
```

The ReplicaSet doesn't "own" Pods by name — it finds and manages Pods **by matching labels**. This is why labels are one of the most important concepts in Kubernetes.

---

### replicaset.yaml Deep Dive

```yaml
apiVersion: apps/v1     # apps group — ReplicaSet is a higher-level resource
kind: ReplicaSet
metadata:
  name: nginx-replicaset
spec:
  replicas: 3           # Always maintain exactly 3 running Pods
  selector:             # How the ReplicaSet FINDS its Pods
    matchLabels:
      app: nginx        # "I manage all Pods with label app=nginx"
  template:             # Blueprint for creating new Pods (if count < 3)
    metadata:
      labels:
        app: nginx      # ← MUST match selector.matchLabels above
    spec:
      containers:
      - name: nginx-container
        image: nginx:latest
        ports:
        - containerPort: 80
```

**Key structural difference from Pod:**

```
pod.yaml              replicaset.yaml
────────────          ───────────────
apiVersion: v1        apiVersion: apps/v1
kind: Pod             kind: ReplicaSet
metadata:             metadata:
  name: ...             name: ...
spec:                 spec:
  containers: ...       replicas: 3       ← NEW
                        selector: ...     ← NEW (label matching)
                        template:         ← NEW (pod blueprint)
                          metadata:
                            labels: ...   ← MUST match selector
                          spec:
                            containers: ...
```

> 💡 **The `template` section is literally a Pod spec embedded inside the ReplicaSet.** The Pod spec you learned above is reused here inside `template.spec`.

---

### Hands-On Lab: Self-Healing Demo

```bash
# Apply the ReplicaSet
$ kubectl apply -f replicaset.yaml
replicaset.apps/nginx-replicaset created

# 3 pods created with auto-generated suffixes
$ kubectl get pods
NAME                      READY   STATUS    RESTARTS   AGE
nginx-replicaset-7tcd7    1/1     Running   0          5s
nginx-replicaset-f5pr6    1/1     Running   0          5s
nginx-replicaset-gjlzc    1/1     Running   0          5s

# Delete one pod manually (simulating a crash)
$ kubectl delete pod nginx-replicaset-7tcd7
pod "nginx-replicaset-7tcd7" deleted

# Check immediately — ReplicaSet spawned a replacement (nginx-replicaset-2qn4r)
$ kubectl get pods
NAME                      READY   STATUS    RESTARTS   AGE
nginx-replicaset-2qn4r    1/1     Running   0          4s   ← NEW replacement
nginx-replicaset-f5pr6    1/1     Running   0          25s
nginx-replicaset-gjlzc    1/1     Running   0          25s
```

**What happened internally:**

```
ReplicaSet Controller (Control Loop — runs every few seconds)
    │
    ├── Desired state:  replicas = 3
    ├── Actual state:   running = 2  (we deleted one)
    ├── Diff:           need 1 more
    └── Action:         CREATE new Pod from template
```

> 🔄 **The Control Loop is Kubernetes' superpower.** Every controller (ReplicaSet, Deployment) continuously compares *desired state* vs *actual state* and acts to reconcile them. This is called the **reconciliation loop**.

---

### Proving Rolling Updates Do NOT Work in ReplicaSet

**The experiment:** Change the container image from `nginx:latest` to `httpd:latest` in replicaset.yaml while Pods are running.

```bash
# Edit image in replicaset.yaml: nginx:latest → httpd:latest

$ kubectl apply -f replicaset.yaml
replicaset.apps/nginx-replicaset configured   ← "configured" = ReplicaSet updated

$ kubectl get pods
NAME                      READY   STATUS    RESTARTS   AGE
nginx-replicaset-2qn4r    1/1     Running   0          3m26s   ← Still running nginx!
nginx-replicaset-f5pr6    1/1     Running   0          3m47s   ← Still running nginx!
nginx-replicaset-gjlzc    1/1     Running   0          3m47s   ← Still running nginx!
```

The YAML changed, but the running Pods did NOT update. Inspect confirms:

```bash
$ kubectl describe pod nginx-replicaset-gjlzc
    Image:  nginx:latest   ← Still old image!
```

**Why?** ReplicaSet only creates new Pods when existing ones are missing. It does NOT replace healthy running Pods just because the template changed.

**The only workaround:** Delete all pods manually, then ReplicaSet recreates them with the new image — but this causes **complete downtime**:

```bash
$ kubectl delete -f replicaset.yaml    # All 3 pods gone = DOWNTIME
$ kubectl apply -f replicaset.yaml     # Now recreates with httpd:latest

$ kubectl describe pod nginx-replicaset-qbk45
    Image:  httpd:latest   ← New image picked up only after full delete+recreate
```

> 🚨 **This is why ReplicaSet is NOT used directly in production for application updates.** The downtime is unacceptable.

---

### ReplicaSet Drawbacks

| Capability | ReplicaSet | Notes |
|------------|------------|-------|
| Maintain desired count | ✅ Yes | Core feature |
| Self-healing (restart crashed pods) | ✅ Yes | Replaces deleted/crashed Pods |
| Rolling update (zero downtime) | ❌ No | Requires delete + recreate |
| Version history / rollback | ❌ No | No concept of revisions |
| Pause/resume deployment | ❌ No | No such controls |

---

## 🚀 Kubernetes Workload 3 — Deployment

### What is a Deployment?

A **Deployment** is a higher-level controller that **manages ReplicaSets** to enable:
- Zero-downtime rolling updates
- Version history and rollback
- Pause and resume of rollouts

> 🎯 **The golden rule:** In real production environments, you **always** use Deployments. You almost never create ReplicaSets or Pods directly.

---

### deployment.yaml Deep Dive

```yaml
apiVersion: apps/v1       # Same API group as ReplicaSet
kind: Deployment          # The most important workload type
metadata:
  name: nginx-deployment
spec:
  replicas: 3             # Desired Pod count
  selector:
    matchLabels:
      app: nginx          # Identifies which Pods this Deployment owns
  template:               # Pod blueprint (identical structure to ReplicaSet)
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx-container
        image: nginx:latest
        ports:
        - containerPort: 80
```

**Structural comparison — all three workloads:**

```
Pod                ReplicaSet            Deployment
───────────        ───────────────────   ──────────────────────
apiVersion: v1     apiVersion: apps/v1   apiVersion: apps/v1
kind: Pod          kind: ReplicaSet      kind: Deployment
metadata:          metadata:             metadata:
  name: ...          name: ...             name: ...
spec:              spec:                 spec:
  containers:        replicas: N           replicas: N
  - image: ...       selector: ...         selector: ...
    ports: ...       template:             template:
                       spec:                 spec:
                         containers:           containers:
                         - image: ...          - image: ...
```

The YAML structure for Deployment and ReplicaSet is **almost identical** — the difference is `kind: Deployment` and the superpowers it unlocks.

---

### Hands-On Lab: Rolling Update in Action

**Phase 1: Deploy with nginx:latest**

```bash
$ kubectl apply -f Deployment.yaml
deployment.apps/nginx-deployment created

$ kubectl get pods
NAME                                READY   STATUS    RESTARTS   AGE
nginx-deployment-6586c5b5fb-d74cb   1/1     Running   0          5s
nginx-deployment-6586c5b5fb-kdf7j   1/1     Running   0          5s
nginx-deployment-6586c5b5fb-tqddm   1/1     Running   0          5s
```

Note the pod names: `nginx-deployment-[rs-hash]-[pod-hash]`
- `6586c5b5fb` = ReplicaSet hash (tied to the pod template version)
- `d74cb` = individual Pod hash

**Phase 2: Prove self-healing works**

```bash
$ kubectl delete pod nginx-deployment-6586c5b5fb-d74cb
pod "nginx-deployment-6586c5b5fb-d74cb" deleted

$ kubectl get pods
NAME                                READY   STATUS    RESTARTS   AGE
nginx-deployment-6586c5b5fb-6bb8w   1/1     Running   0          3s   ← NEW replacement
nginx-deployment-6586c5b5fb-kdf7j   1/1     Running   0          54s
nginx-deployment-6586c5b5fb-tqddm   1/1     Running   0          54s
```

**Phase 3: Rolling update — change image to httpd:latest (WHILE PODS ARE RUNNING)**

```bash
# Edit Deployment.yaml: image: nginx:latest → image: httpd:latest
$ kubectl apply -f Deployment.yaml
deployment.apps/nginx-deployment configured

# Watch the magic — rolling update in progress
$ kubectl get pods
NAME                                READY   STATUS              RESTARTS   AGE
nginx-deployment-59d5b764dd-62d45   0/1     ContainerCreating   0          1s   ← NEW httpd pod
nginx-deployment-59d5b764dd-gmnrh   1/1     Running             0          4s   ← NEW httpd pod
nginx-deployment-59d5b764dd-vflpg   1/1     Running             0          3s   ← NEW httpd pod
nginx-deployment-6586c5b5fb-6bb8w   1/1     Running             0          72s  ← OLD nginx pod
nginx-deployment-6586c5b5fb-tqddm   0/1     Completed           0          2m   ← OLD being terminated
```

**Two ReplicaSets exist simultaneously during the rollout:**

```bash
$ kubectl get rs
NAME                          DESIRED   CURRENT   READY   AGE
nginx-deployment-59d5b764dd   3         3         3       12s   ← NEW (httpd)
nginx-deployment-6586c5b5fb   0         0         0       2m    ← OLD (nginx) — scaled to 0
```

**After rollout completes:**

```bash
$ kubectl get pods
NAME                                READY   STATUS    RESTARTS   AGE
nginx-deployment-59d5b764dd-62d45   1/1     Running   0          31s
nginx-deployment-59d5b764dd-gmnrh   1/1     Running   0          34s
nginx-deployment-59d5b764dd-vflpg   1/1     Running   0          33s

# Verify new image
$ kubectl describe pod nginx-deployment-59d5b764dd-62d45
    Image:  httpd:latest   ← Updated WITHOUT any downtime!
```

---

### The Rolling Update Mechanism (Zero Downtime)

Default rolling update strategy creates new pods before deleting old ones:

```
Time →      T0      T1      T2      T3      T4
            ──────────────────────────────────────
nginx Pod1  [RUN]   [RUN]   [STOP]
nginx Pod2  [RUN]   [RUN]           [STOP]
nginx Pod3  [RUN]   [RUN]                   [STOP]
httpd Pod1          [START] [RUN]   [RUN]   [RUN]
httpd Pod2                  [START] [RUN]   [RUN]
httpd Pod3                          [START] [RUN]
            ──────────────────────────────────────
Min Avail:  3       4       3       3       3
```

At NO point does availability drop below 3 (or whatever your `minAvailable` config is).

---

### The Layer Architecture — Pod ⊂ ReplicaSet ⊂ Deployment

```
┌─────────────────────────────────────────────────────────────┐
│                       DEPLOYMENT                            │
│  • Rolling update strategy    • Revision history            │
│  • Rollback support           • Pause/Resume                │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    REPLICASET v2 (httpd)             │   │
│  │  • Maintains desired count   • Self-healing          │   │
│  │                                                      │   │
│  │  ┌──────────┐   ┌──────────┐   ┌──────────┐        │   │
│  │  │  POD 1   │   │  POD 2   │   │  POD 3   │        │   │
│  │  │  httpd   │   │  httpd   │   │  httpd   │        │   │
│  │  └──────────┘   └──────────┘   └──────────┘        │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │           REPLICASET v1 (nginx) — scaled to 0       │   │
│  │           (kept for rollback capability)             │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

> 🎓 **The insight:** A Deployment never directly creates Pods. It creates **ReplicaSets**, and ReplicaSets create Pods. The Deployment manages the transition from old ReplicaSet to new ReplicaSet during updates — and keeps the old one scaled to 0 for rollback.

---

## 📊 Side-by-Side Comparison

| Feature | Pod | ReplicaSet | Deployment |
|---------|-----|------------|------------|
| **apiVersion** | `v1` | `apps/v1` | `apps/v1` |
| **Self-healing** | ❌ No | ✅ Yes | ✅ Yes |
| **Replication** | ❌ No | ✅ Yes | ✅ Yes |
| **Rolling Updates** | ❌ No | ❌ No | ✅ Yes |
| **Rollback** | ❌ No | ❌ No | ✅ Yes |
| **Zero-downtime deploy** | ❌ No | ❌ No | ✅ Yes |
| **Used in production?** | ❌ Rarely | ⚠️ Indirect | ✅ Always |
| **Who creates Pods?** | You | ReplicaSet Controller | Deployment → RS → Pod |
| **Manages image updates?** | Manual | Delete+Recreate | Automatic |

---

## 🏭 Real-World Scenarios & Interview Q&A

### Scenario 1 — Blue/Green Deployment

Deployments enable Blue/Green strategy — run old (blue) and new (green) simultaneously, then switch traffic:

```bash
# This is what kubectl get rs shows during a rolling update — same concept
nginx-deployment-59d5b764dd   3    3    3    12s   ← Green (new)
nginx-deployment-6586c5b5fb   0    0    0    2m    ← Blue (old, scaled to 0)
```

### Scenario 2 — Rollback After Bad Deploy

```bash
# Deploy bad image
kubectl set image deployment/nginx-deployment nginx-container=nginx:broken

# Check rollout status
kubectl rollout status deployment/nginx-deployment

# Roll back to previous version
kubectl rollout undo deployment/nginx-deployment

# Roll back to specific revision
kubectl rollout undo deployment/nginx-deployment --to-revision=2
```

### Scenario 3 — Why Labels Matter

```bash
# If Pod labels don't match ReplicaSet selector, RS ignores those Pods
# Result: RS creates MORE Pods (thinking count is low)

# This is why you MUST ensure label consistency:
spec.selector.matchLabels.app: nginx
              must match
spec.template.metadata.labels.app: nginx
```

---

### Interview Q&A

**Q: What is the difference between ReplicaSet and Deployment?**  
A: ReplicaSet ensures Pod count but doesn't support rolling updates — you must delete and recreate all Pods to change the image, causing downtime. A Deployment manages ReplicaSets and supports rolling updates, rollback, and zero-downtime deployments. In production, always use Deployment.

**Q: What happens if you delete a Deployment's Pod manually?**  
A: The Deployment (via ReplicaSet) immediately detects the count dropped and creates a replacement Pod. This is self-healing.

**Q: What is etcd and why does `rm -rf pod.yaml` not stop the Pod?**  
A: etcd is Kubernetes' distributed key-value database that stores all cluster state. When you run `kubectl apply`, the configuration is stored in etcd — not in your local file. Deleting the file only removes it from Linux; etcd still has the resource definition. The Pod keeps running until you run `kubectl delete`.

**Q: Why does `kubectl apply` say "unchanged" even when I re-run it?**  
A: Kubernetes stores the last-applied configuration in etcd. On `kubectl apply`, it compares your YAML to the stored state. If nothing changed, it returns "unchanged" and takes no action.

**Q: Why do ReplicaSet pods not update when I change the image in the YAML?**  
A: ReplicaSet only uses the template when *creating* new Pods (e.g., to replace a failed one). It does not restart healthy running Pods when the template changes. That's Deployment's job.

**Q: What are the two hashes in a Deployment Pod name like `nginx-deployment-59d5b764dd-62d45`?**  
A: The first hash (`59d5b764dd`) is the ReplicaSet hash — tied to the pod template version. Every time you update the Deployment (e.g., change image), a new ReplicaSet with a new hash is created. The second hash (`62d45`) is the individual Pod's unique identifier.

---

## 📌 Quick Reference — All kubectl Commands Used Today

```bash
# ── CLUSTER & NODES ──────────────────────────────────────────
kubectl get nodes                          # List worker nodes
kubectl get pods                           # List pods in default namespace
kubectl get pods -A                        # List all pods in all namespaces
kubectl get rs                             # List ReplicaSets
kubectl get deploy                         # List Deployments

# ── CREATE / APPLY ───────────────────────────────────────────
kubectl apply -f pod.yaml                  # Create or update from file
kubectl apply -f replicaset.yaml
kubectl apply -f Deployment.yaml

# ── INSPECT ──────────────────────────────────────────────────
kubectl describe pod <pod-name>            # Full details + events
kubectl describe rs <rs-name>
kubectl describe deploy <deploy-name>

# ── DELETE ───────────────────────────────────────────────────
kubectl delete pod <pod-name>              # Delete specific pod
kubectl delete pod pod1 pod2               # Delete multiple
kubectl delete -f pod.yaml                 # Delete using manifest file
kubectl delete -f replicaset.yaml
kubectl delete -f Deployment.yaml

# ── ROLLOUT (Deployment only) ────────────────────────────────
kubectl rollout status deployment/<name>   # Check rollout progress
kubectl rollout history deployment/<name>  # View revision history
kubectl rollout undo deployment/<name>     # Rollback to previous version

# ── LIVE UPDATES ─────────────────────────────────────────────
kubectl set image deployment/<name> <container>=<new-image>
```

---

## ⚠️ Common Mistakes & Gotchas

### 1. Labels Don't Match Selector
```yaml
# WRONG — selector won't find these pods!
selector:
  matchLabels:
    app: nginx
template:
  metadata:
    labels:
      app: web    ← Different value!
```
**Error:** `The selector does not match the template labels`

### 2. Deleting File vs Deleting Resource
```bash
rm -rf pod.yaml          # Deletes file from Linux — Pod KEEPS RUNNING
kubectl delete -f pod.yaml   # Actually terminates the Pod in Kubernetes
```

### 3. Expecting ReplicaSet to Do Rolling Updates
```bash
# WRONG approach for production image updates
$ kubectl apply -f replicaset.yaml   # Image change WON'T apply to running pods
# You'd need: kubectl delete -f replicaset.yaml && kubectl apply -f replicaset.yaml
# This causes downtime!

# RIGHT approach — use Deployment
$ kubectl apply -f Deployment.yaml   # Rolling update happens automatically
```

### 4. `kubectl descirbe` / `kubectl desribe` Typo
```bash
$ kubectl descirbe pod nginx-pod   # ERROR
# Kubernetes helpfully suggests: "Did you mean: describe"
$ kubectl describe pod nginx-pod   # CORRECT
```

### 5. Using Free Tier for EKS
> Free tier does NOT provide real EKS cluster access. EKS control plane costs ~$0.10/hour. Always stop/delete your cluster after practice to avoid surprise bills.

```bash
# Delete cluster when done
eksctl delete cluster --name test --region ap-south-1
```

---

## 🎓 Key Takeaways From Today's Session

```
1. Pod      = basic unit, no HA, no self-healing → use for learning/debugging only

2. ReplicaSet = self-healing, maintains count, but NO rolling updates
              → don't use directly for app deployments

3. Deployment = production standard: self-healing + rolling updates + rollback
              → ALWAYS use Deployment for real applications

4. Labels     = the glue between controllers and pods — must match exactly

5. etcd       = Kubernetes' memory — stores desired state, not your local files

6. apiVersion: v1 (core) vs apps/v1 (extended) — determined by resource type

7. Rolling update creates NEW ReplicaSet, scales OLD to 0 — old RS kept for rollback
```

---

*📁 Directory structure used in class:*
```
May7th-Kubernetes730am/
├── pod.yaml        (renamed to pod1.yaml mid-session)
├── replicaset.yaml
└── Deployment.yaml
```

*🖥️ Environment: EC2 instance `ip-172-31-45-208` | EKS nodes in `ap-south-1` | Worker node IPs: `192.168.58.97`, `192.168.1.109`*

---
> 📝 **Notes compiled from live class session — 7th May 2026 | NareshIT DevOps/CloudOps Batch | 7:30 AM**
