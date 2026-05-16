# Kubernetes ResourceQuota Notes

A `ResourceQuota` limits the total resource consumption of a namespace.
Unlike `LimitRange` (per-container/pod constraints), ResourceQuota controls aggregate usage.

## Why ResourceQuota matters

- Prevents one namespace from consuming all cluster capacity.
- Enables fair multi-tenant usage.
- Supports policy by workload class (for example via PriorityClass scopes).

## YAML in this folder

Source file: `quotas.yaml`

It defines three quotas scoped by `PriorityClass` values:
- high
- medium
- low

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: resource-quotas-quotas-pods-high
spec:
  hard:
    cpu: "1000"
    memory: 200Gi
    pods: "10"
  scopeSelector:
    matchExpressions:
      - operator: In
        scopeName: PriorityClass
        values: ["high"]
```

The same pattern is repeated for `medium` and `low` with smaller hard limits.

### Field-by-field

- `spec.hard`: Maximum aggregate usage in that namespace for matching pods.
- `cpu`, `memory`, `pods`: total caps.
- `scopeSelector.scopeName: PriorityClass`: quota applies only to pods of listed priority classes.

## Hands-on lab

### 1. Create namespace and apply quotas

```bash
kubectl create ns quotas-lab
kubectl -n quotas-lab apply -f quotas.yaml
kubectl -n quotas-lab get resourcequota
kubectl -n quotas-lab describe resourcequota
```

### 2. Create matching PriorityClass objects (cluster-scoped)

Create `priority-classes.yaml`:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high
value: 100000
globalDefault: false
description: "High priority"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: medium
value: 50000
globalDefault: false
description: "Medium priority"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low
value: 1000
globalDefault: false
description: "Low priority"
```

Apply:

```bash
kubectl apply -f priority-classes.yaml
kubectl get priorityclass
```

### 3. Create a deployment in `low` class

Create `low-deploy.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: low-app
  namespace: quotas-lab
spec:
  replicas: 3
  selector:
    matchLabels:
      app: low-app
  template:
    metadata:
      labels:
        app: low-app
    spec:
      priorityClassName: low
      containers:
        - name: app
          image: nginx:1.27
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: 500m
              memory: 1Gi
```

Apply and observe quota usage:

```bash
kubectl apply -f low-deploy.yaml
kubectl -n quotas-lab describe resourcequota resource-quotas-quotas-pods-low
```

### 4. Exceed low quota and observe rejection

Scale beyond quota:

```bash
kubectl -n quotas-lab scale deploy low-app --replicas=12
kubectl -n quotas-lab get events --sort-by=.lastTimestamp | tail -n 20
```

Expected: new pods fail admission due to quota exceeded.

## Common mistakes

- Forgetting to create corresponding PriorityClass objects (`high`, `medium`, `low`).
- Expecting quota to apply across namespaces.
- Not setting resource requests, causing quota accounting surprises.

## Production guidance

- Define quota tiers per environment/team.
- Combine with LimitRange to avoid tiny/huge container specs.
- Monitor `kubectl describe resourcequota` and alerts for near-exhaustion.
