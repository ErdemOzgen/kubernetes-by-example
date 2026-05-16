# Kubernetes Gateway API

Gateway API is the Kubernetes networking API family designed to solve the limitations of classic `Ingress`. It gives you a more expressive, role-oriented model for exposing services, routing HTTP/gRPC/TCP/TLS traffic, delegating ownership, and implementing advanced routing features like traffic splitting, header matching, redirects, rewrites, TLS termination, and cross-namespace routing.

As of May 2026, Gateway API’s latest supported API version is `v1`, with Gateway API `v1.5.1` listed as the latest release. The project currently lists GA-level support for resources such as `GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute`, `TLSRoute`, `BackendTLSPolicy`, `ReferenceGrant`, and `ListenerSet`. ([GitHub][1])

---

# 1. The mental model

Classic `Ingress` combines too many concerns into one object:

```text
Ingress
  ├── external listener intent
  ├── hostname routing
  ├── path routing
  ├── TLS
  ├── controller-specific annotations
  └── backend service routing
```

Gateway API splits these responsibilities:

```text
GatewayClass
    |
    v
Gateway
    |
    v
HTTPRoute / GRPCRoute / TLSRoute / TCPRoute
    |
    v
Service
    |
    v
Pods
```

The core resource model is:

```text
GatewayClass -> what kind of gateway implementation exists
Gateway      -> actual listener / entry point
Route        -> how traffic is routed to Services
Service      -> stable backend target
Pods         -> actual workloads
```

The official Gateway API docs describe the three main model objects as `GatewayClass`, `Gateway`, and `Routes`: `GatewayClass` defines a set of gateways with common behavior, `Gateway` requests a traffic entry point, and Routes map traffic arriving at the Gateway to Services. ([Gateway API][2])

---

# 2. Why Gateway API exists

Ingress is simple and useful, but it becomes weak for serious platform engineering.

Ingress handles this well:

```text
app.example.com/      -> frontend-service
app.example.com/api   -> api-service
```

But Ingress becomes awkward for:

```text
80/20 canary traffic splitting
header-based routing
method-based routing
query-param routing
cross-namespace route ownership
multi-team gateway sharing
clear platform/app separation
gRPC routing
TLS passthrough
backend TLS policy
multi-listener ownership
portable advanced routing
```

Ingress controllers solved these problems with annotations.

Example:

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "20"
```

That works, but it is controller-specific. An NGINX annotation does not necessarily work on Traefik, HAProxy, Kong, Envoy Gateway, GKE Gateway, AWS Load Balancer Controller, or Istio.

Gateway API tries to standardize these patterns as Kubernetes-native API resources.

---

# 3. Gateway API is not just “Ingress v2”

This is the most important point:

> Gateway API is a role-oriented networking API.

It separates responsibilities between different personas. The Gateway API documentation explicitly models infrastructure providers, cluster operators, and application developers as separate roles. ([Gateway API][2])

A practical mapping:

```text
Infrastructure/platform team:
  - installs Gateway controller
  - manages GatewayClass
  - creates shared Gateways
  - controls listeners, TLS policy, allowed namespaces

Application team:
  - creates HTTPRoute
  - owns app-specific host/path/header routing
  - routes traffic to its own Services
```

This is much better than giving every team permission to edit the same `Ingress` or same controller annotations.

---

# 4. Gateway API objects

## 4.1 GatewayClass

`GatewayClass` is cluster-scoped.

It represents a type of gateway implementation.

Example:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

Meaning:

```text
GatewayClass name: eg
Controller: Envoy Gateway
```

Comparable objects:

```text
IngressClass  -> used by Ingress
GatewayClass  -> used by Gateway API
StorageClass  -> used by PersistentVolumeClaims
```

A cluster can have multiple GatewayClasses:

```text
public-nginx
internal-nginx
envoy-external
istio-mesh
gke-l7-global-external-managed
aws-alb
```

---

## 4.2 Gateway

`Gateway` is the actual traffic entry point.

Example:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gateway
  namespace: gateway-lab
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "*.demo.local"
      allowedRoutes:
        namespaces:
          from: Same
```

This says:

```text
Create a Gateway using GatewayClass eg.
Listen on HTTP port 80.
Accept hostnames matching *.demo.local.
Only allow Routes from the same namespace.
```

A Gateway has **listeners**. A listener is basically:

```text
port + protocol + hostname + TLS settings + route attachment policy
```

Examples:

```yaml
listeners:
  - name: http
    protocol: HTTP
    port: 80

  - name: https
    protocol: HTTPS
    port: 443
    tls:
      mode: Terminate
      certificateRefs:
        - name: app-tls
```

---

## 4.3 HTTPRoute

`HTTPRoute` is the HTTP routing object.

The Gateway API docs describe `HTTPRoute` as the resource for specifying HTTP routing behavior from a Gateway listener to a backend object such as a Kubernetes `Service`. ([Gateway API][3])

Example:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-route
  namespace: gateway-lab
spec:
  parentRefs:
    - name: shared-gateway
  hostnames:
    - app.demo.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: api
          port: 80

    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: web
          port: 80
```

This means:

```text
Host: app.demo.local
Path: /api  -> api Service
Path: /     -> web Service
```

---

## 4.4 Service

Gateway API still routes to Kubernetes `Service` objects.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: gateway-lab
spec:
  selector:
    app: api
  ports:
    - port: 80
      targetPort: 5678
```

The flow is still:

```text
Client
  -> Gateway implementation
  -> Gateway listener
  -> HTTPRoute rule
  -> Service
  -> Pod
```

Gateway API does not remove the need for Services.

---

# 5. Gateway API vs Ingress

| Area                    | Ingress                    | Gateway API                                                 |
| ----------------------- | -------------------------- | ----------------------------------------------------------- |
| API object              | `Ingress`                  | `GatewayClass`, `Gateway`, `HTTPRoute`, etc.                |
| Routing model           | Mostly host/path           | Host, path, method, headers, query params, weights, filters |
| Ownership               | Often mixed                | Platform owns Gateway, app owns Route                       |
| Cross-namespace routing | Awkward                    | Built into model with `allowedRoutes` and `ReferenceGrant`  |
| Extensibility           | Mostly annotations         | Standard fields plus extension points                       |
| Controller portability  | Often annotation-dependent | More portable when using standard fields                    |
| TLS model               | Basic                      | More expressive                                             |
| Canary support          | Controller-specific        | Standard weighted backend refs for HTTPRoute                |
| Future direction        | Stable but limited         | Strategic Kubernetes networking direction                   |

The Gateway API getting-started guide explicitly recommends installing Gateway API CRDs plus a Gateway controller, then trying simple Gateway examples and advanced topics like HTTP routing, traffic splitting, cross-namespace routing, TLS, TCP routing, and gRPC routing. ([Gateway API][4])

---

# 6. Hands-on lab with Envoy Gateway

We will deploy this:

```text
app.demo.local/       -> web service
app.demo.local/api    -> api-v1 service
```

Then we will add:

```text
80/20 traffic split between api-v1 and api-v2
header-based routing with x-api-version: v2
TLS termination example
```

The lab uses Envoy Gateway because it has good Gateway API support and simple local testing. The Envoy Gateway quickstart installs the Gateway API CRDs and Envoy Gateway using Helm, then demonstrates `GatewayClass`, `Gateway`, and `HTTPRoute` usage. ([Envoy Gateway][5])

---

# 7. Install Envoy Gateway

Prerequisites:

```bash
kubectl
helm
minikube, kind, Docker Desktop Kubernetes, or another cluster
```

Install Envoy Gateway:

```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.8.0 \
  -n envoy-gateway-system \
  --create-namespace
```

Wait until ready:

```bash
kubectl wait --timeout=5m \
  -n envoy-gateway-system \
  deployment/envoy-gateway \
  --for=condition=Available
```

Check:

```bash
kubectl get pods -n envoy-gateway-system
```

Expected:

```text
NAME                             READY   STATUS
envoy-gateway-xxxxxxxxxx-xxxxx   1/1     Running
```

---

# 8. Lab YAML: applications

Create `01-apps.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: gateway-lab
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: gateway-lab
spec:
  replicas: 2
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
          image: hashicorp/http-echo:1.0
          args:
            - "-text=Hello from WEB"
          ports:
            - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: gateway-lab
spec:
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: 5678
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-v1
  namespace: gateway-lab
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-v1
  template:
    metadata:
      labels:
        app: api-v1
    spec:
      containers:
        - name: api-v1
          image: hashicorp/http-echo:1.0
          args:
            - "-text=Hello from API v1"
          ports:
            - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: api-v1
  namespace: gateway-lab
spec:
  selector:
    app: api-v1
  ports:
    - name: http
      port: 80
      targetPort: 5678
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-v2
  namespace: gateway-lab
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-v2
  template:
    metadata:
      labels:
        app: api-v2
    spec:
      containers:
        - name: api-v2
          image: hashicorp/http-echo:1.0
          args:
            - "-text=Hello from API v2"
          ports:
            - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: api-v2
  namespace: gateway-lab
spec:
  selector:
    app: api-v2
  ports:
    - name: http
      port: 80
      targetPort: 5678
```

Apply:

```bash
kubectl apply -f 01-apps.yaml
```

Check:

```bash
kubectl get pods,svc -n gateway-lab
```

Expected:

```text
pod/web-...
pod/api-v1-...
pod/api-v2-...

service/web
service/api-v1
service/api-v2
```

---

# 9. GatewayClass and Gateway

Create `02-gateway.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gateway
  namespace: gateway-lab
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "*.demo.local"
      allowedRoutes:
        namespaces:
          from: Same
```

Apply:

```bash
kubectl apply -f 02-gateway.yaml
```

Check:

```bash
kubectl get gatewayclass
kubectl get gateway -n gateway-lab
kubectl describe gateway shared-gateway -n gateway-lab
```

You want to see conditions like:

```text
Accepted=True
Programmed=True
```

Meaning:

```text
Accepted=True   -> controller accepted the Gateway config
Programmed=True -> controller has programmed the data plane
```

---

# 10. Basic HTTPRoute: path-based routing

Create `03-httproute-basic.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-route
  namespace: gateway-lab
spec:
  parentRefs:
    - name: shared-gateway
      sectionName: http
  hostnames:
    - app.demo.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: api-v1
          port: 80

    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: web
          port: 80
```

Apply:

```bash
kubectl apply -f 03-httproute-basic.yaml
```

Check:

```bash
kubectl get httproute -n gateway-lab
kubectl describe httproute app-route -n gateway-lab
```

Expected condition:

```text
Accepted=True
ResolvedRefs=True
```

Meaning:

```text
Accepted=True     -> Route attached to Gateway
ResolvedRefs=True -> backend Service references are valid
```

---

# 11. Test the Gateway

Get the Envoy service created for this Gateway:

```bash
export ENVOY_SERVICE=$(kubectl get svc \
  -n envoy-gateway-system \
  --selector=gateway.envoyproxy.io/owning-gateway-namespace=gateway-lab,gateway.envoyproxy.io/owning-gateway-name=shared-gateway \
  -o jsonpath='{.items[0].metadata.name}')
```

Port-forward it:

```bash
kubectl -n envoy-gateway-system port-forward service/${ENVOY_SERVICE} 8888:80
```

In another terminal:

```bash
curl -H "Host: app.demo.local" http://localhost:8888/
curl -H "Host: app.demo.local" http://localhost:8888/api
```

Expected:

```text
Hello from WEB
Hello from API v1
```

Traffic flow:

```text
curl
  -> localhost:8888
  -> Envoy Gateway data plane
  -> Gateway listener http:80
  -> HTTPRoute app-route
  -> Service web or api-v1
  -> Pod
```

---

# 12. Traffic splitting: 80% API v1, 20% API v2

Now replace the `/api` rule with weighted backends.

Create `04-httproute-split.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-route
  namespace: gateway-lab
spec:
  parentRefs:
    - name: shared-gateway
      sectionName: http
  hostnames:
    - app.demo.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: api-v1
          port: 80
          weight: 80
        - name: api-v2
          port: 80
          weight: 20

    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: web
          port: 80
```

Apply:

```bash
kubectl apply -f 04-httproute-split.yaml
```

Test:

```bash
for i in {1..20}; do
  curl -s -H "Host: app.demo.local" http://localhost:8888/api
done
```

Expected approximate result:

```text
Most responses: Hello from API v1
Some responses: Hello from API v2
```

This is the Gateway API-native way to do basic canary routing.

No NGINX-specific annotation.

No controller-specific `canary-weight`.

Just standard `backendRefs.weight`.

---

# 13. Header-based routing

Now route requests with this header to API v2:

```text
x-api-version: v2
```

Create `05-httproute-header.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-route
  namespace: gateway-lab
spec:
  parentRefs:
    - name: shared-gateway
      sectionName: http
  hostnames:
    - app.demo.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
          headers:
            - type: Exact
              name: x-api-version
              value: v2
      backendRefs:
        - name: api-v2
          port: 80

    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: api-v1
          port: 80

    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: web
          port: 80
```

Apply:

```bash
kubectl apply -f 05-httproute-header.yaml
```

Test normal request:

```bash
curl -H "Host: app.demo.local" http://localhost:8888/api
```

Expected:

```text
Hello from API v1
```

Test header-based request:

```bash
curl \
  -H "Host: app.demo.local" \
  -H "x-api-version: v2" \
  http://localhost:8888/api
```

Expected:

```text
Hello from API v2
```

This is useful for:

```text
beta users
mobile app version routing
internal testing
A/B experiments
migration by client capability
```

---

# 14. Request header modification

Gateway API can also apply filters.

Example: add a request header before sending to backend.

Create `06-httproute-header-modifier.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-route
  namespace: gateway-lab
spec:
  parentRefs:
    - name: shared-gateway
      sectionName: http
  hostnames:
    - app.demo.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - name: x-gateway-api-lab
                value: enabled
      backendRefs:
        - name: api-v1
          port: 80

    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: web
          port: 80
```

Apply:

```bash
kubectl apply -f 06-httproute-header-modifier.yaml
```

The backend now receives:

```text
x-gateway-api-lab: enabled
```

In a real app, this is useful for:

```text
tenant metadata
gateway identity
trace propagation
migration signals
security context propagation
```

---

# 15. HTTPS / TLS termination

Now let the Gateway terminate TLS.

Create a self-signed cert:

```bash
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout app.demo.local.key \
  -out app.demo.local.crt \
  -subj "/CN=app.demo.local/O=gateway-lab"
```

Create a TLS Secret:

```bash
kubectl create secret tls app-demo-local-tls \
  -n gateway-lab \
  --cert=app.demo.local.crt \
  --key=app.demo.local.key
```

Create `07-gateway-tls.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gateway
  namespace: gateway-lab
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "*.demo.local"
      allowedRoutes:
        namespaces:
          from: Same

    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.demo.local"
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: app-demo-local-tls
      allowedRoutes:
        namespaces:
          from: Same
```

Apply:

```bash
kubectl apply -f 07-gateway-tls.yaml
```

Update route to attach to HTTPS listener if desired:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-route
  namespace: gateway-lab
spec:
  parentRefs:
    - name: shared-gateway
      sectionName: https
  hostnames:
    - app.demo.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: api-v1
          port: 80

    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: web
          port: 80
```

Then port-forward the HTTPS port. First find the Envoy service:

```bash
kubectl get svc -n envoy-gateway-system
```

Port-forward service port `443` to local `8443`:

```bash
kubectl -n envoy-gateway-system port-forward service/${ENVOY_SERVICE} 8443:443
```

Test:

```bash
curl -k -H "Host: app.demo.local" https://localhost:8443/
curl -k -H "Host: app.demo.local" https://localhost:8443/api
```

Expected:

```text
Hello from WEB
Hello from API v1
```

TLS flow:

```text
Client HTTPS
  -> Gateway HTTPS listener
  -> TLS terminated at Gateway
  -> HTTPRoute
  -> backend Service over HTTP
```

For production, you normally combine Gateway API with cert-manager instead of manually creating TLS Secrets.

---

# 16. Cross-namespace routing

This is one of Gateway API’s strongest features.

Imagine this model:

```text
Namespace: platform
  Gateway: shared-public-gateway

Namespace: payments
  HTTPRoute: payments-route
  Service: payments-api

Namespace: orders
  HTTPRoute: orders-route
  Service: orders-api
```

The platform team owns the shared Gateway.

App teams own their own Routes.

Example platform Gateway:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: public-gateway
  namespace: platform
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "*.example.com"
      allowedRoutes:
        namespaces:
          from: All
```

Then an app team can create this in `payments` namespace:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: payments-route
  namespace: payments
spec:
  parentRefs:
    - name: public-gateway
      namespace: platform
      sectionName: http
  hostnames:
    - payments.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: payments-api
          port: 80
```

The important field is:

```yaml
parentRefs:
  - name: public-gateway
    namespace: platform
```

That means:

```text
This HTTPRoute lives in payments namespace,
but wants to attach to a Gateway in platform namespace.
```

The Gateway listener must allow that route attachment. The HTTPRoute documentation notes that the target Gateway must allow HTTPRoutes from the route’s namespace for attachment to succeed. ([Gateway API][3])

---

# 17. ReferenceGrant

`ReferenceGrant` controls cross-namespace backend references.

Example problem:

```text
HTTPRoute namespace: frontend
Backend Service namespace: backend
```

By default, arbitrary cross-namespace references are not automatically trusted. The backend namespace should explicitly allow the reference.

Create this in the **backend namespace**:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: ReferenceGrant
metadata:
  name: allow-frontend-routes
  namespace: backend
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: frontend
  to:
    - group: ""
      kind: Service
```

Then this route in `frontend` namespace may reference a Service in `backend`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: frontend-route
  namespace: frontend
spec:
  parentRefs:
    - name: public-gateway
      namespace: platform
  rules:
    - backendRefs:
        - name: backend-api
          namespace: backend
          port: 80
```

This is a clean security model:

```text
The referencing namespace cannot unilaterally consume backends.
The backend namespace must grant permission.
```

---

# 18. Gateway API traffic flow in detail

For this request:

```bash
curl -H "Host: app.demo.local" http://localhost:8888/api/users
```

The flow is:

```text
1. Client sends HTTP request.

2. Envoy Gateway data plane receives request.

3. Gateway listener checks:
   - protocol: HTTP
   - port: 80
   - hostname: *.demo.local

4. HTTPRoute attachment is evaluated:
   - parentRefs points to shared-gateway
   - hostname app.demo.local matches
   - route is accepted

5. HTTPRoute rule matching:
   - /api/users matches PathPrefix /api

6. BackendRef selected:
   - api-v1:80

7. Kubernetes Service api-v1 resolves endpoints.

8. Traffic reaches one api-v1 Pod.
```

---

# 19. Debugging Gateway API

## Check installed CRDs

```bash
kubectl get crds | grep gateway.networking.k8s.io
```

Expected resources include things like:

```text
gatewayclasses.gateway.networking.k8s.io
gateways.gateway.networking.k8s.io
httproutes.gateway.networking.k8s.io
referencegrants.gateway.networking.k8s.io
```

The Gateway API standard channel includes resources that have graduated to GA or beta, including `GatewayClass`, `Gateway`, `HTTPRoute`, and `ReferenceGrant`. ([Gateway API][4])

---

## Check GatewayClass

```bash
kubectl get gatewayclass
kubectl describe gatewayclass eg
```

Look for:

```text
Accepted=True
```

If `GatewayClass` is not accepted, your controller name may be wrong or your controller is not running.

---

## Check Gateway

```bash
kubectl get gateway -n gateway-lab
kubectl describe gateway shared-gateway -n gateway-lab
```

Look for:

```text
Accepted=True
Programmed=True
```

Common problems:

```text
Wrong gatewayClassName
Gateway controller not installed
Listener invalid
TLS secret missing
Hostname conflict
Port not supported by implementation
```

---

## Check HTTPRoute

```bash
kubectl get httproute -n gateway-lab
kubectl describe httproute app-route -n gateway-lab
```

Look for:

```text
Accepted=True
ResolvedRefs=True
```

Common problems:

```text
Wrong parentRefs.name
Wrong parentRefs.namespace
Wrong sectionName
Gateway listener does not allow routes from this namespace
Backend Service does not exist
Backend Service port is wrong
Cross-namespace backend missing ReferenceGrant
Hostname does not match listener hostname
```

---

## Check backend Services

```bash
kubectl get svc -n gateway-lab
kubectl get endpoints -n gateway-lab
kubectl get endpointslices -n gateway-lab
```

If the Route is accepted but traffic returns 503, your Service may have no endpoints.

Check labels:

```bash
kubectl get pods -n gateway-lab --show-labels
kubectl describe svc api-v1 -n gateway-lab
```

Common issue:

```yaml
Service selector:
  app: api
```

But Pod label:

```yaml
app: api-v1
```

Result:

```text
Service has no endpoints.
Gateway routes correctly.
Backend has nowhere to send traffic.
```

---

## Check Envoy Gateway controller

```bash
kubectl get pods -n envoy-gateway-system
kubectl logs -n envoy-gateway-system deployment/envoy-gateway
```

Check generated Envoy service:

```bash
kubectl get svc -n envoy-gateway-system
```

For Envoy Gateway, the quickstart shows getting the data-plane Service using labels derived from the owning Gateway namespace and name. ([Envoy Gateway][5])

---

# 20. Common failure modes

## Problem: `HTTPRoute` is not attached

Symptoms:

```text
HTTPRoute Accepted=False
```

Likely causes:

```text
parentRefs.name is wrong
parentRefs.namespace is wrong
sectionName does not match listener name
Gateway listener allowedRoutes rejects this namespace
hostname does not match listener hostname
```

Fix:

```bash
kubectl describe httproute app-route -n gateway-lab
kubectl describe gateway shared-gateway -n gateway-lab
```

---

## Problem: `ResolvedRefs=False`

Likely causes:

```text
backend Service does not exist
backend Service port does not exist
cross-namespace Service reference lacks ReferenceGrant
TLS Secret does not exist
invalid certificate reference
```

Fix:

```bash
kubectl get svc -n gateway-lab
kubectl describe httproute app-route -n gateway-lab
```

---

## Problem: Gateway has no address

Symptoms:

```bash
kubectl get gateway -n gateway-lab
```

Shows:

```text
ADDRESS <empty>
```

Likely causes:

```text
No LoadBalancer support in local cluster
Gateway controller cannot provision data plane
Cloud provider integration missing
MetalLB missing in bare-metal cluster
```

For local labs, use port-forwarding.

---

## Problem: 404

Usually:

```text
Gateway received request, but no Route matched.
```

Check:

```text
Host header
Path
HTTPRoute hostnames
Gateway listener hostname
```

Test explicitly:

```bash
curl -H "Host: app.demo.local" http://localhost:8888/
```

---

## Problem: 503

Usually:

```text
Route matched, but backend is unavailable.
```

Check:

```bash
kubectl get endpoints -n gateway-lab
kubectl get pods -n gateway-lab
kubectl describe svc api-v1 -n gateway-lab
```

---

# 21. Production design guidance

## Use one shared Gateway per exposure boundary

Good pattern:

```text
public-gateway
internal-gateway
partner-gateway
mesh-gateway
```

Avoid one Gateway per app unless you have a strong reason.

Better:

```text
platform namespace:
  public-gateway

app namespaces:
  HTTPRoute per app/team
```

---

## Keep Gateway ownership with platform team

Platform team controls:

```text
GatewayClass
Gateway
external addresses
listeners
TLS defaults
allowed route namespaces
global policies
observability
WAF / auth / rate limiting integration
```

Application team controls:

```text
HTTPRoute
hostnames
paths
backend Services
canary weights
app-level redirects
header matching
```

This separation is one of Gateway API’s biggest advantages.

---

## Prefer standard fields over implementation-specific extensions

Good:

```yaml
backendRefs:
  - name: api-v1
    port: 80
    weight: 90
  - name: api-v2
    port: 80
    weight: 10
```

Less portable:

```yaml
metadata:
  annotations:
    some-controller.io/canary-weight: "10"
```

Gateway API still has implementation-specific extensions, but use standard API fields first.

---

## Use `allowedRoutes` deliberately

Restrictive:

```yaml
allowedRoutes:
  namespaces:
    from: Same
```

More flexible:

```yaml
allowedRoutes:
  namespaces:
    from: Selector
    selector:
      matchLabels:
        shared-gateway-access: "true"
```

Very open:

```yaml
allowedRoutes:
  namespaces:
    from: All
```

For production multi-tenant clusters, prefer `Selector` over `All`.

---

## Use `ReferenceGrant` for cross-namespace trust

Do not allow random namespaces to route to sensitive Services.

Example:

```text
payments namespace should explicitly grant who can reference payments-api.
```

This prevents accidental or malicious traffic binding across namespace boundaries.

---

# 22. Gateway API and service mesh

Gateway API is also relevant for service mesh.

Examples:

```text
Istio supports Gateway API
Linkerd has Gateway API-related integrations
Envoy Gateway implements Gateway API
Cloud providers implement Gateway API
```

In the future, you may see one API family used for:

```text
north-south traffic:
  internet -> cluster

east-west traffic:
  service -> service

mesh ingress:
  external -> mesh workloads

mesh routing:
  internal traffic policies
```

But implementation maturity varies by controller.

Always check your controller’s Gateway API conformance and supported features.

---

# 23. Clean up lab

Delete lab resources:

```bash
kubectl delete namespace gateway-lab
```

Delete Envoy Gateway:

```bash
helm uninstall eg -n envoy-gateway-system
```

Optionally delete namespace:

```bash
kubectl delete namespace envoy-gateway-system
```

---

# 24. Compact senior-engineer summary

Gateway API gives Kubernetes a better networking abstraction than classic Ingress.

The key objects are:

```text
GatewayClass
  Defines the gateway implementation type.

Gateway
  Defines listeners: protocol, port, hostname, TLS, allowed routes.

HTTPRoute
  Defines app routing: hostnames, paths, headers, filters, backendRefs.

Service
  Stable backend target.

ReferenceGrant
  Explicit cross-namespace permission.
```

The key architectural improvement is ownership separation:

```text
Platform team owns Gateway.
Application teams own Routes.
```

The key operational improvement is expressive routing:

```text
Path routing
Host routing
Header routing
Weighted canary
TLS termination
Cross-namespace delegation
Request/response filters
gRPC/TLS/TCP routing depending on resource and implementation
```

The key debugging flow is:

```bash
kubectl describe gatewayclass
kubectl describe gateway
kubectl describe httproute
kubectl get svc,endpoints,endpointslices
kubectl logs -n <controller-namespace> <controller>
```

The most important conditions are:

```text
GatewayClass Accepted
Gateway Accepted
Gateway Programmed
HTTPRoute Accepted
HTTPRoute ResolvedRefs
```

For modern platform engineering, Gateway API is the object model you should learn after Ingress.

[1]: https://github.com/kubernetes-sigs/gateway-api "GitHub - kubernetes-sigs/gateway-api: Repository for the next iteration of composite service (e.g. Ingress) and load balancing APIs. · GitHub"
[2]: https://gateway-api.sigs.k8s.io/concepts/api-overview/ "API Overview - Kubernetes Gateway API"
[3]: https://gateway-api.sigs.k8s.io/api-types/httproute/ "HTTPRoute - Kubernetes Gateway API"
[4]: https://gateway-api.sigs.k8s.io/guides/getting-started/introduction/ "Getting started with Gateway API | Gateway API"
[5]: https://gateway.envoyproxy.io/docs/tasks/quickstart/ "Quickstart | Envoy Gateway"
