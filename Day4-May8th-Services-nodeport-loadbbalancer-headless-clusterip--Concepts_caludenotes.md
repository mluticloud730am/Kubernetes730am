# ☸️ Day 4 — Kubernetes Services: NodePort · ClusterIP · LoadBalancer · Headless

> **Session Date:** 8th May 2026 | **Batch:** 7:30 AM | **Instructor:** Veera Sir  
> **Platform:** AWS EKS | EKS Version: `v1.34.7-eks-4136f65` | Nodes: `t2.medium` (Amazon Linux 2023)  
> **Topics Covered:** Why Services Exist · NodePort · ClusterIP · LoadBalancer · Headless · kube-proxy · iptables · StatefulSet intro

---

## 📋 Table of Contents

1. [The Big Problem — Why Services Exist](#-the-big-problem--why-services-exist)
2. [The 4 Types of Kubernetes Services](#-the-4-types-of-kubernetes-services)
3. [How Traffic Flows — Port Mapping Deep Dive](#-how-traffic-flows--port-mapping-deep-dive)
4. [kube-proxy & iptables — The Internal Magic](#-kube-proxy--iptables--the-internal-magic)
5. [Service 1 — NodePort (External Access)](#-service-1--nodeport-external-access)
   - [nodeport.yaml Deep Dive](#nodeportyaml-deep-dive)
   - [Hands-On Lab: Live nginx via NodePort](#hands-on-lab-live-nginx-via-nodeport)
   - [The Multi-Node Traffic Mystery (IRCTC scenario)](#the-multi-node-traffic-mystery-irctc-scenario)
6. [Service 2 — ClusterIP (Internal Only)](#-service-2--clusterip-internal-only)
7. [Service 3 — LoadBalancer (Production External)](#-service-3--loadbalancer-production-external)
8. [Service 4 — Headless Service (StatefulSet / Databases)](#-service-4--headless-service-statefulset--databases)
   - [StatefulSet vs Deployment — Key Difference](#statefulset-vs-deployment--key-difference)
   - [Why Databases Need Headless + StatefulSet](#why-databases-need-headless--statefulset)
9. [Full Application Architecture — Frontend + Backend + DB](#-full-application-architecture--frontend--backend--db)
10. [Kubernetes DNS and Route53](#-kubernetes-dns-and-route53)
11. [Real-World Scenarios & Interview Q&A](#-real-world-scenarios--interview-qa)
12. [Quick Reference — All kubectl Commands Used Today](#-quick-reference--all-kubectl-commands-used-today)
13. [Common Mistakes & Gotchas](#-common-mistakes--gotchas)

---

## 🚨 The Big Problem — Why Services Exist

After Day 3 you know how to run Pods and Deployments. But there's a massive gap:

```
PROBLEM 1 — Pods get new IPs every time they restart
────────────────────────────────────────────────────
Pod restarts:  192.168.40.47  →  192.168.40.99  (IP changed!)
Your app was hardcoded to 192.168.40.47 → NOW BROKEN ❌

PROBLEM 2 — How does external traffic reach a Pod?
────────────────────────────────────────────────────
Pod IP is PRIVATE (192.168.x.x) — not reachable from the internet ❌
User types yourdomain.com → where does it go? Nobody knows ❌

PROBLEM 3 — Multiple Pods, who gets the request?
────────────────────────────────────────────────────
You have 3 replicas: Pod1, Pod2, Pod3
User sends request → which Pod handles it?
There's no load balancing built into raw Pods ❌
```

**Kubernetes Services solve ALL of this:**

```
                      ┌─────────────────────────────────┐
                      │       KUBERNETES SERVICE         │
                      │                                  │
  External User ─────►│  • Stable IP (never changes)     │──────► Pod1
                      │  • Load balancing across Pods    │──────► Pod2
                      │  • Finds Pods via labels         │──────► Pod3
                      └─────────────────────────────────┘
                            (Pod IPs can change freely)
```

> 🎯 **A Service gives you a STABLE endpoint that always points to the right Pods — regardless of how many times Pods restart or scale.**

---

## 🗂️ The 4 Types of Kubernetes Services

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    KUBERNETES SERVICE TYPES                               │
├──────────────────┬──────────────────┬─────────────────────────────────── ┤
│   SERVICE TYPE   │   ACCESS SCOPE   │   USE CASE                         │
├──────────────────┼──────────────────┼────────────────────────────────────┤
│                  │                  │                                     │
│  🌐 NodePort     │   EXTERNAL       │  Dev/test, expose via Node IP:Port  │
│                  │                  │  (IP + Port exposed to internet)    │
├──────────────────┼──────────────────┼────────────────────────────────────┤
│                  │                  │                                     │
│  ⚖️ LoadBalancer │   EXTERNAL       │  Production frontend apps           │
│                  │                  │  (Cloud creates ALB/NLB, clean URL) │
├──────────────────┼──────────────────┼────────────────────────────────────┤
│                  │                  │                                     │
│  🔒 ClusterIP    │   INTERNAL ONLY  │  Frontend ↔ Backend communication  │
│                  │                  │  (Not reachable from internet)      │
├──────────────────┼──────────────────┼────────────────────────────────────┤
│                  │                  │                                     │
│  🗄️ Headless     │   INTERNAL ONLY  │  Stateful apps: Databases,          │
│                  │                  │  Elasticsearch, Kafka               │
│                  │                  │  (Direct Pod DNS, no load balance)  │
└──────────────────┴──────────────────┴────────────────────────────────────┘
```

---

## 🔌 How Traffic Flows — Port Mapping Deep Dive

There are **3 different port numbers** involved when traffic reaches a Pod. Understanding this is critical:

```
INTERNET USER
     │
     │  http://54.167.41.45:30007
     ▼
┌─────────────────────────────────┐
│         EC2 NODE (Worker)       │
│      IP: 54.167.41.45           │
│                                 │
│  NodePort: 30007  ◄─────────── │◄── User hits this port on the Node
│         │                       │
│         ▼                       │
│  ┌──────────────────────────┐   │
│  │   KUBERNETES SERVICE     │   │
│  │   ClusterIP: 10.100.x.x  │   │
│  │   Service Port: 80       │   │◄── Service's internal "front door"
│  └──────────┬───────────────┘   │
│             │                   │
│             ▼                   │
│  ┌──────────────────────────┐   │
│  │         POD              │   │
│  │   IP: 192.168.40.47      │   │
│  │   TargetPort: 80         │   │◄── App inside container listens here
│  └──────────────────────────┘   │
└─────────────────────────────────┘
```

**The 3 Ports Explained:**

| Port Name | Where It Lives | Value in Lab | What It Means |
|-----------|---------------|--------------|---------------|
| **nodePort** | On the EC2 Node (Worker) | `30007` | The door users knock on from the internet. Range: `30000–32767` |
| **port** | On the Service object | `80` | The Service's internal listening port |
| **targetPort** | On the Pod/Container | `80` | The port your actual application code listens on |

> 💡 **Fresher analogy:** Think of a hotel building:
> - `nodePort` = the street-level building entrance (public address)
> - `port` = the hotel reception desk (directs you to the right room)
> - `targetPort` = the actual room door (where your guest/app lives)

---

## ⚙️ kube-proxy & iptables — The Internal Magic

Every worker node runs a system component called **kube-proxy**. This is what actually makes Services work under the hood.

```
END USER REQUEST FLOW
─────────────────────────────────────────────────────────────────
User: "I want http://54.167.41.45:30007"
        │
        ▼
   ┌─────────────────────────────────────────────────────────┐
   │                 Worker Node                              │
   │                                                          │
   │  1. Packet arrives at Node IP: 54.167.41.45:30007        │
   │              │                                           │
   │              ▼                                           │
   │  2. kube-proxy checks iptables rules                     │
   │     "Port 30007 maps to Service 10.100.168.126:80"       │
   │              │                                           │
   │              ▼                                           │
   │  3. iptables selects a Pod IP (load balances)            │
   │     "Service has endpoints: 192.168.40.47:80"            │
   │              │                                           │
   │              ▼                                           │
   │  4. Traffic forwarded to Pod: 192.168.40.47:80           │
   │                                                          │
   └─────────────────────────────────────────────────────────┘
```

**What is iptables?**

iptables is a Linux kernel firewall/routing tool. kube-proxy writes rules into iptables that say:

```
"If traffic comes in on port 30007 → DNAT (Destination NAT) it to 192.168.40.47:80"
```

> 🔑 **Key insight:** kube-proxy does NOT proxy traffic directly — it writes iptables rules, and the Linux kernel does the actual packet forwarding. kube-proxy only updates the rules when Services/Pods change.

**kube-proxy confirmed running in our cluster:**

```bash
$ kubectl get pods -A
NAMESPACE     NAME                              READY   STATUS
kube-system   kube-proxy-2qdl8                  1/1     Running   # Node 1
kube-system   kube-proxy-br2d4                  1/1     Running   # Node 2
kube-system   coredns-566b9b9d-cmzfd            1/1     Running   # DNS
kube-system   coredns-566b9b9d-jgkn6            1/1     Running   # DNS
kube-system   aws-node-dr6v6                    2/2     Running   # AWS CNI
kube-system   aws-node-fdn8s                    2/2     Running   # AWS CNI
kube-system   metrics-server-6f49c4bc6c-k82n4   1/1     Running   # Metrics
```

> Every `kube-proxy-xxxxx` pod is a per-node daemon that keeps iptables rules in sync with the cluster's Service/Pod state.

---

## 🌐 Service 1 — NodePort (External Access)

### What is NodePort?

NodePort exposes your application on a **static port** on every worker node. Any traffic hitting `<NodeIP>:<NodePort>` is forwarded into the cluster.

```
                            NodePort Range: 30000–32767
                            ┌──────────────────────────┐
 Internet User              │       WORKER NODES        │
 http://54.167.41.45:30007  │                           │
         │                  │  Node1: 54.167.41.45      │
         └─────────────────►│  :30007 ──────────────►   │──► Pod (192.168.40.47:80)
                            │                           │
                            │  Node2: 54.172.158.83     │
                            │  :30007 ──────────────►   │──► Pod (192.168.40.47:80)
                            │  (even if Pod not here,   │
                            │   iptables routes it!)    │
                            └──────────────────────────┘
```

> ⚠️ **Security note:** NodePort exposes a real port on EC2 instances. You MUST open that port in the **Security Group** of the worker nodes — otherwise traffic is blocked by AWS firewall before it even reaches kube-proxy.

---

### nodeport.yaml Deep Dive

The beauty of Kubernetes: **you can put multiple resources in ONE yaml file** using `---` separator:

```yaml
# ════════════════════════════════════════════════
# RESOURCE 1: Deployment (creates Pods)
# ════════════════════════════════════════════════
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment-np          # Name of the Deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app-np              # This Deployment manages pods with THIS label
  template:
    metadata:
      labels:
        app: my-app-np            # ← Pods get this label
    spec:
      containers:
      - name: my-container
        image: nginx:latest
        ports:
        - containerPort: 80       # App listens on port 80 inside container

---                               # ← Separator between multiple resources in one file

# ════════════════════════════════════════════════
# RESOURCE 2: Service (exposes Pods)
# ════════════════════════════════════════════════
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: NodePort                  # ← SERVICE TYPE: external access via node IP
  selector:
    app: my-app-np                # ← MUST match the Pod label above (this is the glue!)
  ports:
    - port: 80                    # Service's internal port (ClusterIP side)
      targetPort: 80              # Port on the Pod/container to forward to
      nodePort: 30007             # Port on every Node (30000-32767 range)
                                  # If omitted, Kubernetes auto-assigns one
```

**The Label Glue — How Service finds Pods:**

```
Service YAML                      Pod YAML (from template)
────────────────────              ────────────────────────
spec:                             metadata:
  selector:                         labels:
    app: my-app-np    ←──────────►    app: my-app-np
                      MUST MATCH
```

> 🔴 **If labels don't match:** Service has no Endpoints — traffic goes nowhere. This is the #1 debugging point for Service issues.

---

### Hands-On Lab: Live nginx via NodePort

**Step 1: Deploy and expose**

```bash
$ kubectl apply -f nodeport.yaml
deployment.apps/my-deployment-np created
service/my-service unchanged        # Service already existed from earlier

$ kubectl get pods -o wide
NAME                               READY   STATUS    IP              NODE
my-deployment-np-97bbd86dc-jbsj6   1/1     Running   192.168.40.47   ip-192-168-58-97.ec2.internal
```

**Step 2: Check the Service**

```bash
$ kubectl get svc
NAME         TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
kubernetes   ClusterIP   10.100.0.1       <none>        443/TCP        5h21m
my-service   NodePort    10.100.168.126   <none>        80:30007/TCP   5h9m
#                        ↑ stable IP      ↑ no external IP (NodePort uses Node IP)
#                                         ↑ 80:30007 means Service:80 → NodePort:30007
```

**Step 3: Describe the Service — everything is connected here**

```bash
$ kubectl describe svc my-service
Name:       my-service
Type:       NodePort
IP:         10.100.168.126        ← Stable ClusterIP (internal)
Port:       80/TCP                ← Service port
TargetPort: 80/TCP                ← Pod port
NodePort:   30007/TCP             ← External node port
Endpoints:  192.168.40.47:80     ← ACTUAL Pod IP:Port (auto-discovered via labels)
Selector:   app=my-app-np        ← Label used to find pods
```

> 🧩 **Reading `kubectl describe svc` is the best debugging tool.** The `Endpoints` line shows which Pod IPs the Service currently routes to. If this is empty (`<none>`), your labels don't match.

**Step 4: Check Node External IPs**

```bash
$ kubectl get nodes -o wide
NAME                            INTERNAL-IP     EXTERNAL-IP
ip-192-168-1-109.ec2.internal   192.168.1.109   54.167.41.45    ← Node 1
ip-192-168-58-97.ec2.internal   192.168.58.97   54.172.158.83   ← Node 2
```

**Step 5: Open Security Group port 30007 on EC2 nodes**

```
AWS Console → EC2 → Security Groups → eks-cluster-sg-test → Inbound Rules
Add Rule:
  Type:        Custom TCP
  Port Range:  30007
  Source:      0.0.0.0/0   (or restrict to your IP for security)
```

**Step 6: Test from browser**

```
✅ http://54.167.41.45:30007   → "Welcome to nginx!" (Node 1)
✅ http://54.172.158.83:30007  → "Welcome to nginx!" (Node 2)
```

Both nodes serve the same Pod — because iptables on Node 2 routes the request to the Pod sitting on Node 1. **Magic!**

---

### The Multi-Node Traffic Mystery (IRCTC Scenario)

**Question from class:** *"If Pod is on Node 1 and user hits Node 2's IP:30007, how does traffic reach the Pod?"*

```
 User hits Node 2: 54.172.158.83:30007
         │
         ▼
┌─────────────────────────────────┐
│   NODE 2 (54.172.158.83)        │
│                                 │
│   Pod NOT here — no problem!    │
│                                 │
│   kube-proxy iptables rule:     │
│   ":30007 → 192.168.40.47:80"  │
│         │                       │
└─────────┼───────────────────────┘
          │ cross-node traffic via
          │ AWS VPC routing / overlay network
          ▼
┌─────────────────────────────────┐
│   NODE 1 (54.167.41.45)         │
│                                 │
│   Pod: 192.168.40.47:80  ✅     │
└─────────────────────────────────┘
```

**The IRCTC scale example:**

```
IRCTC during Tatkal booking (10 AM rush — millions of requests)
─────────────────────────────────────────────────────────────────
                    Service (ClusterIP)
                         │
              ┌──────────┼──────────┐
              ▼          ▼          ▼
           Pod 1       Pod 2      Pod 3
        (Node 1)     (Node 1)   (Node 2)

All NodePorts (30007) on ALL nodes point to this ONE Service.
Service load-balances across all 3 Pods via iptables round-robin.
→ No single point of failure
→ Requests distributed evenly
→ Adding more Pods = instant scale
```

---

## 🔒 Service 2 — ClusterIP (Internal Only)

ClusterIP is the **default** service type. It gives your Service a stable internal IP that's ONLY reachable from within the cluster.

```
INTERNET ❌ (cannot reach ClusterIP — blocked at cluster boundary)

INSIDE CLUSTER ✅
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                    │
│                                                          │
│   Frontend Pod ──────────────────────────────────────►  │
│   (192.168.x.x)    ClusterIP Service (10.100.x.x:8080) │
│                    "backend-service"                     │
│                         │                               │
│                    ┌────┴────┐                           │
│                    ▼         ▼                           │
│                Backend1   Backend2                       │
│                  Pod         Pod                         │
└─────────────────────────────────────────────────────────┘
```

**When to use ClusterIP:**
- Frontend Pod calling Backend Pod (internal API calls)
- Backend Pod calling another microservice
- Any pod-to-pod communication that should NEVER be exposed externally

**ClusterIP yaml example:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  type: ClusterIP          # Default — can omit "type" entirely
  selector:
    app: backend
  ports:
    - port: 8080           # Frontend calls backend-service:8080
      targetPort: 8080     # Backend pods listen on 8080
```

**Usage in code (Frontend app):**

```javascript
// Frontend doesn't need Pod IP — uses Service name!
// Kubernetes DNS resolves "backend-service" to ClusterIP automatically
const response = await fetch('http://backend-service:8080/api/users');
```

> 🌐 **Kubernetes internal DNS** (CoreDNS) automatically creates DNS entries for every Service:
> `<service-name>.<namespace>.svc.cluster.local`
> So `backend-service` in the same namespace resolves to `10.100.x.x`

---

## ⚖️ Service 3 — LoadBalancer (Production External)

LoadBalancer is the **production-grade** way to expose applications externally. In AWS, it provisions an **Application Load Balancer (ALB)** or **Network Load Balancer (NLB)** automatically.

```
Internet User
     │
     │  https://myapp.com
     ▼
┌───────────────────────────────────────────┐
│       AWS Application Load Balancer       │
│   (Created automatically by Kubernetes)   │
│       DNS: xxx.elb.amazonaws.com          │
│                                           │
│   Health checks built-in ✅               │
│   SSL termination ✅                       │
│   Clean DNS (no port in URL) ✅            │
└──────────────────┬────────────────────────┘
                   │
         ┌─────────┼──────────┐
         ▼         ▼          ▼
       Pod 1     Pod 2      Pod 3
```

**LoadBalancer yaml example:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-lb
spec:
  type: LoadBalancer         # AWS will create an ALB/NLB for this
  selector:
    app: frontend
  ports:
    - port: 80
      targetPort: 3000       # React/Next.js app port
```

**After applying:**

```bash
$ kubectl get svc frontend-lb
NAME          TYPE           CLUSTER-IP      EXTERNAL-IP
frontend-lb   LoadBalancer   10.100.50.10    abc123.elb.amazonaws.com   ← AWS gives a DNS name
```

**NodePort vs LoadBalancer comparison:**

| Aspect | NodePort | LoadBalancer |
|--------|----------|--------------|
| URL Format | `http://54.167.41.45:30007` | `http://abc123.elb.amazonaws.com` |
| Port visible? | Yes (ugly) | No (clean URL) |
| SSL/TLS | Manual | Handled at ALB |
| Health checks | None | Built-in |
| Cost | Free | ~$20–30/month per LB |
| Use case | Dev/Testing | Production |
| Security | Node IP exposed | Only LB IP exposed |

> 🏭 **Real production architecture:**
> - `LoadBalancer` Service for user-facing frontend
> - `ClusterIP` Service for internal backend/API
> - Route53 CNAME → ALB DNS name → Pod

---

## 🗄️ Service 4 — Headless Service (StatefulSet / Databases)

### What is a Headless Service?

A Headless Service is created by setting `clusterIP: None`. This means:
- No stable ClusterIP is assigned
- No load balancing
- Instead — **direct DNS entries for each individual Pod**

```
REGULAR SERVICE (ClusterIP/NodePort/LB):
Request → Service (10.100.x.x) → randomly picks Pod1 OR Pod2 OR Pod3

HEADLESS SERVICE:
Request → DNS lookup → gets back LIST of individual Pod IPs
Client/Application decides which Pod to connect to
```

**Headless yaml example:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql-headless
spec:
  clusterIP: None          # ← This makes it Headless!
  selector:
    app: mysql
  ports:
    - port: 3306
      targetPort: 3306
```

**DNS behavior:**

```bash
# With ClusterIP Service:
nslookup backend-service
→ 10.100.50.10            ← Single stable IP (load balanced)

# With Headless Service:
nslookup mysql-headless
→ 192.168.10.1            ← mysql-0 Pod IP
→ 192.168.10.2            ← mysql-1 Pod IP  
→ 192.168.10.3            ← mysql-2 Pod IP
# Returns ALL pod IPs — app chooses which to connect to
```

---

### StatefulSet vs Deployment — Key Difference

Databases cannot use Deployments because Pods in a Deployment are **interchangeable** (any Pod can die and be replaced with a new name/IP). Databases are NOT interchangeable — they have:
- Persistent data that must survive Pod restarts
- Master/Replica roles that can't be randomly reassigned
- Stable network identity required for replication

```
DEPLOYMENT PODS (Chaos — not suitable for DB):
─────────────────────────────────────────────────
Pod dies:  nginx-deployment-abc123-x7k9q  →  gone
New Pod:   nginx-deployment-abc123-p2m8r  ←  new random name
Data:      LOST (Pod was stateless) ❌

STATEFULSET PODS (Ordered, Stable — perfect for DB):
─────────────────────────────────────────────────────
Pod dies:  mysql-0  →  gone
New Pod:   mysql-0  ←  SAME name (predictable!)
Data:      PRESERVED (EBS volume reattached) ✅
```

**StatefulSet creates Pods in ORDER:**

```
StatefulSet with replicas: 3 creates:
mysql-0  ← created first (MASTER)
mysql-1  ← created second (REPLICA 1)
mysql-2  ← created third  (REPLICA 2)

Delete mysql-2 → StatefulSet recreates mysql-2 (not mysql-3)
Delete mysql-0 → StatefulSet recreates mysql-0 (same name, same role)
```

**StatefulSet yaml example:**

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql-headless    # Must reference the Headless Service
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        volumeMounts:
        - name: mysql-data
          mountPath: /var/lib/mysql   # Where MySQL stores data
  volumeClaimTemplates:              # ← Each Pod gets its OWN EBS volume!
  - metadata:
      name: mysql-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 20Gi             # 20GB EBS per Pod
```

---

### Why Databases Need Headless + StatefulSet

**The Master-Replica problem:**

```
MySQL Cluster:
  mysql-0 = MASTER  (handles writes: INSERT, UPDATE, DELETE)
  mysql-1 = REPLICA (handles reads: SELECT)
  mysql-2 = REPLICA (handles reads: SELECT)

Backend application logic:
  Write query (DML) → must go to MASTER (mysql-0)
  Read query (SELECT) → can go to any REPLICA (mysql-1 or mysql-2)
```

**Why LoadBalancer/ClusterIP FAILS here:**

```
Backend → LoadBalancer Service → randomly sends to mysql-0 OR mysql-1 OR mysql-2
                                                     ↑
                              What if a WRITE goes to a REPLICA? ❌
                              Replicas are READ-ONLY → query FAILS
```

**Why Headless Service WORKS:**

```
Headless DNS gives individual addresses:
  mysql-0.mysql-headless.default.svc.cluster.local  → 192.168.10.1 (MASTER)
  mysql-1.mysql-headless.default.svc.cluster.local  → 192.168.10.2 (REPLICA)
  mysql-2.mysql-headless.default.svc.cluster.local  → 192.168.10.3 (REPLICA)

Backend code:
  WRITE connection string: mysql-0.mysql-headless:3306   ← Always hits MASTER
  READ  connection string: mysql-1.mysql-headless:3306   ← Always hits REPLICA
```

**EBS Volume behavior with StatefulSet:**

```
StatefulSet creates:
  mysql-0  ←→  EBS Volume 1 (vol-aaa111)   20GB
  mysql-1  ←→  EBS Volume 2 (vol-bbb222)   20GB
  mysql-2  ←→  EBS Volume 3 (vol-ccc333)   20GB

mysql-2 Pod gets deleted:
  ┌── StatefulSet recreates mysql-2
  └── AWS reattaches vol-ccc333 to the NEW mysql-2 Pod
      Data is 100% preserved! ✅
```

> 🏭 **What about production DBs?** Class recommendation:
> - **Dev/staging:** StatefulSet + Headless Service is fine
> - **Production:** Use **AWS RDS** (managed) — no pod management, automated backups, Multi-AZ failover, managed patches
> - Just use the RDS endpoint URL directly in your app — it's completely outside Kubernetes

---

## 🏗️ Full Application Architecture — Frontend + Backend + DB

This is the REAL architecture used in production:

```
═══════════════════════════════════════════════════════════════════
                    KUBERNETES CLUSTER (EKS)
═══════════════════════════════════════════════════════════════════

EXTERNAL                    INTERNAL
────────                    ────────

Internet User
     │
     ▼
┌─────────────────┐
│  LoadBalancer   │ ← (type: LoadBalancer)
│  AWS ALB        │   Exposes frontend to internet
│  Clean DNS URL  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐        ┌─────────────────────────┐
│  FRONTEND PODS  │        │   ClusterIP Service      │
│  (React/Next)   │───────►│   "backend-service"      │───► Backend Pod 1
│  Deployment     │        │   (internal only)        │───► Backend Pod 2
└─────────────────┘        └─────────────────────────┘     Backend Pod 3
                                                              │
                                                              │ (write)
                                                              ▼
                                                     mysql-0.mysql-headless:3306
                                                     (StatefulSet MASTER pod)
                                                              │
                                                              │ (read)
                                                              ▼
                                                     mysql-1.mysql-headless:3306
                                                     (StatefulSet REPLICA pod)

═══════════════════════════════════════════════════════════════════
OUTSIDE CLUSTER
═══════════════════════════════════════════════════════════════════

                                             OR use AWS RDS endpoint:
                                             mydb.xxxx.ap-south-1.rds.amazonaws.com
                                             (Fully managed — recommended for PROD)
```

**Which yaml for which component:**

| Component | Kubernetes Object | Service Type | Why |
|-----------|-----------------|--------------|-----|
| Frontend (React) | Deployment | LoadBalancer | External user access, clean URL |
| Backend (Spring Boot / Node) | Deployment | ClusterIP | Only frontend needs to reach it |
| Database (MySQL) | StatefulSet | Headless | Stable pod identity, master/replica routing |
| Cache (Redis) | StatefulSet | Headless | Persistent data, stable pod names |
| Search (Elasticsearch) | StatefulSet | Headless | Cluster nodes need stable identities |

---

## 🌐 Kubernetes DNS and Route53

**CoreDNS** runs inside the cluster (you saw it in `kubectl get pods -A`):

```bash
kube-system   coredns-566b9b9d-cmzfd   1/1   Running
kube-system   coredns-566b9b9d-jgkn6   1/1   Running
```

CoreDNS automatically creates DNS entries for every Service:

```
Full DNS format:
  <service-name>.<namespace>.svc.cluster.local

Examples:
  my-service.default.svc.cluster.local         → 10.100.168.126
  backend-service.default.svc.cluster.local    → 10.100.50.10
  mysql-headless.default.svc.cluster.local     → 192.168.10.1, .2, .3

Short form (within same namespace):
  Just "my-service" or "backend-service" works!
```

**Integration with AWS Route53:**

```
User types:  myapp.company.com
     │
     ▼
AWS Route53 (CNAME record)
     │ → points to ALB DNS
     ▼
abc123.elb.amazonaws.com (AWS Load Balancer)
     │
     ▼
LoadBalancer Service in Kubernetes
     │
     ▼
Frontend Pods
```

---

## 🏭 Real-World Scenarios & Interview Q&A

### Scenario 1 — App not accessible after deploy
```bash
# Debug checklist:
kubectl get svc                            # Is Service created?
kubectl describe svc my-service            # Check Endpoints — are Pods listed?
kubectl get pods -o wide                   # Are Pods running?
kubectl get pods --show-labels             # Do labels match Service selector?

# If Endpoints is empty:
# → Labels on Pods don't match Service selector
# → Fix: ensure spec.selector in Service matches metadata.labels on Pod
```

### Scenario 2 — Scale up and Service auto-discovers new Pods
```bash
kubectl scale deployment my-deployment-np --replicas=3

# Service automatically discovers new Pods via label selector!
kubectl describe svc my-service
# Endpoints: 192.168.40.47:80, 192.168.40.99:80, 192.168.40.123:80
# ↑ All 3 pods now receiving traffic — zero config change needed
```

### Scenario 3 — Two nodes, one service works on both
```bash
# Pod runs on Node 2 (192.168.58.97 / 54.172.158.83)
# User hits Node 1 (54.167.41.45:30007) → still works!
# Because: kube-proxy iptables on Node 1 routes to the Pod on Node 2
http://54.167.41.45:30007  → ✅ nginx page
http://54.172.158.83:30007 → ✅ nginx page (both work)
```

---

### Interview Q&A

**Q: What is the difference between NodePort and LoadBalancer?**  
A: NodePort exposes the app on a high port (30000–32767) on every node's IP — the IP and port are both visible. LoadBalancer provisions a cloud load balancer (AWS ALB) with a clean DNS name, no port in URL, and built-in health checks and SSL. NodePort is for dev/testing; LoadBalancer is for production.

**Q: What is ClusterIP and why is it the default?**  
A: ClusterIP gives the Service a stable internal IP reachable only within the cluster. It's the default because most internal microservice-to-microservice communication should never be exposed externally. Frontend calls backend via ClusterIP — internet users can't access backend directly.

**Q: Why can't I use a regular Deployment for a MySQL master-replica setup?**  
A: Deployments create interchangeable Pods — any Pod can die and get replaced with a different name. Database Pods are NOT interchangeable: the master has a specific role (writes), replicas have another (reads). StatefulSet gives each Pod a stable, predictable name (mysql-0, mysql-1) so your application can always route writes to mysql-0 and reads to mysql-1/mysql-2. Deployment Pods get random name suffixes that change on restart.

**Q: What is a Headless Service and when do you use it?**  
A: A Headless Service has `clusterIP: None` — it doesn't get a stable IP and does no load balancing. Instead, DNS returns the list of individual Pod IPs. This lets applications directly address specific Pods by name. Used for databases (MySQL master vs replica), Kafka brokers, Elasticsearch nodes — anywhere you need to connect to a specific Pod, not a random one.

**Q: What is kube-proxy and what does it do?**  
A: kube-proxy is a per-node daemon that watches the Kubernetes API for Service and Endpoint changes, then updates iptables rules on the node accordingly. When a request hits a NodePort, the Linux kernel's iptables (not kube-proxy itself) does the actual packet forwarding to the right Pod IP. kube-proxy just keeps the rules up to date.

**Q: The `Endpoints` field in `kubectl describe svc` is empty — what's wrong?**  
A: The Service's `selector` labels don't match any running Pod's labels. Either the Pods aren't running (`kubectl get pods`), or the label values don't match exactly (case-sensitive). Fix by ensuring `spec.selector` in the Service exactly matches `metadata.labels` in the Pod/Deployment template.

**Q: Why is `rm -rf pod.yaml` dangerous vs `kubectl delete -f pod.yaml`?**  
A: `rm -rf pod.yaml` only deletes the file from Linux — Kubernetes etcd still has the Pod/Service definition, and the workload keeps running. `kubectl delete -f pod.yaml` sends a delete request to the Kubernetes API, which removes the resource from etcd and terminates the Pod/Service. Always use `kubectl delete` to actually stop Kubernetes resources.

**Q: Can I access a Pod via ClusterIP from outside the cluster?**  
A: No. ClusterIP is only routable within the cluster's private network. To access from outside, you need NodePort, LoadBalancer, or an Ingress controller. For debugging, you can use `kubectl port-forward pod/<name> 8080:80` to temporarily tunnel from your local machine into the Pod.

---

## 📌 Quick Reference — All kubectl Commands Used Today

```bash
# ── CLUSTER INFO ──────────────────────────────────────────────────
kubectl get nodes                          # List nodes
kubectl get nodes -o wide                  # Include internal/external IPs
kubectl get pods -A                        # All pods in all namespaces
kubectl get pods -o wide                   # Include Pod IPs and Node

# ── SERVICES ──────────────────────────────────────────────────────
kubectl get svc                            # List Services
kubectl get svc -o wide                    # Include selector labels
kubectl describe svc <service-name>        # Full details + Endpoints

# ── APPLY / DELETE ────────────────────────────────────────────────
kubectl apply -f nodeport.yaml             # Create/update all resources in file
kubectl delete deployment <name>           # Delete a Deployment

# ── DEBUGGING SERVICES ────────────────────────────────────────────
kubectl get endpoints                      # See which Pod IPs each Service routes to
kubectl get pods --show-labels             # Verify Pod labels match Service selector

# ── SCALING ───────────────────────────────────────────────────────
kubectl scale deployment <name> --replicas=3

# ── PORT FORWARD (local debug) ────────────────────────────────────
kubectl port-forward svc/my-service 8080:80   # Access ClusterIP locally
kubectl port-forward pod/<pod-name> 8080:80
```

---

## ⚠️ Common Mistakes & Gotchas

### 1. Security Group Not Updated
```
Problem: App deployed, Service created, but browser shows "connection refused"
Reason:  Port 30007 not opened in EC2 Security Group

Fix:
AWS Console → EC2 → Security Groups → eks-cluster-sg-test
Add Inbound Rule: TCP, Port 30007, Source 0.0.0.0/0
```

### 2. Label Mismatch (Most Common!)
```yaml
# Service selector:
  selector:
    app: my-app-np       # Expects THIS label

# Pod labels (WRONG):
  labels:
    app: myapp-np        # Missing dash! Won't match!

# Result: kubectl describe svc → Endpoints: <none>
# Traffic goes nowhere — app unreachable!
```

### 3. Using LoadBalancer Type on Bare Metal (Non-Cloud)
```
LoadBalancer type works automatically on:  AWS, GCP, Azure (cloud has built-in integration)
LoadBalancer type STUCK as "Pending" on:  On-prem, minikube, bare metal k8s

Fix for non-cloud: Use MetalLB or NodePort instead
```

### 4. Wrong Port Numbers
```yaml
# WRONG — targetPort doesn't match what app listens on:
ports:
  - port: 80
    targetPort: 3000     # App actually listens on 8080 → connection refused!

# RIGHT:
ports:
  - port: 80
    targetPort: 8080     # Verify your app's listening port!
```

### 5. Using StatefulSet like a Deployment (DB data loss)
```bash
# WRONG — deleting a StatefulSet without retaining volumes:
kubectl delete statefulset mysql --cascade=foreground
# This deletes Pods AND PersistentVolumeClaims → DATA LOSS!

# RIGHT — delete StatefulSet but keep volumes:
kubectl delete statefulset mysql --cascade=orphan
# Volumes (PVCs) remain, data safe, can reattach later
```

### 6. Expecting Headless Service to Load Balance
```
Headless Service → NO load balancing (by design!)
If you want load balancing → use ClusterIP
If you want per-pod addressing → use Headless

Never use Headless for frontend/backend — only for stateful apps needing pod identity
```

---

## 🎓 Key Takeaways From Today's Session

```
1. Services solve 3 problems: stable IP, load balancing, external access

2. NodePort    = External access via Node IP:Port (dev/test only)
                 Range: 30000-32767, must open in Security Group

3. ClusterIP   = Internal only (frontend ↔ backend)
                 Default type, most commonly created service

4. LoadBalancer = External access via Cloud ALB (production)
                  Creates AWS ALB automatically, clean DNS URL

5. Headless    = No ClusterIP, direct Pod DNS (databases, stateful apps)
                 Used WITH StatefulSet for master/replica DB setups

6. kube-proxy  = Per-node daemon writing iptables rules
                 Linux kernel does actual packet forwarding

7. Labels      = The glue between Services and Pods
                 Service selector MUST match Pod labels exactly

8. StatefulSet = Ordered, stable Pod names (mysql-0, mysql-1, mysql-2)
                 Each Pod gets its own PVC (EBS volume in AWS)
                 Use for DBs, Kafka, Elasticsearch

9. Production  = Frontend: LoadBalancer | Backend: ClusterIP | DB: AWS RDS
                 Never expose DB pods to internet
                 Prefer managed RDS over self-managed DB pods in production

10. CoreDNS    = Internal cluster DNS
                 <service>.<namespace>.svc.cluster.local
                 Integrates with Route53 for external DNS
```

---

*📁 Files used in class:*
```
May7th-Kubernetes730am/
└── nodeport.yaml    (combined Deployment + NodePort Service in one file)
```

*🖥️ Environment Details:*

| Component | Value |
|-----------|-------|
| EKS Version | `v1.34.7-eks-4136f65` |
| Bootstrap EC2 | `ip-172-31-45-208` |
| Worker Node 1 | `ip-192-168-1-109` / External: `54.167.41.45` |
| Worker Node 2 | `ip-192-168-58-97` / External: `54.172.158.83` |
| NodePort used | `30007` |
| Service ClusterIP | `10.100.168.126` |
| Pod IP | `192.168.40.47` |
| Container Runtime | `containerd://2.2.3` |
| OS | `Amazon Linux 2023.11.20260505` |

---
> 📝 **Notes compiled from live class session — 8th May 2026 | NareshIT DevOps/CloudOps Batch | 7:30 AM**
