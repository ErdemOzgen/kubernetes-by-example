# Kubernetes ServiceAccount notes

A **Kubernetes ServiceAccount** is an identity for a workload running inside Kubernetes.

Humans usually authenticate to Kubernetes with users such as:

```text
erdem
admin
ci-user
```

Pods authenticate with **ServiceAccounts**.

So the mental model is:

```text
User Account        = identity for humans or external clients
ServiceAccount     = identity for Pods / apps / controllers inside Kubernetes
```

---

## Why ServiceAccounts exist

A Pod may need to talk to the Kubernetes API.

Examples:

```text
A CI/CD runner creates Deployments
A controller watches Pods
An operator manages custom resources
A backup job lists PVCs
A security scanner reads workloads
An app reads ConfigMaps or Secrets from the API
```

Instead of giving the Pod your own admin credentials, Kubernetes gives the Pod a **ServiceAccount identity**.

Then RBAC decides what that identity can do.

---

# Simple example

Create a namespace:

```bash
kubectl create ns app-dev
```

Create a ServiceAccount:

```bash
kubectl -n app-dev create serviceaccount my-app-sa
```

Use it in a Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: app-dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      serviceAccountName: my-app-sa
      containers:
        - name: my-app
          image: nginx
```

Now the Pod runs as this Kubernetes identity:

```text
system:serviceaccount:app-dev:my-app-sa
```

That identity means:

```text
ServiceAccount name: my-app-sa
Namespace: app-dev
Full Kubernetes username: system:serviceaccount:app-dev:my-app-sa
```

---

# Every namespace has a default ServiceAccount

When you create a namespace, Kubernetes automatically creates a ServiceAccount named `default`.

Check:

```bash
kubectl -n app-dev get serviceaccounts
```

Output:

```text
NAME      SECRETS   AGE
default   0         ...
```

If your Pod does not specify a ServiceAccount, it uses the namespace’s `default` ServiceAccount.

This Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: app-dev
spec:
  replicas: 1
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
          image: nginx
```

implicitly becomes:

```yaml
spec:
  serviceAccountName: default
```

Senior advice: do not rely on the `default` ServiceAccount for real apps. Create explicit ServiceAccounts per app.

---

# ServiceAccount does not automatically mean permission

This is very important.

A ServiceAccount is only an **identity**.

RBAC gives that identity **permissions**.

```text
ServiceAccount = who am I?
RBAC            = what can I do?
```

By default, a normal ServiceAccount has very limited or no useful permissions.

For example, this may fail:

```bash
kubectl auth can-i list pods \
  --as=system:serviceaccount:app-dev:my-app-sa \
  -n app-dev
```

Output may be:

```text
no
```

To allow it, you need a `Role` and `RoleBinding`.

---

# Example: allow ServiceAccount to read Pods

Create a Role:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: app-dev
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
```

Create a RoleBinding:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: my-app-sa-pod-reader
  namespace: app-dev
subjects:
  - kind: ServiceAccount
    name: my-app-sa
    namespace: app-dev
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

Apply:

```bash
kubectl apply -f rbac.yaml
```

Now check:

```bash
kubectl auth can-i list pods \
  --as=system:serviceaccount:app-dev:my-app-sa \
  -n app-dev
```

Expected:

```text
yes
```

---

# ServiceAccount token

When a Pod uses a ServiceAccount, Kubernetes can provide it with a token.

Inside the Pod, the token is usually mounted at:

```text
/var/run/secrets/kubernetes.io/serviceaccount/token
```

Also mounted:

```text
/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
/var/run/secrets/kubernetes.io/serviceaccount/namespace
```

The app can use these to call the Kubernetes API.

Example from inside a Pod:

```bash
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)

curl -k \
  -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/$NAMESPACE/pods
```

Whether this works depends on RBAC permissions.

---

# Disabling automatic token mount

Most applications do **not** need to call the Kubernetes API.

For those apps, disable automatic token mounting:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: app-dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      serviceAccountName: my-app-sa
      automountServiceAccountToken: false
      containers:
        - name: my-app
          image: nginx
```

This is a good security practice.

Senior rule:

```text
If the Pod does not need Kubernetes API access, set automountServiceAccountToken: false.
```

You can also set it on the ServiceAccount itself:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  namespace: app-dev
automountServiceAccountToken: false
```

---

# Namespace relationship

ServiceAccounts are namespace-scoped.

This means:

```bash
kubectl -n app-dev create sa my-app-sa
kubectl -n app-prod create sa my-app-sa
```

These are two different ServiceAccounts:

```text
system:serviceaccount:app-dev:my-app-sa
system:serviceaccount:app-prod:my-app-sa
```

Same name, different namespace, different identity.

---

# Common use cases

## 1. Application with no Kubernetes API access

Most normal web apps should use this pattern:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: webapp-sa
  namespace: app-dev
automountServiceAccountToken: false
```

Then:

```yaml
spec:
  serviceAccountName: webapp-sa
  automountServiceAccountToken: false
```

Use this for:

```text
Frontend apps
Backend REST APIs
Worker services
Normal microservices
```

Unless they explicitly need the Kubernetes API.

---

## 2. App that needs to read Pods

Example: monitoring sidecar, internal dashboard, diagnostic tool.

Give only read access:

```yaml
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
```

Do not give `create`, `update`, `delete` unless needed.

---

## 3. CI/CD runner inside Kubernetes

Example: GitLab Runner, Jenkins agent, Argo workflow executor.

It may need to create Deployments, Services, ConfigMaps, Jobs, or Pods.

Example permissions:

```yaml
rules:
  - apiGroups: ["", "apps", "batch"]
    resources:
      - pods
      - services
      - configmaps
      - secrets
      - deployments
      - jobs
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete
```

But scope it to only the namespace where it deploys.

Bad:

```text
cluster-admin for CI
```

Better:

```text
RoleBinding in app-dev only
RoleBinding in app-staging only
Manual approval for prod
```

---

## 4. Kubernetes controller/operator

Controllers and operators usually need wider permissions because they watch and reconcile resources.

Examples:

```text
cert-manager
external-dns
ingress controller
Argo CD
Prometheus operator
Custom operators
```

These often use ServiceAccounts with `ClusterRole` or `ClusterRoleBinding`.

That is normal for infrastructure components, but dangerous for application workloads.

---

# ServiceAccount vs Kubernetes User

Kubernetes does not store normal users as API objects.

There is no:

```bash
kubectl get users
```

But ServiceAccounts are real Kubernetes objects:

```bash
kubectl get serviceaccounts -A
```

Comparison:

| Concept               |                Human user |                             ServiceAccount |
| --------------------- | ------------------------: | -----------------------------------------: |
| Used by               | Humans / external systems |                           Pods / workloads |
| Kubernetes API object |                Usually no |                                        Yes |
| Namespace-scoped      |                        No |                                        Yes |
| Identity format       |  Depends on auth provider | `system:serviceaccount:<namespace>:<name>` |
| Controlled by RBAC    |                       Yes |                                        Yes |
| Common use            |    Admin/developer access |                      App/controller access |

---

# ServiceAccount vs Secret

Do not confuse them.

```text
ServiceAccount = identity
Secret         = sensitive data object
```

Older Kubernetes versions automatically created Secret-based ServiceAccount tokens. Modern Kubernetes uses short-lived projected tokens by default. In daily usage, you usually do not manually manage ServiceAccount token Secrets unless you have a specific legacy or integration need.

For your k3d development cluster, you mostly need:

```bash
kubectl create sa my-app-sa -n app-dev
```

and then reference it from your Deployment.

---

# How to inspect a Pod’s ServiceAccount

List Pods:

```bash
kubectl -n app-dev get pods
```

Inspect one Pod:

```bash
kubectl -n app-dev get pod <pod-name> -o jsonpath='{.spec.serviceAccountName}'
```

Or:

```bash
kubectl -n app-dev describe pod <pod-name>
```

Look for:

```text
Service Account: my-app-sa
```

Check mounted token:

```bash
kubectl -n app-dev exec -it <pod-name> -- ls /var/run/secrets/kubernetes.io/serviceaccount
```

If token mounting is enabled, you should see:

```text
ca.crt
namespace
token
```

---

# How to test ServiceAccount permissions

This is one of the most useful commands:

```bash
kubectl auth can-i list pods \
  --as=system:serviceaccount:app-dev:my-app-sa \
  -n app-dev
```

Other examples:

```bash
kubectl auth can-i get secrets \
  --as=system:serviceaccount:app-dev:my-app-sa \
  -n app-dev

kubectl auth can-i create deployments \
  --as=system:serviceaccount:app-dev:my-app-sa \
  -n app-dev

kubectl auth can-i '*' '*' \
  --as=system:serviceaccount:app-dev:my-app-sa \
  -n app-dev
```

If this returns `yes` for too many things, your RBAC is too permissive.

---

# Practical secure default for your apps

For normal apps in your k3d cluster, use this:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  namespace: app-dev
automountServiceAccountToken: false
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: app-dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      serviceAccountName: my-app-sa
      automountServiceAccountToken: false
      containers:
        - name: my-app
          image: dev-registry:5000/my-app:dev
```

This gives the Pod an explicit identity but prevents unnecessary Kubernetes API token exposure.

---

# Practical example with API access

Use this only when the app really needs to list Pods.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-reader-sa
  namespace: app-dev
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: app-dev
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-sa-binding
  namespace: app-dev
subjects:
  - kind: ServiceAccount
    name: pod-reader-sa
    namespace: app-dev
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pod-reader-app
  namespace: app-dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pod-reader-app
  template:
    metadata:
      labels:
        app: pod-reader-app
    spec:
      serviceAccountName: pod-reader-sa
      containers:
        - name: app
          image: curlimages/curl
          command: ["sleep", "3600"]
```

Apply:

```bash
kubectl apply -f pod-reader.yaml
```

Test:

```bash
kubectl auth can-i list pods \
  --as=system:serviceaccount:app-dev:pod-reader-sa \
  -n app-dev
```

Expected:

```text
yes
```

---

# Senior best practices

Use one ServiceAccount per workload:

```text
api-sa
worker-sa
scanner-sa
controller-sa
```

Avoid sharing one powerful ServiceAccount across many apps.

Disable token mount unless needed:

```yaml
automountServiceAccountToken: false
```

Use namespace-scoped `Role` and `RoleBinding` instead of `ClusterRoleBinding` when possible.

Never give normal apps `cluster-admin`.

Avoid allowing apps to read Secrets unless absolutely necessary.

Audit permissions with:

```bash
kubectl auth can-i
```

Keep ServiceAccounts in the same namespace as their workloads.

Use clear names:

```text
payment-api-sa
inventory-worker-sa
vulnerability-scanner-sa
```

not:

```text
admin
default
test
sa1
```

---

# In one sentence

A **ServiceAccount** is the Kubernetes identity assigned to a Pod; by itself it only says “who the Pod is,” and RBAC decides what that Pod is allowed to do.
