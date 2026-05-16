# Kubernetes Service

A **Service** is a Kubernetes object that gives a stable network identity to a dynamic set of Pods. Pods are ephemeral: they can be recreated, rescheduled, scaled up, scaled down, and assigned new IP addresses. A Service solves this by giving clients a stable DNS name and, usually, a stable virtual IP, while Kubernetes continuously updates the real backend Pod list behind it. The official Kubernetes docs describe a Service as an abstraction for a logical set of Pods that provide the same functionality, with traffic automatically load-balanced to matching Pods. ([Kubernetes][1])

Think of it like this:

```text
Client Pod
   |
   | curl http://web-service
   v
Service: web-service
   |
   | selects Pods with label app=web
   v
Pod 1, Pod 2, Pod 3, ...
```

The Service itself does **not** run your application. It is a stable access layer in front of Pods.

---

# 1. Why Service exists

Without a Service, one Pod would need to know the IP addresses of other Pods directly.

That is fragile because:

```text
Pod IPs are temporary.
Pods die and get recreated.
Deployments scale replicas up and down.
Rolling updates replace old Pods with new Pods.
Clients should not track backend Pod IPs manually.
```

A Service gives you:

```text
Stable DNS name
Stable virtual IP, for most Service types
Load balancing across matching Pods
Decoupling between clients and backend Pods
Automatic backend updates through EndpointSlices
```

Kubernetes automatically manages EndpointSlice objects for Services; these EndpointSlices contain the network endpoints backing the Service, usually Pod IPs. A service proxy such as kube-proxy then programs the node networking data plane so traffic to the Service reaches one of those backends. ([Kubernetes][2])

---

# 2. Service architecture

A normal Service has three important parts:

```text
Service
  |
  | selector: app=web
  v
EndpointSlice
  |
  | endpoints: Pod IPs
  v
Pods
```

Example:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 8080
```

This means:

```text
Expose the Service on port 80.
Find Pods with label app=web.
Forward traffic to those Pods on port 8080.
```

The Service selector is continuously evaluated. When Pods matching the selector are created, removed, or replaced, Kubernetes updates the EndpointSlices for that Service. ([Kubernetes][1])

---

# 3. Important objects involved

## Service

The stable abstraction clients use.

```bash
kubectl get svc
```

Example output:

```text
NAME   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)
web    ClusterIP   10.96.120.10    <none>        80/TCP
```

## Pod

The actual workload.

```bash
kubectl get pods -o wide
```

Example:

```text
NAME                   IP            LABELS
web-6d7c9d9d4f-abcde   10.244.0.21   app=web
web-6d7c9d9d4f-fghij   10.244.0.22   app=web
```

## EndpointSlice

The backend endpoint list used by the Service.

```bash
kubectl get endpointslice -l kubernetes.io/service-name=web
```

EndpointSlices are the modern backend-discovery API for Services. They became stable in Kubernetes v1.21 and are designed to scale better than the older Endpoints API. ([Kubernetes][3])

The older `Endpoints` API is deprecated in favor of EndpointSlices. Kubernetes documentation notes that the old Endpoints API has limitations such as lack of dual-stack support, missing newer fields, and truncation issues when too many endpoints exist. ([Kubernetes][4])

---

# 4. Service YAML anatomy

A realistic Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: production
  labels:
    app: web
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 8080
```

Field explanation:

| Field                     | Meaning                                                                            |
| ------------------------- | ---------------------------------------------------------------------------------- |
| `apiVersion: v1`          | Service is a core Kubernetes API object.                                           |
| `kind: Service`           | Defines a Service object.                                                          |
| `metadata.name`           | Service name. Also used in DNS.                                                    |
| `metadata.namespace`      | Namespace where the Service exists.                                                |
| `spec.type`               | Service exposure type: `ClusterIP`, `NodePort`, `LoadBalancer`, or `ExternalName`. |
| `spec.selector`           | Selects backend Pods by label.                                                     |
| `spec.ports[].port`       | Port exposed by the Service.                                                       |
| `spec.ports[].targetPort` | Port on the backend Pod/container.                                                 |
| `spec.ports[].protocol`   | Usually `TCP`; can also be `UDP` or `SCTP` depending on environment.               |
| `spec.ports[].name`       | Required when multiple ports exist; recommended always.                            |

Important distinction:

```text
port       = Service port
targetPort = Pod/container port
nodePort   = Node-level port, only for NodePort/LoadBalancer Services
```

Example:

```yaml
ports:
  - port: 80
    targetPort: 8080
```

Means:

```text
Client calls Service on port 80.
Service forwards to Pod on port 8080.
```

---

# 5. Service types

Kubernetes supports several Service types. The `type` field is nested conceptually: `NodePort` builds on `ClusterIP`, and `LoadBalancer` usually builds on `NodePort`, though Kubernetes also supports disabling NodePort allocation for some LoadBalancer implementations. ([Kubernetes][4])

---

## 5.1 ClusterIP

This is the default Service type.

```yaml
spec:
  type: ClusterIP
```

It creates an internal virtual IP reachable only inside the cluster.

Use it for:

```text
Backend APIs
Internal microservice-to-microservice communication
Databases exposed only inside the cluster
Internal queues, caches, and control-plane-adjacent services
```

Example:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: payment-api
spec:
  type: ClusterIP
  selector:
    app: payment-api
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

Inside the same namespace:

```bash
curl http://payment-api
```

From another namespace:

```bash
curl http://payment-api.production.svc.cluster.local
```

Kubernetes creates DNS records for Services, allowing Pods to contact Services by name rather than by IP. ([Kubernetes][5])

---

## 5.2 NodePort

A `NodePort` exposes the Service on every node’s IP address at a static port.

```yaml
spec:
  type: NodePort
```

Example:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-nodeport
spec:
  type: NodePort
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: 8080
      nodePort: 30080
```

Access pattern:

```text
http://<node-ip>:30080
```

Use it for:

```text
Local labs
Simple demos
Bare-metal clusters with external routing
Temporary access during debugging
```

Avoid using raw NodePort as your normal public production exposure unless you have a controlled reason. It exposes ports on all nodes and usually needs firewall/security-group coordination.

Kubernetes documentation states that NodePort exposes the Service on each node’s IP at a static port and also sets up a ClusterIP for that Service. ([Kubernetes][4])

---

## 5.3 LoadBalancer

A `LoadBalancer` Service asks the platform/cloud/controller to provision an external load balancer.

```yaml
spec:
  type: LoadBalancer
```

Example:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-lb
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

Access pattern:

```text
Client -> Cloud Load Balancer -> Kubernetes Service -> Pods
```

Use it for:

```text
Public TCP/UDP services
Private cloud load balancers
Exposing ingress controllers
Exposing APIs directly when L4 is enough
```

Kubernetes itself does not directly provide the external load balancer; you need a cloud provider integration or a load balancer implementation such as MetalLB for bare metal. ([Kubernetes][4])

Important production note: `.spec.loadBalancerIP` was deprecated in Kubernetes v1.24 because its behavior varies across providers and does not support dual-stack well. Provider-specific annotations or newer APIs are usually preferred. ([Kubernetes][4])

---

## 5.4 ExternalName

`ExternalName` does not proxy traffic. It creates a DNS CNAME-style mapping.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-db
spec:
  type: ExternalName
  externalName: db.example.com
```

Inside the cluster:

```bash
nslookup external-db.default.svc.cluster.local
```

The DNS response points to:

```text
db.example.com
```

Use it for:

```text
Referencing external databases
Referencing SaaS endpoints
Migration phases where an app expects a Kubernetes Service name
Abstracting an external dependency behind an internal name
```

Kubernetes documentation states that `ExternalName` maps the Service to the `externalName` field through DNS and sets up no proxying. ([Kubernetes][4])

---

# 6. Headless Service

A **headless Service** has no ClusterIP.

```yaml
spec:
  clusterIP: None
```

Example:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-headless
spec:
  clusterIP: None
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

Instead of returning one virtual IP, DNS can return the backend Pod IPs directly.

Use it for:

```text
StatefulSets
Databases
Distributed systems
Peer discovery
Systems where clients need individual Pod identities
```

Common examples:

```text
Kafka
Cassandra
ZooKeeper
Elasticsearch
MongoDB replica sets
PostgreSQL clusters
```

For a StatefulSet, headless Services are especially important because each Pod gets a stable DNS identity like:

```text
pod-0.my-headless-service.namespace.svc.cluster.local
pod-1.my-headless-service.namespace.svc.cluster.local
pod-2.my-headless-service.namespace.svc.cluster.local
```

---

# 7. How Service traffic works internally

For a regular `ClusterIP` Service:

```text
1. Client Pod sends request to web.default.svc.cluster.local.
2. CoreDNS resolves the name to the Service ClusterIP.
3. Packet goes to ClusterIP:port.
4. kube-proxy or an equivalent service proxy catches that traffic.
5. Traffic is redirected to one backend endpoint from the EndpointSlice.
6. Backend Pod receives the request.
```

The Kubernetes virtual IP mechanism is implemented by kube-proxy unless the cluster uses an alternative implementation. kube-proxy watches Service and EndpointSlice objects and configures node-level rules to capture traffic sent to the Service ClusterIP and port, then redirect it to one of the Service endpoints. ([Kubernetes][6])

On Linux, kube-proxy can use modes such as `iptables`, `ipvs`, or `nftables`; on Windows, the available mode is `kernelspace`. ([Kubernetes][6])

The important senior-level point: **Service load balancing is not usually a user-space reverse proxy.** In the common kube-proxy modes, it is implemented through kernel/networking rules such as DNAT.

---

# 8. Service DNS

Assume:

```text
Service name: web
Namespace: svc-lab
Cluster domain: cluster.local
```

DNS names:

```text
web
web.svc-lab
web.svc-lab.svc
web.svc-lab.svc.cluster.local
```

From the same namespace:

```bash
curl http://web
```

From another namespace:

```bash
curl http://web.svc-lab
```

Fully qualified:

```bash
curl http://web.svc-lab.svc.cluster.local
```

A client Pod’s DNS search list normally includes its own namespace and the cluster’s default domain, so short names often work within the same namespace. ([Kubernetes][5])

---

# 9. Hands-on lab: ClusterIP Service

## 9.1 Create namespace

```bash
kubectl create namespace svc-lab
```

---

## 9.2 Create a simple web Deployment

Create `web-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: svc-lab
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: python:3.12-alpine
          ports:
            - containerPort: 8080
          command:
            - sh
            - -c
            - |
              cat > /server.py <<'PY'
              from http.server import BaseHTTPRequestHandler, HTTPServer
              import socket

              class Handler(BaseHTTPRequestHandler):
                  def do_GET(self):
                      self.send_response(200)
                      self.end_headers()
                      self.wfile.write(f"Hello from pod: {socket.gethostname()}\n".encode())

              HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
              PY
              python /server.py
```

Apply:

```bash
kubectl apply -f web-deployment.yaml
```

Check Pods:

```bash
kubectl -n svc-lab get pods -o wide --show-labels
```

Expected:

```text
NAME                   READY   STATUS    IP            LABELS
web-xxxxxxxxx-aaaaa    1/1     Running   10.244.0.10   app=web
web-xxxxxxxxx-bbbbb    1/1     Running   10.244.0.11   app=web
web-xxxxxxxxx-ccccc    1/1     Running   10.244.0.12   app=web
```

---

## 9.3 Create ClusterIP Service

Create `web-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: svc-lab
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 8080
```

Apply:

```bash
kubectl apply -f web-service.yaml
```

Check Service:

```bash
kubectl -n svc-lab get svc web -o wide
```

Expected:

```text
NAME   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   SELECTOR
web    ClusterIP   10.96.x.x       <none>        80/TCP    app=web
```

---

## 9.4 Inspect EndpointSlices

```bash
kubectl -n svc-lab get endpointslice -l kubernetes.io/service-name=web -o wide
```

Expected:

```text
NAME          ADDRESSTYPE   PORTS   ENDPOINTS
web-xxxxx     IPv4          8080    10.244.0.10,10.244.0.11,10.244.0.12
```

This confirms:

```text
Service selector app=web
matched 3 Pods
and Kubernetes created EndpointSlice backends for them
```

---

## 9.5 Test from inside the cluster

Start a temporary curl Pod:

```bash
kubectl -n svc-lab run curl \
  --image=curlimages/curl:8.8.0 \
  --restart=Never \
  --rm -it \
  -- sh
```

Inside the shell:

```bash
curl http://web
```

Expected:

```text
Hello from pod: web-xxxxxxxxx-aaaaa
```

Run multiple times:

```bash
for i in $(seq 1 10); do curl -s http://web; done
```

You should see different Pod names over multiple requests:

```text
Hello from pod: web-xxxxxxxxx-aaaaa
Hello from pod: web-xxxxxxxxx-bbbbb
Hello from pod: web-xxxxxxxxx-ccccc
```

That demonstrates Service-level backend selection.

Exit:

```bash
exit
```

---

# 10. Lab: Scale Pods and observe Service update

Scale the Deployment:

```bash
kubectl -n svc-lab scale deployment web --replicas=5
```

Check Pods:

```bash
kubectl -n svc-lab get pods -o wide
```

Check EndpointSlices again:

```bash
kubectl -n svc-lab get endpointslice -l kubernetes.io/service-name=web -o wide
```

Now you should see 5 backend Pod IPs.

Test again:

```bash
kubectl -n svc-lab run curl \
  --image=curlimages/curl:8.8.0 \
  --restart=Never \
  --rm -it \
  -- sh
```

Inside:

```bash
for i in $(seq 1 20); do curl -s http://web; done
```

The Service continues working without clients knowing that the backend set changed.

---

# 11. Lab: Break the selector and debug

Patch the Service with a wrong selector:

```bash
kubectl -n svc-lab patch svc web \
  -p '{"spec":{"selector":{"app":"wrong"}}}'
```

Check EndpointSlices:

```bash
kubectl -n svc-lab get endpointslice -l kubernetes.io/service-name=web -o wide
```

You should see no valid backend endpoints.

Try curl again:

```bash
kubectl -n svc-lab run curl \
  --image=curlimages/curl:8.8.0 \
  --restart=Never \
  --rm -it \
  -- sh
```

Inside:

```bash
curl --connect-timeout 3 http://web
```

It should fail or timeout because the Service has no matching backend Pods.

Debug commands:

```bash
kubectl -n svc-lab describe svc web
kubectl -n svc-lab get pods --show-labels
kubectl -n svc-lab get endpointslice -l kubernetes.io/service-name=web
```

Fix it:

```bash
kubectl -n svc-lab patch svc web \
  -p '{"spec":{"selector":{"app":"web"}}}'
```

Verify:

```bash
kubectl -n svc-lab get endpointslice -l kubernetes.io/service-name=web -o wide
```

---

# 12. Lab: NodePort Service

Create a NodePort Service:

```bash
kubectl -n svc-lab expose deployment web \
  --type=NodePort \
  --name=web-nodeport \
  --port=80 \
  --target-port=8080
```

Check it:

```bash
kubectl -n svc-lab get svc web-nodeport
```

Example:

```text
NAME           TYPE       CLUSTER-IP      PORT(S)
web-nodeport   NodePort   10.96.20.30     80:31234/TCP
```

Here:

```text
Service port = 80
NodePort     = 31234
Target port  = 8080
```

Get NodePort:

```bash
NODE_PORT=$(kubectl -n svc-lab get svc web-nodeport -o jsonpath='{.spec.ports[0].nodePort}')
echo $NODE_PORT
```

Get node IPs:

```bash
kubectl get nodes -o wide
```

Access:

```bash
curl http://<node-ip>:$NODE_PORT
```

For Minikube:

```bash
minikube service web-nodeport -n svc-lab --url
```

Then curl the printed URL.

---

# 13. Lab: LoadBalancer Service

Create a LoadBalancer Service:

```bash
kubectl -n svc-lab expose deployment web \
  --type=LoadBalancer \
  --name=web-lb \
  --port=80 \
  --target-port=8080
```

Check:

```bash
kubectl -n svc-lab get svc web-lb
```

In a real cloud cluster, you may see:

```text
NAME     TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)
web-lb   LoadBalancer   10.96.x.x       34.x.x.x         80:xxxxx/TCP
```

Access:

```bash
curl http://<external-ip>
```

In Minikube, run this in another terminal:

```bash
minikube tunnel
```

Then check again:

```bash
kubectl -n svc-lab get svc web-lb
```

If `EXTERNAL-IP` stays `<pending>`, your cluster does not have a LoadBalancer implementation installed. That is normal on many local or bare-metal clusters.

---

# 14. Lab: Headless Service

Create `web-headless.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-headless
  namespace: svc-lab
spec:
  clusterIP: None
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

Apply:

```bash
kubectl apply -f web-headless.yaml
```

Test DNS:

```bash
kubectl -n svc-lab run dns-test \
  --image=busybox:1.36 \
  --restart=Never \
  --rm -it \
  -- nslookup web-headless.svc-lab.svc.cluster.local
```

Expected behavior: instead of one ClusterIP, DNS should return backend Pod IPs.

Use this when clients need direct Pod-level discovery rather than a single virtual Service IP.

---

# 15. Lab: ExternalName Service

Create `externalname.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-dns
  namespace: svc-lab
spec:
  type: ExternalName
  externalName: dns.google
```

Apply:

```bash
kubectl apply -f externalname.yaml
```

Test DNS:

```bash
kubectl -n svc-lab run dns-test \
  --image=busybox:1.36 \
  --restart=Never \
  --rm -it \
  -- nslookup external-dns.svc-lab.svc.cluster.local
```

You should see that the Kubernetes Service name resolves toward the external DNS name.

---

# 16. Service without selector

A Service does not always need a selector.

Example use cases:

```text
Pointing a Kubernetes Service to an external database
Pointing to legacy VMs
Gradual migration into Kubernetes
Using Kubernetes DNS for non-Kubernetes backends
```

Example Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: legacy-api
  namespace: svc-lab
spec:
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

No selector.

Then you manually create an EndpointSlice:

```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: legacy-api-1
  namespace: svc-lab
  labels:
    kubernetes.io/service-name: legacy-api
addressType: IPv4
ports:
  - name: http
    protocol: TCP
    port: 8080
endpoints:
  - addresses:
      - "10.10.10.20"
  - addresses:
      - "10.10.10.21"
```

This allows:

```bash
curl http://legacy-api
```

To route to external backend IPs.

Important limitation: Kubernetes docs note that API-server proxying such as `kubectl port-forward service/<service-name>` does not work for Services without selectors because the API server does not allow proxying to endpoints that are not mapped to Pods. ([Kubernetes][4])

---

# 17. `port`, `targetPort`, and `nodePort`

This is one of the most common confusion points.

```yaml
ports:
  - port: 80
    targetPort: 8080
    nodePort: 30080
```

Means:

```text
port:
  The Service port.
  Internal clients call this port.

targetPort:
  The backend Pod/container port.
  Traffic is forwarded here.

nodePort:
  The port opened on every node.
  Only relevant for NodePort and usually LoadBalancer.
```

Example path:

```text
curl http://web:80
    -> Service port 80
    -> Pod IP:8080
```

NodePort path:

```text
curl http://node-ip:30080
    -> NodePort 30080
    -> Service
    -> Pod IP:8080
```

---

# 18. Named targetPort

Instead of using numeric `targetPort`, you can use a named container port.

Pod:

```yaml
ports:
  - name: http
    containerPort: 8080
```

Service:

```yaml
ports:
  - port: 80
    targetPort: http
```

This is useful when different versions of Pods use different numeric ports but keep the same semantic port name.

Production recommendation: use named ports for multi-port services and complex workloads.

---

# 19. Multi-port Service

Example:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: app
spec:
  selector:
    app: app
  ports:
    - name: http
      port: 80
      targetPort: 8080
    - name: metrics
      port: 9090
      targetPort: 9090
```

When a Service exposes multiple ports, each port must have a unique name.

Use cases:

```text
HTTP app traffic
Metrics endpoint
gRPC endpoint
Admin endpoint
```

---

# 20. Readiness and Services

A Service should only send traffic to Pods that are ready.

Example Deployment with readiness probe:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: svc-lab
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-ready
  template:
    metadata:
      labels:
        app: web-ready
    spec:
      containers:
        - name: web
          image: python:3.12-alpine
          ports:
            - containerPort: 8080
          command:
            - sh
            - -c
            - |
              cat > /server.py <<'PY'
              from http.server import BaseHTTPRequestHandler, HTTPServer
              import socket

              class Handler(BaseHTTPRequestHandler):
                  def do_GET(self):
                      if self.path == "/healthz":
                          self.send_response(200)
                          self.end_headers()
                          self.wfile.write(b"ok\n")
                          return

                      self.send_response(200)
                      self.end_headers()
                      self.wfile.write(f"Hello from {socket.gethostname()}\n".encode())

              HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
              PY
              python /server.py
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 3
            periodSeconds: 5
```

Why this matters:

```text
Pod Running does not always mean Pod Ready.
Service traffic should go only to ready Pods.
Bad readiness probes cause Services to have zero usable backends.
```

Debug:

```bash
kubectl -n svc-lab get pods
kubectl -n svc-lab describe pod <pod-name>
kubectl -n svc-lab get endpointslice -l kubernetes.io/service-name=<service-name> -o yaml
```

---

# 21. Session affinity

By default, Service traffic is not sticky.

You can enable client-IP-based affinity:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: sticky-web
spec:
  selector:
    app: web
  sessionAffinity: ClientIP
  ports:
    - port: 80
      targetPort: 8080
```

Use this only when needed.

Good use cases:

```text
Legacy stateful apps
Temporary migration
Apps with local in-memory session state
```

Better production approach:

```text
Externalize session state to Redis/database
Use stateless application replicas
Avoid relying on sticky sessions when possible
```

Kubernetes supports Service session affinity based on client IP when you need repeated connections from a client to go to the same backend Pod. ([Kubernetes][4])

---

# 22. `externalTrafficPolicy`

For `NodePort` and `LoadBalancer` Services:

```yaml
spec:
  externalTrafficPolicy: Cluster
```

or:

```yaml
spec:
  externalTrafficPolicy: Local
```

High-level meaning:

```text
Cluster:
  External traffic can be forwarded to Pods anywhere in the cluster.

Local:
  Node only forwards external traffic to local Pods on the same node.
  Often used to preserve client source IP.
```

Tradeoff:

```text
Cluster:
  Better load spreading.
  May hide original client source IP depending on implementation.

Local:
  Better source IP preservation.
  Can cause uneven traffic if Pods are not evenly distributed.
  Nodes without local endpoints should not receive traffic.
```

Kubernetes Service traffic policy fields such as `internalTrafficPolicy` and `externalTrafficPolicy` control how traffic is routed to healthy, ready backends. ([Kubernetes][4])

---

# 23. `internalTrafficPolicy`

For internal cluster traffic:

```yaml
spec:
  internalTrafficPolicy: Cluster
```

or:

```yaml
spec:
  internalTrafficPolicy: Local
```

Use `Local` only when you explicitly want node-local routing. Otherwise, default cluster-wide routing is usually safer.

---

# 24. `trafficDistribution`

Modern Kubernetes also has `spec.trafficDistribution`, which expresses routing preferences such as preferring same-zone or same-node endpoints. Kubernetes documentation distinguishes this from strict traffic policies: traffic policies enforce hard semantics, while traffic distribution expresses preferences for performance, cost, or reliability optimization. ([Kubernetes][4])

Example:

```yaml
spec:
  trafficDistribution: PreferSameZone
```

Use cases:

```text
Reduce cross-zone traffic cost
Improve latency
Keep traffic closer to clients
```

But do not confuse this with a strict guarantee. It is a preference.

---

# 25. Service vs Ingress vs Gateway

A Service is mostly Layer 4:

```text
TCP
UDP
SCTP
```

It does not natively understand:

```text
HTTP paths
HTTP hosts
TLS routing
Header-based routing
Canary by HTTP header
```

For HTTP/HTTPS routing, use:

```text
Ingress
Gateway API
Service mesh
API gateway
```

Kubernetes documentation positions Gateway API and Ingress as mechanisms for making Services accessible to clients outside the cluster. ([Kubernetes][2])

Typical production path:

```text
Internet
  -> Cloud Load Balancer
  -> Ingress Controller / Gateway
  -> ClusterIP Service
  -> Pods
```

---

# 26. Common Service problems and debugging

## Problem 1: Service has no endpoints

Symptoms:

```bash
curl http://web
# timeout or connection failure
```

Check:

```bash
kubectl describe svc web
kubectl get pods --show-labels
kubectl get endpointslice -l kubernetes.io/service-name=web
```

Most common cause:

```text
Service selector does not match Pod labels.
```

Fix:

```bash
kubectl patch svc web -p '{"spec":{"selector":{"app":"web"}}}'
```

---

## Problem 2: Wrong targetPort

Service:

```yaml
ports:
  - port: 80
    targetPort: 8080
```

But container listens on:

```text
3000
```

Symptoms:

```text
Endpoints exist.
DNS works.
Service IP reachable.
But connection refused or timeout.
```

Debug:

```bash
kubectl describe pod <pod>
kubectl exec -it <pod> -- netstat -tulpn
kubectl exec -it <pod> -- ss -tulpn
```

Fix:

```yaml
targetPort: 3000
```

---

## Problem 3: App listens only on localhost

Inside container, app listens on:

```text
127.0.0.1:8080
```

But Kubernetes needs it to listen on:

```text
0.0.0.0:8080
```

Symptoms:

```text
Pod is running.
Service has endpoints.
Traffic still fails.
```

Fix app binding:

```text
Listen on 0.0.0.0, not 127.0.0.1.
```

---

## Problem 4: LoadBalancer stuck at `<pending>`

Check:

```bash
kubectl get svc web-lb
```

Output:

```text
EXTERNAL-IP   <pending>
```

Causes:

```text
Local cluster has no load balancer controller.
Bare-metal cluster has no MetalLB or equivalent.
Cloud controller manager is missing or misconfigured.
Cloud quota/security issue.
```

Fix options:

```text
Use minikube tunnel.
Install MetalLB on bare metal.
Use a managed cloud Kubernetes cluster.
Check cloud controller logs.
```

---

## Problem 5: NetworkPolicy blocks traffic

A Service does not bypass NetworkPolicy.

If a NetworkPolicy denies traffic to selected Pods, the Service may resolve and have endpoints, but connections still fail.

Debug:

```bash
kubectl get networkpolicy -A
kubectl describe networkpolicy <policy>
```

NetworkPolicies are implemented by the network plugin; creating NetworkPolicy resources without a plugin that supports them has no effect. ([Kubernetes][7])

---

# 27. Production best practices

Use `ClusterIP` for internal services.

Use `LoadBalancer` for L4 external exposure when needed.

Use Ingress or Gateway API for HTTP/HTTPS routing.

Avoid exposing raw `NodePort` publicly unless you have a specific reason.

Always define readiness probes for workloads behind Services.

Name your Service ports:

```yaml
ports:
  - name: http
```

Use clear, stable labels:

```yaml
app.kubernetes.io/name: payment-api
app.kubernetes.io/component: backend
app.kubernetes.io/part-of: checkout
```

Avoid overly broad selectors:

```yaml
selector:
  app: web
```

Can accidentally match unintended Pods in large systems. Prefer more specific labels for production.

Do not hardcode ClusterIP unless you have a migration or legacy compatibility reason.

Use headless Services for StatefulSets and direct peer discovery.

Use `externalTrafficPolicy: Local` carefully. It is useful for source IP preservation, but you need good Pod spreading and load balancer health checks.

Monitor:

```text
Service endpoint count
EndpointSlice health
Pod readiness
DNS latency/errors
kube-proxy health
CNI health
Cloud load balancer health
```

---

# 28. Senior mental model

A Service is a **stable contract** between clients and backend workloads.

```text
Clients depend on the Service.
The Service depends on labels.
Labels select Pods.
EndpointSlices represent current backends.
kube-proxy or another data plane implementation routes packets.
```

When debugging a Service, always walk the chain:

```text
DNS
  -> Service exists?
  -> Service selector correct?
  -> EndpointSlices populated?
  -> Pods Ready?
  -> targetPort correct?
  -> app listening on correct interface?
  -> NetworkPolicy allows traffic?
  -> kube-proxy/CNI working?
  -> cloud/bare-metal load balancer working?
```

The most important command sequence:

```bash
kubectl get svc -n <ns>
kubectl describe svc <svc> -n <ns>
kubectl get pods -n <ns> --show-labels
kubectl get endpointslice -n <ns> -l kubernetes.io/service-name=<svc>
kubectl describe pod <pod> -n <ns>
kubectl exec -n <ns> -it <client-pod> -- curl -v http://<svc>
```

---

# 29. Cleanup

```bash
kubectl delete namespace svc-lab
```

---

# 30. Summary

A Kubernetes Service gives stable access to dynamic Pods.

```text
ClusterIP     -> internal-only virtual IP
NodePort      -> exposes on every node IP at a static port
LoadBalancer  -> asks external LB implementation to expose it
ExternalName  -> DNS alias, no proxying
Headless      -> no virtual IP, direct endpoint DNS
```

For production:

```text
Use ClusterIP behind Ingress/Gateway for most apps.
Use LoadBalancer for L4 exposure.
Use readiness probes.
Debug EndpointSlices, not only Services.
Do not confuse Service with HTTP routing.
Remember: selector mismatch is the classic Service failure.
```

---

# 31. Repository YAML integration

This section maps the YAML manifests in this folder to the concepts in this document and adds the missing pieces.

Already covered in earlier sections:

```text
simple.yaml
  -> Basic ClusterIP Service with selector + port/targetPort.

multi-port-service.yaml
  -> Multi-port Service; each port has a unique name.

spec.ports.nodePort/node-port.yaml
  -> NodePort Service with explicit nodePort.

spec.type/load-balancer.yaml
  -> LoadBalancer Service behavior and caveats.

spec.externalName/external-name.yaml
  -> ExternalName DNS alias Service (no proxying).

headless-service/headless-service.yaml
spec.clusterIP/headless-service.yaml
  -> Headless Service via clusterIP: None.
```

Not previously explained in detail (now integrated below):

```text
spec.externalIPs/external-ips.yaml
Pod.spec.subdomain/subdomain.yaml
```

---

# 32. `externalIPs` Service (from `spec.externalIPs/external-ips.yaml`)

Repository manifest pattern:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: service-external-ips-service
spec:
  selector:
    app: MyApp
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 9376
  externalIPs:
    - 80.11.12.10
```

What it means:

```text
The Service is still a normal selector-based Service for backend Pod discovery.
In addition, traffic sent to 80.11.12.10:80 can be accepted and forwarded to this Service.
Kubernetes does not allocate this IP for you.
You (or your network team/cloud setup) must route that IP to cluster nodes.
```

Important operational note:

```text
externalIPs is not a cloud load balancer API.
It relies on external network routing and can be risky if used casually.
For public production exposure, LoadBalancer + Ingress/Gateway is usually safer.
```

Quick verify flow:

```bash
kubectl apply -f spec.externalIPs/external-ips.yaml
kubectl get svc service-external-ips-service -o yaml | grep -A3 externalIPs
kubectl get endpointslice -l kubernetes.io/service-name=service-external-ips-service
```

---

# 33. Pod `hostname` + `subdomain` with headless Service (from `Pod.spec.subdomain/subdomain.yaml`)

This manifest combines:

```text
1 headless Service named subdomain-simple-subdomain-service
2 Pods with explicit hostname and subdomain fields
```

Why this exists:

```text
Headless Service enables per-Pod DNS records.
Pod hostname/subdomain gives each Pod a stable FQDN entry.
This is useful for peer-to-peer discovery patterns.
```

Conceptual result in default namespace:

```text
subdomain-simple-hostname-1.subdomain-simple-subdomain-service.default.svc.cluster.local
subdomain-simple-hostname-2.subdomain-simple-subdomain-service.default.svc.cluster.local
```

This is different from a normal ClusterIP Service because DNS can identify individual Pods, not just one virtual Service IP.

Quick verify flow:

```bash
kubectl apply -f Pod.spec.subdomain/subdomain.yaml
kubectl get svc subdomain-simple-subdomain-service
kubectl get pods -l name=subdomain-simple-selector -o wide
kubectl exec -it subdomain-simple-pod-1 -- nslookup subdomain-simple-hostname-2.subdomain-simple-subdomain-service.default.svc.cluster.local
```

If DNS tooling is missing in `busybox`, use a dedicated dnsutils Pod (same idea used in your headless-service example).

[1]: https://kubernetes.io/docs/tutorials/services/connect-applications-service/ "Connecting Applications with Services"
[2]: https://kubernetes.io/docs/concepts/services-networking/ "Services, Load Balancing, and Networking"
[3]: https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/ "EndpointSlices"
[4]: https://kubernetes.io/docs/concepts/services-networking/service/ "Service"
[5]: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/ "DNS for Services and Pods"
[6]: https://kubernetes.io/docs/reference/networking/virtual-ips/ "Virtual IPs and Service Proxies"
[7]: https://kubernetes.io/docs/concepts/services-networking/network-policies/ "Network Policies"
