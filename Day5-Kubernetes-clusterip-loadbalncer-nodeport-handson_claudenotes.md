# Kubernetes Services — Complete Guide
> Class Notes | EKS Hands-On Lab | Kubernetes v1.34 | Region: us-east-1

---

## Table of Contents

1. [What is a Kubernetes Service?](#1-what-is-a-kubernetes-service)
2. [The Three IP + Three Port Model](#2-the-three-ip--three-port-model)
3. [How kube-proxy Works](#3-how-kube-proxy-works)
4. [Service Types Deep Dive](#4-service-types-deep-dive)
   - [ClusterIP](#41-clusterip---internal-only)
   - [NodePort](#42-nodeport---external-via-node)
   - [LoadBalancer](#43-loadbalancer---external-via-aws-elb)
   - [Headless](#44-headless-services---for-stateful-apps)
5. [EKS Cluster Setup (eksctl)](#5-eks-cluster-setup-with-eksctl)
6. [Lab Walkthrough — NodePort](#6-lab-walkthrough--nodeport-service)
7. [Lab Walkthrough — LoadBalancer](#7-lab-walkthrough--loadbalancer-service)
8. [Lab Walkthrough — ClusterIP](#8-lab-walkthrough--clusterip-service)
9. [Critical Concept: Label Matching](#9-critical-concept-label-matching)
10. [Interview Questions & Troubleshooting](#10-interview-questions--troubleshooting)
11. [Quick Reference Cheat Sheet](#11-quick-reference-cheat-sheet)

---

## 1. What is a Kubernetes Service?

When Pods run in Kubernetes, they are **ephemeral** — they get created, destroyed, and rescheduled constantly. Every time a Pod restarts, it gets a **new IP address**. This creates a problem:

> How do other Pods or external users reliably talk to a Pod if its IP keeps changing?

**Kubernetes Services solve this problem.**

A Service is a stable, long-lived abstraction that:
- Gets a **fixed virtual IP** (called ClusterIP) that never changes
- Acts as a **load balancer** across all matching Pods
- Uses **label selectors** to automatically discover which Pods to route traffic to
- Handles **cross-node routing** transparently — even if the Pod is on a different node

```
Without Service:           With Service:
                           
Client → Pod-IP (changes)  Client → Service-IP (stable) → Pod-A
                                                         → Pod-B
                                                         → Pod-C
```

---

## 2. The Three IP + Three Port Model

This is one of the most important mental models in Kubernetes networking. There are **3 layers of IPs and 3 layers of Ports**.

### IPs

| IP Type      | What It Represents                              | Example from Lab         |
|--------------|-------------------------------------------------|--------------------------|
| **Node IP**  | The EC2 instance's IP (internal or external)    | `192.168.4.64` (internal), `18.233.9.84` (external) |
| **Service IP** | Virtual IP assigned to the Service (ClusterIP) | `10.100.154.227`         |
| **Pod IP**   | The IP assigned to the individual Pod            | `192.168.21.190`         |

### Ports

| Port Type         | What It Represents                                            | Example from Lab |
|-------------------|---------------------------------------------------------------|------------------|
| **NodePort**      | The port opened on every Node's IP for external traffic       | `30007`          |
| **Service Port**  | The port the Service listens on (inside the cluster)          | `80`             |
| **TargetPort**    | The actual port the container/Pod listens on                  | `80`             |

### How Traffic Flows Through All Three Layers

```
External User
      │
      ▼
NodeIP:NodePort          → e.g. 18.233.9.84:30007
      │
      ▼
Service (ClusterIP)      → e.g. 10.100.154.227:80   (Service Port)
      │
      ▼
Pod (Container)          → e.g. 192.168.21.190:80   (TargetPort)
```

> **Fresher Tip:** Think of it like a restaurant.
> - NodePort = The street address + door number (anyone can walk in)
> - Service Port = The waiter who takes your order (routes you to the right table)
> - TargetPort = The actual chef cooking your food (the real container/application)

---

## 3. How kube-proxy Works

### What is kube-proxy?

`kube-proxy` is a **network component that runs on every node** in the cluster. Its sole responsibility is to manage **network rules** so that traffic reaches the correct Pod.

> kube-proxy is responsible for **Service-to-Pod routing only**. It does NOT handle Pod-to-Pod communication (that is handled by the CNI plugin like `vpc-cni`).

### How It Works — Step by Step

```
Step 1: You create a Service (e.g., NodePort or ClusterIP)
         ↓
Step 2: API Server updates the Endpoint object
        (Endpoint = the list of Pod IPs that match the Service's label selector)
         ↓
Step 3: kube-proxy on EVERY node watches the API Server for Service/Endpoint changes
         ↓
Step 4: kube-proxy writes iptables rules (or IPVS rules) on the node
         ↓
Step 5: Incoming traffic hits the iptables rules → gets forwarded to correct Pod
        (even if the Pod is on a DIFFERENT node)
```

### Cross-Node Routing Example

```
Cluster Setup:
  Node-1 (192.168.4.64)   → Pod-A running here (192.168.21.190)
  Node-2 (192.168.56.244) → No pod here

User hits Node-2:30007
         │
         ▼
kube-proxy on Node-2
         │  (checks Endpoint list → Pod-A is on Node-1)
         ▼
iptables rule: forward to 192.168.21.190:80 on Node-1
         │
         ▼
Pod-A responds ✅
```

The user doesn't know or care which node the Pod is actually on. Kubernetes handles it transparently.

### What are Endpoints?

An **Endpoint** object is automatically created and managed by Kubernetes when you create a Service. It holds the list of `PodIP:Port` combinations that the Service should route traffic to.

```bash
kubectl get endpoints
# NAME         ENDPOINTS                                              AGE
# my-service   192.168.21.190:80,192.168.56.204:80,192.168.12.190:80   15m
```

> **Key insight:** If your Service has **no Endpoints**, traffic will never reach any Pod. This is the most common reason for "Service is running but application is not accessible."

---

## 4. Service Types Deep Dive

Kubernetes has **4 Service types**. Each serves a different use case.

```
┌─────────────────────────────────────────────────────────────────┐
│                  Kubernetes Service Types                       │
│                                                                 │
│  ClusterIP     ─── Internal only (Pod ↔ Pod, Frontend→Backend) │
│  NodePort      ─── External via Node IP (Dev/Testing)          │
│  LoadBalancer  ─── External via Cloud LB (Production)          │
│  Headless      ─── Internal, DNS-based, for StatefulSets (DBs) │
└─────────────────────────────────────────────────────────────────┘
```

---

### 4.1 ClusterIP — Internal Only

**Default service type.** Accessible only within the cluster. No external access at all.

**Use Cases:**
- Frontend Pod talking to Backend Pod
- Backend talking to a database Pod
- Any microservice-to-microservice communication inside the cluster

**What gets created:**
- A stable virtual IP (ClusterIP) only reachable inside the cluster
- No NodePort, no external IP, no load balancer

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-svc
  labels:
    app: my-app
spec:
  type: ClusterIP          # ← Default type
  ports:
  - port: 80               # Service port
    targetPort: 80         # Container port
    protocol: TCP
  selector:
    app: my-app-np         # Must match Pod labels exactly
```

```bash
kubectl get svc my-app-svc
# NAME         TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
# my-app-svc   ClusterIP   10.100.232.162   <none>        80/TCP    9s
#                                           ^^^^^^
#                          No external IP — internal only!
```

**Accessing ClusterIP from inside the cluster:**
```bash
# From inside a Pod (DNS works here)
curl http://my-app-svc          # Using service name (DNS)
curl http://10.100.232.162      # Using ClusterIP directly

# From a Node (EC2 machine that's part of the cluster)
curl http://10.100.232.162      # Works! Node is part of the cluster network
```

**Cannot access from outside:**
```bash
# From your laptop or external machine — this will FAIL
curl http://10.100.232.162      # ❌ This IP is not routable externally
```

---

### 4.2 NodePort — External via Node

Exposes the Service on a **specific port (30000–32767) on every Node's IP**. External users can reach the app using `NodeIP:NodePort`.

**Use Cases:**
- Development and testing environments
- Quick demos when you don't need a cloud load balancer
- Situations where you manage your own external load balancer

**What gets created:**
- All the ClusterIP features (internal routing still works)
- A port opened on **every** node (even nodes not running the Pod)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment-np
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app-np
  template:
    metadata:
      labels:
        app: my-app-np         # ← This label must match Service selector
    spec:
      containers:
      - name: my-container
        image: nginx:latest
        ports:
        - containerPort: 80    # ← Pod's port (TargetPort)
---
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: NodePort
  selector:
    app: my-app-np             # ← Must match Deployment's Pod labels
  ports:
    - port: 80                 # Service port (internal)
      targetPort: 80           # Pod's container port
      nodePort: 30007          # External port on Node (30000–32767)
```

```bash
kubectl get svc
# NAME         TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
# my-service   NodePort   10.100.154.227   <none>        80:30007/TCP   24s
#                                                            ↑
#                                          NodePort : ServicePort format
```

**Accessing NodePort:**
```bash
# Using Node's External IP (AWS Public IP)
http://18.233.9.84:30007      # Node-1's public IP
http://44.213.75.182:30007    # Node-2's public IP — works even if Pod is on Node-1!
```

> **Important:** You must allow port `30007` (TCP) in the Node's **Security Group** for external access to work.

---

### 4.3 LoadBalancer — External via AWS ELB

The **production-grade** way to expose services externally. When you create a LoadBalancer Service in EKS, AWS **automatically provisions** a Classic Load Balancer (or NLB if configured) and wires it up to your nodes.

**Use Cases:**
- Production workloads on AWS EKS
- When you need a stable, highly available DNS endpoint
- When you want AWS to handle TLS termination and health checks

**What AWS automatically creates:**
- Classic Load Balancer (ELB) with its own DNS name
- Target Groups pointing to your Node IPs
- Listener rules (port 80 → nodePort internally)
- Security Group rules (port 80 open by default)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-np
  labels:
    app: my-app-np
spec:
  type: LoadBalancer         # ← Cloud provider creates an ELB
  ports:
  - port: 80                 # ELB listens on port 80
    targetPort: 80           # Forwards to Pod port 80
    protocol: TCP
  selector:
    app: my-app-np
```

```bash
kubectl get svc
# NAME        TYPE           CLUSTER-IP      EXTERNAL-IP                                    PORT(S)        AGE
# my-app-np   LoadBalancer   10.100.28.159   a40d7a4d...elb.amazonaws.com   80:31425/TCP   16s
#                                            ↑
#                            AWS ELB DNS name — use this to access!
```

**Traffic flow with LoadBalancer:**
```
Internet User
     │
     ▼
AWS ELB (DNS: a40d7a4d...elb.amazonaws.com) ← Port 80
     │
     ▼
Node-1 or Node-2 (NodePort, auto-assigned e.g. 31425)
     │
     ▼
kube-proxy → iptables rules
     │
     ▼
Pod (nginx container) ← Port 80
```

> **Security note from lab:** The ELB Security Group automatically allows port 80. The internal listener forwards traffic to the NodePort (e.g., 30007 or auto-assigned). You do NOT need to manually open the NodePort on the Node SG — the ELB handles it.

---

### 4.4 Headless Services — For Stateful Apps

A special type where `clusterIP: None` is set. Kubernetes does **not** assign a virtual IP. Instead, DNS returns the **individual Pod IPs** directly.

**Use Cases:**
- Databases: MongoDB, MySQL, Cassandra, Redis Cluster
- Any StatefulSet where you need to reach a **specific** Pod (e.g., the primary/writer node)
- Applications that need peer discovery

**Why databases need Headless Services:**

In a database cluster (e.g., MySQL with read replicas):
- You must send **WRITE** operations to the **primary** node specifically
- You can send **READ** operations to any replica

With a regular ClusterIP, traffic is load-balanced randomly — you can't control which Pod gets the request. With Headless, DNS gives you each Pod's IP individually.

```
Regular ClusterIP:   client → Service → random Pod (any replica)
Headless Service:    client → DNS query → Pod-0-IP, Pod-1-IP, Pod-2-IP (choose yourself)
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql-headless
spec:
  clusterIP: None            # ← This makes it headless
  selector:
    app: mysql
  ports:
  - port: 3306
    targetPort: 3306
```

> **Single DB instance?** If you only have one database (no replicas), a regular ClusterIP Service is perfectly fine. Headless is needed only when you have multiple instances and need direct Pod addressing.

---

## 5. EKS Cluster Setup with eksctl

### Prerequisites

Before setting up the cluster, an EC2 instance needs an IAM Role with access to:
- IAM
- EC2
- VPC
- CloudFormation

> If your bootstrap machine is **outside AWS** (e.g., your laptop), create an IAM User with programmatic access (Access Key + Secret Key) instead of a Role.

### Install kubectl and eksctl

```bash
# Install kubectl
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s \
  https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

# Install eksctl
curl --silent --location \
  "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" \
  | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Verify
eksctl version
# 0.226.0
```

### Create EKS Cluster

```bash
eksctl create cluster \
  --name test \
  --region us-east-1 \
  --node-type t2.medium
```

**What eksctl does behind the scenes:**
1. Creates CloudFormation stack for the control plane (`eksctl-test-cluster`)
2. Installs EKS addons: `vpc-cni`, `kube-proxy`, `coredns`, `metrics-server`
3. Waits for control plane to become ready
4. Creates a Managed Node Group (`eksctl-test-nodegroup-ng-bb972c8b`) with 2 nodes
5. Saves kubeconfig to `~/.kube/config`

**From the lab — cluster creation log (condensed):**
```
[✔] saved kubeconfig as "/home/ec2-user/.kube/config"
[✔] all EKS cluster resources for "test" have been created
[ℹ] nodegroup "ng-bb972c8b" has 2 node(s)
[ℹ] node "ip-192-168-4-64.ec2.internal" is ready
[ℹ] node "ip-192-168-56-244.ec2.internal" is ready
[✔] EKS cluster "test" in "us-east-1" region is ready
```

```bash
kubectl get nodes
# NAME                             STATUS   ROLES    AGE   VERSION
# ip-192-168-4-64.ec2.internal     Ready    <none>   12m   v1.34.7-eks-4136f65
# ip-192-168-56-244.ec2.internal   Ready    <none>   12m   v1.34.7-eks-4136f65
```

---

## 6. Lab Walkthrough — NodePort Service

### Step 1: Create Deployment + Service YAML

```bash
vi np.yaml
```

```yaml
# np.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment-np
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app-np           # ← Deployment selects Pods with this label
  template:
    metadata:
      labels:
        app: my-app-np         # ← Pod gets this label
    spec:
      containers:
      - name: my-container
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: NodePort
  selector:
    app: my-app-np             # ← Service selects Pods with this label (must match above)
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30007
```

### Step 2: Apply and Verify

```bash
kubectl apply -f np.yaml
# deployment.apps/my-deployment-np created
# service/my-service created

kubectl get pods
# NAME                               READY   STATUS    RESTARTS   AGE
# my-deployment-np-97bbd86dc-82z7j   1/1     Running   0          14s

kubectl get svc
# NAME         TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
# kubernetes   ClusterIP   10.100.0.1       <none>        443/TCP        19m
# my-service   NodePort    10.100.154.227   <none>        80:30007/TCP   24s

kubectl describe svc my-service
# Selector:    app=my-app-np
# Type:        NodePort
# IP:          10.100.154.227
# Port:        80/TCP
# TargetPort:  80/TCP
# NodePort:    30007/TCP
# Endpoints:   192.168.21.190:80   ← Pod IP!
```

### Step 3: Verify the Linkage

```bash
kubectl get pods -o wide
# NAME                               IP               NODE
# my-deployment-np-97bbd86dc-82z7j   192.168.21.190   ip-192-168-4-64.ec2.internal

kubectl get nodes -o wide
# NAME                             INTERNAL-IP     EXTERNAL-IP
# ip-192-168-4-64.ec2.internal     192.168.4.64    18.233.9.84
# ip-192-168-56-244.ec2.internal   192.168.56.244  44.213.75.182

kubectl get endpoints
# NAME         ENDPOINTS             AGE
# my-service   192.168.21.190:80     6m13s
```

The chain is clear:
```
Service Endpoint (192.168.21.190:80) = Pod IP = Pod running on ip-192-168-4-64 (Node External IP: 18.233.9.84)
```

### Step 4: Access the Application

After opening port `30007` in the Node Security Group:
```
http://44.213.75.182:30007   → Welcome to nginx! ✅
```

> Note: Traffic went to **Node-2's** public IP (`44.213.75.182`) even though the Pod was running on **Node-1**. kube-proxy handled the cross-node forwarding automatically.

### Step 5: Scale to 3 Replicas

Change `replicas: 1` to `replicas: 3` in np.yaml and re-apply:

```bash
kubectl apply -f np.yaml
# deployment.apps/my-deployment-np configured

kubectl get pods -o wide
# NAME                               IP               NODE
# my-deployment-np-97bbd86dc-82z7j   192.168.21.190   ip-192-168-4-64.ec2.internal    ← Node 1
# my-deployment-np-97bbd86dc-lsl64   192.168.56.204   ip-192-168-56-244.ec2.internal  ← Node 2
# my-deployment-np-97bbd86dc-xmx7m   192.168.12.190   ip-192-168-4-64.ec2.internal    ← Node 1

kubectl get endpoints
# NAME         ENDPOINTS
# my-service   192.168.12.190:80,192.168.21.190:80,192.168.56.204:80
#              ↑ All 3 Pod IPs automatically added to the Endpoint!
```

> The Service's Endpoint list **automatically updated** to include all 3 Pod IPs. The Service now load-balances across all of them.

---

## 7. Lab Walkthrough — LoadBalancer Service

### Update svc.yaml to type LoadBalancer

```yaml
# svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-np
  labels:
    app: my-app-np
spec:
  type: LoadBalancer       # ← Changed from NodePort
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
  selector:
    app: my-app-np
```

```bash
kubectl apply -f svc.yaml
# service/my-app-np created

kubectl get svc
# NAME        TYPE           CLUSTER-IP      EXTERNAL-IP                                       PORT(S)        AGE
# my-app-np   LoadBalancer   10.100.28.159   a40d7a4d...us-east-1.elb.amazonaws.com   80:31425/TCP   16s
```

AWS automatically created:
- A Classic Load Balancer
- Target Groups
- Listener rules (80 → NodePort 31425)

```bash
# Access via ELB DNS:
http://a40d7a4d518214e829f8faacbdb1ad83-531795687.us-east-1.elb.amazonaws.com/
# → Welcome to nginx! ✅
```

---

## 8. Lab Walkthrough — ClusterIP Service

```yaml
# svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-svc
  labels:
    app: my-app
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
  selector:
    app: my-app-np
```

```bash
kubectl apply -f svc.yaml
kubectl get svc
# NAME         TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
# my-app-svc   ClusterIP   10.100.232.162   <none>        80/TCP    9s
#                                           ↑ No external IP — internal only!

kubectl get endpoints
# NAME         ENDPOINTS
# my-app-svc   192.168.0.243:80,192.168.12.190:80,192.168.56.204:80
```

### Accessing from inside a Pod

```bash
kubectl exec -it my-deployment-np-97bbd86dc-skcf5 -- sh

# Inside the Pod:
curl http://10.100.232.162        # Using ClusterIP — works ✅
curl http://my-app-svc            # Using DNS name — works ✅ (via CoreDNS)
```

### Accessing from a Node (EC2)

```bash
# SSH into one of the worker nodes
curl http://10.100.232.162        # Works! ✅ (Node is part of cluster network)
```

### Cannot Access from Outside

```bash
# From your laptop or any external machine
curl http://10.100.232.162        # ❌ Fails — ClusterIP is not routable externally
```

---

## 9. Critical Concept: Label Matching

**This is the #1 cause of Service issues in interviews and production.**

Labels connect three objects together:

```
Deployment (matchLabels) → Pod (labels) → Service (selector)
```

All three must use the **exact same label value**.

### Working Example ✅

```yaml
# Deployment
selector:
  matchLabels:
    app: my-app-np          # ← "my-app-np"

# Pod template
labels:
  app: my-app-np            # ← "my-app-np" (matches)

# Service
selector:
  app: my-app-np            # ← "my-app-np" (matches)
```

Result:
```bash
kubectl get endpoints
# my-service   192.168.21.190:80   ← Endpoints populated ✅
```

### Broken Example ❌ — Label Mismatch

```yaml
# Deployment labels pods as:
labels:
  app: my-app-np

# Service selector says:
selector:
  app: my-app-npp           # ← Extra 'p' — TYPO!
```

Result:
```bash
kubectl get endpoints
# my-service   <none>        ← No endpoints! Service is running but useless!

kubectl describe svc my-service
# Selector: app=my-app-npp  ← Doesn't match any Pod
# Endpoints: (none)
```

The application will be completely unreachable even though both the Deployment and Service are "Running."

### How to Debug Label Mismatch

```bash
# Step 1: Check what labels your Pods have
kubectl get pods --show-labels

# Step 2: Check what selector your Service is using
kubectl describe svc <service-name>
# Look at: Selector: field

# Step 3: Check if Endpoints got created
kubectl get endpoints <service-name>
# If <none> → label mismatch confirmed

# Step 4: Fix the label in the YAML and re-apply
kubectl apply -f svc.yaml
```

---

## 10. Interview Questions & Troubleshooting

### Common Interview Question

**"The Service is running but the application is not accessible from outside. What do you check?"**

Work through these layers in order:

```
Layer 1 — Security Group
  └── Is the NodePort (e.g., 30007) open in the Node's SG?
  └── For LoadBalancer: Is port 80 open in the ELB's SG?

Layer 2 — Endpoints
  └── kubectl get endpoints <service-name>
  └── If <none> → label mismatch between Service selector and Pod labels

Layer 3 — Pod Health
  └── kubectl get pods → are Pods in Running state?
  └── kubectl describe pod <pod-name> → any CrashLoopBackOff or errors?

Layer 4 — Service Config
  └── kubectl describe svc <service-name>
  └── Check: correct type? correct port? correct selector?

Layer 5 — Application Level
  └── kubectl exec -it <pod> -- curl http://localhost:80
  └── Is the app actually listening on the right port inside the container?
```

### Key Commands Reference

```bash
# View all services
kubectl get svc
kubectl get svc -o wide

# Describe a specific service (shows selector, endpoints, type)
kubectl describe svc <service-name>

# View endpoints (the actual Pod IPs a service routes to)
kubectl get endpoints

# View pods with their IPs and node placement
kubectl get pods -o wide

# View nodes with external IPs
kubectl get nodes -o wide

# Show pod labels
kubectl get pods --show-labels

# Execute command inside a pod
kubectl exec -it <pod-name> -- sh
kubectl exec -it <pod-name> -- curl http://<clusterip>

# Apply/Delete resources
kubectl apply -f <file>.yaml
kubectl delete -f <file>.yaml
```

### Service Type Decision Guide

```
Q: Does only internal traffic need to reach this service?
   Yes → ClusterIP

Q: Is it a database/stateful app with multiple instances?
   Yes → Headless Service (clusterIP: None)

Q: Need external access for dev/testing quickly?
   Yes → NodePort (remember to open the port in SG)

Q: Production-grade external access on AWS?
   Yes → LoadBalancer (EKS auto-creates the ELB)
```

---

## 11. Quick Reference Cheat Sheet

### Service Types Summary

| Feature               | ClusterIP     | NodePort         | LoadBalancer         | Headless           |
|-----------------------|---------------|------------------|----------------------|--------------------|
| External Access       | ❌ No          | ✅ Yes (NodeIP:Port) | ✅ Yes (ELB DNS)   | ❌ No (internal)   |
| Virtual IP (ClusterIP)| ✅ Yes         | ✅ Yes            | ✅ Yes               | ❌ None             |
| Port Range            | Any           | 30000–32767      | Any (ELB handles)    | Any                |
| AWS Resource Created  | None          | None             | ELB, TG, Listener    | None               |
| Best For              | Pod↔Pod comms | Dev/Testing      | Production           | DBs, StatefulSets  |

### Port Mapping Summary

```
External Request → NodeIP:30007 → Service:80 → Pod:80
                   (NodePort)    (ServicePort)  (TargetPort)
```

### Label Chain (must match exactly)

```
Deployment.spec.selector.matchLabels.app = "X"
Pod.metadata.labels.app                  = "X"
Service.spec.selector.app                = "X"
```

If any of these don't match → `Endpoints: <none>` → app unreachable.

### Endpoint Status Meaning

```bash
kubectl get endpoints
# my-service   192.168.21.190:80    → Pod found, traffic will route ✅
# my-service   <none>               → No matching Pods — check labels! ❌
```

---

> **Lab Environment:** EKS Cluster `test` | Region `us-east-1` | Kubernetes v1.34.7 | Node Type t2.medium | 2 worker nodes (Amazon Linux 2023)
