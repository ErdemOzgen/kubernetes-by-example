# Kubernetes NetworkPolicy

`NetworkPolicy` is Kubernetes’ built-in way to control **Pod-to-Pod**, **Pod-to-namespace**, and **Pod-to-external-network** traffic.

Think of it as a **namespaced L3/L4 firewall for Pods**.

It answers questions like:

```text
Can frontend Pods call backend Pods?
Can backend Pods call database Pods?
Can Pods in namespace A talk to Pods in namespace B?
Can this workload access the internet?
Can this workload resolve DNS?
```

Officially, Kubernetes describes `NetworkPolicy` as a way to specify how groups of Pods are allowed to communicate with each other and with other network endpoints. Policies apply to Pods selected by labels, and enforcement requires a network plugin that supports NetworkPolicy. ([Kubernetes][1])

---

# 1. Critical concept: NetworkPolicy is allow-list based

Standard Kubernetes `NetworkPolicy` does **not** have explicit deny rules.

It works like this:

```text
No NetworkPolicy selects a Pod
  -> all ingress and egress traffic is allowed for that Pod.

At least one NetworkPolicy selects a Pod for ingress
  -> ingress becomes isolated.
  -> only explicitly allowed ingress traffic is allowed.

At least one NetworkPolicy selects a Pod for egress
  -> egress becomes isolated.
  -> only explicitly allowed egress traffic is allowed.
```

So the model is:

```text
Default: allow all
After policy selects Pod: deny by default for that direction
Then: allow only declared traffic
```

Kubernetes documents this isolation behavior separately for ingress and egress: policies are additive, and once a Pod is isolated for a direction, only traffic allowed by applicable policies is permitted. ([Kubernetes][1])

---

# 2. Important prerequisite: your CNI must enforce it

A `NetworkPolicy` object is just Kubernetes API configuration. It does nothing unless your CNI plugin supports and enforces NetworkPolicy.

Common CNIs with NetworkPolicy support include:

```text
Calico
Cilium
Antrea
Weave Net
Kube-router
```

Cilium supports Kubernetes NetworkPolicy and also extends policy enforcement with eBPF-based L3-L7 capabilities. ([GitHub][2]) Calico also supports Kubernetes NetworkPolicy and provides additional Calico-specific policy types such as `GlobalNetworkPolicy`, policy ordering, and deny rules. ([docs.tigera.io][3])

For this lab, I will use **Calico on Minikube** because it is easy to test locally. Minikube’s Network Policy handbook states that enabling Calico can be done by starting Minikube with the `--cni calico` flag. ([minikube][4])

---

# 3. Core YAML structure

A basic NetworkPolicy looks like this:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-api
  namespace: netpol-lab
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 80
```

Meaning:

```text
Select destination Pods:
  app=api

For ingress traffic:
  allow traffic from Pods with app=frontend

Only to:
  TCP port 80
```

Important:

```text
podSelector in spec selects the protected Pods.
from selects allowed sources.
to selects allowed destinations for egress.
ports selects allowed destination ports.
```

---

# 4. Ingress vs egress from the Pod’s perspective

NetworkPolicy direction is always from the perspective of the **selected Pod**.

```text
Ingress = traffic entering the selected Pod
Egress  = traffic leaving the selected Pod
```

Example:

```text
frontend -> api
```

For the `api` Pod:

```text
This is ingress.
```

For the `frontend` Pod:

```text
This is egress.
```

For traffic to work when both sides are isolated, both conditions must be true:

```text
source Pod egress allows the traffic
destination Pod ingress allows the traffic
```

Kubernetes treats ingress and egress rules independently, and policies are additive. ([Kubernetes][1])

---

# 5. Mental model

Imagine this app:

```text
frontend
   |
   v
api
   |
   v
database
```

Security goal:

```text
frontend can call api.
api can call database.
frontend cannot call database directly.
random Pods cannot call api or database.
database cannot access the internet.
```

NetworkPolicy lets you enforce this.

---

# 6. Hands-on lab setup

Start Minikube with Calico:

```bash
minikube delete

minikube start --cni calico
```

Verify Calico:

```bash
kubectl get pods -n kube-system | grep calico
```

You should see Calico Pods running.

Create a namespace:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: netpol-lab
```

Apply:

```bash
kubectl apply -f 00-namespace.yaml
```

---

# 7. Deploy lab workloads

We will deploy:

```text
frontend   -> curl client
attacker   -> curl client
api        -> HTTP echo service
database   -> HTTP echo service
```

Create `01-workloads.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: netpol-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
        tier: frontend
    spec:
      containers:
        - name: curl
          image: curlimages/curl:8.11.1
          command: ["sh", "-c", "sleep 365d"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: attacker
  namespace: netpol-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: attacker
  template:
    metadata:
      labels:
        app: attacker
        tier: test
    spec:
      containers:
        - name: curl
          image: curlimages/curl:8.11.1
          command: ["sh", "-c", "sleep 365d"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: netpol-lab
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
        tier: backend
    spec:
      containers:
        - name: api
          image: hashicorp/http-echo:1.0
          args:
            - "-listen=:8080"
            - "-text=hello from api"
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: netpol-lab
spec:
  selector:
    app: api
  ports:
    - name: http
      port: 80
      targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database
  namespace: netpol-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: database
  template:
    metadata:
      labels:
        app: database
        tier: database
    spec:
      containers:
        - name: database
          image: hashicorp/http-echo:1.0
          args:
            - "-listen=:8080"
            - "-text=hello from database"
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: database
  namespace: netpol-lab
spec:
  selector:
    app: database
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

Apply:

```bash
kubectl apply -f 01-workloads.yaml
```

Check:

```bash
kubectl get pods,svc -n netpol-lab
```

---

# 8. Test default behavior: everything allowed

Get Pod names:

```bash
FRONTEND=$(kubectl get pod -n netpol-lab -l app=frontend -o jsonpath='{.items[0].metadata.name}')
ATTACKER=$(kubectl get pod -n netpol-lab -l app=attacker -o jsonpath='{.items[0].metadata.name}')
```

Test from `frontend` to `api`:

```bash
kubectl exec -n netpol-lab "$FRONTEND" -- curl -s --max-time 3 http://api
```

Expected:

```text
hello from api
```

Test from `attacker` to `api`:

```bash
kubectl exec -n netpol-lab "$ATTACKER" -- curl -s --max-time 3 http://api
```

Expected:

```text
hello from api
```

Test from `frontend` to `database`:

```bash
kubectl exec -n netpol-lab "$FRONTEND" -- curl -s --max-time 3 http://database
```

Expected:

```text
hello from database
```

This is the default Kubernetes behavior:

```text
All Pods can talk to all Pods unless NetworkPolicy isolates them.
```

---

# 9. Lab 1: default deny ingress

Now we deny all incoming traffic to all Pods in the namespace.

Create `02-default-deny-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: netpol-lab
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

Apply:

```bash
kubectl apply -f 02-default-deny-ingress.yaml
```

Test again:

```bash
kubectl exec -n netpol-lab "$FRONTEND" -- curl -s --max-time 3 http://api
```

Expected:

```text
timeout or connection failure
```

Why?

Because this policy selects all Pods:

```yaml
podSelector: {}
```

And declares:

```yaml
policyTypes:
  - Ingress
```

But it has no `ingress` allow rules.

So all selected Pods are ingress-isolated.

Kubernetes’ official docs show this same default-deny pattern: an empty `podSelector` selects all Pods in the namespace, and a policy with `policyTypes: [Ingress]` and no ingress rules denies all ingress to selected Pods. ([Kubernetes][1])

---

# 10. Lab 2: allow only frontend to api

Create `03-allow-frontend-to-api.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-api
  namespace: netpol-lab
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 8080
```

Apply:

```bash
kubectl apply -f 03-allow-frontend-to-api.yaml
```

Now test from frontend:

```bash
kubectl exec -n netpol-lab "$FRONTEND" -- curl -s --max-time 3 http://api
```

Expected:

```text
hello from api
```

Test from attacker:

```bash
kubectl exec -n netpol-lab "$ATTACKER" -- curl -s --max-time 3 http://api
```

Expected:

```text
timeout or connection failure
```

Why?

The `api` Pods are selected here:

```yaml
podSelector:
  matchLabels:
    app: api
```

The allowed source is only:

```yaml
from:
  - podSelector:
      matchLabels:
        app: frontend
```

So:

```text
frontend -> api     allowed
attacker -> api     denied
```

Important detail: the port in NetworkPolicy is the backend Pod port, not necessarily the Service port.

Here the Service is:

```yaml
port: 80
targetPort: 8080
```

The Pod receives traffic on `8080`, so the NetworkPolicy allows port `8080`.

---

# 11. Lab 3: allow only api to database

Create `04-allow-api-to-database.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-to-database
  namespace: netpol-lab
spec:
  podSelector:
    matchLabels:
      app: database
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api
      ports:
        - protocol: TCP
          port: 8080
```

Apply:

```bash
kubectl apply -f 04-allow-api-to-database.yaml
```

Test from frontend to database:

```bash
kubectl exec -n netpol-lab "$FRONTEND" -- curl -s --max-time 3 http://database
```

Expected:

```text
timeout or connection failure
```

Test from attacker to database:

```bash
kubectl exec -n netpol-lab "$ATTACKER" -- curl -s --max-time 3 http://database
```

Expected:

```text
timeout or connection failure
```

To test from `api` to `database`, our `api` container does not include curl. For this lab, the important policy result is:

```text
Only Pods with app=api may connect to database Pods.
```

The final architecture is now:

```text
frontend  -> api       allowed
attacker  -> api       denied
frontend  -> database  denied
attacker  -> database  denied
api       -> database  allowed
```

---

# 12. Important: NetworkPolicy is additive

Suppose you have these policies:

```text
Policy A:
  allow frontend -> api

Policy B:
  allow monitoring -> api
```

The result is:

```text
frontend   -> api allowed
monitoring -> api allowed
```

Policies do not override each other. There is no rule order in standard Kubernetes NetworkPolicy.

The effective allowed traffic is the **union** of all applicable allow rules.

---

# 13. Lab 4: egress default deny

So far we controlled incoming traffic to Pods.

Now let’s control outgoing traffic from Pods.

Create `05-default-deny-egress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: netpol-lab
spec:
  podSelector: {}
  policyTypes:
    - Egress
```

Apply:

```bash
kubectl apply -f 05-default-deny-egress.yaml
```

Now every Pod in `netpol-lab` is egress-isolated.

Try:

```bash
kubectl exec -n netpol-lab "$FRONTEND" -- curl -s --max-time 3 http://api
```

Expected:

```text
failure
```

Why?

Earlier we allowed `api` ingress from `frontend`, but now `frontend` egress is denied.

The complete decision requires both sides:

```text
frontend egress -> must allow api
api ingress     -> must allow frontend
```

Right now:

```text
frontend egress -> denied
api ingress     -> allowed
final result    -> denied
```

---

# 14. Lab 5: allow frontend egress to api

Create `06-allow-frontend-egress-to-api.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-egress-to-api
  namespace: netpol-lab
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: api
      ports:
        - protocol: TCP
          port: 8080
```

Apply:

```bash
kubectl apply -f 06-allow-frontend-egress-to-api.yaml
```

Test:

```bash
kubectl exec -n netpol-lab "$FRONTEND" -- curl -s --max-time 3 http://api
```

This may still fail because DNS is blocked.

Why?

`curl http://api` first needs DNS resolution:

```text
api -> api.netpol-lab.svc.cluster.local -> ClusterIP
```

But egress default deny blocked DNS traffic to CoreDNS.

This is one of the most common NetworkPolicy mistakes.

---

# 15. Lab 6: allow DNS egress

First inspect CoreDNS labels:

```bash
kubectl get pods -n kube-system --show-labels | grep -E 'coredns|kube-dns'
```

Most clusters use:

```text
k8s-app=kube-dns
```

Now create `07-allow-dns-egress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: netpol-lab
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

Apply:

```bash
kubectl apply -f 07-allow-dns-egress.yaml
```

Test again:

```bash
kubectl exec -n netpol-lab "$FRONTEND" -- curl -s --max-time 3 http://api
```

Expected:

```text
hello from api
```

Now the full decision is:

```text
frontend egress to CoreDNS: allowed
frontend egress to api:     allowed
api ingress from frontend:  allowed
```

So the request works.

---

# 16. `podSelector` vs `namespaceSelector`

This part is very important.

## `podSelector` only

```yaml
from:
  - podSelector:
      matchLabels:
        app: frontend
```

Meaning:

```text
Allow Pods with app=frontend in the same namespace as the NetworkPolicy.
```

A `podSelector` without `namespaceSelector` selects Pods only within the policy’s own namespace. ([Kubernetes][1])

---

## `namespaceSelector` only

```yaml
from:
  - namespaceSelector:
      matchLabels:
        environment: production
```

Meaning:

```text
Allow all Pods from namespaces labeled environment=production.
```

---

## `namespaceSelector` plus `podSelector`

```yaml
from:
  - namespaceSelector:
      matchLabels:
        environment: production
    podSelector:
      matchLabels:
        app: frontend
```

Meaning:

```text
Allow Pods with app=frontend
from namespaces labeled environment=production.
```

When `namespaceSelector` and `podSelector` are in the same peer item, they are combined as an AND condition. Kubernetes documents this combined behavior for NetworkPolicy peers. ([Kubernetes][1])

---

# 17. Important YAML trap: AND vs OR

These two examples are not equivalent.

## AND condition

```yaml
from:
  - namespaceSelector:
      matchLabels:
        environment: production
    podSelector:
      matchLabels:
        app: frontend
```

Meaning:

```text
Pods with app=frontend
AND
inside namespaces with environment=production
```

---

## OR condition

```yaml
from:
  - namespaceSelector:
      matchLabels:
        environment: production
  - podSelector:
      matchLabels:
        app: frontend
```

Meaning:

```text
All Pods from production namespaces
OR
Pods with app=frontend in this namespace
```

This indentation difference is security-critical.

Bad indentation can accidentally allow far more traffic than intended.

---

# 18. Lab 7: namespace-based access

Create two namespaces:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: client-a
  labels:
    tenant: a
---
apiVersion: v1
kind: Namespace
metadata:
  name: client-b
  labels:
    tenant: b
```

Apply:

```bash
kubectl apply -f 08-client-namespaces.yaml
```

Create curl clients:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: client
  namespace: client-a
spec:
  replicas: 1
  selector:
    matchLabels:
      app: client
  template:
    metadata:
      labels:
        app: client
    spec:
      containers:
        - name: curl
          image: curlimages/curl:8.11.1
          command: ["sh", "-c", "sleep 365d"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: client
  namespace: client-b
spec:
  replicas: 1
  selector:
    matchLabels:
      app: client
  template:
    metadata:
      labels:
        app: client
    spec:
      containers:
        - name: curl
          image: curlimages/curl:8.11.1
          command: ["sh", "-c", "sleep 365d"]
```

Apply:

```bash
kubectl apply -f 09-client-pods.yaml
```

Now allow only namespace `client-a` to access `api`.

Create `10-allow-client-a-to-api.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client-a-to-api
  namespace: netpol-lab
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              tenant: a
      ports:
        - protocol: TCP
          port: 8080
```

Apply:

```bash
kubectl apply -f 10-allow-client-a-to-api.yaml
```

Test:

```bash
CLIENT_A=$(kubectl get pod -n client-a -l app=client -o jsonpath='{.items[0].metadata.name}')
CLIENT_B=$(kubectl get pod -n client-b -l app=client -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n client-a "$CLIENT_A" -- curl -s --max-time 3 http://api.netpol-lab.svc.cluster.local
kubectl exec -n client-b "$CLIENT_B" -- curl -s --max-time 3 http://api.netpol-lab.svc.cluster.local
```

Expected:

```text
client-a -> api allowed
client-b -> api denied
```

---

# 19. Egress to external IPs

You can allow egress to external CIDRs.

Example: allow selected Pods to call a public API range:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-to-external-api
  namespace: netpol-lab
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 203.0.113.0/24
      ports:
        - protocol: TCP
          port: 443
```

Meaning:

```text
frontend Pods may connect to 203.0.113.0/24 on TCP 443.
```

You can also exclude ranges:

```yaml
ipBlock:
  cidr: 10.0.0.0/8
  except:
    - 10.96.0.0/12
```

Use `ipBlock` carefully. Kubernetes documentation states that `ipBlock` is intended for cluster-external IPs, because Pod IPs are ephemeral and cluster behavior around NAT can vary by plugin and environment. ([Kubernetes][1])

---

# 20. What NetworkPolicy cannot do well

Standard Kubernetes NetworkPolicy is intentionally simple.

It usually cannot do these by itself:

```text
L7 HTTP path rules
HTTP method filtering
JWT-aware authorization
DNS-name-based egress
FQDN policies
explicit deny rules
policy priority
global cluster-wide policies
logging denied flows
rate limiting
mTLS identity policy
host firewalling
```

For those, you typically need:

```text
CiliumNetworkPolicy
Calico NetworkPolicy / GlobalNetworkPolicy
service mesh authorization policies
API gateway / ingress / gateway policies
cloud firewall rules
eBPF observability tooling
```

Calico’s own policy model adds features beyond Kubernetes NetworkPolicy, including explicit deny rules and policy ordering. ([docs.tigera.io][3]) Cilium similarly extends policy capability beyond basic Kubernetes L3/L4 policies, including L7-aware enforcement depending on configuration. ([GitHub][2])

---

# 21. Debugging NetworkPolicy

## Check policies

```bash
kubectl get networkpolicy -n netpol-lab
kubectl describe networkpolicy -n netpol-lab
```

---

## Check labels

Most NetworkPolicy bugs are label bugs.

```bash
kubectl get pods -n netpol-lab --show-labels
kubectl get ns --show-labels
```

Verify:

```text
Does spec.podSelector match the Pods I want to protect?
Does from.podSelector match the allowed source Pods?
Does namespaceSelector match the expected namespace labels?
```

---

## Check Service target ports

NetworkPolicy port usually matches the **Pod/container listening port**, not just the Service port.

Service:

```yaml
ports:
  - port: 80
    targetPort: 8080
```

Policy should usually allow:

```yaml
ports:
  - port: 8080
```

---

## Check DNS

If egress default deny is enabled, test DNS:

```bash
kubectl exec -n netpol-lab "$FRONTEND" -- nslookup api
```

If DNS fails, allow UDP/TCP 53 to CoreDNS.

---

## Use direct Pod IP test

Get API Pod IP:

```bash
API_POD_IP=$(kubectl get pod -n netpol-lab -l app=api -o jsonpath='{.items[0].status.podIP}')
```

Test direct IP:

```bash
kubectl exec -n netpol-lab "$FRONTEND" -- curl -s --max-time 3 http://$API_POD_IP:8080
```

If direct IP works but Service DNS does not, the issue is likely DNS.

If direct IP fails too, the issue is likely policy, CNI, labels, or target port.

---

# 22. Production design pattern

For serious clusters, use a baseline like this.

## Per namespace baseline

```text
1. default deny ingress
2. default deny egress
3. allow DNS egress
4. allow only required service-to-service flows
5. allow observability scraping only from monitoring namespace
6. allow ingress only from gateway/ingress namespace
```

Example architecture:

```text
ingress-nginx namespace
        |
        v
frontend namespace
        |
        v
backend namespace
        |
        v
database namespace
```

Policies:

```text
frontend:
  allow ingress from ingress-nginx
  allow egress to backend
  allow egress to DNS

backend:
  allow ingress from frontend
  allow egress to database
  allow egress to DNS

database:
  allow ingress from backend
  deny all egress except DNS or backup target if needed
```

---

# 23. Clean up lab

```bash
kubectl delete namespace netpol-lab
kubectl delete namespace client-a
kubectl delete namespace client-b
```

---

# 24. Senior-engineer summary

`NetworkPolicy` is a Kubernetes-native, label-driven allow-list firewall for Pods.

Core rules:

```text
No policy selects Pod:
  traffic is allowed.

Policy selects Pod for ingress:
  ingress is denied except what policies allow.

Policy selects Pod for egress:
  egress is denied except what policies allow.

Policies are additive:
  effective allow = union of all matching allow rules.

Ingress and egress are evaluated independently:
  source egress and destination ingress must both allow traffic.

NetworkPolicy requires CNI enforcement:
  without Calico, Cilium, Antrea, etc., policies may do nothing.
```

Most important YAML fields:

```text
spec.podSelector
  Selects the Pods protected by this policy.

policyTypes
  Ingress, Egress, or both.

ingress.from
  Allowed sources.

egress.to
  Allowed destinations.

ports
  Allowed destination ports.

namespaceSelector
  Select namespaces by namespace labels.

podSelector
  Select Pods by Pod labels.

ipBlock
  Select external CIDR ranges.
```

A strong production baseline is:

```text
default deny ingress
default deny egress
allow DNS
allow only explicit app flows
verify labels and target ports
monitor denied traffic using CNI tooling
```

[1]: https://kubernetes.io/docs/concepts/services-networking/network-policies/ "Network Policies"
[2]: https://github.com/cilium/cilium "cilium/cilium: eBPF-based Networking, Security, and ..."
[3]: https://docs.tigera.io/calico/latest/network-policy/get-started/calico-policy/calico-network-policy "Get started with Calico network policy"
[4]: https://minikube.sigs.k8s.io/docs/handbook/network_policy/ "Network Policy - Minikube - Kubernetes"
