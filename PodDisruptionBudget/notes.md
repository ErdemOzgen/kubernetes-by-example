# Kubernetes PodDisruptionBudget (PDB) Notes

A `PodDisruptionBudget` limits voluntary disruptions for selected pods.
Voluntary disruptions include drain/upgrade/maintenance actions that evict pods.

PDB does not protect against involuntary disruptions (node crash, kernel panic, hardware failure).

## Why PDB matters

- Protects application availability during maintenance.
- Prevents too many replicas being evicted simultaneously.
- Enforces minimum healthy capacity for replicated workloads.

## YAMLs in this folder

### 1) `pod-disruption-budget-min-available.yaml`

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: pod-disruption-budget-min-available-simple
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: app-simple
```

Meaning:
- At least 2 matching pods must remain available.

### 2) `pod-disruption-budget-max-unavailable.yaml`

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: pod-disruption-budget-max-unavailable-simple
spec:
  maxUnavailable: "10%"
  selector:
    matchLabels:
      app: app-simple
```

Meaning:
- At most 10% of matching pods may be unavailable due to voluntary disruptions.

## `minAvailable` vs `maxUnavailable`

- `minAvailable`: absolute safety floor.
- `maxUnavailable`: upper bound of allowed disruption.

Pick one based on operational style; avoid defining both in the same PDB.

## Hands-on lab

### 1. Create namespace and sample deployment

```bash
kubectl create ns pdb-lab
```

Create `app-simple-deploy.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-simple
  namespace: pdb-lab
spec:
  replicas: 5
  selector:
    matchLabels:
      app: app-simple
  template:
    metadata:
      labels:
        app: app-simple
    spec:
      containers:
        - name: app
          image: nginx:1.27
```

Apply:

```bash
kubectl apply -f app-simple-deploy.yaml
kubectl -n pdb-lab get pods -l app=app-simple
```

### 2. Apply `minAvailable` PDB

```bash
kubectl -n pdb-lab apply -f pod-disruption-budget-min-available.yaml
kubectl -n pdb-lab get pdb
kubectl -n pdb-lab describe pdb pod-disruption-budget-min-available-simple
```

### 3. Test with `kubectl drain` behavior via eviction

Pick one pod name:

```bash
POD=$(kubectl -n pdb-lab get pod -l app=app-simple -o jsonpath='{.items[0].metadata.name}')
```

Attempt eviction:

```bash
kubectl -n pdb-lab delete pod "$POD"
```

Note: direct delete is not always treated as a voluntary disruption flow like eviction APIs.
For realistic maintenance simulation, use node drain in a multi-node lab:

```bash
kubectl get nodes
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

Observe if PDB blocks excessive evictions.

### 4. Switch to `maxUnavailable` version

```bash
kubectl -n pdb-lab delete pdb pod-disruption-budget-min-available-simple
kubectl -n pdb-lab apply -f pod-disruption-budget-max-unavailable.yaml
kubectl -n pdb-lab describe pdb pod-disruption-budget-max-unavailable-simple
```

Scale deployment and observe allowed disruptions:

```bash
kubectl -n pdb-lab scale deploy app-simple --replicas=10
kubectl -n pdb-lab get pdb
```

## Common mistakes

- Label mismatch between PDB selector and workload pods.
- Using PDB with too few replicas (for example 1 replica + strict minAvailable).
- Assuming PDB protects against node failures.

## Production guidance

- Set PDB values per SLO and replica count.
- Validate drain workflows in staging.
- Pair PDB with readiness probes and topology spread constraints.
