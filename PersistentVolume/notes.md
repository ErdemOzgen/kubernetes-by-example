# Kubernetes PersistentVolume Notes

A `PersistentVolume` (PV) is cluster-scoped storage provisioned by an admin or dynamic provisioner.
A PV exists independently from Pods and can outlive workload restarts.

## Why PV exists

Containers are ephemeral. If data is written only to the container filesystem, it is lost when the Pod is recreated.
PV provides durable storage decoupled from Pod lifecycle.

## YAML in this folder

Source file: `spec.local/local.yaml`

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: volumes-local-persistent-volume
  labels:
    pv: local
spec:
  capacity:
    storage: 5Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: hostpath
  local:
    path: /mnt/disks/ssd1
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - docker-desktop
```

## Field-by-field breakdown

- `capacity.storage: 5Gi`: PV capacity.
- `volumeMode: Filesystem`: Mounted as a filesystem.
- `accessModes: ReadWriteOnce`: Usually mounted read-write by one node at a time.
- `persistentVolumeReclaimPolicy: Delete`: Behavior after PVC release (may delete backend depending on plugin).
- `storageClassName: hostpath`: Must match the PVC storageClassName for class-based binding.
- `local.path`: Node local disk path.
- `nodeAffinity`: Restricts scheduling so pods can mount this local volume only on matching nodes.

Important:
- Local PV is node-tied. If workload is scheduled to another node, volume is not usable there.
- For production HA storage, use network/distributed backends when needed.

## Hands-on lab

### 1. Prepare host path on the target node

For Docker Desktop, ensure the path exists and is shared with Kubernetes VM:

```bash
sudo mkdir -p /mnt/disks/ssd1
echo "hello from local pv" | sudo tee /mnt/disks/ssd1/index.html
```

### 2. Apply PV

```bash
kubectl apply -f spec.local/local.yaml
kubectl get pv
kubectl describe pv volumes-local-persistent-volume
```

Expected:
- Status should be `Available` until a matching PVC binds.

### 3. Bind with PVC

Use the repo PVC:

```bash
kubectl apply -f ../PersistentVolumeClaim/pvc.yaml
kubectl get pvc
kubectl get pv
```

Expected:
- PVC status `Bound`.
- PV status `Bound`.

### 4. Mount into a test Pod

Example Pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pv-test
spec:
  containers:
    - name: nginx
      image: nginx:1.27
      volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: persistent-volume-claim
```

Apply and verify data:

```bash
kubectl apply -f pv-test.yaml
kubectl port-forward pod/pv-test 8080:80
curl http://127.0.0.1:8080
```

Expected response includes content from `/mnt/disks/ssd1/index.html`.

## Troubleshooting

- PVC stuck `Pending`:
  - Check `storageClassName` matches.
  - Check access mode compatibility.
  - Check requested size <= PV size.
- Pod fails mount:
  - Check node affinity and where Pod is scheduled.
  - Check local path exists and permissions are valid.

## Production guidance

- Prefer dynamic provisioning with StorageClass for most clusters.
- Use local PV only for node-local performance use cases with clear failure strategy.
