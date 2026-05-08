# ☸️ Day 2 — Kubernetes: Components Deep Dive, EKS Cluster Setup & First Pod

> 📚 **Class Notes — Enriched & Documented**
> *Covers: Control Plane & Worker Node components in depth, KOPS vs Managed Kubernetes, EKS cluster creation with eksctl, CloudFormation resources explained, First Pod creation with real terminal output walkthrough.*

---

## 📌 Table of Contents

1. [Control Plane Components — Deep Dive](#1-control-plane-components--deep-dive)
2. [Worker Node Components — Deep Dive](#2-worker-node-components--deep-dive)
3. [Kubernetes Deployment Models — KOPS vs Managed](#3-kubernetes-deployment-models--kops-vs-managed)
4. [Managed Kubernetes: EKS vs AKS vs GKE](#4-managed-kubernetes-eks-vs-aks-vs-gke)
5. [What is a Pod? — Full Explanation](#5-what-is-a-pod--full-explanation)
6. [CRI — Container Runtime Interface Explained](#6-cri--container-runtime-interface-explained)
7. [Kubernetes Namespaces](#7-kubernetes-namespaces)
8. [EKS Cluster Setup — Step by Step](#8-eks-cluster-setup--step-by-step)
9. [What eksctl Creates Behind the Scenes](#9-what-eksctl-creates-behind-the-scenes)
10. [Real Lab Terminal Output — Explained Line by Line](#10-real-lab-terminal-output--explained-line-by-line)
11. [CloudFormation Resources Created by eksctl — Explained](#11-cloudformation-resources-created-by-eksctl--explained)
12. [kubectl describe pod — Every Field Explained](#12-kubectl-describe-pod--every-field-explained)
13. [Production-Ready EKS Cluster — What More is Needed](#13-production-ready-eks-cluster--what-more-is-needed)
14. [Common Mistakes & Fixes from the Lab](#14-common-mistakes--fixes-from-the-lab)
15. [Interview Questions & Answers](#15-interview-questions--answers)
16. [Quick Reference — kubectl Commands Used Today](#16-quick-reference--kubectl-commands-used-today)
17. [Summary](#17-summary)

---

## 1. Control Plane Components — Deep Dive

The **Control Plane** is the brain of your Kubernetes cluster. It makes global decisions about the cluster (scheduling, detecting and responding to events). In AWS EKS, this entire layer is fully managed by AWS — you never SSH into the control plane.

```
┌─────────────────────────────────────────────────────────────────┐
│                    CONTROL PLANE                                │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   API SERVER                             │   │
│  │      (Central hub — ALL traffic goes through here)       │   │
│  └────┬──────────┬──────────────┬────────────────┬──────────┘   │
│       │          │              │                │              │
│  ┌────▼───┐  ┌───▼──────┐  ┌───▼──────┐  ┌──────▼──────┐       │
│  │  etcd  │  │Scheduler │  │Controller│  │  Cloud       │       │
│  │  (DB)  │  │          │  │ Manager  │  │  Controller  │       │
│  └────────┘  └──────────┘  └──────────┘  └─────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

---

### 🔵 API Server (`kube-apiserver`)

**"The single gateway for ALL instructions in Kubernetes."**

Every operation — from a developer running `kubectl apply` to a controller checking pod status — goes through the API Server. Nothing bypasses it.

**What it does:**

| Responsibility | Detail |
|---|---|
| **Authentication** | Verifies *who* you are (certificates, tokens, OIDC) |
| **Authorization** | Verifies *what* you're allowed to do (RBAC) |
| **Admission Control** | Validates and mutates requests (e.g., inject sidecars, enforce policies) |
| **API Validation** | Checks YAML/JSON is structurally correct |
| **etcd Gateway** | Only component that reads/writes directly to etcd |
| **Watch API** | Other components subscribe to changes via long-lived HTTP connections |

**Real-world analogy:** The **reception + security desk** at a corporate office. Every visitor (request) must sign in, show ID, and get a badge (auth token) before being allowed in. No one enters the office without going through reception.

**How other components communicate:**

```
Controller Manager ──→ API Server ──→ etcd
Scheduler          ──→ API Server ──→ etcd
Kubelet            ──→ API Server (reports status)
kubectl            ──→ API Server (developer commands)
```

**Key technical details:**
- Runs on port **6443** (HTTPS) — this is why you see `https://....:6443` in kubeconfig
- Horizontally scalable — in HA setups, multiple API server instances behind a load balancer
- Stateless — all state is in etcd, so API server can be restarted without data loss
- Exposes OpenAPI spec — this is how `kubectl explain` works

---

### 🟡 etcd

**"The single source of truth for the entire cluster."**

etcd is a **distributed, consistent key-value store** — think of it as the cluster's database. Every piece of information about the cluster is stored here.

**What it stores:**

```
/registry/pods/default/myapp          → Pod definition
/registry/deployments/prod/web-app    → Deployment spec
/registry/nodes/ip-192-168-2-225      → Node info
/registry/secrets/default/db-pass     → Encrypted secrets
/registry/configmaps/default/app-cfg  → ConfigMaps
/registry/namespaces/                 → All namespaces
/registry/services/                   → Service definitions
```

**Key properties:**
- Uses the **Raft consensus algorithm** — guarantees all etcd nodes agree on data even during partial failures
- In production: always run **3 or 5 etcd nodes** (odd number for quorum — majority must agree)
- **Strongly consistent** — every read returns the latest committed write
- Data is **encrypted at rest** (especially important for secrets)

**Raft Consensus in simple terms:**

```
etcd Node 1 (Leader) ──→ "Write: pod=myapp"
etcd Node 2           ──→ "Acknowledged ✅"
etcd Node 3           ──→ "Acknowledged ✅"

Majority agreed (2 out of 3) → Write committed ✅

If Node 3 is down:
etcd Node 1 + 2 still form majority → Cluster healthy ✅

If Node 1 + 2 are down:
Only Node 3 remains → No majority → Cluster PAUSED ⛔
(This is why you need 3+ nodes, not 2)
```

**⚠️ Critical Production Practice:**
> Always back up etcd regularly. If etcd data is lost, the cluster loses all knowledge of what should be running. Use:
> ```bash
> ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot.db
> ```
> In EKS, AWS handles etcd backup automatically.

---

### 🟢 Scheduler (`kube-scheduler`)

**"Decides WHICH node a pod runs on — never creates the pod itself."**

When a new pod is created (as a definition, not yet running), it has `nodeName: ""` — no node assigned. The Scheduler watches for such unscheduled pods and assigns them.

**Scheduling algorithm — two phases:**

```
Phase 1: FILTERING (remove nodes that can't run the pod)
──────────────────────────────────────────────────────
  ❌ Node doesn't have enough CPU/memory
  ❌ Node has a taint the pod doesn't tolerate
  ❌ Node is in the wrong zone (if affinity set)
  ❌ Node is unschedulable (cordoned)
  ✅ Remaining nodes = "feasible nodes"

Phase 2: SCORING (rank feasible nodes, pick the best)
──────────────────────────────────────────────────────
  Node A: 80% CPU free → Score: 80
  Node B: 40% CPU free → Score: 40
  Node C: 90% CPU free → Score: 90  ← WINNER
  
  Pod assigned to Node C
```

**Advanced scheduling controls you can configure:**

| Feature | What it does | Example use case |
|---|---|---|
| **Resource Requests** | Pod tells scheduler how much CPU/memory it needs | `requests: cpu: 500m` |
| **Node Affinity** | "I prefer/require nodes with label X" | Run only on nodes in us-east-1a |
| **Pod Anti-Affinity** | "Don't put me on the same node as pod Y" | Spread replicas across nodes |
| **Taints & Tolerations** | Reserve nodes for specific workloads | GPU node only for ML pods |
| **Priority Classes** | High-priority pods evict low-priority ones | Critical system pods |
| **Topology Spread** | Spread pods evenly across zones | HA for multi-AZ deployments |

---

### 🔴 Controller Manager (`kube-controller-manager`)

**"Watches the cluster and acts when actual state ≠ desired state."**

The Controller Manager is a single binary that runs many **controllers** — each controller is a control loop responsible for a specific resource type.

**The Control Loop pattern (applies to ALL controllers):**

```python
# Pseudocode of every controller
while True:
    desired_state = read_from_etcd()
    actual_state  = observe_cluster()
    
    if desired_state != actual_state:
        take_corrective_action()
    
    sleep(short_interval)
```

**Key controllers and their jobs:**

| Controller | What it watches | What it does when things go wrong |
|---|---|---|
| **ReplicaSet Controller** | ReplicaSets and Pods | Creates new pods if count is low; deletes if too many |
| **Deployment Controller** | Deployments | Creates/updates ReplicaSets for rolling updates |
| **Node Controller** | Nodes | Marks nodes as NotReady after 40s; evicts pods after 5min |
| **Service Account Controller** | Namespaces | Creates `default` service account in every namespace |
| **Endpoints Controller** | Services + Pods | Updates the list of pod IPs behind each Service |
| **Job Controller** | Jobs | Creates pods to run batch tasks; cleans up after completion |
| **CronJob Controller** | CronJobs | Creates Job objects on schedule |
| **Namespace Controller** | Namespaces | Cleans up all resources when a namespace is deleted |

**🔵 Cloud Controller Manager (separate in cloud environments):**

In cloud environments like AWS, there is an additional **Cloud Controller Manager** that handles cloud-specific resources:
- Creates/deletes **Load Balancers** when you create a Kubernetes `Service` of type `LoadBalancer`
- Manages **EBS volumes** for PersistentVolumeClaims
- Updates **Route53** DNS entries
- Syncs node labels with EC2 instance metadata (instance type, AZ, etc.)

---

## 2. Worker Node Components — Deep Dive

Worker Nodes are where your actual application workloads run. In EKS, these are EC2 instances that **you** manage (unless using Fargate).

```
┌──────────────────────────────────────────────────────┐
│                  WORKER NODE                         │
│  (EC2 Instance — t2.medium in our lab)               │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │                  KUBELET                       │  │
│  │  (Node agent — talks to API Server)            │  │
│  └────────────────────┬───────────────────────────┘  │
│                       │                              │
│  ┌────────────────────▼───────────────────────────┐  │
│  │         CONTAINER RUNTIME (containerd)         │  │
│  │  (Actually creates and runs the containers)    │  │
│  └────────────────────┬───────────────────────────┘  │
│                       │                              │
│  ┌────────────────────▼───────────────────────────┐  │
│  │    POD 1          POD 2          POD 3         │  │
│  │  [Container]    [Container]    [Container]     │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │               KUBE-PROXY                       │  │
│  │  (Manages iptables for network routing)        │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

---

### ⚙️ Kubelet

**"The node's agent — the foreman on the factory floor."**

Kubelet is the **most important component on a worker node**. All instructions from the control plane reach the node through Kubelet.

**Kubelet responsibilities:**

1. **Node Registration** — On startup, registers the node with the API Server (`kubectl get nodes`)
2. **Pod Watching** — Continuously watches API Server for pods assigned to its node
3. **Container Lifecycle** — Tells CRI to start/stop/restart containers
4. **Health Monitoring** — Runs liveness and readiness probes on every container
5. **Resource Reporting** — Reports node CPU/memory/disk usage to API Server
6. **Volume Management** — Mounts/unmounts volumes (EBS, ConfigMaps, Secrets) into pods
7. **Log Collection** — Manages container stdout/stderr (accessible via `kubectl logs`)

**Kubelet health probes:**

```yaml
# Liveness Probe — "Is the container alive? Restart if not"
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30   # Wait 30s after start before first check
  periodSeconds: 10          # Check every 10s
  failureThreshold: 3        # Restart after 3 consecutive failures

# Readiness Probe — "Is the container ready to receive traffic?"
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  # Pod removed from Service endpoints if this fails (but NOT restarted)

# Startup Probe — "Has the container finished starting up?"
startupProbe:
  httpGet:
    path: /health
    port: 8080
  failureThreshold: 30       # Give slow-starting apps up to 5 minutes
  periodSeconds: 10
```

**Kubelet configuration file location:**
```
/var/lib/kubelet/config.yaml   (on worker node)
/etc/kubernetes/kubelet.conf   (kubeconfig for talking to API Server)
```

---

### 🐳 Container Runtime Interface (CRI)

**"The actual engine that creates containers."**

Kubernetes defines a standard interface called **CRI** — any container runtime that implements this interface can be used. This makes Kubernetes runtime-agnostic.

**Supported CRI runtimes:**

| Runtime | Used By | Notes |
|---|---|---|
| **containerd** | EKS (default), most modern clusters | Lightweight, battle-tested, CNCF project |
| **CRI-O** | OpenShift, some K8s clusters | Designed specifically for Kubernetes |
| **Docker** | Legacy (pre K8s 1.24) | Removed from K8s 1.24 via dockershim deprecation |

**In our lab (`kubectl describe pod` output):**
```
Container ID: containerd://92b040ade9154422653e6db3fb83214b2d316692...
```
This confirms our EKS cluster is using **containerd** as the runtime.

**CRI workflow when a pod is scheduled:**

```
Kubelet: "Start pod myapp with image nginx"
    ↓
containerd: "Pull image from Docker Hub"
    ↓
containerd: "Create container filesystem (layers)"
    ↓
containerd: "Set up network namespace"
    ↓
containerd: "Start the container process"
    ↓
Kubelet: "Container started, reporting to API Server"
```

---

### 🌐 Kube-Proxy

**"The network plumber — ensures traffic reaches your pods."**

Kube-proxy runs as a **DaemonSet** (one instance on every node) and manages the networking rules that allow pods to be reachable.

**What kube-proxy does:**
- Watches the API Server for new **Services** and **Endpoints**
- Creates **iptables** rules (or IPVS rules) on each node
- When traffic hits a Service IP → iptables rule → forwarded to one of the healthy pod IPs
- Handles **load balancing** at the OS network level

**Traffic flow:**

```
External User
    ↓
AWS Load Balancer (ALB/NLB)
    ↓
Node's network interface (public IP)
    ↓
iptables rules (managed by kube-proxy)
    ↓
Pod IP (192.168.x.x — inside the cluster)
    ↓
Application
```

**iptables mode vs IPVS mode:**

| Mode | Default | Performance | Use case |
|---|---|---|---|
| **iptables** | Yes (most clusters) | Good for <10,000 services | Standard clusters |
| **IPVS** | No (must enable) | Better for large clusters | 10,000+ services |

---

## 3. Kubernetes Deployment Models — KOPS vs Managed

There are two main ways to run a Kubernetes cluster:

### Option A: Self-Managed — KOPS (Kubernetes Operations)

**KOPS** is a tool that creates and manages a full Kubernetes cluster on cloud or on-premises. **You are responsible for EVERYTHING** — control plane + worker nodes.

```
┌─────────────────────────────────────────────────────┐
│                  KOPS Cluster                       │
│                                                     │
│  YOUR RESPONSIBILITY:                               │
│  ┌───────────────────┐  ┌───────────────────────┐   │
│  │  CONTROL PLANE    │  │   WORKER NODES        │   │
│  │  (EC2 instances)  │  │   (EC2 instances)     │   │
│  │                   │  │                       │   │
│  │  - OS patching    │  │   - OS patching       │   │
│  │  - etcd backup    │  │   - Node scaling      │   │
│  │  - API server HA  │  │   - Monitoring        │   │
│  │  - Upgrades       │  │   - Upgrades          │   │
│  └───────────────────┘  └───────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

**KOPS setup example:**
```bash
# Create cluster with KOPS
kops create cluster \
  --name=mycluster.k8s.local \
  --state=s3://my-kops-state \
  --zones=us-east-1a,us-east-1b \
  --node-count=3 \
  --node-size=t3.medium \
  --master-size=t3.large \
  --yes
```

**KOPS advantages:**
- Full control over every Kubernetes configuration
- Can run on any cloud or on-premises
- Free (no managed service cost)
- Supports air-gapped environments (no internet)

**KOPS disadvantages:**
- You manage control plane — etcd backups, upgrades, HA setup
- More operational overhead
- More expertise required
- You pay for control plane EC2 instances

---

### Option B: Cloud-Managed Kubernetes

AWS, Azure, and GCP all offer **fully managed Kubernetes** where the cloud provider manages the control plane. You only manage worker nodes.

```
┌─────────────────────────────────────────────────────┐
│          MANAGED KUBERNETES (EKS example)           │
│                                                     │
│  AWS MANAGES (you don't see these):                 │
│  ┌───────────────────┐                              │
│  │  CONTROL PLANE    │  ← AWS runs and manages this │
│  │  - API Server     │  ← Highly available by default│
│  │  - etcd cluster   │  ← Backup handled by AWS     │
│  │  - Scheduler      │  ← Upgraded by AWS           │
│  │  - Controllers    │  ← You just pay per hour     │
│  └───────────────────┘                              │
│                                                     │
│  YOU MANAGE:                                        │
│  ┌───────────────────────────────────────────────┐  │
│  │  WORKER NODES (EC2 / Fargate)                 │  │
│  │  - Node group scaling                         │  │
│  │  - AMI updates (managed node groups do this)  │  │
│  │  - Application deployments                    │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

---

## 4. Managed Kubernetes: EKS vs AKS vs GKE

| Feature | EKS (AWS) | AKS (Azure) | GKE (Google) |
|---|---|---|---|
| **Full name** | Elastic Kubernetes Service | Azure Kubernetes Service | Google Kubernetes Engine |
| **Control plane cost** | ~$0.10/hour (~$72/month) | Free | Free (Autopilot: per pod) |
| **Worker nodes** | EC2 / Fargate | Azure VMs / Virtual Nodes | GCE VMs / Autopilot |
| **Setup tool** | eksctl / Console / Terraform | az aks create / Terraform | gcloud container clusters create |
| **Kubernetes versions** | Slightly behind upstream | Slightly behind upstream | Fastest to get new versions |
| **Managed node groups** | Yes (AMI auto-update) | Yes (node image auto-update) | Yes (auto-repair, auto-upgrade) |
| **Serverless nodes** | AWS Fargate | Azure Container Instances | GKE Autopilot |
| **Best for** | AWS-centric organizations | Microsoft/Azure shops | Best K8s experience overall |
| **IAM integration** | IAM Roles for Service Accounts (IRSA) | Workload Identity | Workload Identity |
| **CLI tool** | `eksctl` | `az aks` | `gcloud container` |
| **Networking** | VPC CNI (native VPC IPs) | Azure CNI / kubenet | VPC-native |

**Fully Managed Options (no node management at all):**

| Service | Cloud | Description |
|---|---|---|
| **AWS Fargate** | AWS | Run pods serverlessly — no EC2 to manage |
| **GKE Autopilot** | GCP | Fully managed cluster, pay per pod |
| **ACI (Azure Container Instances)** | Azure | Serverless containers, integrates with AKS |

---

## 5. What is a Pod? — Full Explanation

### The Layered Architecture

```
┌─────────────────────────────────────────────────┐
│                  NODE (EC2)                     │
│  Hardware + OS (Amazon Linux 2023)              │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │              POD                          │  │
│  │  (Abstract layer — Kubernetes unit)       │  │
│  │                                           │  │
│  │  ┌─────────────────────────────────────┐  │  │
│  │  │          CONTAINER                  │  │  │
│  │  │  (Created by CRI/containerd)        │  │  │
│  │  │                                     │  │  │
│  │  │  ┌───────────────────────────────┐  │  │  │
│  │  │  │         APPLICATION           │  │  │  │
│  │  │  │  (nginx, Java app, etc.)      │  │  │  │
│  │  │  └───────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

### Pod is an Abstraction Layer

From your notes: *"Pod is an abstract layer on top of container."*

This is exactly right. Here's why this abstraction matters:

1. **Network abstraction:** Every pod gets its own IP. Containers inside the pod share this IP (they talk via `localhost`). You don't need to know which node the pod is on — just use the pod IP.

2. **Storage abstraction:** Volumes are attached to the pod, not the container. If the container restarts, the volume remains. Multiple containers in the same pod share the same volumes.

3. **Lifecycle abstraction:** Kubernetes manages the pod lifecycle, not individual containers. If a container crashes, Kubernetes restarts it *within the same pod* (same IP, same volumes — seamless).

4. **Scheduling abstraction:** Kubernetes schedules pods (not containers) to nodes. All containers in a pod always end up on the same node.

### Pod vs Container — Clear Comparison

| Aspect | Container (Docker world) | Pod (Kubernetes world) |
|---|---|---|
| **Created by** | `docker run` | `kubectl apply` |
| **Managed by** | Docker daemon | Kubernetes control plane |
| **Network** | Gets Docker bridge IP | Gets cluster IP (shared among containers in pod) |
| **Scaling** | Manual | Controlled by ReplicaSet/Deployment |
| **Self-healing** | ❌ No | ✅ Yes (via controllers) |
| **Contains** | One process | One or more containers |
| **Ephemeral** | Yes | Yes (but replaced automatically) |
| **Direct creation** | `docker run nginx` | `kubectl apply -f pod.yaml` |

### Pod IP addressing — important concept

In our lab, `kubectl describe pod` showed:
```
IP: 192.168.1.248
```

This IP (`192.168.x.x`) is a **cluster-internal IP** — not the node's IP (`172.31.x.x`). This is because:
- EKS uses the **VPC CNI plugin** — each pod gets a real VPC IP from the subnet CIDR
- Pod IPs are routable within the VPC without any NAT
- This is different from standard Kubernetes where pods use an overlay network (like Flannel, Calico)

```
Node IP (EC2): 192.168.2.225  (from EKS node subnet)
Pod IP:        192.168.1.248  (directly from VPC CIDR)
              ↑
              Real AWS VPC IP — not hidden behind overlay!
```

---

## 6. CRI — Container Runtime Interface Explained

From your notes: *"Kubernetes is not using any containerization platform, it is using CRI native containerization platform (Container Runtime Interface). CRI → Interface"*

### What is CRI exactly?

**CRI** is a **plugin interface** — a contract/specification that Kubernetes defines. Any container runtime that implements the CRI spec can be plugged into Kubernetes.

```
Kubernetes (kubelet)
       ↓
  [CRI Interface]       ← Standard API: RunPodSandbox(), CreateContainer(), etc.
       ↓
  ┌──────────────────────────────────────────┐
  │  containerd  OR  CRI-O  OR  any CRI impl │
  └──────────────────────────────────────────┘
       ↓
  Linux kernel features:
  - Namespaces (isolation)
  - cgroups (resource limits)
  - UnionFS (layered filesystems)
```

### CRI API — the key operations

```
gRPC Methods (how kubelet talks to CRI):
├── RunPodSandbox()        → Create pod network namespace, cgroups
├── CreateContainer()      → Create container inside sandbox
├── StartContainer()       → Start the container process
├── StopContainer()        → Stop the container
├── RemoveContainer()      → Delete the container
├── ListContainers()       → Get running containers
├── ContainerStatus()      → Get container state
├── ExecSync()             → kubectl exec (run command in container)
├── Attach()               → kubectl attach
└── PortForward()          → kubectl port-forward
```

### Why Docker was removed from Kubernetes (v1.24)

Docker was never designed to implement CRI. Kubernetes had to use a compatibility shim called **dockershim** to make Docker work. This shim:
- Added extra process overhead
- Was maintained by the K8s team (not Docker) — a maintenance burden
- Was unnecessary because Docker itself uses containerd internally

```
Old way (pre-1.24):            New way (1.24+):
kubelet                        kubelet
  ↓                              ↓
dockershim (compatibility)     containerd (CRI native)
  ↓                              ↓
dockerd                        container ←
  ↓                           (same container, fewer layers)
containerd
  ↓
container
```

> ✅ **Your Docker images still work 100%.** Only the runtime daemon changed. The OCI image format (which Docker uses) is the standard that containerd also uses.

---

## 7. Kubernetes Namespaces

In the lab, we ran `kubectl get ns` and saw 4 namespaces. Let's understand each.

```
[ec2-user@ip-172-31-44-55 ~]$ kubectl get ns
NAME              STATUS   AGE
default           Active   33m
kube-node-lease   Active   33m
kube-public       Active   33m
kube-system       Active   33m
```

### What is a Namespace?

A **Namespace** is a virtual cluster inside your Kubernetes cluster. It provides:
- **Isolation:** Resources in namespace A can't directly access resources in namespace B (by default)
- **RBAC scope:** Grant a team access to only their namespace
- **Resource quotas:** Limit CPU/memory per namespace
- **Name uniqueness:** Two pods can have the same name if they're in different namespaces

### The 4 Default Namespaces Explained

| Namespace | Purpose | What runs inside |
|---|---|---|
| `default` | Where your workloads go if you don't specify a namespace | Your app pods (like `myapp` we created) |
| `kube-system` | Core Kubernetes system components | coredns, kube-proxy, aws-node (VPC CNI), metrics-server |
| `kube-public` | Publicly readable (no auth needed) | ConfigMap with cluster info |
| `kube-node-lease` | Node heartbeats | Lease objects — kubelet sends heartbeats every 10s to indicate node health |

**Check what's running in kube-system:**
```bash
kubectl get pods -n kube-system
# You'll see:
# coredns-xxx        → DNS resolution inside cluster
# kube-proxy-xxx     → One per node (DaemonSet)
# aws-node-xxx       → VPC CNI plugin (one per node)
# metrics-server-xxx → CPU/memory metrics for kubectl top
```

### Creating and Using Namespaces

```bash
# Create namespace for your team
kubectl create namespace dev-team

# Deploy into specific namespace
kubectl apply -f deployment.yaml -n dev-team

# Set default namespace for your kubectl session
kubectl config set-context --current --namespace=dev-team

# Get pods in all namespaces
kubectl get pods -A
```

---

## 8. EKS Cluster Setup — Step by Step

### Prerequisites

#### Step 1: Launch a Bootstrap EC2 Instance

This is a regular EC2 instance (Amazon Linux, t2.micro is fine) that acts as your **management machine** — not part of the cluster itself.

```
Your Laptop → SSH → Bootstrap EC2 → eksctl → AWS API → EKS Cluster
```

#### Step 2: IAM Role for Bootstrap EC2 (Recommended for AWS)

Create an IAM Role and attach it to the EC2 instance with these permissions:

```json
{
  "Permissions needed": [
    "IAM (create roles for EKS)",
    "EC2 (create instances for worker nodes)",
    "VPC (create VPC, subnets, route tables)",
    "CloudFormation (eksctl uses CloudFormation)",
    "EKS (create/manage clusters)",
    "AutoScaling (manage node groups)"
  ]
}
```

**Easiest approach for learning:** Attach the `AdministratorAccess` policy to the EC2 role. In production, use least-privilege custom policies.

> **Note from class:** If your bootstrap machine is **outside AWS** (your laptop), create an IAM **User** with programmatic access (Access Key + Secret Key) instead of a role.

#### Step 3: Install kubectl

```bash
# Download kubectl binary
curl -LO https://storage.googleapis.com/kubernetes-release/release/\
$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)\
/bin/linux/amd64/kubectl

# Make it executable
chmod +x ./kubectl

# Move to system PATH
sudo mv ./kubectl /usr/local/bin/kubectl

# Verify (correct command — no double dash)
kubectl version --client
```

> ⚠️ **Common mistake from lab:** `kubectl --version` gives an error. The correct command is `kubectl version` or `kubectl version --client`.

#### Step 4: Install eksctl

```bash
# Download and install eksctl
curl --silent --location \
  "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" \
  | tar xz -C /tmp

sudo mv /tmp/eksctl /usr/local/bin

# Verify
eksctl version
# Output: 0.226.0
```

#### Step 5: Create the EKS Cluster

```bash
eksctl create cluster \
  --name test \
  --region us-east-1 \
  --node-type t2.medium \
  --nodes-min 2 \
  --nodes-max 2 \
  --zones us-east-1b,us-east-1d
```

**What each parameter means:**

| Parameter | Value | Meaning |
|---|---|---|
| `--name` | test | Cluster name (appears in AWS Console) |
| `--region` | us-east-1 | AWS region to deploy in |
| `--node-type` | t2.medium | EC2 instance type for worker nodes |
| `--nodes-min` | 2 | Minimum worker nodes (ASG minimum) |
| `--nodes-max` | 2 | Maximum worker nodes (ASG maximum) |
| `--zones` | us-east-1b, us-east-1d | Availability zones for HA |

> **💡 Production tip:** Use different min/max values for auto-scaling: `--nodes-min 2 --nodes-max 10`

**⏱️ Time taken:** The cluster creation took approximately **16 minutes** (from 18:14 to 18:30 in the lab). This is normal — CloudFormation provisions ~26 resources.

#### Step 6: Verify the Cluster

```bash
# Check nodes are ready
kubectl get nodes
# NAME                             STATUS   ROLES    AGE   VERSION
# ip-192-168-2-225.ec2.internal    Ready    <none>   26m   v1.34.7-eks-4136f65
# ip-192-168-54-222.ec2.internal   Ready    <none>   27m   v1.34.7-eks-4136f65

# Check namespaces
kubectl get ns

# Check system pods
kubectl get pods -n kube-system
```

#### Step 7: Understand kubeconfig (How kubectl Knows About Your Cluster)

After `eksctl create cluster` succeeds, it automatically saves credentials to:
```
/home/ec2-user/.kube/config
```

This file tells `kubectl` where the API server is and how to authenticate:
```yaml
# ~/.kube/config (simplified)
apiVersion: v1
clusters:
- cluster:
    server: https://XXXX.gr7.us-east-1.eks.amazonaws.com   # EKS API endpoint
    certificate-authority-data: BASE64_CERT
  name: test.us-east-1.eksctl.io
contexts:
- context:
    cluster: test.us-east-1.eksctl.io
    user: admin@test.us-east-1.eksctl.io
  name: admin@test.us-east-1.eksctl.io
current-context: admin@test.us-east-1.eksctl.io
```

**This is why before cluster creation:**
```
kubectl version
→ "The connection to the server localhost:8080 was refused"
```
No kubeconfig existed, so kubectl defaulted to `localhost:8080` — which has nothing.

**After cluster creation:**
```
kubectl get nodes
→ Shows real nodes
```
Because kubeconfig now points to the real EKS endpoint.

---

## 9. What eksctl Creates Behind the Scenes

eksctl uses **AWS CloudFormation** to create all resources. Two CloudFormation stacks are created:

### Stack 1: `eksctl-test-cluster` (Control Plane + Networking)

This stack creates the VPC, networking, and the EKS control plane:

```
eksctl-test-cluster (26 resources)
│
├── AWS::EKS::Cluster          → The EKS control plane itself ("test")
├── AWS::IAM::Role             → Service role for EKS to call AWS APIs
│
├── Networking
│   ├── AWS::EC2::VPC          → New dedicated VPC (192.168.0.0/16)
│   ├── AWS::EC2::Subnet × 4  → 2 public + 2 private subnets (one per AZ)
│   ├── AWS::EC2::InternetGateway → For public subnet internet access
│   ├── AWS::EC2::NatGateway   → For private subnet outbound internet
│   ├── AWS::EC2::EIP          → Elastic IP for NAT Gateway (54.198.194.128)
│   └── AWS::EC2::RouteTable × 3 → Routing rules for public + private subnets
│
└── Security Groups × 3
    ├── ClusterSharedNodeSecurityGroup → All nodes can communicate
    ├── ControlPlaneSecurityGroup      → API server communication
    └── SecurityGroupIngress rules × 3 → Inter-node + node-to-control-plane rules
```

### Stack 2: `eksctl-test-nodegroup-ng-b2d46311` (Worker Nodes)

```
eksctl-test-nodegroup (resources)
│
├── AWS::EKS::Nodegroup        → Managed node group definition
├── AWS::IAM::Role             → EC2 instance role (with EKS worker policies)
├── EC2 instances × 2          → Your actual t2.medium worker nodes
└── AWS::AutoScaling::AutoScalingGroup → ASG managing the worker nodes
```

### Network Architecture Created:

```
VPC: 192.168.0.0/16
│
├── us-east-1b
│   ├── Public Subnet:  192.168.0.0/19   (for Load Balancers)
│   └── Private Subnet: 192.168.64.0/19  (for Worker Nodes)
│
└── us-east-1d
    ├── Public Subnet:  192.168.32.0/19  (for Load Balancers)
    └── Private Subnet: 192.168.96.0/19  (for Worker Nodes)

Internet Gateway → Public subnets
NAT Gateway (in Public) → Private subnets (outbound only)
```

> **Why private subnets for worker nodes?**
> Security best practice — worker nodes (EC2) should not be directly accessible from the internet. They go outbound through NAT Gateway, and inbound traffic comes only through the Load Balancer.

---

## 10. Real Lab Terminal Output — Explained Line by Line

### kubectl install error explained:

```bash
$ kubectl --version
error: unknown flag: --version
```
**Why:** kubectl uses single-word subcommands, not flags. `--version` is not a valid flag.

```bash
$ kubectl -version
error: invalid argument "ersion" for "-v, --v" flag
```
**Why:** Single dash `-v` is interpreted as the **verbosity flag**. `-version` = `-v ersion` which kubectl tries to parse `ersion` as a number.

**Correct command:**
```bash
kubectl version          # Shows both client and server version
kubectl version --client # Shows only client version (no server needed)
```

### kubectl version output before cluster:
```bash
$ kubectl version
Client Version: v1.31.0
Kustomize Version: v5.4.2
The connection to the server localhost:8080 was refused
```
**Why:** kubectl is installed (client works) but no cluster exists yet. Without a kubeconfig, kubectl defaults to `localhost:8080`.

### pod.xml vs pod.yaml:

```bash
$ vi pod.xml      # Created file with .xml extension (works fine, just unusual naming)
$ kubectl apply -y pod.xml   # Wrong flag
error: unknown shorthand flag: 'y' in -y
$ kubectl apply -f pod.xml   # Correct! -f means "file"
pod/myapp created
```
**Note:** Kubernetes doesn't care about the file extension (`.xml`, `.yaml`, `.yml`, `.json` all work). The content is what matters — it's parsed as YAML/JSON regardless of extension. But **best practice** is always `.yaml`.

### eksctl cluster creation — key log lines explained:

```
[ℹ]  using Kubernetes version 1.34
```
eksctl automatically uses the latest supported K8s version for the region.

```
[!]  Auto Mode will be enabled by default in an upcoming release of eksctl.
```
EKS Auto Mode is a newer feature where AWS manages node groups automatically. Currently still opt-in.

```
[ℹ]  will create 2 separate CloudFormation stacks
```
Stack 1 for the cluster, Stack 2 for the node group.

```
[!]  recommended policies were found for "vpc-cni" addon, but since OIDC is disabled...
```
OIDC (OpenID Connect) is needed for **IRSA (IAM Roles for Service Accounts)** — allows pods to assume IAM roles. We didn't enable it in this command. For production, add `--with-oidc` flag.

```
[ℹ]  default addons metrics-server, vpc-cni, kube-proxy, coredns were not specified, will install them as EKS addons
```
eksctl automatically installs essential addons:
- **vpc-cni** — AWS VPC networking for pods
- **kube-proxy** — Network rules on each node
- **coredns** — DNS resolution inside the cluster
- **metrics-server** — CPU/memory metrics for `kubectl top`

```
[✔]  saved kubeconfig as "/home/ec2-user/.kube/config"
```
kubectl is now configured to talk to the new cluster.

```
node "ip-192-168-2-225.ec2.internal" is ready
node "ip-192-168-54-222.ec2.internal" is ready
```
Both worker nodes are registered and Ready. Note the IPs are in `192.168.x.x` — the VPC CIDR we saw in the CloudFormation subnets.

---

## 11. CloudFormation Resources Created by eksctl — Explained

These were the 26 resources created in the `eksctl-test-cluster` stack:

| Resource | Physical ID | What it is |
|---|---|---|
| `ControlPlane` | `test` | The EKS control plane (the brain) — AWS manages this |
| `ServiceRole` | `eksctl-test-cluster-ServiceRole-xxx` | IAM role that allows EKS to call AWS APIs (EC2, ELB, etc.) |
| `VPC` | `vpc-01a4460f1cd4e1aae` | Dedicated VPC for the cluster (192.168.0.0/16) |
| `InternetGateway` | `igw-0dce670507c20bc86` | Allows public subnets to reach internet |
| `VPCGatewayAttachment` | `IGW\|vpc-...` | Attaches IGW to the VPC |
| `NATGateway` | `nat-0f2a77dc51542f1bf` | Allows private subnet nodes to reach internet (pull images, etc.) |
| `NATIP` | `54.198.194.128` | Elastic IP for NAT Gateway |
| `SubnetPublicUSEAST1B` | `subnet-035334806135974f9` | Public subnet in AZ us-east-1b (Load Balancers) |
| `SubnetPublicUSEAST1D` | `subnet-035c56f260306e3db` | Public subnet in AZ us-east-1d |
| `SubnetPrivateUSEAST1B` | `subnet-0bbac37976dd75ae5` | Private subnet in AZ us-east-1b (Worker Nodes) |
| `SubnetPrivateUSEAST1D` | `subnet-0c53331a12de7137a` | Private subnet in AZ us-east-1d |
| `PublicRouteTable` | `rtb-0d1ab08265fbeca2f` | Routes public subnet traffic → IGW |
| `PrivateRouteTableUSEAST1B` | `rtb-0a1e419dedfd12808` | Routes private subnet → NAT Gateway |
| `PrivateRouteTableUSEAST1D` | `rtb-0f09b86170115be1b` | Routes private subnet → NAT Gateway |
| `RouteTableAssociation × 4` | (various) | Associates subnets with their route tables |
| `ClusterSharedNodeSecurityGroup` | `sg-0f83f40f24f29a37f` | All nodes can communicate with each other |
| `ControlPlaneSecurityGroup` | `sg-0181a2f5ccd73dc01` | Controls access to the API server |
| `IngressDefaultClusterToNodeSG` | `sgr-xxx` | Control plane → nodes communication rule |
| `IngressInterNodeGroupSG` | `sgr-xxx` | Node → Node communication rule |
| `IngressNodeToDefaultClusterSG` | `sgr-xxx` | Nodes → control plane communication rule |

---

## 12. kubectl describe pod — Every Field Explained

```bash
$ kubectl describe pod myapp
```

**Full output from the lab, explained:**

```yaml
Name:             myapp           # Pod name (from metadata.name in YAML)
Namespace:        default         # Namespace (default since we didn't specify)
Priority:         0               # Scheduling priority (0 = normal)
Service Account:  default         # K8s service account (for API access)

Node: ip-192-168-2-225.ec2.internal/192.168.2.225
# ↑ Scheduler assigned this pod to Worker Node 1
# Format: nodeName/nodeIP

Start Time: Fri, 08 May 2026 18:56:28 +0000
# When Kubelet started creating the pod

Labels:
  app=webapp       # From our YAML metadata.labels
  type=front-end

IP: 192.168.1.248
# ↑ VPC CNI assigned a real VPC IP to this pod
# This IP is directly routable within the VPC

Containers:
  nginx-container:                          # Container name from YAML
    Container ID: containerd://92b040a...   # Confirms containerd runtime
    Image: nginx                            # Image we specified
    Image ID: docker.io/library/nginx@sha256:6e23...  # Exact image digest pulled
    Port: <none>                            # We didn't specify ports in YAML
    State: Running
      Started: Fri, 08 May 2026 18:56:32   # 4 seconds after Start Time (image pull)
    Ready: True
    Restart Count: 0                        # No crashes yet

Conditions:  # Pod health checklist
  PodReadyToStartContainers: True  # Network namespace created, volumes mounted
  Initialized: True                 # All init containers completed
  Ready: True                       # All containers passing readiness probes
  ContainersReady: True             # All containers are running
  PodScheduled: True                # Scheduler assigned it to a node

Volumes:
  kube-api-access-l48b5:           # Auto-injected into every pod
    Type: Projected                  # Contains:
    TokenExpirationSeconds: 3607    # Service Account JWT token (for API auth)
    ConfigMapName: kube-root-ca.crt # Cluster CA certificate

QoS Class: BestEffort
# ↑ Because we didn't set resource requests/limits
# QoS classes: BestEffort (no limits) → Burstable (partial) → Guaranteed (full)
# BestEffort pods are FIRST to be evicted when node is under memory pressure

Tolerations:
  node.kubernetes.io/not-ready:NoExecute for 300s
  node.kubernetes.io/unreachable:NoExecute for 300s
# ↑ If node becomes NotReady or Unreachable, pod gets 5 minutes before eviction

Events:  # The timeline of what happened
  Normal  Scheduled  2m16s  default-scheduler
    → "Successfully assigned default/myapp to ip-192-168-2-225.ec2.internal"
    # Scheduler picked Node 1

  Normal  Pulling    2m15s  kubelet
    → "Pulling image 'nginx'"
    # Kubelet told containerd to pull the nginx image

  Normal  Pulled     2m12s  kubelet
    → "Successfully pulled image 'nginx' in 3.061s"
    # Image pull took 3 seconds (was cached or fast network)

  Normal  Created    2m12s  kubelet
    → "Created container: nginx-container"
    # containerd created the container

  Normal  Started    2m12s  kubelet
    → "Started container nginx-container"
    # Container process is now running
```

**Events are the most important section for debugging!** When a pod is stuck, always check Events first.

---

## 13. Production-Ready EKS Cluster — What More is Needed

The cluster we created is great for learning. A production cluster needs more:

### Must-Have Production Additions

#### 1. OIDC Provider (IAM Roles for Service Accounts)
```bash
eksctl utils associate-iam-oidc-provider \
  --region us-east-1 \
  --cluster test \
  --approve
```
Allows pods to assume IAM roles without embedding AWS credentials.

#### 2. Cluster Autoscaler
```bash
# Automatically scales EC2 worker nodes based on pod demand
# When pods can't be scheduled (insufficient nodes) → add nodes
# When nodes are underutilized → remove nodes
kubectl apply -f cluster-autoscaler-autodiscover.yaml
```

#### 3. AWS Load Balancer Controller
```bash
# Creates ALB/NLB automatically when you create K8s Ingress/Service
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=test
```

#### 4. Metrics Server (already installed by eksctl)
```bash
kubectl top nodes    # CPU/memory per node
kubectl top pods     # CPU/memory per pod
```

#### 5. Logging — FluentBit to CloudWatch
```bash
# Ship container logs to CloudWatch Logs
eksctl utils enable-logging --cluster test --region us-east-1 --all
```

#### 6. Monitoring — Prometheus + Grafana
```bash
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace
```

#### 7. Secrets Management
```bash
# AWS Secrets Manager integration
# Secrets appear as files inside pods — no hardcoding
kubectl apply -f secrets-store-csi-driver.yaml
```

#### 8. Network Policy (Calico or AWS VPC CNI)
```bash
# Control which pods can talk to which
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```

#### 9. Pod Disruption Budgets
```yaml
# Ensure minimum pods available during node upgrades
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: webapp
```

#### 10. Resource Requests and Limits on All Pods
```yaml
# Always set these — enables proper scheduling and QoS
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

### Delete Cluster (Cost Saving — Important for Learning!)
```bash
# Always delete your cluster after class to avoid charges
# EKS control plane: ~$0.10/hour
# 2x t2.medium: ~$0.094/hour each
# NAT Gateway: ~$0.045/hour + data

eksctl delete cluster --name test --region us-east-1
```

---

## 14. Common Mistakes & Fixes from the Lab

| Mistake | Error | Fix |
|---|---|---|
| `kubectl --version` | `error: unknown flag: --version` | Use `kubectl version` |
| `kubectl -version` | `invalid argument "ersion"` | Use `kubectl version` |
| `kubectl apply -y` | `unknown shorthand flag: 'y'` | Use `kubectl apply -f` |
| `kuebctl get nodes` | `command not found` | Typo — it's `kubectl` not `kuebctl` |
| `kubectl version` before cluster | `connection to localhost:8080 refused` | Create cluster first OR configure kubeconfig |
| Named file `.xml` instead of `.yaml` | Works but misleading | Use `.yaml` extension for K8s manifests |
| Forgot `--region` in eksctl | Defaults to wrong region | Always specify `--region` |

---

## 15. Interview Questions & Answers

### Q1: What is the difference between KOPS and EKS?
**A:** KOPS is a self-managed Kubernetes setup where you control both the control plane and worker nodes. EKS is AWS's managed Kubernetes service where AWS manages the control plane (API server, etcd, scheduler, controller manager) and you only manage worker nodes. KOPS gives more control and flexibility; EKS reduces operational overhead for the control plane.

### Q2: What does eksctl do?
**A:** eksctl is a CLI tool that simplifies EKS cluster creation. It uses CloudFormation to provision all required AWS resources — VPC, subnets, security groups, IAM roles, the EKS control plane, and managed node groups. A single `eksctl create cluster` command replaces what would otherwise require many manual AWS Console steps.

### Q3: What is kubeconfig and where is it stored?
**A:** Kubeconfig is a YAML file that tells kubectl how to connect to a Kubernetes cluster — the API server endpoint, authentication credentials, and context. It is stored at `~/.kube/config` by default. After `eksctl create cluster`, it is automatically populated. Without it, kubectl defaults to `localhost:8080` and cannot connect.

### Q4: What is the difference between a Node and a Pod in Kubernetes?
**A:** A Node is a physical or virtual machine (EC2 instance in AWS) that provides compute resources. A Pod is the smallest deployable unit in Kubernetes that runs on a node — it wraps one or more containers. Many pods can run on a single node.

### Q5: What is QoS class in Kubernetes? What does BestEffort mean?
**A:** QoS (Quality of Service) class determines pod eviction priority when a node is under memory pressure. There are 3 classes: Guaranteed (requests = limits for all containers), Burstable (partial requests/limits), and BestEffort (no requests or limits set). BestEffort pods are evicted first when the node runs low on memory. Always set resource requests and limits in production to get at least Burstable QoS.

### Q6: What addons does eksctl install automatically?
**A:** eksctl automatically installs: vpc-cni (AWS VPC networking for pods), kube-proxy (iptables rules on each node), coredns (DNS resolution within the cluster), and metrics-server (CPU/memory metrics).

### Q7: Why do worker nodes in EKS use private subnets?
**A:** Security best practice — worker nodes should not be directly accessible from the internet. Placing them in private subnets means they have no public IP and can only be reached through the Load Balancer. They access the internet outbound through a NAT Gateway for pulling container images, etc.

### Q8: What is the Container Runtime and why was Docker removed from Kubernetes?
**A:** The Container Runtime is the software that actually creates and runs containers on worker nodes. Docker was the original runtime but required a compatibility shim (dockershim) because it didn't natively implement the CRI interface. This shim was removed in Kubernetes v1.24. Now containerd (which Docker itself uses internally) is the default CRI — simpler, lighter, and directly CRI-compliant. Docker images still work because containerd reads the same OCI image format.

### Q9: What are Kubernetes Namespaces? What are the default ones?
**A:** Namespaces provide virtual isolation within a cluster. The 4 default namespaces are: `default` (user workloads), `kube-system` (K8s system components like coredns, kube-proxy), `kube-public` (public cluster info), and `kube-node-lease` (node heartbeat lease objects). In production, you create additional namespaces per team or environment (dev, staging, prod).

### Q10: What information does `kubectl describe pod` give you?
**A:** It shows: which node the pod is on, pod and container IPs, container image and ID, runtime (containerd), current state and conditions, volumes mounted, QoS class, tolerations, and most importantly — the Events section which shows the timeline of scheduling → image pull → container creation → start. Events are the primary debugging tool for pod issues.

---

## 16. Quick Reference — kubectl Commands Used Today

```bash
# ── Installation Verification ──────────────────────────────────
kubectl version                    # Check kubectl version (client + server)
kubectl version --client           # Check only client version
eksctl version                     # Check eksctl version

# ── Cluster Management ────────────────────────────────────────
eksctl create cluster \
  --name test \
  --region us-east-1 \
  --node-type t2.medium \
  --nodes-min 2 \
  --nodes-max 2          # Create EKS cluster

eksctl delete cluster \
  --name test \
  --region us-east-1     # ⚠️ Always delete after learning to save costs

# ── Nodes ─────────────────────────────────────────────────────
kubectl get nodes                  # List worker nodes and status
kubectl get nodes -o wide          # With extra info (IP, OS, container runtime)
kubectl describe node <node-name>  # Full node details

# ── Namespaces ────────────────────────────────────────────────
kubectl get ns                     # List all namespaces
kubectl get namespaces             # Same as above

# ── Pods ──────────────────────────────────────────────────────
kubectl apply -f pod.yaml          # Create/update a pod from YAML file
kubectl get pods                   # List pods in default namespace
kubectl get pods -n kube-system    # List pods in kube-system namespace
kubectl get pods -A                # List pods in ALL namespaces
kubectl get pods -o wide           # With node and IP info
kubectl describe pod               # Describe the only pod (or first pod)
kubectl describe pod myapp         # Describe specific pod named myapp
kubectl delete pod myapp           # Delete a pod

# ── Debugging ─────────────────────────────────────────────────
kubectl logs myapp                 # View pod logs
kubectl logs myapp -f              # Stream live logs
kubectl exec -it myapp -- bash     # Shell into the pod
kubectl get events                 # View cluster events
```

---

## 17. Summary

```
TODAY'S KEY LEARNINGS
═════════════════════

CONTROL PLANE (AWS manages in EKS)          WORKER NODES (You manage)
─────────────────────────────────          ─────────────────────────
API Server    → Central gateway             Kubelet   → Node agent
etcd          → Cluster database            CRI       → Runs containers
Scheduler     → Places pods on nodes        Kube-proxy→ Network rules
Controller    → Maintains desired state

DEPLOYMENT MODELS
─────────────────
KOPS           → You manage everything (control plane + workers)
EKS/AKS/GKE   → Cloud manages control plane, you manage workers
Fargate/Autopilot → Cloud manages everything

EKS SETUP FLOW
──────────────
Bootstrap EC2 → Install kubectl + eksctl → eksctl create cluster
→ CloudFormation creates 26 resources (VPC, subnets, NAT, EKS, EC2 nodes)
→ kubeconfig auto-saved → kubectl works → Deploy pods!

WHAT eksctl CREATES
───────────────────
Stack 1: VPC, 4 subnets, IGW, NAT GW, Security Groups, EKS Control Plane
Stack 2: Managed Node Group, ASG, IAM Role, 2x t2.medium EC2 worker nodes

POD LIFECYCLE (from describe output)
────────────────────────────────────
Scheduled → Pulling image → Pulled (3s) → Created → Started → Running ✅

3 MANDATORY FILES FOR EVERY PROJECT
────────────────────────────────────
Dockerfile | kubernetes/*.yaml | cicd pipeline file
```

---

## 📚 Further Learning Resources

| Topic | Resource |
|---|---|
| eksctl documentation | https://eksctl.io |
| EKS User Guide | https://docs.aws.amazon.com/eks/latest/userguide |
| EKS Best Practices Guide | https://aws.github.io/aws-eks-best-practices |
| Kubernetes Components (official) | https://kubernetes.io/docs/concepts/overview/components |
| containerd project | https://containerd.io |
| KillerCoda EKS labs | https://killercoda.com/aws |

---

## 🏷️ Tags

`kubernetes` `k8s` `eks` `aws` `eksctl` `devops` `containers` `pods` `controlplane` `workernode` `kops` `managed-kubernetes` `kubectl` `cloudformation` `containerd` `cri` `namespaces` `cloudops`

---

*📝 Notes enriched from class session — NareshIT DevOps/CloudOps Program*
*🖥️ Lab environment: EC2 Amazon Linux, EKS v1.34, eksctl v0.226.0, kubectl v1.31.0*
*✅ Suitable for: Freshers, Experienced Engineers, CKA / AWS SAA exam preparation*
