See: https://kubernetes.io/docs/concepts/services-networking/ingress/
# Kubernetes Ingress 

## 1. What Ingress is

**Ingress** is a Kubernetes API object that defines **HTTP/HTTPS routing rules** from outside the cluster to internal Kubernetes `Service` objects.

Think of it as:

```text
External Client
      |
      v
LoadBalancer / NodePort / Cloud LB
      |
      v
Ingress Controller
      |
      v
Ingress Rules
      |
      v
Service
      |
      v
Pods
```

The important point:

> `Ingress` itself does not proxy traffic.

It is only a **declarative routing configuration**. The actual traffic handling is done by an **Ingress Controller**, such as NGINX, Traefik, HAProxy, Kong, Contour, cloud-provider ALB controllers, and others. Kubernetes documents Ingress as an API object for external HTTP access, and notes that it can provide host/path routing, load balancing, and TLS termination depending on the controller implementation. ([Kubernetes][1])

---

## 2. Problem Ingress solves

Without Ingress, you usually expose apps like this:

```yaml
Service type: LoadBalancer
```

For example:

```text
frontend-service     -> external LB 1
api-service          -> external LB 2
admin-service        -> external LB 3
grafana-service      -> external LB 4
```

This is expensive and operationally messy.

With Ingress:

```text
one external IP / load balancer
        |
        v
Ingress Controller
        |
        +-- app.example.com/        -> frontend-service
        +-- app.example.com/api     -> api-service
        +-- admin.example.com/      -> admin-service
        +-- grafana.example.com/    -> grafana-service
```

Ingress gives you **centralized L7 routing** for HTTP and HTTPS.

---

# 3. Ingress vs Service vs Ingress Controller

## Service

A `Service` gives stable networking inside the cluster.

Example:

```text
frontend-service.default.svc.cluster.local
```

It load-balances traffic to matching Pods.

```yaml
kind: Service
spec:
  selector:
    app: frontend
  ports:
    - port: 80
      targetPort: 8080
```

The Service knows **which Pods** to send traffic to.

---

## Ingress

An `Ingress` says:

```text
When HTTP Host is app.example.com
and path is /api
send traffic to api-service:80
```

Example:

```yaml
kind: Ingress
spec:
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api-service
                port:
                  number: 80
```

The Ingress knows **which Service** should receive which HTTP request.

---

## Ingress Controller

The `Ingress Controller` watches Kubernetes API objects and configures a real proxy/load balancer.

For NGINX, the controller roughly does this:

```text
Watch Ingress objects
Watch Services
Watch Endpoints / EndpointSlices
Generate NGINX config
Reload/apply proxy routing
Forward client traffic to Services/Pods
```

Kubernetes requires an ingress controller implementation for Ingress resources to have effect; multiple controllers can run in one cluster, selected using `ingressClassName`. ([Kubernetes][2])

---

# 4. Core Ingress fields

A modern Ingress usually contains these important fields:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example
spec:
  ingressClassName: nginx
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend
                port:
                  number: 80
```

## `ingressClassName`

This tells Kubernetes which controller should handle this Ingress.

```yaml
spec:
  ingressClassName: nginx
```

Older manifests often used this annotation:

```yaml
kubernetes.io/ingress.class: nginx
```

For modern Kubernetes, prefer:

```yaml
spec.ingressClassName
```

The Kubernetes documentation states that `ingressClassName` replaces the older annotation-based selection method. ([Kubernetes][2])

---

## `rules.host`

This is the HTTP `Host` header.

```yaml
host: app.example.com
```

This matches:

```bash
curl http://app.example.com
```

or:

```bash
curl -H "Host: app.example.com" http://<INGRESS_IP>
```

The Ingress controller uses the `Host` header to decide the backend.

---

## `paths.path`

This is the URL path.

```yaml
path: /api
```

Example request:

```text
GET /api/users HTTP/1.1
Host: app.example.com
```

Can match:

```yaml
path: /api
pathType: Prefix
```

---

## `pathType`

Kubernetes supports three common path types:

```yaml
pathType: Exact
pathType: Prefix
pathType: ImplementationSpecific
```

### `Exact`

Matches only the exact path.

```yaml
path: /api
pathType: Exact
```

Matches:

```text
/api
```

Does not match:

```text
/api/
/api/users
```

---

### `Prefix`

Matches based on URL path prefix.

```yaml
path: /api
pathType: Prefix
```

Matches:

```text
/api
/api/
/api/users
```

Usually this is the safest default for application routing.

---

### `ImplementationSpecific`

The behavior depends on the Ingress Controller.

```yaml
pathType: ImplementationSpecific
```

Avoid this unless you know the controller-specific behavior. It reduces portability.

---

# 5. Simple mental model

Ingress is like a reverse proxy routing table:

```text
Host: shop.example.com
Path: /
Backend: frontend-service:80

Host: shop.example.com
Path: /api
Backend: api-service:80

Host: admin.example.com
Path: /
Backend: admin-service:80
```

Equivalent NGINX-ish mental model:

```nginx
server {
    server_name shop.example.com;

    location /api {
        proxy_pass http://api-service;
    }

    location / {
        proxy_pass http://frontend-service;
    }
}

server {
    server_name admin.example.com;

    location / {
        proxy_pass http://admin-service;
    }
}
```

You do not write this NGINX config manually. The controller generates equivalent runtime configuration from Kubernetes resources.

---

# 6. Hands-on lab: two apps behind one Ingress

This lab deploys two apps:

```text
http://demo.local/       -> web app
http://demo.local/api    -> API app
```

We will create:

```text
Namespace
Deployment: web
Service: web
Deployment: api
Service: api
Ingress: demo-ingress
```

---

## 6.1 Prerequisites

You need:

```bash
kubectl
minikube
```

Start Minikube:

```bash
minikube start
```

Enable Ingress:

```bash
minikube addons enable ingress
```

For Docker Desktop users on macOS, Minikube documents that `minikube tunnel` may be required for Ingress to work; in that case, run it in a separate terminal and use `127.0.0.1` for local testing. ([minikube][3])

```bash
minikube tunnel
```

Check controller:

```bash
kubectl get pods -n ingress-nginx
```

You should see something like:

```text
ingress-nginx-controller-xxxxx   Running
```

---

# 7. Lab YAML: Namespace

Create `00-namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ingress-lab
```

Apply:

```bash
kubectl apply -f 00-namespace.yaml
```

---

# 8. Lab YAML: Web app

Create `01-web.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: ingress-lab
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
            - "-text=Hello from WEB service"
          ports:
            - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: ingress-lab
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: 5678
```

Apply:

```bash
kubectl apply -f 01-web.yaml
```

---

# 9. Lab YAML: API app

Create `02-api.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: ingress-lab
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: api
          image: hashicorp/http-echo:1.0
          args:
            - "-text=Hello from API service"
          ports:
            - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: ingress-lab
spec:
  type: ClusterIP
  selector:
    app: api
  ports:
    - name: http
      port: 80
      targetPort: 5678
```

Apply:

```bash
kubectl apply -f 02-api.yaml
```

---

# 10. Lab YAML: Ingress

Create `03-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-ingress
  namespace: ingress-lab
spec:
  ingressClassName: nginx
  rules:
    - host: demo.local
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 80
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 80
```

Apply:

```bash
kubectl apply -f 03-ingress.yaml
```

Check:

```bash
kubectl get ingress -n ingress-lab
```

Example:

```text
NAME           CLASS   HOSTS        ADDRESS        PORTS   AGE
demo-ingress   nginx   demo.local   192.168.49.2   80      20s
```

---

# 11. Test without editing `/etc/hosts`

Get the Ingress IP:

```bash
kubectl get ingress demo-ingress -n ingress-lab
```

Or:

```bash
minikube ip
```

Then test using `curl --resolve`.

On Linux or VM-based Minikube:

```bash
INGRESS_IP=$(minikube ip)

curl --resolve demo.local:80:$INGRESS_IP http://demo.local/
curl --resolve demo.local:80:$INGRESS_IP http://demo.local/api
```

Expected:

```text
Hello from WEB service
Hello from API service
```

On Docker Desktop macOS with `minikube tunnel`, use:

```bash
curl --resolve demo.local:80:127.0.0.1 http://demo.local/
curl --resolve demo.local:80:127.0.0.1 http://demo.local/api
```

Expected:

```text
Hello from WEB service
Hello from API service
```

---

# 12. What happened internally

When you applied the Ingress:

```bash
kubectl apply -f 03-ingress.yaml
```

The NGINX Ingress Controller watched the API server and saw:

```text
Ingress: demo-ingress
Host: demo.local
Path: /api -> Service api:80
Path: /    -> Service web:80
```

Then it resolved:

```text
Service api -> Pods with label app=api
Service web -> Pods with label app=web
```

The runtime flow became:

```text
curl http://demo.local/api
        |
        v
Ingress Controller
        |
        v
Ingress rule: host demo.local, path /api
        |
        v
Service: api
        |
        v
One of the api Pods
```

And:

```text
curl http://demo.local/
        |
        v
Ingress Controller
        |
        v
Ingress rule: host demo.local, path /
        |
        v
Service: web
        |
        v
One of the web Pods
```

---

# 13. Important production detail: Ingress does not replace Service

Ingress always routes to a `Service`.

This is wrong:

```yaml
backend:
  pod:
    name: my-pod
```

Ingress does not route directly to Pods in normal usage.

Correct:

```yaml
backend:
  service:
    name: web
    port:
      number: 80
```

Why?

Because Pods are ephemeral:

```text
Pod IPs change
Pods scale up/down
Pods restart
Deployments replace Pods
```

The Service provides stable discovery and load balancing.

---

# 14. Host-based routing

You can route multiple domains to different services.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: host-routing
  namespace: ingress-lab
spec:
  ingressClassName: nginx
  rules:
    - host: web.demo.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 80
    - host: api.demo.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 80
```

Traffic:

```text
web.demo.local -> web service
api.demo.local -> api service
```

Test:

```bash
INGRESS_IP=$(minikube ip)

curl --resolve web.demo.local:80:$INGRESS_IP http://web.demo.local/
curl --resolve api.demo.local:80:$INGRESS_IP http://api.demo.local/
```

---

# 15. Path-based routing

One host, multiple paths:

```yaml
rules:
  - host: app.demo.local
    http:
      paths:
        - path: /api
          pathType: Prefix
          backend:
            service:
              name: api
              port:
                number: 80
        - path: /
          pathType: Prefix
          backend:
            service:
              name: web
              port:
                number: 80
```

Traffic:

```text
app.demo.local/       -> web
app.demo.local/api    -> api
```

Be careful with backend apps. Some apps expect to run at `/`, not `/api`.

That creates a common problem.

---

# 16. Common issue: `/api` path is forwarded as `/api`

Ingress does not automatically strip `/api`.

Request:

```text
GET /api/users
```

Backend receives:

```text
/api/users
```

Not:

```text
/users
```

If your API expects `/users`, you need either:

1. Configure the app to serve under `/api`
2. Use controller-specific rewrite rules
3. Use Gateway API / service mesh / app-level routing depending on architecture

For NGINX Ingress, URI rewriting is done with annotations such as `nginx.ingress.kubernetes.io/rewrite-target`, but annotations are controller-specific and reduce portability. The ingress-nginx documentation describes `rewrite-target` as the annotation used when the exposed URL differs from the backend’s expected path. ([GitHub][4])

Example NGINX-specific rewrite:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-rewrite
  namespace: ingress-lab
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - host: rewrite.demo.local
      http:
        paths:
          - path: /api(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: api
                port:
                  number: 80
```

Request:

```text
/api/users
```

Backend receives:

```text
/users
```

Senior-engineer warning: rewrites are useful, but they couple your manifest to one controller. Prefer application-aware base paths where possible.

---

# 17. TLS termination

Ingress can terminate HTTPS.

Flow:

```text
Client HTTPS
    |
    v
Ingress Controller decrypts TLS
    |
    v
Backend Service receives HTTP
```

Example TLS Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-demo
  namespace: ingress-lab
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - demo.local
      secretName: demo-local-tls
  rules:
    - host: demo.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 80
```

The TLS Secret must exist:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: demo-local-tls
  namespace: ingress-lab
type: kubernetes.io/tls
data:
  tls.crt: <base64-cert>
  tls.key: <base64-key>
```

Create a local self-signed cert:

```bash
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout demo.local.key \
  -out demo.local.crt \
  -subj "/CN=demo.local/O=ingress-lab"
```

Create the Secret:

```bash
kubectl create secret tls demo-local-tls \
  --namespace ingress-lab \
  --cert demo.local.crt \
  --key demo.local.key
```

Apply the TLS Ingress.

Test:

```bash
INGRESS_IP=$(minikube ip)

curl -k --resolve demo.local:443:$INGRESS_IP https://demo.local/
```

For real production certificates, many clusters use cert-manager. cert-manager supports an `ingress-shim` flow where annotations on Ingress resources can trigger creation of `Certificate` resources. ([cert-manager][5])

Example with cert-manager:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: production-ingress
  namespace: ingress-lab
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - app.example.com
      secretName: app-example-com-tls
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 80
```

---

# 18. Default backend

A default backend handles requests that do not match any rule.

Example:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: default-backend-demo
  namespace: ingress-lab
spec:
  ingressClassName: nginx
  defaultBackend:
    service:
      name: web
      port:
        number: 80
```

This means:

```text
Any unmatched host/path -> web service
```

Use cases:

```text
custom 404 page
maintenance page
catch-all landing service
```

---

# 19. IngressClass

`IngressClass` is how you define available ingress controller classes.

Example:

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
spec:
  controller: k8s.io/ingress-nginx
```

Then your Ingress uses:

```yaml
spec:
  ingressClassName: nginx
```

This matters in clusters with multiple controllers:

```text
nginx public ingress
nginx internal ingress
aws alb ingress
traefik ingress
istio ingress
```

Example:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: public-app
spec:
  ingressClassName: public-nginx
```

Another:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: internal-app
spec:
  ingressClassName: internal-nginx
```

Same cluster, different exposure model.

---

# 20. Important production annotations

Annotations are controller-specific.

For NGINX Ingress, common examples are:

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60"
```

NGINX Ingress supports customization through ConfigMaps, annotations, and custom templates; annotations are per-Ingress configuration, while ConfigMaps usually affect global controller behavior. ([Kubernetes][6])

Example:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: upload-api
  namespace: ingress-lab
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
spec:
  ingressClassName: nginx
  rules:
    - host: upload.demo.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 80
```

Senior-engineer warning:

> Annotations are not portable across controllers.

This means an Ingress written for NGINX may not behave the same on Traefik, HAProxy, Kong, AWS ALB, Azure Application Gateway, or GCP load balancers.

---

# 21. Debugging Ingress

## Check Ingress object

```bash
kubectl get ingress -n ingress-lab
```

More detail:

```bash
kubectl describe ingress demo-ingress -n ingress-lab
```

Look for:

```text
Rules
Backends
Events
Address
IngressClass
```

---

## Check controller Pod

```bash
kubectl get pods -n ingress-nginx
```

Logs:

```bash
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller
```

---

## Check Service endpoints

If Ingress returns `503`, often the Service has no endpoints.

Check Service:

```bash
kubectl get svc -n ingress-lab
```

Check endpoints:

```bash
kubectl get endpoints -n ingress-lab
```

or newer:

```bash
kubectl get endpointslices -n ingress-lab
```

If endpoints are empty, your Service selector does not match your Pods.

Example problem:

```yaml
Service selector:
  app: api
```

But Pod labels:

```yaml
labels:
  app: backend
```

Result:

```text
Ingress -> Service -> no Pods -> 503
```

---

## Check backend Pods

```bash
kubectl get pods -n ingress-lab --show-labels
```

Test Service inside cluster:

```bash
kubectl run curl-test \
  -n ingress-lab \
  --image=curlimages/curl \
  --rm -it \
  --restart=Never \
  -- curl http://api
```

Expected:

```text
Hello from API service
```

---

## Test Host header manually

```bash
curl -H "Host: demo.local" http://$INGRESS_IP/
curl -H "Host: demo.local" http://$INGRESS_IP/api
```

This is useful because Ingress routing depends heavily on the HTTP `Host` header.

---

# 22. Common Ingress errors

## Error 1: Ingress has no address

```bash
kubectl get ingress -n ingress-lab
```

Shows:

```text
ADDRESS <empty>
```

Possible causes:

```text
Ingress controller not installed
Wrong ingressClassName
Controller cannot provision external load balancer
Local cluster needs tunnel or port-forward
```

---

## Error 2: 404 from Ingress controller

Usually means:

```text
Controller received request
but no host/path rule matched
```

Check:

```bash
curl -v http://$INGRESS_IP/
```

Make sure you send the correct host:

```bash
curl -H "Host: demo.local" http://$INGRESS_IP/
```

---

## Error 3: 503 from Ingress controller

Usually means:

```text
Rule matched
but backend Service has no healthy endpoints
```

Check:

```bash
kubectl get endpoints -n ingress-lab
kubectl get pods -n ingress-lab
kubectl describe svc api -n ingress-lab
```

---

## Error 4: TLS certificate mismatch

Usually means:

```text
Wrong secret
Wrong host in certificate
Wrong tls.hosts field
Default certificate served by controller
```

Check:

```bash
kubectl describe ingress tls-demo -n ingress-lab
kubectl get secret demo-local-tls -n ingress-lab
```

---

# 23. Senior-level design considerations

## Use Ingress for basic HTTP routing

Ingress is good for:

```text
HTTP routing
HTTPS termination
host-based routing
path-based routing
simple centralized exposure
```

---

## Be careful with complex traffic management

Ingress becomes awkward for:

```text
traffic splitting
header-based routing
weighted canary
advanced retries
advanced auth chains
cross-namespace routing
multi-team ownership
TCP/UDP routing
mTLS between gateway and backend
```

These features are usually controller-specific or require annotations, CRDs, or service mesh.

---

## Gateway API is the strategic future

For new platform-level designs, evaluate **Gateway API**. Kubernetes Gateway API documentation describes it as the successor to Ingress and the next-generation Kubernetes API for L4/L7 routing. ([Gateway API][7])

Ingress is still widely used and stable, but Gateway API gives a better resource model:

```text
GatewayClass -> infrastructure type
Gateway      -> actual listener / entry point
HTTPRoute    -> app/team-owned routing rule
```

Ingress model:

```text
Ingress
```

Gateway API model:

```text
GatewayClass
Gateway
HTTPRoute
GRPCRoute
TLSRoute
TCPRoute / UDPRoute depending on implementation
```

For learning Kubernetes networking, you should understand Ingress first. For modern platform engineering, you should also learn Gateway API after this.

---

# 24. Clean up lab

```bash
kubectl delete namespace ingress-lab
```

---

# 25. Compact summary

Ingress is:

```text
A Kubernetes HTTP/HTTPS routing object.
```

Ingress Controller is:

```text
The actual proxy/load balancer implementation.
```

Service is:

```text
The stable internal target for traffic.
```

Typical flow:

```text
Client
  -> External IP / LoadBalancer
  -> Ingress Controller
  -> Ingress rule
  -> Service
  -> Pod
```

Production rule of thumb:

```text
Use Ingress for simple HTTP/HTTPS exposure.
Use controller annotations carefully.
Use cert-manager for automated TLS.
Use Gateway API for new advanced platform designs.
```

[1]: https://kubernetes.io/docs/concepts/services-networking/ingress/"Ingress"
[2]: https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/"Ingress Controllers"
[3]: https://minikube.sigs.k8s.io/docs/start/"minikube start"
[4]: https://github.com/kubernetes/ingress-nginx/blob/main/docs/user-guide/nginx-configuration/annotations.md"Annotations.md"
[5]: https://cert-manager.io/docs/usage/ingress/"Annotated Ingress resource - cert-manager Documentation"
[6]: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/"Introduction - Ingress-Nginx Controller"
[7]: https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress/"Migrating from Ingress - Gateway API - Kubernetes"
