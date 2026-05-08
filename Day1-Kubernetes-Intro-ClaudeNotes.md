# ☸️ Day 1 — Kubernetes: Introduction, Architecture & Core Concepts

> 📚 **Class Notes — Enriched & Documented**
> *Covers: What is Kubernetes, Why we need it, Architecture deep-dive, Core objects (Pod, ReplicaSet, Deployment), and the complete DevOps workflow.*

---

## 📌 Table of Contents

1. [What is a Container? (Quick Recap)](#1-what-is-a-container-quick-recap)
2. [What is Kubernetes?](#2-what-is-kubernetes)
3. [Why Kubernetes? — The Problem it Solves](#3-why-kubernetes--the-problem-it-solves)
4. [Kubernetes vs OpenShift](#4-kubernetes-vs-openshift)
5. [Core Responsibilities of Kubernetes](#5-core-responsibilities-of-kubernetes)
6. [Container vs Pod — Key Difference](#6-container-vs-pod--key-difference)
7. [Kubernetes Architecture — Deep Dive](#7-kubernetes-architecture--deep-dive)
   - [Control Plane Components](#control-plane-components)
   - [Worker Node Components](#worker-node-components)
   - [Full Request Flow](#full-request-flow-kubectl-apply-to-pod-running)
8. [Core Kubernetes Objects](#8-core-kubernetes-objects)
   - [Pod](#81-pod)
   - [ReplicaSet](#82-replicaset)
   - [Deployment](#83-deployment)
9. [YAML File Structure — Explained Line by Line](#9-yaml-file-structure--explained-line-by-line)
10. [The Complete DevOps Workflow with Kubernetes](#10-the-complete-devops-workflow-with-kubernetes)
11. [Three Mandatory Files Every DevOps Engineer Must Have](#11-three-mandatory-files-every-devops-engineer-must-have)
12. [Kubernetes vs Traditional ASG/EC2 Approach](#12-kubernetes-vs-traditional-asgec2-approach)
13. [Interview Questions & Answers](#13-interview-questions--answers)
14. [Quick Reference — kubectl Commands](#14-quick-reference--kubectl-commands)
15. [Summary Mind Map](#15-summary-mind-map)

---

## 1. What is a Container? (Quick Recap)

Before understanding Kubernetes, you must clearly understand **what a container is**.

### The Problem Before Containers

Imagine you are a developer. You write an application on your laptop. It works perfectly. But when you send it to the server (EC2), it fails — because the server has a different OS version, different libraries, different Java version, etc.

**"It works on my machine!"** — This is the classic problem.

### The Container Solution

A **container** is a **lightweight, portable, self-sufficient unit** that packages:
- Your application code
- Its runtime (e.g., JRE for Java)
- All libraries and dependencies
- Configuration files

All bundled together as an **image**, and when that image runs — it becomes a **container**.

Think of it like this:

```
📦 Container = Code + Runtime + Libraries + Config
               (Everything the app needs to run)
```

Containers share the **host OS kernel** but are isolated from each other using Linux features called **namespaces** and **cgroups**. This makes them:
- **Lighter** than Virtual Machines (no separate OS per container)
- **Faster** to start (seconds vs minutes for VMs)
- **Consistent** across all environments (laptop → staging → production)

**Docker** is the most popular tool to build and run containers.

---

## 2. What is Kubernetes?

**Kubernetes** (also written as **K8s** — because there are 8 letters between 'K' and 's') is an **open-source container orchestration platform**.

| Property | Details |
|---|---|
| **Developed by** | Google (internally called "Borg"), open-sourced in 2014 |
| **Current Maintainer** | Cloud Native Computing Foundation (CNCF) |
| **Written in** | Go (Golang) |
| **Latest Stable Version** | v1.30+ |
| **Purpose** | Automate deployment, scaling, and management of containerized applications |

### Simple Definition

> **Kubernetes = The manager of your containers**

If Docker is the factory that **builds** containers, Kubernetes is the **operations manager** that decides:
- How many containers to run
- On which server to run them
- What to do if one crashes
- How to scale up when traffic increases
- How to route user traffic to the right container

### The Orchestration Analogy

Think of an **orchestra** (a music performance group). There are 60 musicians each playing different instruments. Without a conductor, it would be chaos. The **conductor** coordinates everyone — who plays when, how loud, how fast.

Kubernetes is that **conductor** for your containers.

---

## 3. Why Kubernetes? — The Problem it Solves

### Real-World Example: Flipkart (India's Largest E-Commerce)

Flipkart has hundreds of microservices:
- 🛍️ Fashion service
- 💄 Beauty service
- 📱 Electronics service
- 🏠 Home & Furniture service
- 💳 Payments service
- 🔔 Notifications service
- ⭐ Reviews service
- ... and hundreds more

Each of these runs as a **separate container**.

#### Without Kubernetes (The Old Way):

```
EC2 Instance 1: Fashion Container
EC2 Instance 2: Electronics Container
EC2 Instance 3: Payments Container
...

For scaling → manually launch new EC2
              + configure Load Balancer
              + configure Auto Scaling Group (ASG)
              + set up health checks
              + manage security groups
              → For 6 services = 6 Target Groups + 6 ASGs = NIGHTMARE
```

**Problems:**
- Manual effort to scale each service individually
- No automatic healing if a container crashes
- Complex load balancer and ASG configurations
- Inconsistent configurations across environments
- Monitoring 100+ ASGs is very difficult
- No intelligent bin packing (wasteful resource usage)

#### With Kubernetes (The New Way):

```yaml
# Just write this YAML and Kubernetes handles EVERYTHING:
replicas: 3   # Run 3 copies
# Kubernetes will:
# ✅ Choose the best nodes to place pods
# ✅ Auto-scale based on CPU/memory load
# ✅ Restart if any pod crashes
# ✅ Load balance traffic automatically
# ✅ Roll out updates with zero downtime
```

---

## 4. Kubernetes vs OpenShift

This is a very common interview question!

| Feature | Kubernetes (K8s) | OpenShift (OCP) |
|---|---|---|
| **Developed by** | Google / CNCF | Red Hat (IBM) |
| **Type** | Open-source platform | Enterprise product built ON TOP of K8s |
| **Relationship** | Base platform | OpenShift = K8s + extra enterprise features |
| **Cost** | Free | Paid (with Red Hat subscription) |
| **Security** | Needs manual hardening | Stricter security by default (no root containers) |
| **Built-in Registry** | No (need ECR, Docker Hub) | Yes — built-in image registry |
| **CI/CD** | Manual setup (Jenkins, GitLab) | Built-in CI/CD pipelines |
| **Monitoring** | Manual setup (Prometheus, Grafana) | Better built-in monitoring |
| **Logging** | Manual setup (EFK stack) | Better built-in logging (EFK pre-configured) |
| **Dashboard** | Basic | Advanced, more user-friendly |
| **CLI** | `kubectl` | `oc` (OpenShift CLI, superset of kubectl) |
| **Who uses it** | Startups, tech companies, AWS/GCP | Banks, enterprises, government organizations |

### Key Point:
> OpenShift is **NOT a competitor** to Kubernetes. It is an **enterprise distribution** built on top of Kubernetes — similar to how Ubuntu is built on top of Linux kernel.
>
> Think of it as:
> - **Kubernetes** = Linux Kernel
> - **OpenShift** = Red Hat Enterprise Linux (RHEL)

---

## 5. Core Responsibilities of Kubernetes

Kubernetes handles **everything** after your Docker image is ready:

### 1. 🔢 Container Count Management
Kubernetes ensures the **exact number of containers** you specified are always running.
- You say: `replicas: 3`
- Kubernetes guarantees: exactly 3 pods will always be running

### 2. 🔧 Self Healing
If a container/pod **crashes or becomes unhealthy**, Kubernetes automatically:
- Detects the failure (via health checks called **liveness probes**)
- Kills the failed pod
- Launches a new pod to replace it
- Does this **automatically, without human intervention**

### 3. 📈 Auto-Scaling (Horizontal Pod Autoscaler - HPA)
- Similar to AWS Auto Scaling Group (ASG), but for pods
- If CPU usage > 70%, automatically add more pods
- If traffic drops, automatically remove pods
- Also supports **Vertical Pod Autoscaler (VPA)** — adjusts CPU/memory of existing pods

### 4. ⚖️ Load Balancing
- Kubernetes has a built-in component called **kube-proxy** and **Services**
- Automatically distributes traffic across all healthy pods
- No need to manually configure load balancers for internal traffic

### 5. 🔒 Security
- **RBAC** (Role-Based Access Control) — control who can do what
- **Network Policies** — control which pods can talk to which
- **Secrets management** — store passwords, API keys encrypted
- **Pod Security Admission** — enforce security standards

### 6. 🖥️ Node High Availability
- If an entire **worker node fails** (EC2 instance down), Kubernetes detects it
- All pods that were on that node are **automatically rescheduled** to healthy nodes
- Applications remain available — zero downtime for users

### 7. 📦 Declarative Configuration (YAML)
- You **declare** the desired state in a YAML file
- Kubernetes **continuously reconciles** actual state with desired state
- This is called the **Reconciliation Loop** or **Control Loop**

---

## 6. Container vs Pod — Key Difference

This is a **very important conceptual distinction**:

| | Container | Pod |
|---|---|---|
| **Created by** | Container runtime (Docker, containerd) | Kubernetes orchestration |
| **Tool** | `docker run` | `kubectl apply` |
| **Unit of** | Docker world | Kubernetes world |
| **Contains** | One application process | One or more containers |
| **IP Address** | Gets Docker network IP | Gets cluster IP (shared among containers in same pod) |
| **Managed by** | Docker daemon | Kubernetes control plane |

### Visual Explanation:

```
Docker World:
  docker run nginx  →  Creates a CONTAINER

Kubernetes World:
  kubectl apply -f pod.yaml  →  Creates a POD
  (Pod internally uses container runtime to run the container)
```

### What is a Pod really?

A **Pod** is the **smallest deployable unit** in Kubernetes. It is a **wrapper around one or more containers** that:
- Share the same **network namespace** (same IP address, can talk via localhost)
- Share the same **storage volumes**
- Are always **scheduled together** on the same node

**90% of the time**: 1 Pod = 1 Container

**Sometimes**: 1 Pod = multiple containers (called **sidecar pattern**)
- Example: Main app container + Logging sidecar container + Monitoring sidecar container

```
┌─────────────────────────────────────┐
│              POD                    │
│  ┌─────────────┐ ┌───────────────┐  │
│  │ Main App    │ │  Log Sidecar  │  │
│  │ Container   │ │  Container    │  │
│  │ (nginx)     │ │  (fluentd)    │  │
│  └─────────────┘ └───────────────┘  │
│  Shared Network: 10.0.0.5           │
│  Shared Volume: /var/logs           │
└─────────────────────────────────────┘
```

---

## 7. Kubernetes Architecture — Deep Dive

> ⭐ **This is the #1 most important interview topic in Kubernetes. Learn this thoroughly.**

Kubernetes has a **master-worker architecture**:

```
┌─────────────────────────────────────────────────────────────────┐
│                    KUBERNETES CLUSTER                           │
│                                                                 │
│  ┌─────────────────────────────────────┐                        │
│  │        CONTROL PLANE NODE           │                        │
│  │  (Brain / Manager of the cluster)   │                        │
│  │                                     │                        │
│  │  ┌──────────┐    ┌────────────┐     │                        │
│  │  │ API      │    │   etcd     │     │                        │
│  │  │ Server   │◄──►│ (Database) │     │                        │
│  │  └─────┬────┘    └────────────┘     │                        │
│  │        │                            │                        │
│  │  ┌─────▼────┐    ┌────────────┐     │                        │
│  │  │Scheduler │    │ Controller │     │                        │
│  │  └──────────┘    │ Manager    │     │                        │
│  │                  └────────────┘     │                        │
│  └──────────────────┬──────────────────┘                        │
│                     │ API Communication                         │
│         ┌───────────┼───────────┐                               │
│         │           │           │                               │
│  ┌──────▼──────┐ ┌──▼──────┐ ┌─▼───────┐                       │
│  │  Worker     │ │ Worker  │ │ Worker  │                        │
│  │  Node 1     │ │ Node 2  │ │ Node 3  │                        │
│  │             │ │         │ │         │                        │
│  │ ┌─────────┐ │ │         │ │         │                        │
│  │ │ Kubelet │ │ │Kubelet  │ │Kubelet  │                        │
│  │ ├─────────┤ │ │         │ │         │                        │
│  │ │  CRI    │ │ │  CRI    │ │  CRI    │                        │
│  │ ├─────────┤ │ │         │ │         │                        │
│  │ │Kube-    │ │ │Kube-    │ │Kube-    │                        │
│  │ │Proxy    │ │ │Proxy    │ │Proxy    │                        │
│  │ ├─────────┤ │ │         │ │         │                        │
│  │ │Pod│Pod  │ │ │  Pods   │ │  Pods   │                        │
│  │ └─────────┘ │ │         │ │         │                        │
│  └─────────────┘ └─────────┘ └─────────┘                       │
└─────────────────────────────────────────────────────────────────┘
```

---

### Control Plane Components

The **Control Plane** (also called the **Master Node**) is the **brain** of the cluster. In production, this always runs on **dedicated nodes** (never mixed with application workloads).

In AWS, when you use **Amazon EKS**, AWS manages the control plane for you automatically.

---

#### 🔵 1. API Server (`kube-apiserver`)

**The single entry point for ALL operations in Kubernetes.**

- Every command you run (`kubectl apply`, `kubectl get pods`, etc.) goes to the API Server
- It is a **REST API** server — everything communicates via HTTP/HTTPS
- Performs **authentication** (who are you?) and **authorization** (what can you do?)
- Validates all YAML/JSON configurations before processing
- The **only component** that directly reads/writes to etcd

```
Developer → kubectl apply -f deploy.yaml
              ↓
           API Server (validates, authenticates, authorizes)
              ↓
           etcd (saves desired state)
              ↓
           Other components react
```

**Think of it as:** The **reception desk** of a hospital — every request goes through it.

---

#### 🟡 2. etcd

**The cluster's database — stores ALL cluster state.**

- **etcd** = Distributed key-value store (like a very reliable Redis)
- Stores everything: pod definitions, node info, secrets, configmaps, RBAC rules, all YAML data
- Uses the **Raft consensus algorithm** — guarantees data consistency even if some etcd nodes fail
- In production, etcd runs as a **cluster of 3 or 5 nodes** for high availability
- **If etcd is lost, the entire cluster state is lost** — this is why etcd backups are critical

```
etcd stores entries like:
Key: /registry/pods/default/nginx-pod
Value: { "apiVersion": "v1", "kind": "Pod", "metadata": {...}, "spec": {...} }
```

**Think of it as:** The **hospital's records department** — all patient files (cluster state) are stored here.

---

#### 🟢 3. Scheduler (`kube-scheduler`)

**Decides which Worker Node a new Pod should run on.**

When a new pod needs to be created, the scheduler:
1. Looks at all available worker nodes
2. **Filters** nodes that cannot run the pod (insufficient CPU, memory, taints, etc.)
3. **Scores** the remaining nodes based on available resources, affinity rules, etc.
4. **Assigns** the pod to the best-scoring node
5. Updates the API server with the decision (not the pod itself — just the assignment)

**Scheduling Factors:**
- Available CPU and memory on the node
- **Taints and Tolerations** — "this node is reserved for GPU workloads"
- **Node Affinity** — "I want my pod to run in us-east-1a"
- **Pod Anti-Affinity** — "don't put 2 replicas on the same node"
- **Resource Requests and Limits** defined in the pod spec

**Think of it as:** The **hospital's bed allocation desk** — assigns patients to the right ward/room based on availability and requirements.

---

#### 🔴 4. Controller Manager (`kube-controller-manager`)

**Ensures the actual state of the cluster matches the desired state.**

The Controller Manager is actually a collection of multiple controllers running as a single process. Each controller watches for specific resource types:

| Controller | Responsibility |
|---|---|
| **ReplicaSet Controller** | Ensures correct number of pod replicas are running |
| **Deployment Controller** | Manages rolling updates and rollbacks |
| **Node Controller** | Detects node failures, marks nodes as NotReady |
| **Service Account Controller** | Creates default service accounts in new namespaces |
| **Job Controller** | Manages batch jobs to completion |
| **CronJob Controller** | Manages scheduled jobs |

**The Reconciliation Loop (Control Loop):**

```
LOOP (runs forever):
  1. Read desired state from etcd
     (e.g., "I want 3 nginx pods")
  2. Read actual state from cluster
     (e.g., "Currently 2 nginx pods are running")
  3. If mismatch → take corrective action
     (e.g., "Create 1 more nginx pod")
  4. Report back to API Server
  5. Go to step 1
```

**Think of it as:** A **hospital quality manager** who constantly checks if the number of nurses matches requirements, hires if short-staffed, and reports deviations.

---

### Worker Node Components

Worker Nodes are the **actual machines** where your application containers run. In AWS, these are EC2 instances.

---

#### ⚙️ 1. Kubelet

**The primary agent that runs on every worker node.**

- Communicates with the API Server (registers itself, reports node health)
- Receives pod specifications (PodSpec) from API Server
- Instructs the **Container Runtime** to start/stop containers
- Continuously monitors pod health using **liveness probes** and **readiness probes**
- Reports pod and node status back to API Server
- Does NOT manage containers not created by Kubernetes

```
API Server → "Run this pod spec on Node 1"
                ↓
           Kubelet on Node 1
                ↓
           "CRI, please start this container"
                ↓
           Container Runtime Interface (CRI)
                ↓
           Container is running
                ↓
           Kubelet → API Server: "Pod is Running"
```

**Think of it as:** The **ward nurse** — receives instructions from hospital management, carries them out at the patient (pod) level, and reports status back.

---

#### 🐳 2. Container Runtime Interface (CRI)

**The actual engine that creates and runs containers.**

- Kubernetes does NOT directly create containers — it delegates to the CRI
- The CRI is a plugin interface — Kubernetes can work with multiple runtimes

| Runtime | Details |
|---|---|
| **containerd** | Default in modern Kubernetes (v1.24+). Lightweight, CNCF project |
| **CRI-O** | Lightweight runtime, designed specifically for Kubernetes, used in OpenShift |
| **Docker** | Was the original runtime. Removed as default in K8s v1.24 (but containerd still used underneath) |

> 📝 **Note on Docker removal:** From Kubernetes v1.24, `dockershim` (the Docker adapter) was removed. Kubernetes now uses **containerd** directly. Your Docker images still work perfectly — only the runtime layer changed.

---

#### 🌐 3. Kube-Proxy

**Manages network rules to allow traffic to reach pods.**

- Runs on every worker node as a DaemonSet (one instance per node)
- Maintains **iptables** (or IPVS) rules on each node
- Enables the Kubernetes **Service** abstraction — when you create a Service, kube-proxy sets up routing rules so traffic to the Service IP gets forwarded to the correct pods
- Handles **east-west traffic** (pod-to-pod) and **north-south traffic** (external → pod)

```
External User → Load Balancer → Node's Kube-Proxy → Service → Pod
```

**Think of it as:** The **hospital's switchboard operator** — routes incoming calls (traffic) to the right department (pod).

---

### Full Request Flow: `kubectl apply` to Pod Running

This is the **complete end-to-end flow** — extremely important for interviews!

```
STEP 1: Developer runs:
  $ kubectl apply -f deployment.yaml

STEP 2: kubectl → API Server
  - kubectl converts YAML to JSON REST API request
  - Sends HTTP POST to API Server
  - API Server authenticates & authorizes the request

STEP 3: API Server → etcd
  - API Server saves desired state to etcd
  - e.g., "Desired: 2 nginx pods"

STEP 4: API Server → Controller Manager
  - Controller Manager is watching (via watch API) for changes
  - Deployment Controller detects new Deployment
  - Creates a ReplicaSet object
  - ReplicaSet Controller detects ReplicaSet with 0 pods (actual) vs 2 (desired)
  - Creates 2 Pod objects (just the definition, not actual pods yet)
  - Saves Pod definitions back to API Server → etcd

STEP 5: API Server → Scheduler
  - Scheduler is watching for Pods with no node assigned
  - Detects 2 unscheduled pods
  - Evaluates available nodes
  - Assigns Pod 1 to Worker Node 1, Pod 2 to Worker Node 2
  - Updates Pod definitions with nodeName field
  - Saves back to API Server → etcd

STEP 6: API Server → Kubelet (on Worker Node 1 & 2)
  - Kubelet on each node is watching for pods assigned to its node
  - Kubelet detects a new pod assigned to it
  - Kubelet calls CRI: "Please start container with this image"

STEP 7: CRI → Container starts
  - CRI pulls the Docker image from ECR/Docker Hub
  - Creates and starts the container
  - Pod moves to "Running" state

STEP 8: Kubelet → API Server
  - Kubelet reports: "Pod is Running"
  - API Server saves updated status to etcd

STEP 9: Kube-Proxy → iptables updated
  - Kube-proxy detects new running pods
  - Updates iptables rules so traffic can reach the pods

RESULT: Pod is Running and accessible!
```

**Simplified Flow:**
```
Developer → API → etcd → Controller → API → Scheduler → API → etcd → Kubelet → CRI → Pod Created → Kubelet → API → etcd ✅
```

---

## 8. Core Kubernetes Objects

### 8.1 Pod

**The smallest deployable unit in Kubernetes.**

```yaml
# pod.yaml
apiVersion: v1           # API version for core objects
kind: Pod                # Object type
metadata:
  name: myapp            # Unique name in the namespace
  labels:
    app: webapp          # Labels are key-value pairs used for selection
    type: front-end
spec:                    # Desired state / specification
  containers:
  - name: nginx-container
    image: nginx         # Docker image (pulled from Docker Hub by default)
```

**Key points about Pods:**
- Pods are **ephemeral** (temporary) — they are born and die. Never "restart" a pod manually.
- Each pod gets a unique **cluster-internal IP address**
- Pods are **not self-healing** on their own — you need ReplicaSet or Deployment for that
- Direct pod creation is only for **testing** — never use bare pods in production

**Pod Lifecycle States:**

```
Pending → ContainerCreating → Running → Succeeded/Failed → Terminating
```

| Phase | Meaning |
|---|---|
| `Pending` | Pod accepted, but containers not started yet (maybe image pulling) |
| `Running` | All containers started, at least one is running |
| `Succeeded` | All containers completed successfully (for Jobs) |
| `Failed` | All containers terminated, at least one failed |
| `Unknown` | Pod state cannot be determined (node communication issue) |

---

### 8.2 ReplicaSet

**Ensures a specified number of pod replicas are always running.**

```yaml
# replicaset.yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: web-rs
spec:
  replicas: 3            # Always maintain exactly 3 pods
  selector:              # How to identify pods it owns
    matchLabels:
      app: webapp        # This RS owns pods with label app=webapp
  template:              # Pod template (blueprint for new pods)
    metadata:
      name: myapp-pod
      labels:
        app: webapp
        type: front-end  # At least 1 label must match selector
    spec:
      containers:
      - name: nginx-container
        image: httpd     # Apache httpd image
```

**How ReplicaSet Self-Healing Works:**

```
Desired state (etcd): replicas=3
Actual state: 3 pods running → No action needed ✅

Pod crashes → Actual state: 2 pods running
ReplicaSet Controller detects: desired(3) ≠ actual(2)
Action: Create 1 new pod automatically ✅

Manual extra pod created with same label → Actual: 4 pods
ReplicaSet Controller detects: desired(3) ≠ actual(4)
Action: Delete 1 extra pod ✅
```

> ⚠️ **Note:** In production, you rarely create ReplicaSets directly. You use **Deployments** which manage ReplicaSets for you.

**The `selector` field is critical:**
- ReplicaSet uses labels to "claim" pods
- Any pod in the namespace with the matching label is "adopted" by the ReplicaSet
- This is how self-healing works — RS doesn't care which pods, just that the count matches

---

### 8.3 Deployment

**The recommended way to run stateless applications in Kubernetes.**

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: httpd      # Container image
        ports:
        - containerPort: 80
```

**Deployment = ReplicaSet + Version Control + Rolling Updates**

| Feature | Pod | ReplicaSet | Deployment |
|---|---|---|---|
| Self-healing | ❌ | ✅ | ✅ |
| Scaling | ❌ | ✅ | ✅ |
| Rolling Update | ❌ | ❌ | ✅ |
| Rollback | ❌ | ❌ | ✅ |
| Update History | ❌ | ❌ | ✅ |

**Rolling Update Process (Zero Downtime Deployment):**

```
Current: 3 pods running v1

Deploy v2:
Step 1: Create 1 pod with v2 → 3×v1 + 1×v2 running (4 total)
Step 2: Delete 1 pod with v1 → 2×v1 + 1×v2 running (3 total)
Step 3: Create 1 pod with v2 → 2×v1 + 2×v2 running (4 total)
Step 4: Delete 1 pod with v1 → 1×v1 + 2×v2 running (3 total)
Step 5: Create 1 pod with v2 → 1×v1 + 3×v2 running (4 total)
Step 6: Delete 1 pod with v1 → 0×v1 + 3×v2 running (3 total) ✅

Result: All traffic on v2, zero downtime!
```

**Rollback:**
```bash
kubectl rollout undo deployment/nginx-deployment         # Rollback to previous version
kubectl rollout undo deployment/nginx-deployment --to-revision=2  # Rollback to specific version
```

---

## 9. YAML File Structure — Explained Line by Line

All Kubernetes YAML files have **4 mandatory top-level fields:**

```yaml
apiVersion: apps/v1   # ① Which Kubernetes API version handles this resource
kind: Deployment      # ② What type of resource are you creating
metadata:             # ③ Data that identifies the resource
  name: my-app
  namespace: production
  labels:
    team: backend
spec:                 # ④ Desired state (the actual configuration)
  replicas: 3
  ...
```

### apiVersion Quick Reference:

| Resource | apiVersion |
|---|---|
| Pod, Service, ConfigMap, Secret | `v1` |
| Deployment, ReplicaSet, DaemonSet | `apps/v1` |
| HorizontalPodAutoscaler | `autoscaling/v2` |
| CronJob | `batch/v1` |
| Ingress | `networking.k8s.io/v1` |
| RBAC (Role, ClusterRole) | `rbac.authorization.k8s.io/v1` |

### Labels vs Selectors:

```yaml
# Labels are like tags on your pod
metadata:
  labels:
    app: webapp         # "My name is webapp"
    env: production     # "I belong to production"
    version: v2         # "I am version 2"

# Selectors are like queries to find pods
selector:
  matchLabels:
    app: webapp         # "Find all pods where app=webapp"
```

---

## 10. The Complete DevOps Workflow with Kubernetes

```
┌─────────────────────────────────────────────────────────────────────┐
│                 COMPLETE DEVOPS PIPELINE                            │
│                                                                     │
│  Developer                                                          │
│     │                                                               │
│     │  1. Write code                                                │
│     ▼                                                               │
│  GitHub Repository                                                  │
│     │  (code + Dockerfile + K8s YAML + CI/CD config)               │
│     │                                                               │
│     │  2. Push code → Triggers CI/CD pipeline                      │
│     ▼                                                               │
│  CI/CD Tool (Jenkins / GitHub Actions / GitLab CI / Azure DevOps)  │
│     │                                                               │
│     │  3. Build Docker image using Dockerfile                       │
│     │     docker build -t myapp:v1.0 .                              │
│     │                                                               │
│     │  4. Run tests (unit, integration)                             │
│     │                                                               │
│     │  5. Push image to ECR (Elastic Container Registry)            │
│     │     docker push 123456.ecr.aws/myapp:v1.0                    │
│     │                                                               │
│     │  6. Deploy to Kubernetes                                      │
│     │     kubectl apply -f kubernetes/deployment.yaml               │
│     ▼                                                               │
│  Kubernetes Cluster (EKS)                                           │
│     │                                                               │
│     │  7. Pull image from ECR                                       │
│     │  8. Create pods on worker nodes                               │
│     │  9. Expose via Service/Ingress                                │
│     ▼                                                               │
│  🌍 Application Live for End Users                                  │
└─────────────────────────────────────────────────────────────────────┘
```

### AWS-Specific Architecture:

```
Internet
   ↓
Route 53 (DNS)
   ↓
Application Load Balancer (ALB)
   ↓
Kubernetes Ingress Controller (e.g., AWS Load Balancer Controller)
   ↓
Kubernetes Service (ClusterIP)
   ↓
Pods (running on EC2 worker nodes in EKS)
   ↓
Amazon ECR (where container images are pulled from)
```

---

## 11. Three Mandatory Files Every DevOps Engineer Must Have

In every production-grade project repository, you must maintain these 3 files:

### File 1: `Dockerfile`
Defines how to **build** the Docker image.

```dockerfile
# Example: Spring Boot application
FROM openjdk:17-alpine         # Base image
WORKDIR /app                   # Working directory inside container
COPY target/myapp.jar app.jar  # Copy built artifact
EXPOSE 8080                    # Document the port
ENTRYPOINT ["java", "-jar", "app.jar"]  # How to start the app
```

### File 2: Kubernetes Manifests (`kubernetes/` folder)
Defines how to **run** the application in Kubernetes.

```
kubernetes/
├── deployment.yaml      # How many pods, which image, resources
├── service.yaml         # How to expose the pods (load balancing)
├── ingress.yaml         # External URL routing
├── configmap.yaml       # Non-sensitive configuration
├── secret.yaml          # Sensitive data (passwords, API keys)
└── hpa.yaml             # Auto-scaling rules
```

### File 3: CI/CD Pipeline File
Defines how to **automate** the build and deploy process.

```yaml
# Example: .github/workflows/deploy.yml (GitHub Actions)
name: Build and Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build Docker Image
        run: docker build -t myapp:${{ github.sha }} .
      - name: Push to ECR
        run: docker push $ECR_REGISTRY/myapp:${{ github.sha }}
      - name: Deploy to Kubernetes
        run: kubectl apply -f kubernetes/
```

> **Repository Structure Best Practice:**
> ```
> my-project/
> ├── src/                    # Application source code
> ├── Dockerfile              # Container build instructions
> ├── kubernetes/             # K8s manifests
> │   ├── deployment.yaml
> │   ├── service.yaml
> │   └── ingress.yaml
> ├── .github/workflows/      # CI/CD pipeline
> │   └── deploy.yml
> └── README.md
> ```

---

## 12. Kubernetes vs Traditional ASG/EC2 Approach

| Feature | Traditional (EC2 + ASG + ALB) | Kubernetes (EKS) |
|---|---|---|
| **Unit of scale** | EC2 instance (VM) | Pod (container) |
| **Startup time** | Minutes (boot OS, install deps) | Seconds (container already has deps) |
| **Resource efficiency** | Low (each EC2 = full VM) | High (bin-packing, multiple pods per node) |
| **Self-healing** | ASG replaces failed EC2 | K8s replaces failed pods (much faster) |
| **Multi-service management** | 1 ASG + 1 TG per service | All services in one cluster |
| **Rolling updates** | Complex (blue/green, manual) | Built-in, automatic |
| **Config management** | User data scripts, SSM | ConfigMaps, Secrets |
| **Secrets** | SSM Parameter Store (manual) | Kubernetes Secrets (native) |
| **Complexity** | Simple for 1-2 apps, nightmare for 10+ | Initial complexity, then scales easily |
| **Cost** | Can be wasteful | More efficient resource utilization |
| **Observability** | CloudWatch (limited) | Prometheus + Grafana (rich metrics) |
| **Learning curve** | Low | Higher (but worth it) |

**Decision guide:**
- ✅ Use **EC2 + ASG** if: you have < 5 services, small team, simple app, no container expertise
- ✅ Use **Kubernetes** if: microservices architecture, multiple teams, frequent deployments, high scale requirements

---

## 13. Interview Questions & Answers

### Q1: What is Kubernetes and why do we use it?
**A:** Kubernetes is an open-source container orchestration platform developed by Google. We use it to automate deployment, scaling, and management of containerized applications. It provides self-healing, auto-scaling, load balancing, rolling updates, and high availability — ensuring applications run reliably at scale.

### Q2: Explain the Kubernetes architecture.
**A:** Kubernetes has a master-worker architecture.
- **Control Plane:** API Server (single entry point), etcd (cluster database), Scheduler (assigns pods to nodes), Controller Manager (ensures desired state)
- **Worker Nodes:** Kubelet (node agent), CRI (runs containers), Kube-Proxy (network rules)
All communication goes through the API Server. etcd is the source of truth.

### Q3: What is the difference between a Pod and a Container?
**A:** A Container is created by a container runtime tool like Docker. A Pod is the smallest unit in Kubernetes — it wraps one or more containers and provides shared network and storage. Containers are in the "Docker world"; Pods are in the "Kubernetes world."

### Q4: What is etcd and why is it important?
**A:** etcd is a distributed key-value store that serves as Kubernetes' database. It stores the entire cluster state — all pod definitions, configurations, secrets, RBAC rules, etc. If etcd is lost, the cluster loses all its state. This is why etcd backup is a critical production practice.

### Q5: What is the difference between ReplicaSet and Deployment?
**A:** A ReplicaSet ensures a fixed number of pod replicas are always running and provides self-healing. A Deployment manages ReplicaSets and adds rolling update and rollback capabilities. In production, you always use Deployments — never bare ReplicaSets.

### Q6: What is self-healing in Kubernetes?
**A:** Kubernetes continuously compares desired state (stored in etcd) with actual state (running pods). If a pod crashes, the ReplicaSet Controller detects the mismatch and creates a new pod automatically. If a node fails, the Node Controller marks it as NotReady and all pods are rescheduled to healthy nodes.

### Q7: What is the difference between Kubernetes and OpenShift?
**A:** OpenShift is an enterprise Kubernetes distribution built by Red Hat on top of standard Kubernetes. It adds built-in CI/CD pipelines, internal image registry, enhanced security (no root by default), better monitoring/logging, and enterprise support. Kubernetes is the open-source base; OpenShift is the enterprise product built on it.

### Q8: What does the Scheduler do?
**A:** The Scheduler assigns newly created pods (that have no node assigned) to suitable worker nodes. It evaluates node resources (CPU, memory), taints/tolerations, node affinity rules, and pod anti-affinity to select the best node. It does NOT create the pod — it just decides where it should go.

### Q9: What is Kubelet?
**A:** Kubelet is an agent running on every worker node. It registers the node with the API Server, watches for pod assignments to its node, instructs the container runtime to start/stop containers, monitors pod health via probes, and reports status back to the API Server.

### Q10: Walk me through what happens when you run `kubectl apply -f deployment.yaml`
**A:** kubectl sends the YAML as a REST API request to the API Server → API Server validates and stores desired state in etcd → Controller Manager creates a ReplicaSet and Pod definitions → Scheduler assigns pods to nodes → Kubelets on assigned nodes receive pod specs → CRI pulls the image and starts containers → Pod status updated back to etcd. End-to-end: Developer → API → etcd → Controller → API → Scheduler → API → etcd → Kubelet → CRI → Pod Running.

---

## 14. Quick Reference — kubectl Commands

```bash
# ── Cluster Info ──────────────────────────────────────────────
kubectl cluster-info                        # Show cluster endpoint info
kubectl get nodes                           # List all nodes
kubectl get nodes -o wide                   # List nodes with extra info (IP, OS, runtime)
kubectl describe node <node-name>           # Detailed node info

# ── Pods ──────────────────────────────────────────────────────
kubectl get pods                            # List pods in default namespace
kubectl get pods -n kube-system             # List pods in kube-system namespace
kubectl get pods -A                         # List pods in ALL namespaces
kubectl get pods -o wide                    # Show which node each pod runs on
kubectl describe pod <pod-name>             # Detailed pod info + events
kubectl logs <pod-name>                     # View pod logs
kubectl logs <pod-name> -f                  # Stream live pod logs
kubectl logs <pod-name> -c <container>      # Logs for specific container in pod
kubectl exec -it <pod-name> -- bash         # Shell into a pod
kubectl delete pod <pod-name>               # Delete a pod

# ── Deployments ───────────────────────────────────────────────
kubectl get deployments                     # List deployments
kubectl apply -f deployment.yaml            # Create or update deployment
kubectl delete -f deployment.yaml           # Delete deployment
kubectl scale deployment <name> --replicas=5  # Scale deployment
kubectl rollout status deployment/<name>    # Watch rollout progress
kubectl rollout history deployment/<name>   # View rollout history
kubectl rollout undo deployment/<name>      # Rollback to previous version

# ── ReplicaSets ───────────────────────────────────────────────
kubectl get replicasets                     # List ReplicaSets
kubectl get rs                              # Shorthand

# ── Services ──────────────────────────────────────────────────
kubectl get services                        # List services
kubectl get svc                             # Shorthand

# ── Namespaces ────────────────────────────────────────────────
kubectl get namespaces                      # List namespaces
kubectl create namespace dev                # Create namespace
kubectl config set-context --current --namespace=dev  # Switch default namespace

# ── Debugging ─────────────────────────────────────────────────
kubectl get events --sort-by='.lastTimestamp'   # Recent events
kubectl top pods                                # CPU/memory usage per pod
kubectl top nodes                               # CPU/memory usage per node
```

---

## 15. Summary Mind Map

```
                        ☸️ KUBERNETES
                             │
          ┌──────────────────┼──────────────────┐
          │                  │                  │
    WHAT IS IT?          WHY USE IT?       ARCHITECTURE
          │                  │                  │
    Container           Self-Healing      ┌─────┴─────┐
    Orchestration       Auto-Scaling   Control    Worker
    Tool by Google      Load Balancing  Plane      Nodes
                        HA              │            │
                        Rolling Update  ├─API Server ├─Kubelet
                                        ├─etcd       ├─CRI
                                        ├─Scheduler  └─KubeProxy
                                        └─Controller
                             │
                    CORE OBJECTS
                             │
              ┌──────────────┼──────────────┐
              │              │              │
             Pod          ReplicaSet    Deployment
              │              │              │
           Smallest       Ensures       RS + Rolling
           Unit           Replica       Updates +
           1+ containers  Count         Rollback
                             │
                    DEVOPS WORKFLOW
                             │
         Code → GitHub → CI/CD → Docker Build
              → ECR → kubectl apply → K8s Cluster
                             │
                   3 MANDATORY FILES
                             │
              ┌──────────────┼──────────────┐
              │              │              │
          Dockerfile    K8s Manifests    CI/CD
          (Build image) (Run app)        Pipeline
```

---

## 📚 Further Learning Resources

| Resource | Link |
|---|---|
| Official Kubernetes Docs | https://kubernetes.io/docs |
| Kubernetes Interactive Tutorial | https://kubernetes.io/docs/tutorials/ |
| Play with Kubernetes (free lab) | https://labs.play-with-k8s.com |
| CNCF Landscape | https://landscape.cncf.io |
| KillerCoda (K8s practice labs) | https://killercoda.com/kubernetes |
| AWS EKS Documentation | https://docs.aws.amazon.com/eks |

---

## 🏷️ Tags

`kubernetes` `k8s` `devops` `containers` `docker` `orchestration` `aws` `eks` `openshift` `cloudops` `devsecops` `cicd` `microservices` `architecture`

---

*📝 Notes enriched from class session — NareshIT DevOps/CloudOps Program*
*✅ Suitable for: Freshers, Experienced Engineers, AWS SAA/CKA exam preparation*
