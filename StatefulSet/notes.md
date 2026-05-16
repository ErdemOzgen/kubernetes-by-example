# Kubernetes StatefulSet Notes

`StatefulSet` manages stateful applications with stable identity and storage.
Compared with Deployment, StatefulSet provides:
- Stable Pod names (`<name>-0`, `<name>-1`, ...)
- Ordered rollout/termination semantics
- Stable per-replica storage (typically via `volumeClaimTemplates`)

## YAMLs in this folder

### 1) `simple-stateful-set.yaml`

This file contains:
- A headless Service (`clusterIP: None`) named `nginx`
- A StatefulSet with 3 replicas
- `volumeClaimTemplates` named `www`

Key points:
- `serviceName: nginx` ties StatefulSet network identity to the headless Service.
- Each replica gets its own PVC from template `www`.
- `storageClassName: my-storage-class` must exist in your cluster or PVCs remain pending.

### 2) `stateful-set-shared-pv.yaml`

This file attempts shared storage via one PVC mounted by all StatefulSet replicas.

Important correction for this manifest:
- PVC uses `selector.matchLabels.pv: stateful-set-shared-pv-volume`
- PV currently has no matching label.

You should add label to PV metadata:

```yaml
metadata:
  name: stateful-set-shared-pv-volume
  labels:
    pv: stateful-set-shared-pv-volume
```

Without this label, PVC may not bind.

## Hands-on lab A: StatefulSet with per-replica PVCs

### 1. Prepare StorageClass compatible with manifest

If `my-storage-class` does not exist, either:
- Create it, or
- Update StatefulSet `storageClassName` to an existing class.

Check:

```bash
kubectl get storageclass
```

### 2. Apply simple StatefulSet stack

```bash
kubectl apply -f simple-stateful-set.yaml
kubectl get svc nginx
kubectl get statefulset simple-stateful-set
kubectl get pod -l app=nginx
kubectl get pvc
```

Expected:
- Pods named `simple-stateful-set-0..2`
- PVCs named like `www-simple-stateful-set-0`, `www-simple-stateful-set-1`, ...

### 3. Verify stable identity

```bash
kubectl get pod simple-stateful-set-0 -o wide
kubectl delete pod simple-stateful-set-0
kubectl get pod simple-stateful-set-0 -w
```

Expected:
- Pod recreated with same ordinal name.
- Associated PVC remains and is reattached.

## Hands-on lab B: Shared PVC StatefulSet pattern

### 1. Patch manifest label mismatch first

Add PV label as shown above, then apply:

```bash
kubectl apply -f stateful-set-shared-pv.yaml
kubectl get pv
kubectl get pvc stateful-set-shared-pv-claim
kubectl get statefulset stateful-set-shared-pv-stateful-set
```

### 2. Validate shared volume behavior

Write from one pod, read from another:

```bash
kubectl exec -it stateful-set-shared-pv-stateful-set-0 -- sh -c 'echo hello-shared > /usr/share/nginx/html/shared.txt'
kubectl exec -it stateful-set-shared-pv-stateful-set-1 -- cat /usr/share/nginx/html/shared.txt
```

Expected:
- Same file visible across replicas when backend and access mode support it.

## Common mistakes

- Missing headless Service for StatefulSet DNS identity.
- StorageClass mismatch causing PVC pending.
- Assuming shared-write semantics with backend that does not truly support RWX.
- Using tiny capacities (`1M`) in examples and forgetting to adjust for real workloads.

## Production guidance

- Prefer per-replica PVCs for databases/queues requiring isolated data.
- Use shared storage only when application design explicitly requires it.
- Combine with PodDisruptionBudget, anti-affinity, and backup policies.
