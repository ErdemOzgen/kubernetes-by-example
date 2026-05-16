# Kubernetes StorageClass Notes

A `StorageClass` defines how dynamic volumes are provisioned.
It allows workloads to request storage without pre-creating PVs manually.

## Why StorageClass matters

- Standardizes storage behavior across workloads.
- Encapsulates provisioner, topology, and binding policy.
- Enables on-demand PV creation via PVCs.

## YAML in this folder

Source file: `simple.yaml`

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: storage-class-simple
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
```

## Field-by-field breakdown

- `provisioner: kubernetes.io/no-provisioner`:
  - No dynamic provisioning.
  - Typically used with statically-managed local volumes.
- `volumeBindingMode: WaitForFirstConsumer`:
  - Delays PV binding/provisioning until a Pod is scheduled.
  - Helps topology-aware placement (zone/node constraints).

## Hands-on lab

### 1. Create StorageClass

```bash
kubectl apply -f simple.yaml
kubectl get storageclass
kubectl describe storageclass storage-class-simple
```

### 2. Create a PVC using this class

Create `pvc-wffc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-wffc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: storage-class-simple
```

Apply:

```bash
kubectl apply -f pvc-wffc.yaml
kubectl get pvc pvc-wffc
```

With `WaitForFirstConsumer`, claim may remain pending until a Pod references it.

### 3. Create a Pod that consumes the PVC

Create `pod-wffc.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-wffc
spec:
  containers:
    - name: app
      image: nginx:1.27
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: pvc-wffc
```

Apply and inspect:

```bash
kubectl apply -f pod-wffc.yaml
kubectl get pod pod-wffc -o wide
kubectl get pvc pvc-wffc
kubectl get pv
```

## Troubleshooting

- Using `no-provisioner` but expecting automatic PV creation.
- No matching static PV exists for claim requirements.
- Misunderstanding `WaitForFirstConsumer` pending state before pod scheduling.

## Production guidance

- Use CSI provisioners for dynamic production storage classes.
- Keep different classes for performance/retention tiers.
- Define default storage class carefully to avoid accidental provisioning.
