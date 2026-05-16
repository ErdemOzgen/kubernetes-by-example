# Kubernetes LimitRange Notes

A `LimitRange` defines min/max/default resource constraints in a namespace.
It is an admission-time policy: when a new Pod/Container is created, Kubernetes checks whether requested and limited resources comply.

## Why LimitRange matters

Without LimitRange:
- Teams can create containers with no limits, causing noisy-neighbor issues.
- Teams can request unreasonably large resources and starve other workloads.
- Resource requests/limits become inconsistent across teams.

With LimitRange:
- You enforce namespace-level guardrails.
- You keep resource usage predictable.
- You improve scheduler behavior and cluster stability.

## YAML in this folder

Source file: `mem-min-max.yaml`

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: limit-range-mem-min-max
spec:
  limits:
    - max:
        memory: 1Gi
      min:
        memory: 500Mi
      type: Container
```

### Field-by-field

- `kind: LimitRange`: Namespace policy object.
- `spec.limits[].type: Container`: Policy applies to each container.
- `min.memory: 500Mi`: Every container must request/limit memory >= 500Mi when set.
- `max.memory: 1Gi`: Every container must request/limit memory <= 1Gi when set.

Important: this example sets min/max boundaries. It does not define default requests/limits.

## Hands-on lab

### 1. Create namespace and apply policy

```bash
kubectl create ns limits-lab
kubectl -n limits-lab apply -f mem-min-max.yaml
kubectl -n limits-lab get limitrange
kubectl -n limits-lab describe limitrange limit-range-mem-min-max
```

### 2. Try a Pod that violates `min.memory`

Create `pod-too-small.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-too-small
spec:
  containers:
    - name: app
      image: nginx:1.27
      resources:
        requests:
          memory: 128Mi
        limits:
          memory: 128Mi
```

Apply:

```bash
kubectl -n limits-lab apply -f pod-too-small.yaml
```

Expected: rejected by admission with min-memory violation.

### 3. Try a Pod that violates `max.memory`

Create `pod-too-large.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-too-large
spec:
  containers:
    - name: app
      image: nginx:1.27
      resources:
        requests:
          memory: 2Gi
        limits:
          memory: 2Gi
```

Apply:

```bash
kubectl -n limits-lab apply -f pod-too-large.yaml
```

Expected: rejected by admission with max-memory violation.

### 4. Create a valid Pod

Create `pod-valid.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-valid
spec:
  containers:
    - name: app
      image: nginx:1.27
      resources:
        requests:
          memory: 700Mi
        limits:
          memory: 700Mi
```

Apply and verify:

```bash
kubectl -n limits-lab apply -f pod-valid.yaml
kubectl -n limits-lab get pod pod-valid
kubectl -n limits-lab describe pod pod-valid
```

## Common mistakes

- Assuming LimitRange applies cluster-wide. It is namespace-scoped.
- Defining `requests` and `limits` outside policy boundaries.
- Forgetting CPU constraints if you also need CPU governance.

## Production guidance

- Pair LimitRange with ResourceQuota.
- Keep namespace guardrails aligned with node sizes and scheduling policy.
- Use clear environment-specific namespaces (`dev`, `staging`, `prod`).
