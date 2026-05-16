# Kubernetes Endpoints

In Kubernetes, **Endpoints** are the concrete backend network addresses behind a Service.

When you create a Service like this:

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

Kubernetes looks for Pods matching:

```yaml
app: web
```

Then it builds backend records containing the selected Pod IPs and ports. Historically those backend records were stored in the legacy `Endpoints` object. Modern Kubernetes uses **EndpointSlice** as the primary API for this. Kubernetes documents EndpointSlices as the objects that represent subsets of the backing network endpoints for a Service, and the older `Endpoints` API is deprecated as of Kubernetes v1.33. ([Kubernetes][1])

---

# 1. Mental model

A Service is the stable frontend.

Endpoints are the changing backend list.

```text
Client Pod
   |
   | curl http://web
   v
Service: web
   |
   | backend discovery
   v
EndpointSlice / legacy Endpoints
   |
   | Pod IPs + ports
   v
Pod 10.244.0.10:8080
Pod 10.244.0.11:8080
Pod 10.244.0.12:8080
```

So:

```text
Service = stable abstraction
Endpoints / EndpointSlices = actual backend destinations
Pods = running application instances
```

A Service proxy implementation watches Service and EndpointSlice objects and programs the networking data plane so Service traffic is routed to healthy backends. ([Kubernetes][2])

---

# 2. Endpoints vs EndpointSlice

This distinction is critical.

| Object          | API                                 | Status                            | Meaning                                        |
| --------------- | ----------------------------------- | --------------------------------- | ---------------------------------------------- |
| `Endpoints`     | `v1/Endpoints`                      | Deprecated since Kubernetes v1.33 | Legacy object containing backend IPs and ports |
| `EndpointSlice` | `discovery.k8s.io/v1/EndpointSlice` | Stable since Kubernetes v1.21     | Modern scalable backend discovery object       |

Modern Kubernetes documentation recommends that clients use EndpointSlice instead of Endpoints because the legacy Endpoints API does not support dual-stack clusters, lacks data for newer features such as traffic distribution, and truncates if the backend list grows too large. ([Kubernetes][1])

In senior-engineer terms:

```text
Do not build new controllers or automation against v1/Endpoints.
Use discovery.k8s.io/v1 EndpointSlice instead.
Still know Endpoints because old clusters, scripts, and kubectl output may expose it.
```

---

# 3. Why Endpoints exist

Pods are ephemeral.

A Deployment can create Pods like:

```text
web-7d8f9c9f5d-a1b2c -> 10.244.0.21
web-7d8f9c9f5d-d3e4f -> 10.244.0.22
web-7d8f9c9f5d-g5h6i -> 10.244.0.23
```

After a rollout, those Pods may become:

```text
web-6c7f8b9d4c-x1y2z -> 10.244.0.31
web-6c7f8b9d4c-p3q4r -> 10.244.0.32
web-6c7f8b9d4c-s5t6u -> 10.244.0.33
```

Clients should not track those IPs manually. Kubernetes continuously updates the backend endpoint objects for the Service. The Service keeps the stable DNS name and virtual IP; EndpointSlices track the current backend Pods. ([Kubernetes][2])

---

# 4. How Kubernetes creates endpoints

For a normal Service with a selector:

```yaml
spec:
  selector:
    app: web
```

Kubernetes does this:

```text
1. Watch Service object.
2. Watch Pods in the same namespace.
3. Find Pods whose labels match the Service selector.
4. Check Pod readiness.
5. Create or update EndpointSlice objects.
6. Service proxy uses EndpointSlices to route traffic.
```

EndpointSlices are usually created automatically by the control plane for Services with selectors. A Service can have more than one EndpointSlice, and clients of the EndpointSlice API must aggregate all EndpointSlices for a Service to build the complete backend list. ([Kubernetes][3])

---

# 5. Legacy `Endpoints` object anatomy

A legacy `Endpoints` object looks like this:

```yaml
apiVersion: v1
kind: Endpoints
metadata:
  name: web
  namespace: default
subsets:
  - addresses:
      - ip: 10.244.0.21
        nodeName: worker-1
        targetRef:
          kind: Pod
          namespace: default
          name: web-abcde
      - ip: 10.244.0.22
        nodeName: worker-2
        targetRef:
          kind: Pod
          namespace: default
          name: web-fghij
    ports:
      - name: http
        port: 8080
        protocol: TCP
```

Important fields:

| Field               | Meaning                                        |
| ------------------- | ---------------------------------------------- |
| `metadata.name`     | Usually same as the Service name               |
| `subsets`           | Groups of addresses and ports                  |
| `addresses`         | Ready backend addresses                        |
| `notReadyAddresses` | Backend addresses that exist but are not ready |
| `ports`             | Backend ports                                  |
| `targetRef`         | Usually points to the backing Pod              |
| `nodeName`          | Node where the endpoint is located             |

Example:

```text
Service name: web
Endpoints name: web
Backend Pod IPs: 10.244.0.21, 10.244.0.22
Backend port: 8080
```

The legacy Endpoints API is now deprecated, and Kubernetes v1.33+ can return warnings when users read or write Endpoints resources. ([Kubernetes][4])

---

# 6. EndpointSlice anatomy

A modern `EndpointSlice` looks like this:

```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: web-abc12
  namespace: default
  labels:
    kubernetes.io/service-name: web
    endpointslice.kubernetes.io/managed-by: endpointslice-controller.k8s.io
addressType: IPv4
ports:
  - name: http
    protocol: TCP
    port: 8080
endpoints:
  - addresses:
      - 10.244.0.21
    conditions:
      ready: true
      serving: true
      terminating: false
    nodeName: worker-1
    targetRef:
      kind: Pod
      namespace: default
      name: web-abcde
  - addresses:
      - 10.244.0.22
    conditions:
      ready: true
      serving: true
      terminating: false
    nodeName: worker-2
    targetRef:
      kind: Pod
      namespace: default
      name: web-fghij
```

Important fields:

| Field                                           | Meaning                                      |
| ----------------------------------------------- | -------------------------------------------- |
| `metadata.labels["kubernetes.io/service-name"]` | Links the EndpointSlice to a Service         |
| `addressType`                                   | Usually `IPv4`, `IPv6`, or `FQDN`            |
| `ports`                                         | Backend port definitions                     |
| `endpoints[].addresses`                         | Backend IPs or names                         |
| `endpoints[].conditions.ready`                  | Whether endpoint is ready for normal traffic |
| `endpoints[].conditions.serving`                | Whether endpoint is currently serving        |
| `endpoints[].conditions.terminating`            | Whether endpoint is terminating              |
| `targetRef`                                     | Usually the backing Pod                      |
| `nodeName`                                      | Node hosting the backend Pod                 |
| `zone`                                          | Zone information when available              |

By default, Kubernetes creates a new EndpointSlice when existing EndpointSlices for a Service already contain at least 100 endpoints and another endpoint must be added. ([Kubernetes][1])

---

# 7. Why EndpointSlice replaced Endpoints

The old `Endpoints` object has serious scaling and feature limitations.

## Problem 1: One large object

Legacy Endpoints stores all backend addresses in one object. For a Service with hundreds or thousands of Pods, that object becomes large and expensive to update.

EndpointSlice shards the backend list:

```text
web-abc12   -> 100 endpoints
web-def34   -> 100 endpoints
web-ghi56   -> 100 endpoints
...
```

Only changed slices need updates.

## Problem 2: 1000 endpoint truncation

Kubernetes limits how many endpoints can fit in a single legacy Endpoints object. When a Service has more than 1000 backing endpoints, the Endpoints object is truncated and annotated with `endpoints.kubernetes.io/over-capacity: truncated`. Traffic can still go to backends, but any old load-balancing implementation relying only on legacy Endpoints may see only up to 1000 endpoints. ([Kubernetes][1])

## Problem 3: Missing modern networking features

The legacy Endpoints API does not support some newer Service features, including dual-stack and traffic distribution metadata. EndpointSlice is the API that supports modern Service discovery semantics. ([Kubernetes][1])

---

# 8. Endpoint readiness

Endpoints are affected by Pod readiness.

A Pod can be:

```text
Running but not Ready
```

That means the container process exists, but Kubernetes should not send normal Service traffic to it yet.

Example causes:

```text
Readiness probe failing
Application still warming up
Database migration in progress
Dependency unavailable
Pod terminating
```

With legacy Endpoints:

```yaml
subsets:
  - addresses:
      - ip: 10.244.0.21
    notReadyAddresses:
      - ip: 10.244.0.22
```

With EndpointSlice:

```yaml
endpoints:
  - addresses:
      - 10.244.0.21
    conditions:
      ready: true
  - addresses:
      - 10.244.0.22
    conditions:
      ready: false
```

For headless Services and DNS, Kubernetes documentation notes that Pod records require the Pod to be ready unless `publishNotReadyAddresses=True` is set on the Service. ([Kubernetes][5])

---

# 9. Service selector and endpoint generation

The Service selector is the most important connection between Service and endpoints.

Deployment:

```yaml
template:
  metadata:
    labels:
      app: web
```

Service:

```yaml
spec:
  selector:
    app: web
```

This produces endpoint records.

But this Service:

```yaml
spec:
  selector:
    app: wrong
```

produces no useful endpoints.

Typical debugging flow:

```bash
kubectl get svc web
kubectl describe svc web
kubectl get pods --show-labels
kubectl get endpointslice -l kubernetes.io/service-name=web
kubectl get endpoints web
```

In modern Kubernetes, prefer `EndpointSlice` for correctness. Use `Endpoints` mostly for legacy visibility.

---

# 10. Hands-on lab 1: Service creates EndpointSlices

## 10.1 Create namespace

```bash
kubectl create namespace endpoints-lab
```

## 10.2 Create Deployment

Create `web-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: endpoints-lab
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
            - name: http
              containerPort: 8080
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
                      self.wfile.write(f"pod={socket.gethostname()}\n".encode())

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
kubectl -n endpoints-lab get pods -o wide --show-labels
```

Expected:

```text
NAME                   READY   STATUS    IP            LABELS
web-xxxxxxxxx-aaaaa    1/1     Running   10.244.0.10   app=web
web-xxxxxxxxx-bbbbb    1/1     Running   10.244.0.11   app=web
web-xxxxxxxxx-ccccc    1/1     Running   10.244.0.12   app=web
```

---

## 10.3 Create Service

Create `web-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: endpoints-lab
spec:
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: http
```

Apply:

```bash
kubectl apply -f web-service.yaml
```

Check Service:

```bash
kubectl -n endpoints-lab get svc web -o wide
```

Expected:

```text
NAME   TYPE        CLUSTER-IP      PORT(S)   SELECTOR
web    ClusterIP   10.96.x.x       80/TCP    app=web
```

---

## 10.4 Inspect EndpointSlices

```bash
kubectl -n endpoints-lab get endpointslice \
  -l kubernetes.io/service-name=web \
  -o wide
```

Expected:

```text
NAME        ADDRESSTYPE   PORTS   ENDPOINTS
web-abc12   IPv4          8080    10.244.0.10,10.244.0.11,10.244.0.12
```

Inspect YAML:

```bash
kubectl -n endpoints-lab get endpointslice \
  -l kubernetes.io/service-name=web \
  -o yaml
```

Focus on:

```yaml
addressType: IPv4
ports:
  - name: http
    port: 8080
endpoints:
  - addresses:
      - 10.244.0.10
    conditions:
      ready: true
```

This is the real backend routing data.

---

## 10.5 Inspect legacy Endpoints

```bash
kubectl -n endpoints-lab get endpoints web -o yaml
```

On Kubernetes v1.33+, you may see a deprecation warning because `v1/Endpoints` is deprecated. That is expected. ([Kubernetes][4])

Example shape:

```yaml
apiVersion: v1
kind: Endpoints
metadata:
  name: web
subsets:
  - addresses:
      - ip: 10.244.0.10
      - ip: 10.244.0.11
      - ip: 10.244.0.12
    ports:
      - name: http
        port: 8080
        protocol: TCP
```

---

## 10.6 Test routing through Service

Create a temporary curl Pod:

```bash
kubectl -n endpoints-lab run curl \
  --image=curlimages/curl:8.8.0 \
  --restart=Never \
  --rm -it \
  -- sh
```

Inside the shell:

```bash
for i in $(seq 1 10); do curl -s http://web; done
```

Expected:

```text
pod=web-xxxxxxxxx-aaaaa
pod=web-xxxxxxxxx-bbbbb
pod=web-xxxxxxxxx-ccccc
```

Exit:

```bash
exit
```

---

# 11. Hands-on lab 2: Scale Pods and watch EndpointSlices update

Scale up:

```bash
kubectl -n endpoints-lab scale deployment web --replicas=5
```

Watch Pods:

```bash
kubectl -n endpoints-lab get pods -o wide
```

Watch EndpointSlices:

```bash
kubectl -n endpoints-lab get endpointslice \
  -l kubernetes.io/service-name=web \
  -o wide
```

You should now see five backend addresses.

Scale down:

```bash
kubectl -n endpoints-lab scale deployment web --replicas=2
```

Check again:

```bash
kubectl -n endpoints-lab get endpointslice \
  -l kubernetes.io/service-name=web \
  -o wide
```

You should now see two backend addresses.

Production meaning:

```text
Clients keep calling http://web.
Kubernetes updates backend endpoint data automatically.
Clients do not need to know Pod IP changes.
```

---

# 12. Hands-on lab 3: Break the Service selector

Patch the Service selector to the wrong label:

```bash
kubectl -n endpoints-lab patch svc web \
  -p '{"spec":{"selector":{"app":"wrong"}}}'
```

Check EndpointSlices:

```bash
kubectl -n endpoints-lab get endpointslice \
  -l kubernetes.io/service-name=web \
  -o wide
```

You should see no useful backend endpoints.

Describe Service:

```bash
kubectl -n endpoints-lab describe svc web
```

Expected issue:

```text
Selector: app=wrong
Endpoints: <none>
```

Check Pod labels:

```bash
kubectl -n endpoints-lab get pods --show-labels
```

You will see:

```text
app=web
```

Fix Service selector:

```bash
kubectl -n endpoints-lab patch svc web \
  -p '{"spec":{"selector":{"app":"web"}}}'
```

Verify:

```bash
kubectl -n endpoints-lab get endpointslice \
  -l kubernetes.io/service-name=web \
  -o wide
```

Senior debugging lesson:

```text
Most Service connectivity failures are not DNS failures.
They are selector, readiness, targetPort, or NetworkPolicy failures.
```

---

# 13. Hands-on lab 4: Readiness controls endpoints

Create a Deployment whose readiness can fail.

Create `web-readiness.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-ready
  namespace: endpoints-lab
spec:
  replicas: 2
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
            - name: http
              containerPort: 8080
          command:
            - sh
            - -c
            - |
              cat > /server.py <<'PY'
              from http.server import BaseHTTPRequestHandler, HTTPServer
              import socket
              import os

              class Handler(BaseHTTPRequestHandler):
                  def do_GET(self):
                      if self.path == "/ready":
                          if os.path.exists("/tmp/ready"):
                              self.send_response(200)
                              self.end_headers()
                              self.wfile.write(b"ready\n")
                          else:
                              self.send_response(503)
                              self.end_headers()
                              self.wfile.write(b"not ready\n")
                          return

                      self.send_response(200)
                      self.end_headers()
                      self.wfile.write(f"pod={socket.gethostname()}\n".encode())

              HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
              PY
              python /server.py
          readinessProbe:
            httpGet:
              path: /ready
              port: http
            periodSeconds: 3
```

Apply:

```bash
kubectl apply -f web-readiness.yaml
```

Create Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-ready
  namespace: endpoints-lab
spec:
  selector:
    app: web-ready
  ports:
    - name: http
      port: 80
      targetPort: http
```

Save as `web-ready-service.yaml` and apply:

```bash
kubectl apply -f web-ready-service.yaml
```

Check Pods:

```bash
kubectl -n endpoints-lab get pods -l app=web-ready
```

Expected:

```text
READY   STATUS
0/1     Running
0/1     Running
```

Check EndpointSlices:

```bash
kubectl -n endpoints-lab get endpointslice \
  -l kubernetes.io/service-name=web-ready \
  -o yaml
```

Look for:

```yaml
conditions:
  ready: false
```

Now mark one Pod as ready:

```bash
POD=$(kubectl -n endpoints-lab get pod -l app=web-ready -o jsonpath='{.items[0].metadata.name}')
kubectl -n endpoints-lab exec "$POD" -- touch /tmp/ready
```

Wait a few seconds:

```bash
kubectl -n endpoints-lab get pods -l app=web-ready
```

Check EndpointSlice again:

```bash
kubectl -n endpoints-lab get endpointslice \
  -l kubernetes.io/service-name=web-ready \
  -o yaml
```

You should see one endpoint with:

```yaml
ready: true
```

and another with:

```yaml
ready: false
```

Test Service:

```bash
kubectl -n endpoints-lab run curl \
  --image=curlimages/curl:8.8.0 \
  --restart=Never \
  --rm -it \
  -- sh
```

Inside:

```bash
for i in $(seq 1 10); do curl -s http://web-ready; done
```

You should only receive responses from the ready backend.

---

# 14. Hands-on lab 5: Selectorless Service with manual EndpointSlice

This is a powerful advanced use case.

You can create a Service with no selector and manually attach endpoints. This is useful for:

```text
External database
Legacy VM backend
Migration from VM to Kubernetes
Manually managed backend pool
Hybrid infrastructure
```

Kubernetes documents that selectorless Services can route to endpoints defined by EndpointSlice objects, and custom EndpointSlices are linked to a Service using the `kubernetes.io/service-name` label. ([Kubernetes][1])

## 14.1 Create selectorless Service

Create `legacy-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: legacy-api
  namespace: endpoints-lab
spec:
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

Apply:

```bash
kubectl apply -f legacy-service.yaml
```

Notice: no `selector`.

```bash
kubectl -n endpoints-lab get svc legacy-api -o yaml
```

---

## 14.2 Create manual EndpointSlice

For this lab, point the Service to the existing `web` Pod IPs.

Get one Pod IP:

```bash
POD_IP=$(kubectl -n endpoints-lab get pod -l app=web -o jsonpath='{.items[0].status.podIP}')
echo "$POD_IP"
```

Create `legacy-endpointslice.yaml` manually, replacing `POD_IP_HERE`:

```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: legacy-api-manual-1
  namespace: endpoints-lab
  labels:
    kubernetes.io/service-name: legacy-api
    endpointslice.kubernetes.io/managed-by: manual
addressType: IPv4
ports:
  - name: http
    protocol: TCP
    port: 8080
endpoints:
  - addresses:
      - POD_IP_HERE
    conditions:
      ready: true
```

Apply:

```bash
kubectl apply -f legacy-endpointslice.yaml
```

Check:

```bash
kubectl -n endpoints-lab get endpointslice \
  -l kubernetes.io/service-name=legacy-api \
  -o wide
```

Test:

```bash
kubectl -n endpoints-lab run curl \
  --image=curlimages/curl:8.8.0 \
  --restart=Never \
  --rm -it \
  -- sh
```

Inside:

```bash
curl http://legacy-api
```

Expected:

```text
pod=web-...
```

Important limitation: the Kubernetes API server does not allow proxying to endpoints that are not mapped to Pods, so commands such as `kubectl port-forward service/<service-name>` fail for selectorless Services whose endpoints are not Pod-backed. ([Kubernetes][1])

---

# 15. Headless Service and endpoints

A headless Service has:

```yaml
clusterIP: None
```

Example:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-headless
  namespace: endpoints-lab
spec:
  clusterIP: None
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: http
```

Apply:

```bash
kubectl apply -f web-headless.yaml
```

Check DNS:

```bash
kubectl -n endpoints-lab run dns-test \
  --image=busybox:1.36 \
  --restart=Never \
  --rm -it \
  -- nslookup web-headless.endpoints-lab.svc.cluster.local
```

With a normal ClusterIP Service, DNS usually resolves to the Service IP.

With a headless Service, DNS can resolve to the backend Pod IPs directly. Kubernetes DNS documentation explains that for headless Services and Pods with matching subdomain configuration, DNS can serve A/AAAA records pointing to Pod IPs, subject to readiness behavior. ([Kubernetes][5])

Use headless Services for:

```text
StatefulSets
Databases
Peer discovery
Kafka
Cassandra
ZooKeeper
Elasticsearch
MongoDB replica sets
```

---

# 16. EndpointSlice labels

A Service discovers its EndpointSlices through labels.

Most important label:

```yaml
kubernetes.io/service-name: web
```

Example:

```bash
kubectl -n endpoints-lab get endpointslice \
  -l kubernetes.io/service-name=web
```

For manually created EndpointSlices, Kubernetes recommends also setting `endpointslice.kubernetes.io/managed-by` to identify who manages the slice, and avoiding the reserved value `"controller"` because that identifies Kubernetes control-plane-managed EndpointSlices. ([Kubernetes][1])

Example:

```yaml
metadata:
  labels:
    kubernetes.io/service-name: legacy-api
    endpointslice.kubernetes.io/managed-by: manual
```

---

# 17. EndpointSlice conditions

EndpointSlice has richer condition metadata than legacy Endpoints.

Common fields:

```yaml
conditions:
  ready: true
  serving: true
  terminating: false
```

Interpretation:

| Condition     | Meaning                                        |
| ------------- | ---------------------------------------------- |
| `ready`       | Endpoint should receive normal Service traffic |
| `serving`     | Endpoint is still serving traffic              |
| `terminating` | Endpoint is being terminated                   |

Why this matters:

```text
A terminating Pod may still be serving existing connections.
A not-ready Pod should usually not receive new traffic.
A load balancer or service mesh may need more nuance than just ready/not-ready.
```

This richer metadata is one reason EndpointSlice is preferred over legacy Endpoints for modern controllers and proxies. Kubernetes states that newer Service features such as dual-stack networking and traffic distribution are supported via EndpointSlice rather than the legacy Endpoints API. ([Kubernetes][4])

---

# 18. Common endpoint failure modes

## Failure 1: Service selector does not match Pods

Check:

```bash
kubectl -n endpoints-lab describe svc web
kubectl -n endpoints-lab get pods --show-labels
```

Bad:

```yaml
Service selector:
  app: web

Pod labels:
  app: frontend
```

Result:

```text
No endpoints
```

Fix either the Pod labels or the Service selector.

---

## Failure 2: Pods are not Ready

Check:

```bash
kubectl -n endpoints-lab get pods
kubectl -n endpoints-lab describe pod <pod-name>
kubectl -n endpoints-lab get endpointslice -l kubernetes.io/service-name=<service-name> -o yaml
```

Symptoms:

```text
Pod is Running
Service exists
Endpoint exists but ready=false
Traffic does not reach that Pod
```

Fix readiness probe, application health endpoint, dependencies, or startup timing.

---

## Failure 3: Wrong `targetPort`

Service:

```yaml
ports:
  - port: 80
    targetPort: 8080
```

But app listens on:

```text
3000
```

EndpointSlice may show port `8080`, but the container is not listening there.

Debug:

```bash
kubectl -n endpoints-lab exec -it <pod-name> -- sh
netstat -tulpn
# or
ss -tulpn
```

Fix:

```yaml
targetPort: 3000
```

or use named ports:

```yaml
targetPort: http
```

---

## Failure 4: Application listens on `127.0.0.1`

Inside the container, the app must listen on:

```text
0.0.0.0:<port>
```

Bad:

```text
127.0.0.1:8080
```

Good:

```text
0.0.0.0:8080
```

Symptoms:

```text
EndpointSlice exists
Pod is Ready
Service traffic still fails
```

---

## Failure 5: NetworkPolicy blocks traffic

Services and EndpointSlices do not bypass NetworkPolicy.

Check:

```bash
kubectl get networkpolicy -A
kubectl -n endpoints-lab describe networkpolicy <policy-name>
```

Symptoms:

```text
DNS works
EndpointSlice exists
Pod is Ready
Connection times out
```

---

## Failure 6: EndpointSlice exists, but client sees incomplete backend list

This matters for custom controllers.

A Service can have multiple EndpointSlices. A correct controller must list all EndpointSlices with:

```text
kubernetes.io/service-name=<service-name>
```

Then aggregate and deduplicate endpoints. Kubernetes explicitly notes that EndpointSlice clients must iterate through all associated EndpointSlices and build the complete set of unique network endpoints because endpoints may be duplicated across slices. ([Kubernetes][3])

---

# 19. Debugging command sequence

Use this sequence when Service traffic is broken:

```bash
# 1. Does Service exist?
kubectl -n <ns> get svc <svc-name> -o wide

# 2. What selector does it use?
kubectl -n <ns> describe svc <svc-name>

# 3. Do Pods match selector?
kubectl -n <ns> get pods --show-labels -o wide

# 4. Are EndpointSlices populated?
kubectl -n <ns> get endpointslice \
  -l kubernetes.io/service-name=<svc-name> \
  -o wide

# 5. Are endpoints ready?
kubectl -n <ns> get endpointslice \
  -l kubernetes.io/service-name=<svc-name> \
  -o yaml

# 6. Legacy view, if needed
kubectl -n <ns> get endpoints <svc-name> -o yaml

# 7. Is the app actually listening?
kubectl -n <ns> exec -it <pod-name> -- sh
ss -tulpn

# 8. Test from inside cluster
kubectl -n <ns> run curl \
  --image=curlimages/curl:8.8.0 \
  --restart=Never \
  --rm -it \
  -- sh
```

Inside curl Pod:

```bash
curl -v http://<service-name>
```

---

# 20. Production best practices

Use EndpointSlice, not Endpoints, for new tooling.

Avoid manually creating legacy `Endpoints`.

For selectorless Services, manually create `EndpointSlice` objects instead.

Always define readiness probes for applications behind Services.

Use named container ports:

```yaml
ports:
  - name: http
    containerPort: 8080
```

Then reference them from Services:

```yaml
targetPort: http
```

Use precise Service selectors:

```yaml
selector:
  app.kubernetes.io/name: payment-api
  app.kubernetes.io/component: backend
```

Avoid broad selectors like this in large clusters:

```yaml
selector:
  app: web
```

For custom controllers:

```text
Watch EndpointSlice, not Endpoints.
Handle multiple slices per Service.
Handle duplicate endpoints.
Handle IPv4 and IPv6.
Handle ready/serving/terminating conditions.
Handle endpoint deletion and replacement.
```

---

# 21. Endpoints vs Service vs Pod

| Concept                  | Layer             | Stability | Purpose                            |
| ------------------------ | ----------------- | --------- | ---------------------------------- |
| Pod                      | Workload instance | Ephemeral | Runs containers                    |
| Endpoint / EndpointSlice | Backend discovery | Dynamic   | Lists actual backend addresses     |
| Service                  | Stable frontend   | Stable    | Gives clients stable DNS/IP        |
| Ingress / Gateway        | HTTP/L7 routing   | Stable    | Routes external HTTP/HTTPS traffic |

The endpoint object is not what clients usually call directly. Clients call the Service. Kubernetes uses EndpointSlices internally to know where the Service should send traffic.

---

# 22. Cleanup

```bash
kubectl delete namespace endpoints-lab
```

---

# 23. Summary

Endpoints are the backend address records for a Kubernetes Service.

```text
Service selects Pods.
Selected ready Pods become endpoints.
EndpointSlices store those backend IPs and ports.
Service proxies use EndpointSlices to route traffic.
```

Modern Kubernetes view:

```text
Use EndpointSlice for real systems.
Treat v1/Endpoints as legacy/deprecated.
```

Most important debugging rule:

```text
When a Service does not work, inspect EndpointSlices first.
```

Core commands:

```bash
kubectl get svc
kubectl describe svc <service>
kubectl get pods --show-labels
kubectl get endpointslice -l kubernetes.io/service-name=<service>
kubectl get endpoints <service>
```

Senior-level takeaway:

```text
Service is the stable contract.
EndpointSlice is the live backend inventory.
Pod readiness determines whether backends should receive traffic.
Selector correctness determines whether endpoints exist at all.
```

[1]: https://kubernetes.io/docs/concepts/services-networking/service/ "Service | Kubernetes"
[2]: https://kubernetes.io/docs/concepts/services-networking/ "Services, Load Balancing, and Networking | Kubernetes"
[3]: https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/ "EndpointSlices | Kubernetes"
[4]: https://kubernetes.io/blog/2025/04/24/endpoints-deprecation/ "Kubernetes v1.33: Continuing the transition from Endpoints to EndpointSlices | Kubernetes"
[5]: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/ "DNS for Services and Pods | Kubernetes"
