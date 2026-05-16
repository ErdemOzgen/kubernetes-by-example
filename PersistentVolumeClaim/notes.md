# Kubernetes PersistentVolumeClaim Notes

A `PersistentVolumeClaim` (PVC) is a namespace-scoped storage request.
Pods consume storage through PVCs, not by mounting PVs directly.

## Why PVC exists

PVC decouples application teams from storage implementation details.
Developers request size/mode/class; platform maps that to an actual PV.

## YAML in this folder

Source file: `pvc.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: persistent-volume-claim
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  selector:
    matchLabels:
      pv: local
  storageClassName: hostpath
```

## Field-by-field breakdown

- `accessModes: ReadWriteOnce`: Request compatible with RWO PVs.
- `resources.requests.storage: 5Gi`: Requested size.
- `selector.matchLabels.pv: local`: Bind only to PVs labeled `pv=local`.
- `storageClassName: hostpath`: Restrict binding to this class.

Binding rules (high level):
- Access mode must match.
- Requested storage must be <= PV capacity.
- Class and selectors must match.

## Hands-on lab

### 1. Create matching PV first

```bash
kubectl apply -f ../PersistentVolume/spec.local/local.yaml
kubectl get pv
```

### 2. Apply PVC

```bash
kubectl apply -f pvc.yaml
kubectl get pvc
kubectl describe pvc persistent-volume-claim
```

Expected:
- PVC transitions from `Pending` to `Bound`.

### 3. Use PVC from a Pod

Create `pod-uses-pvc.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-uses-pvc
spec:
  containers:
    - name: app
      image: nginx:1.27
      volumeMounts:
        - name: webroot
          mountPath: /usr/share/nginx/html
  volumes:
    - name: webroot
      persistentVolumeClaim:
        claimName: persistent-volume-claim
```

Apply and test:

```bash
kubectl apply -f pod-uses-pvc.yaml
kubectl get pod pod-uses-pvc -o wide
kubectl port-forward pod/pod-uses-pvc 8080:80
curl http://127.0.0.1:8080
```

### 4. Observe claim lifecycle

```bash
kubectl get pvc persistent-volume-claim -o yaml
kubectl get pv volumes-local-persistent-volume -o yaml
```

Check `claimRef` on PV and `volumeName` on PVC.

## Troubleshooting

- PVC `Pending` forever:
  - No matching PV exists.
  - selector or storageClass mismatch.
  - requested size too large.
- Pod cannot mount:
  - PVC not bound.
  - Node affinity/storage backend constraints.

## Production guidance

- Prefer dynamic provisioning via StorageClass.
- Use selectors only when you intentionally bind to specific PVs.
- Keep reclaim policy and backup strategy aligned with data criticality.
