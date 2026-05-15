## Kubernetes namespace

A **Kubernetes namespace** is a logical partition inside one Kubernetes cluster. It gives you a scoped area for Kubernetes objects such as `Pods`, `Deployments`, `Services`, `ConfigMaps`, `Secrets`, `Roles`, `RoleBindings`, `ResourceQuotas`, and `LimitRanges`. Object names must be unique **inside the same namespace**, but the same object name can exist in different namespaces. For example, you can have `api` Deployment in both `dev` and `staging`. Namespaces apply only to namespaced objects; cluster wide objects like `Nodes`, `PersistentVolumes`, `StorageClass`, and `ClusterRole` are not inside a namespace. ([Kubernetes][1])

Think of a namespace as:

```text
One Kubernetes cluster
├── namespace: dev
│   ├── deployment/api
│   ├── service/api
│   ├── configmap/api-config
│   └── secret/api-secret
├── namespace: staging
│   ├── deployment/api
│   ├── service/api
│   ├── configmap/api-config
│   └── secret/api-secret
└── namespace: prod
    ├── deployment/api
    ├── service/api
    ├── configmap/api-config
    └── secret/api-secret
```

It is **not** the same thing as a Linux namespace. Kubernetes namespaces are Kubernetes API level organization and scoping constructs. Linux namespaces isolate processes, networking, mounts, users, and so on at the kernel level.

---

# 1. Why namespaces exist

Namespaces solve several practical problems.

## 1.1 Object name separation

Without namespaces, every object name in the cluster would collide.

With namespaces:

```bash
kubectl create namespace dev
kubectl create namespace staging
```

You can have:

```bash
kubectl -n dev get deploy api
kubectl -n staging get deploy api
```

Both can exist independently.

## 1.2 Environment separation

Common local or enterprise setup:

```text
dev
test
staging
prod
```

In your **k3d local setup**, this is very useful. You can simulate multiple environments inside the same local cluster:

```bash
kubectl create ns dev
kubectl create ns staging
kubectl create ns prod
```

Then deploy the same app into each namespace with different configs.

## 1.3 Team/project separation

Example:

```text
team-platform
team-security
team-payments
team-ml
```

Each team gets its own namespace, its own RBAC, quotas, secrets, and deployment ownership.

## 1.4 Resource governance

Namespaces are the unit where you usually apply `ResourceQuota` and `LimitRange`. A `ResourceQuota` limits aggregate resource consumption per namespace, including CPU, memory, object counts, storage claims, and other API resources. ([Kubernetes][2])

Example:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: dev-quota
  namespace: dev
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
    pods: "20"
    services: "10"
```

This prevents one namespace from consuming the entire cluster.

## 1.5 Access control

RBAC is usually namespace scoped with `Role` and `RoleBinding`. RBAC regulates access based on roles assigned to users, groups, or service accounts. ([Kubernetes][3])

Example:

```text
developer Alice can deploy only in namespace dev
CI pipeline can deploy only in namespace staging
production deploy requires separate permission
```

This is one of the most important production use cases.

## 1.6 Network segmentation

`NetworkPolicy` can control traffic between Pods. Policies can select Pods in the same namespace, and `namespaceSelector` can allow or deny traffic from selected namespaces. ([Kubernetes][4])

Example:

```text
frontend namespace can call backend namespace
backend namespace can call database namespace
random test namespace cannot call database namespace
```

Important: NetworkPolicy only works if your cluster CNI enforces it. K3s bundles Flannel and also includes a kube-router network policy controller, while still allowing components to be swapped or disabled. ([GitHub][5])

---

# 2. Default namespaces you will see

Run:

```bash
kubectl get namespaces
```

Typical output:

```text
NAME              STATUS   AGE
default           Active   ...
kube-node-lease   Active   ...
kube-public       Active   ...
kube-system       Active   ...
```

Kubernetes starts with four initial namespaces: `default`, `kube-node-lease`, `kube-public`, and `kube-system`. `kube-system` is for Kubernetes system components; `kube-node-lease` stores node heartbeat lease objects; `kube-public` is conventionally readable by all clients; `default` exists so you can start using the cluster immediately. ([Kubernetes][1])

For real work, avoid deploying applications into `default`. Create explicit namespaces.

Good:

```bash
kubectl create ns app-dev
kubectl create ns app-staging
kubectl create ns app-prod
```

Bad:

```bash
kubectl apply -f app.yaml
# Accidentally goes to default namespace
```

Also avoid creating namespaces with the `kube-` prefix because Kubernetes reserves that prefix for system namespaces. ([Kubernetes][1])

---

# 3. Namespaced vs cluster scoped resources

This is critical.

## Namespaced resources

These live inside a namespace:

```text
Pod
Deployment
ReplicaSet
StatefulSet
DaemonSet
Job
CronJob
Service
Ingress
ConfigMap
Secret
ServiceAccount
Role
RoleBinding
ResourceQuota
LimitRange
NetworkPolicy
PersistentVolumeClaim
```

Example:

```bash
kubectl -n dev get pods
kubectl -n dev get services
kubectl -n dev get secrets
```

## cluster scoped resources

These do **not** belong to any namespace:

```text
Node
Namespace
PersistentVolume
StorageClass
ClusterRole
ClusterRoleBinding
CustomResourceDefinition
IngressClass
PriorityClass
VolumeSnapshotClass
```

Example:

```bash
kubectl get nodes
kubectl get storageclass
kubectl get clusterrole
```

To check this directly:

```bash
kubectl api-resources --namespaced=true
kubectl api-resources --namespaced=false
```

Kubernetes explicitly distinguishes namespaced resources from cluster wide resources. ([Kubernetes][1])

---

# 4. Basic namespace commands

## List namespaces

```bash
kubectl get ns
kubectl get namespaces
```

## Create namespace

```bash
kubectl create namespace dev
```

Equivalent YAML:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dev
```

Apply:

```bash
kubectl apply -f namespace.yaml
```

## Delete namespace

```bash
kubectl delete namespace dev
```

Be careful: deleting a namespace deletes namespaced resources inside it.

## Use namespace for one command

```bash
kubectl -n dev get pods
kubectl --namespace dev get services
```

## Set default namespace for your current kubectl context

```bash
kubectl config set-context --current --namespace=dev
```

Verify:

```bash
kubectl config view --minify | grep namespace
```

Kubernetes supports setting namespace per request with `--namespace`, and also saving a namespace preference into the current context. ([Kubernetes][1])

## Return to default namespace

```bash
kubectl config set-context --current --namespace=default
```

## See all resources in a namespace

```bash
kubectl -n dev get all
```

But `get all` does **not** show literally everything. It misses things like `ConfigMap`, `Secret`, `Ingress`, `PVC`, `NetworkPolicy`, etc.

Better:

```bash
kubectl -n dev get deploy,po,svc,ingress,cm,secret,pvc,sa,role,rolebinding
```

Or exhaustive:

```bash
kubectl api-resources --verbs=list --namespaced -o name \
  | xargs -n 1 kubectl get --show-kind --ignore-not-found -n dev
```

---

# 5. Namespace in YAML manifests

Every namespaced object can include:

```yaml
metadata:
  namespace: dev
```

Example:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: dev
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
      containers:
        - name: my-app
          image: dev-registry:5000/my-app:dev
          ports:
            - containerPort: 8080
```

For your k3d setup, this image name is correct **inside Kubernetes**:

```yaml
image: dev-registry:5000/my-app:dev
```

From your WSL shell, you build/push with:

```bash
docker build -t localhost:5111/my-app:dev .
docker push localhost:5111/my-app:dev
```

Inside k3d/k3s, Pods pull using:

```text
dev-registry:5000/my-app:dev
```

That is because the registry container is reachable inside the k3d Docker network by its registry container name and internal port.

---

# 6. Service discovery and DNS across namespaces

When you create a Service, Kubernetes creates DNS records for it. Kubernetes Service DNS commonly follows this pattern:

```text
<service-name>.<namespace>.svc.cluster.local
```

The official docs describe Service DNS as `<service-name>.<namespace-name>.svc.cluster.local`; using only `<service-name>` resolves to a Service in the same namespace, while cross-namespace access requires the longer DNS name. ([Kubernetes][1])

Example:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: backend
spec:
  selector:
    app: api
  ports:
    - port: 80
      targetPort: 8080
```

From another Pod in namespace `backend`:

```bash
curl http://api
```

From namespace `frontend`:

```bash
curl http://api.backend.svc.cluster.local
```

Usually this shorter form also works:

```bash
curl http://api.backend
```

But for clarity in production manifests, use the fully qualified form when crossing namespaces.

---

# 7. Namespace isolation: what it does and does not do

This is where many engineers misunderstand Kubernetes.

## What namespace gives you

A namespace gives you:

```text
API object scoping
Name separation
RBAC scoping
ResourceQuota scoping
LimitRange scoping
NetworkPolicy scoping
ServiceAccount scoping
ConfigMap/Secret scoping
Operational ownership boundary
```

## What namespace does not automatically give you

A namespace does **not** automatically give you:

```text
Hard security isolation
Separate nodes
Separate control plane
Separate etcd
Separate network by default
Separate container runtime
Separate kernel
Automatic traffic blocking
Automatic secret protection from cluster admins
```

By default, Pods in different namespaces can usually talk to each other unless NetworkPolicy or service mesh policy blocks them.

By default, a cluster-admin can read everything across all namespaces.

By default, namespaces are not strong multi-tenant security boundaries by themselves. You need RBAC, NetworkPolicy, Pod Security Admission, admission policies, quotas, and usually separate clusters for high-trust isolation.

Senior rule:

```text
Namespace = logical/administrative boundary.
Namespace + RBAC + NetworkPolicy + quotas + admission control = useful soft multi-tenancy.
Separate cluster = stronger isolation boundary.
```

---

# 8. Namespace and RBAC

There are four common RBAC objects:

```text
Role               namespace scoped permissions
RoleBinding        binds Role/ClusterRole to user/group/serviceaccount inside namespace
ClusterRole        cluster scoped permission definition
ClusterRoleBinding binds permissions cluster wide
```

## Give a user read only access to namespace `dev`

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: dev
  name: dev-readonly
rules:
  - apiGroups: ["", "apps", "batch"]
    resources: ["pods", "services", "configmaps", "deployments", "jobs"]
    verbs: ["get", "list", "watch"]
```

Bind it:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: alice-dev-readonly
  namespace: dev
subjects:
  - kind: User
    name: alice@example.com
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: dev-readonly
  apiGroup: rbac.authorization.k8s.io
```

## Check permissions

```bash
kubectl auth can-i get pods -n dev
kubectl auth can-i delete deployments -n dev
kubectl auth can-i get secrets -n prod
```

For service accounts:

```bash
kubectl auth can-i get pods \
  --as=system:serviceaccount:dev:my-app \
  -n dev
```

Senior advice: never use `ClusterRoleBinding` when a `RoleBinding` is enough.

---

# 9. Namespace and ServiceAccount

A `ServiceAccount` is a non-human identity used by Pods, controllers, and applications to authenticate to the Kubernetes API. ([Kubernetes][6])

ServiceAccounts are namespaced:

```bash
kubectl -n dev create serviceaccount my-app
```

Use it in a Pod:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: dev
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
      serviceAccountName: my-app
      containers:
        - name: my-app
          image: dev-registry:5000/my-app:dev
```

If the application does not need Kubernetes API access, avoid giving it permissions. The default service account should usually have no useful privileges.

---

# 10. Namespace and Secrets

Secrets are namespaced.

This means:

```bash
kubectl -n dev create secret generic db-secret --from-literal=password=devpass
kubectl -n prod create secret generic db-secret --from-literal=password=prodpass
```

Both can exist with the same name, but they are different Secrets.

A Pod in `dev` cannot directly mount a Secret from `prod`.

This is good:

```yaml
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-secret
        key: password
```

This refers to `db-secret` in the **same namespace as the Pod**.

Senior warning: Kubernetes Secrets are not automatically “secure” just because they are called Secrets. They are base64-encoded API objects. In production, use RBAC strictly, enable encryption at rest, and consider external secret managers.

---

# 11. Namespace and ConfigMap

ConfigMaps are also namespaced.

Example:

```bash
kubectl -n dev create configmap app-config \
  --from-literal=LOG_LEVEL=debug

kubectl -n prod create configmap app-config \
  --from-literal=LOG_LEVEL=info
```

Same name, different namespace, different value.

This is one of the cleanest ways to deploy the same app to multiple environments.

---

# 12. Namespace and ResourceQuota

A `ResourceQuota` limits total consumption in a namespace.

Example:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: dev
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
    pods: "20"
```

With this, Kubernetes will reject new objects that exceed the namespace quota.

Common quota fields:

```text
requests.cpu
requests.memory
limits.cpu
limits.memory
pods
services
configmaps
secrets
persistentvolumeclaims
requests.storage
```

Useful for:

```text
Preventing dev workloads from eating the cluster
Preventing accidental infinite scaling
Separating teams fairly
Cost governance
Training/lab environments
```

In your local k3d, quotas are very useful because your WSL/Docker Desktop resources are limited.

---

# 13. Namespace and LimitRange

A `LimitRange` sets default or min/max CPU/memory per Pod/container in a namespace.

Example:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: dev
spec:
  limits:
    - type: Container
      defaultRequest:
        cpu: "100m"
        memory: "128Mi"
      default:
        cpu: "500m"
        memory: "512Mi"
      max:
        cpu: "1"
        memory: "1Gi"
      min:
        cpu: "50m"
        memory: "64Mi"
```

Why this matters:

If you create a `ResourceQuota` that limits CPU/memory, Pods usually need requests/limits. `LimitRange` helps by applying defaults so developers do not have to specify them every time.

Senior rule:

```text
ResourceQuota controls total namespace usage.
LimitRange controls default/min/max per container or pod.
Use both together.
```

---

# 14. Namespace and NetworkPolicy

By default, Kubernetes networking is usually permissive: Pods can talk to other Pods across namespaces unless something blocks them.

A good baseline is default deny.

## Default deny all ingress in namespace

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: backend
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

## Allow traffic from frontend namespace

First label the namespace:

```bash
kubectl label namespace frontend name=frontend
```

Then:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-frontend
  namespace: backend
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
              name: frontend
      ports:
        - protocol: TCP
          port: 8080
```

Important detail: `NetworkPolicy` is namespaced. The policy object lives in one namespace and applies to Pods in that namespace.

---

# 15. Namespace and Ingress

Ingress objects are namespaced.

Example:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: dev
spec:
  rules:
    - host: my-app.localhost
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80
```

The backend Service must usually be in the same namespace as the Ingress.

For your script:

```bash
--port "8080:80@loadbalancer"
--port "8443:443@loadbalancer"
```

So if Traefik is active in your k3d/k3s cluster, HTTP ingress should be reachable through:

```text
http://localhost:8080
```

If using host rules locally, add entries to `/etc/hosts` inside WSL or Windows depending on where you access from:

```text
127.0.0.1 my-app.localhost
```

---

# 16. Namespace and Helm

Helm releases are namespace scoped by default.

Install into namespace:

```bash
helm install my-app ./chart -n dev --create-namespace
```

List releases in namespace:

```bash
helm list -n dev
```

List all:

```bash
helm list -A
```

Uninstall:

```bash
helm uninstall my-app -n dev
```

Common mistake:

```bash
helm install my-app ./chart
```

This installs into whatever your current namespace is, often `default`.

Senior habit:

```bash
helm install my-app ./chart -n dev --create-namespace
```

Always specify `-n`.

---

# 17. Namespace and Kustomize

Common structure:

```text
k8s/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/
    ├── dev/
    │   └── kustomization.yaml
    ├── staging/
    │   └── kustomization.yaml
    └── prod/
        └── kustomization.yaml
```

Example `overlays/dev/kustomization.yaml`:

```yaml
namespace: dev

resources:
  - ../../base

images:
  - name: my-app
    newName: dev-registry:5000/my-app
    newTag: dev
```

Apply:

```bash
kubectl apply -k k8s/overlays/dev
```

This is clean for local k3d testing.

---

# 18. Namespace and labels

Namespaces can have labels.

Example:

```bash
kubectl label ns dev environment=dev
kubectl label ns staging environment=staging
kubectl label ns prod environment=prod
```

Check:

```bash
kubectl get ns --show-labels
```

Use cases:

```text
NetworkPolicy namespaceSelector
Pod Security Admission labels
Cost allocation
Backup selection
Monitoring grouping
Admission policy selection
GitOps targeting
```

Kubernetes automatically adds an immutable label `kubernetes.io/metadata.name` to namespaces, with the namespace name as its value. ([Kubernetes][1])

---

# 19. Namespace and Pod Security Admission

In modern Kubernetes, Pod Security Admission can be applied using namespace labels.

Common levels:

```text
privileged
baseline
restricted
```

Example:

```bash
kubectl label ns dev \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted
```

For stricter workloads:

```bash
kubectl label ns prod \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted
```

This prevents dangerous Pod specs depending on the level.

Senior recommendation:

```text
dev: baseline + warn restricted
prod: restricted where possible
security/system namespaces: carefully customized
```

---

# 20. Namespace lifecycle and deletion issues

When you delete a namespace:

```bash
kubectl delete ns dev
```

Kubernetes tries to delete all namespaced resources inside it.

Sometimes a namespace gets stuck:

```text
dev   Terminating
```

Common reasons:

```text
Finalizers waiting for cleanup
Broken custom controller/operator
CRD removed before its custom resources were deleted
PVC/storage cleanup issue
APIService unavailable
```

Finalizers tell Kubernetes to wait until cleanup conditions are complete before fully deleting an object. The API marks the object for deletion and keeps it in a terminating state until finalizers are removed. ([Kubernetes][7])

Debug:

```bash
kubectl get ns dev -o yaml
```

Find resources still inside:

```bash
kubectl api-resources --verbs=list --namespaced -o name \
  | xargs -n 1 kubectl get --show-kind --ignore-not-found -n dev
```

For local k3d, if a namespace is badly stuck and you do not care about data, it is often faster to recreate the whole cluster:

```bash
k3d cluster delete dev
./your-script.sh
```

In production, do **not** force-remove finalizers blindly. Investigate the owning controller first.

---

# 21. Recommended namespace layout for your k3d cluster

For your local setup, I would use this:

```text
default          keep empty
kube-system      system only
app-dev          your application
app-staging      staging simulation
observability    prometheus/grafana/loki/etc.
ingress          optional, if you install ingress components manually
security         security tools, scanners, policies
```

Create them:

```bash
kubectl create ns app-dev
kubectl create ns app-staging
kubectl create ns observability
kubectl create ns security
```

Set current namespace while working:

```bash
kubectl config set-context --current --namespace=app-dev
```

Deploy app:

```bash
kubectl -n app-dev apply -f k8s/
```

Check:

```bash
kubectl -n app-dev get pods,svc,ingress
```

---

# 22. Production grade namespace design

A mature setup usually looks like this:

```text
platform-system
ingress-nginx
cert-manager
external-dns
monitoring
logging
security
team-a-dev
team-a-staging
team-a-prod
team-b-dev
team-b-staging
team-b-prod
```

But be careful: putting `dev`, `staging`, and `prod` in the same cluster is not always acceptable. For serious production systems, prefer:

```text
cluster-dev
cluster-staging
cluster-prod
```

Then use namespaces inside each cluster for apps/teams.

Senior rule:

```text
Use namespaces for organization and soft isolation.
Use separate clusters/accounts/projects/subscriptions for hard environment isolation.
```

---

# 23. Common namespace mistakes

## Mistake 1: Deploying everything into `default`

Bad:

```bash
kubectl apply -f deployment.yaml
```

Better:

```bash
kubectl -n app-dev apply -f deployment.yaml
```

Best:

```yaml
metadata:
  namespace: app-dev
```

or Kustomize:

```yaml
namespace: app-dev
```

## Mistake 2: Thinking namespaces block traffic

They do not automatically block traffic. Use `NetworkPolicy`.

## Mistake 3: Using ClusterRoleBinding everywhere

Bad:

```text
CI/CD has cluster-admin
```

Better:

```text
CI/CD has deploy permissions only in app-dev/app-staging
```

## Mistake 4: Putting Secrets in the wrong namespace

A Secret must be in the same namespace as the Pod that consumes it.

## Mistake 5: Forgetting namespace in kubectl commands

Use:

```bash
kubectl config set-context --current --namespace=app-dev
```

Or install `kubens`:

```bash
kubens app-dev
```

## Mistake 6: Confusing namespace with labels

Use namespaces for ownership/isolation boundaries.

Use labels for selection/grouping inside or across namespaces.

Example:

```yaml
labels:
  app: api
  tier: backend
  environment: dev
```

## Mistake 7: Deleting namespace before uninstalling Helm releases/operators

Better:

```bash
helm uninstall my-app -n app-dev
kubectl delete ns app-dev
```

Not:

```bash
kubectl delete ns app-dev
```

Especially with operators, CRDs, PVCs, and finalizers.

---

# 24. Practical lab for your k3d setup

Run this.

## Create namespaces

```bash
kubectl create ns frontend
kubectl create ns backend
```

## Deploy backend

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: backend
spec:
  replicas: 1
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
          image: nginx:stable
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: backend
spec:
  selector:
    app: api
  ports:
    - port: 80
      targetPort: 80
```

Apply:

```bash
kubectl apply -f backend.yaml
```

## Test DNS from another namespace

```bash
kubectl -n frontend run curl --image=curlimages/curl -it --rm -- sh
```

Inside the shell:

```sh
curl http://api.backend.svc.cluster.local
```

This proves cross-namespace service discovery.

---

# 25. The commands you should memorize

```bash
kubectl get ns
kubectl create ns dev
kubectl delete ns dev

kubectl -n dev get all
kubectl -n dev get pods
kubectl -n dev describe pod <pod>
kubectl -n dev logs <pod>
kubectl -n dev exec -it <pod> -- sh

kubectl config set-context --current --namespace=dev
kubectl config view --minify | grep namespace

kubectl api-resources --namespaced=true
kubectl api-resources --namespaced=false

kubectl auth can-i get pods -n dev
kubectl auth can-i create deployments -n dev
kubectl auth can-i '*' '*' -n dev
```

---

# 26. Verdict

Use namespaces to divide one Kubernetes cluster into logical workspaces. They are excellent for environment separation, team ownership, RBAC scoping, quotas, service discovery, secrets/config separation, and network policy targeting. Do not treat namespaces alone as a hard security boundary. For your k3d local cluster, create explicit namespaces like `app-dev`, `app-staging`, `observability`, and `security`; keep `default` empty; always use `kubectl -n ...`; put Secrets and ConfigMaps in the same namespace as the consuming Pods; and use quotas/limits early so your WSL Docker environment does not get exhausted.

[1]: https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/ "Namespaces"
[2]: https://kubernetes.io/docs/concepts/policy/resource-quotas/ "Resource Quotas"
[3]: https://kubernetes.io/docs/reference/access-authn-authz/rbac/ "Using RBAC Authorization"
[4]: https://kubernetes.io/docs/concepts/services-networking/network-policies/ "Network Policies"
[5]: https://github.com/k3s-io/k3s/ "k3s-io/k3s: Lightweight Kubernetes"
[6]: https://kubernetes.io/docs/concepts/security/service-accounts/ "Service Accounts"
[7]: https://kubernetes.io/docs/concepts/overview/working-with-objects/finalizers/ "Finalizers"
