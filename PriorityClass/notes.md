# Kubernetes PriorityClass Notes

`PriorityClass` controls pod scheduling priority and preemption behavior.
Higher numeric `value` means higher priority.

## Why PriorityClass matters

- Critical workloads should schedule before less important workloads.
- During resource pressure, high-priority pods can preempt lower-priority pods.
- It supports predictable SLO behavior for platform-critical services.

## YAML in this folder

Source file: `default-priority-class.yaml`

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: default-priority-class
value: 1000
globalDefault: true
description: "Default priority class for all pods"
```

### Field-by-field

- `value: 1000`: Priority score assigned to pods using this class.
- `globalDefault: true`: Pods without `priorityClassName` get this class by default.
- `description`: Operational context for platform teams.

Important:
- Only one `PriorityClass` in the cluster can have `globalDefault: true`.
- `PriorityClass` is cluster-scoped.

## Hands-on lab

### 1. Apply default priority class

```bash
kubectl apply -f default-priority-class.yaml
kubectl get priorityclass
kubectl describe priorityclass default-priority-class
```

### 2. Create an explicit high-priority class

Create `high-priority-class.yaml`:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 100000
globalDefault: false
description: "High-priority workload class"
```

Apply:

```bash
kubectl apply -f high-priority-class.yaml
```

### 3. Compare pod priorities

Create `priority-pods.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-default-priority
spec:
  containers:
    - name: app
      image: nginx:1.27
---
apiVersion: v1
kind: Pod
metadata:
  name: pod-high-priority
spec:
  priorityClassName: high-priority
  containers:
    - name: app
      image: nginx:1.27
```

Apply and verify:

```bash
kubectl apply -f priority-pods.yaml
kubectl get pod pod-default-priority pod-high-priority -o jsonpath='{range .items[*]}{.metadata.name}{" -> priority="}{.spec.priority}{" class="}{.spec.priorityClassName}{"\n"}{end}'
```

Expected: high-priority pod has larger `spec.priority` than default.

### 4. Preemption experiment (optional, advanced)

In a small cluster with constrained resources:
- Schedule many low-priority pods until nodes are full.
- Create a high-priority pod with resource requests.
- Kubernetes may evict lower-priority pods to schedule high-priority pod.

Check events:

```bash
kubectl get events --sort-by=.lastTimestamp | grep -i -E 'preempt|priority|evict'
```

## Common mistakes

- Setting multiple `globalDefault: true` classes.
- Using priority as a substitute for quotas and limits.
- Forgetting that priority affects scheduling order, not application-level correctness.

## Production guidance

- Keep a small, well-defined set of priority tiers.
- Document what each tier means (business criticality, SLO, owner).
- Use with ResourceQuota and PodDisruptionBudget for robust workload policy.
