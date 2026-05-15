## 1. Mental model: what is a Pod?

A **Pod** is the smallest deployable compute unit in Kubernetes. It is not exactly the same as a container. A Pod is an execution environment that can contain **one or more containers**, shared networking, shared storage volumes, and runtime configuration. Kubernetes manages Pods, and the kubelet on a node turns the Pod spec into actual running containers via the container runtime. ([Kubernetes][1])

Think of a Pod as a **logical machine**:

```text
Pod
 ├── shared IP address
 ├── shared network namespace
 ├── shared volumes
 ├── container A
 ├── container B
 └── init / sidecar / ephemeral containers when needed
```

Most Pods contain **one application container**. Multi-container Pods are advanced and should be used only when the containers are tightly coupled, for example a main app plus a log shipper, proxy, file synchronizer, or local helper sidecar. Kubernetes explicitly warns that multi-container Pods should be used only for specific tightly coupled cases. ([Kubernetes][1])

**Multiple containers in one Pod share:**

```text
Network namespace (same IP, must use different ports)
Storage volumes
Configuration and runtime settings
CPU and memory resources
```

**Example:** See [spec.containers/multi-container.yaml](spec.containers/multi-container.yaml) for a multi-container Pod example.

---

## 2. Basic Pod example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
  labels:
    app: nginx
    env: dev
spec:
  containers:
    - name: nginx
      image: nginx:1.27
      ports:
        - containerPort: 80
```

Apply it:

```bash
kubectl apply -f pod.yaml
kubectl get pods
kubectl get pod nginx-pod -o wide
kubectl describe pod nginx-pod
kubectl logs nginx-pod
kubectl exec -it nginx-pod -- sh
kubectl delete pod nginx-pod
```

**Example:** See [simple.yaml](simple.yaml) for a basic Pod example.

This is good for learning, debugging, and experiments. In production, you usually do **not** create naked Pods directly. You normally use a **Deployment**, **StatefulSet**, **DaemonSet**, **Job**, or **CronJob**, because controllers handle replication, rollout, replacement, and self-healing. ([Kubernetes][1])

---

## 3. Important rule: Pods are ephemeral

A Pod is disposable. If a node dies, Kubernetes does not “move” the same Pod to another node. A controller creates a **new replacement Pod** with a new UID. Even if the new Pod has the same name, it is a different Pod identity. ([Kubernetes][2])

This matters a lot.

Bad assumption:

```text
My Pod will live forever.
```

Correct assumption:

```text
My Pod can disappear at any time. My app must tolerate replacement.
```

Therefore:

```text
Do not store important state only inside the container filesystem.
Do not rely on Pod IPs being permanent.
Do not manually repair production Pods.
Use controllers.
Use PersistentVolumes for durable state.
Use Services for stable networking.
```

---

## 4. Pod lifecycle

A Pod goes through lifecycle phases. The main phases are:

| Phase       | Meaning                                                                                                                                                   |
| ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Pending`   | Accepted by the cluster, but not fully running yet. This may mean scheduling is pending, image pull is happening, or containers are still being prepared. |
| `Running`   | Bound to a node, containers created, and at least one container is running or starting/restarting.                                                        |
| `Succeeded` | All containers exited successfully and will not restart. Common for Jobs.                                                                                 |
| `Failed`    | All containers terminated, and at least one failed.                                                                                                       |
| `Unknown`   | Kubernetes cannot determine the Pod state, usually because the node cannot be reached.                                                                    |

Kubernetes also shows user-friendly statuses like `CrashLoopBackOff`, `ImagePullBackOff`, or `Terminating`, but those are not the same thing as the Pod’s formal `phase`. ([Kubernetes][2])

Example:

```bash
kubectl get pod nginx-pod
```

Output:

```text
NAME        READY   STATUS             RESTARTS   AGE
nginx-pod   0/1     CrashLoopBackOff   5          3m
```

Here, `CrashLoopBackOff` means the container keeps starting, crashing, and being restarted with backoff delay.

---

## 5. Pod vs container restart

This is a very common confusion.

A **container inside a Pod** can restart without the Pod itself being recreated. The Pod is the environment; containers are processes running inside that environment. Kubernetes documentation explicitly distinguishes restarting a container from restarting a Pod. ([Kubernetes][1])

Example:

```bash
kubectl get pod my-pod
```

```text
NAME     READY   STATUS    RESTARTS   AGE
my-pod   1/1     Running   7          2h
```

The Pod is still the same Pod, but the container restarted 7 times.

Check why:

```bash
kubectl describe pod my-pod
kubectl logs my-pod
kubectl logs my-pod --previous
```

`--previous` is extremely important when the current container has restarted and you need logs from the crashed instance.

---

## 6. Pod networking

Every Pod gets its own IP address. All containers inside the same Pod share the Pod network namespace, meaning they share the same IP address and port space. Containers in the same Pod can communicate with each other over `localhost`. ([Kubernetes][1])

Example:

```text
Pod IP: 10.244.1.25

Container A: app listens on localhost:8080
Container B: sidecar proxy connects to localhost:8080
```

Important consequences:

```text
Two containers in the same Pod cannot both bind to the same port.
Containers inside the Pod can talk via localhost.
Other Pods should not rely directly on this Pod IP.
Use a Service for stable access.
```

Bad production pattern:

```text
Frontend connects directly to backend Pod IP.
```

Correct pattern:

```text
Frontend connects to backend Service DNS name.
```

For example:

```text
backend.default.svc.cluster.local
```

### Host aliases

Pods can add static host entries to `/etc/hosts` via `hostAliases`. This is useful when you need to map IP addresses to hostnames inside the Pod.

```yaml
spec:
  hostAliases:
    - ip: "127.0.0.1"
      hostnames:
        - "foo.local"
        - "bar.local"
    - ip: "10.1.2.3"
      hostnames:
        - "foo.remote"
        - "bar.remote"
  containers:
    - name: app
      image: busybox
```

Inside the container:

```bash
cat /etc/hosts
```

You will see the entries added. This is useful for legacy applications or development environments where DNS resolution is not available.

**Example:** See [spec.hostAliases/host-aliases.yaml](spec.hostAliases/host-aliases.yaml) for a hostAliases example.

### DNS configuration

Pods can customize DNS settings using `dnsPolicy` and `dnsConfig`:

```yaml
spec:
  dnsPolicy: ClusterFirst
  dnsConfig:
    nameservers:
      - 1.2.3.4
    searches:
      - ns1.svc.cluster-domain.example
    options:
      - name: ndots
        value: "2"
```

**DNS Policy options:**

```text
Default: inherit from the node
ClusterFirst: forward non-cluster queries to upstream nameserver
ClusterFirstWithHostNet: for Pods with hostNetwork
None: use only dnsConfig settings
```

**Example:** See [spec.dnsPolicy/policy.yaml](spec.dnsPolicy/policy.yaml) and [spec.dnsConfig/dns-config.yaml](spec.dnsConfig/dns-config.yaml) for DNS configuration examples.

---

## 7. Pod storage

Containers in a Pod can share data using **volumes**. Kubernetes volumes give containers in a Pod a filesystem-based way to share or persist data depending on the volume type. ([Kubernetes][3])

Example with `emptyDir`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: shared-volume-demo
spec:
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh", "-c", "while true; do date >> /data/out.txt; sleep 5; done"]
      volumeMounts:
        - name: shared-data
          mountPath: /data

    - name: reader
      image: busybox:1.36
      command: ["sh", "-c", "tail -f /data/out.txt"]
      volumeMounts:
        - name: shared-data
          mountPath: /data

  volumes:
    - name: shared-data
      emptyDir: {}
```

`emptyDir` lives as long as that specific Pod exists. If the Pod is deleted and replaced, the `emptyDir` data is gone. For durable storage, use PersistentVolumes and PersistentVolumeClaims. Kubernetes documents that things with the same lifetime as a Pod, such as certain volumes, are tied to that exact Pod UID and are destroyed when that Pod is deleted. ([Kubernetes][2])

**Example:** See [emptydir.yaml](spec.volumes.emptyDir/emptydir.yaml) for an emptyDir volume example.

### hostPath volumes

`hostPath` mounts a file or directory from the host node into the Pod. This is dangerous for multi-node clusters because Pods can be scheduled on different nodes and see different data.

```yaml
spec:
  containers:
    - name: app
      image: busybox
      volumeMounts:
        - name: host-data
          mountPath: /data
  volumes:
    - name: host-data
      hostPath:
        path: /tmp
        type: Directory
```

**hostPath types:**

```text
Directory: expects a directory to exist
DirectoryOrCreate: creates directory if missing
File: expects a file to exist
FileOrCreate: creates file if missing
Socket: expects a Unix socket
CharDevice: expects a character device
BlockDevice: expects a block device
```

Use `hostPath` only for:

```text
DaemonSets that intentionally run on every node
Node-level debugging
Access to host system information
```

Do not use `hostPath` for general application data.

**Examples:** See [spec.volumes.hostPath/hostdir.yaml](spec.volumes.hostPath/hostdir.yaml) and [spec.volumes.hostPath.type/file-or-create.yaml](spec.volumes.hostPath.type/file-or-create.yaml) for hostPath examples.

### PersistentVolumeClaim

Pods can request durable storage using `PersistentVolumeClaim` (PVC). A PVC is a request for storage that Kubernetes binds to a `PersistentVolume` (PV).

```yaml
spec:
  containers:
    - name: app
      image: nginx
      volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: my-pvc
```

The PVC must exist in the same namespace as the Pod. Unlike `hostPath` or `emptyDir`, PVC data persists beyond Pod lifetime when properly configured.

**Example:** See [spec.volumes.persistentVolumeClaim/pod-pvc.yaml](spec.volumes.persistentVolumeClaim/pod-pvc.yaml) for a PVC example.

### subPath

`subPath` allows a container to mount a subdirectory or subfile of a volume instead of the entire volume. This is useful when multiple containers need different parts of the same volume.

```yaml
spec:
  containers:
    - name: mysql
      image: mysql
      volumeMounts:
        - name: shared-data
          mountPath: /var/lib/mysql
          subPath: mysql
    - name: php
      image: php:7.0-apache
      volumeMounts:
        - name: shared-data
          mountPath: /var/www/html
          subPath: html
  volumes:
    - name: shared-data
      persistentVolumeClaim:
        claimName: my-lamp-site-data
```

**Example:** See [spec.containers.volumeMounts.subPath/subpath.yaml](spec.containers.volumeMounts.subPath/subpath.yaml) for a subPath example.

### subPathExpr

`subPathExpr` allows dynamic subPath values using environment variables and Downward API fields.

```yaml
spec:
  containers:
    - name: app
      image: busybox
      env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
      volumeMounts:
        - name: logs
          mountPath: /var/log
          subPathExpr: $(POD_NAME)
  volumes:
    - name: logs
      hostPath:
        path: /var/log/pods
```

This creates a unique subdirectory for each Pod based on its name.

**Example:** See [spec.containers.volumeMounts.subPathExpr/subpathexpr.yaml](spec.containers.volumeMounts.subPathExpr/subpathexpr.yaml) for a subPathExpr example.

### Projected volumes

Projected volumes combine multiple volume sources into a single directory. Common sources include Secrets, ConfigMaps, Downward API, and ServiceAccount tokens.

```yaml
spec:
  containers:
    - name: app
      image: busybox
      volumeMounts:
        - name: config
          mountPath: /etc/config
          readOnly: true
  volumes:
    - name: config
      projected:
        sources:
          - secret:
              name: db-secret
              items:
                - key: username
                  path: db/username
          - configMap:
              name: app-config
              items:
                - key: app.conf
                  path: app.conf
          - downwardAPI:
              items:
                - path: pod-labels
                  fieldRef:
                    fieldPath: metadata.labels
          - serviceAccountToken:
              audience: api
              path: sa-token
```

All sources are projected into the single mount path. This is cleaner than mounting each source separately.

**Examples:** See [spec.containers.volumes.projected/projected.yaml](spec.containers.volumes.projected/projected.yaml) and [spec.containers.volumes.projected.sources.serviceAccountToken/sa-token.yaml](spec.containers.volumes.projected.sources.serviceAccountToken/sa-token.yaml) for projected volume examples.

---

## 8. Init containers

An **init container** runs before the main application containers. Init containers run sequentially and must complete successfully before the next init container or app container starts. ([Kubernetes][4])

Use init containers for:

```text
Waiting for dependency readiness
Database migration checks
Downloading configuration
Generating files
Permission setup
Pre-flight validation
```

Example:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: init-demo
spec:
  initContainers:
    - name: wait-for-service
      image: busybox:1.36
      command:
        - sh
        - -c
        - |
          echo "Checking dependency..."
          nslookup kubernetes.default.svc.cluster.local

  containers:
    - name: app
      image: nginx:1.27
      ports:
        - containerPort: 80
```

**Example:** See [init-container.yaml](spec.initContainers/init-container.yaml) for a practical init container example.

Production tip: keep init containers deterministic and fast. If an init container hangs forever, your Pod stays stuck in init state.

Debug:

```bash
kubectl get pod init-demo
kubectl describe pod init-demo
kubectl logs init-demo -c wait-for-service
```

---

## 9. Sidecar containers

A **sidecar** is a helper container that runs alongside the main application container. Kubernetes now documents sidecar containers as a special case of init containers that remain running after Pod startup. ([Kubernetes][5])

Common sidecar use cases:

```text
Service mesh proxy, for example Envoy
Log forwarding
Certificate renewal
Config reloader
Local cache
File synchronization
Metrics exporter
```

Example pattern:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sidecar-demo
spec:
  containers:
    - name: app
      image: nginx:1.27
      ports:
        - containerPort: 80
      volumeMounts:
        - name: logs
          mountPath: /var/log/nginx

    - name: log-reader
      image: busybox:1.36
      command: ["sh", "-c", "tail -F /var/log/nginx/access.log"]
      volumeMounts:
        - name: logs
          mountPath: /var/log/nginx

  volumes:
    - name: logs
      emptyDir: {}
```

Senior-level advice: do not use sidecars just because you can. Sidecars increase resource consumption, startup complexity, shutdown complexity, observability complexity, and failure modes.

---

## 9.5. Container lifecycle hooks

Containers can execute custom logic at specific points in their lifecycle using `postStart` and `preStop` hooks. These hooks are executed **inside the container** and can run commands.

**Important:** `postStart` runs asynchronously and there is no guarantee it completes before the container starts accepting traffic. Do not rely on it for critical initialization.

Example:

```yaml
spec:
  containers:
    - name: app
      image: nginx:1.27
      lifecycle:
        postStart:
          exec:
            command: ["/bin/sh", "-c", "echo 'Container started' > /tmp/started.txt"]
        preStop:
          exec:
            command: ["/bin/sh", "-c", "nginx -s quit; while killall -0 nginx 2>/dev/null; do sleep 1; done"]
```

**Common use cases:**

```text
postStart: Pre-cache files, validate environment, log startup
preStop: Graceful shutdown, cleanup resources, drain requests
```

Do not use lifecycle hooks for initialization. Use `startupProbe`, `readinessProbe`, and `initContainers` instead.

**Example:** See [spec.containers.lifecycle/lifecycle.yaml](spec.containers.lifecycle/lifecycle.yaml) for lifecycle hooks example.

---

## 10. Ephemeral containers

**Ephemeral containers** are temporary containers injected into an existing Pod for troubleshooting. They are for debugging, not for normal application execution. Kubernetes marks ephemeral containers as stable since v1.25. ([Kubernetes][6])

Example:

```bash
kubectl debug -it my-pod --image=busybox:1.36 --target=my-container -- sh
```

Useful when your application image is minimal and lacks tools like:

```text
sh
curl
dig
netstat
ps
tcpdump
```

Example debugging flow:

```bash
kubectl debug -it my-pod --image=nicolaka/netshoot --target=app -- bash
```

Then inside:

```bash
curl localhost:8080/health
dig backend.default.svc.cluster.local
ss -tulpn
ip addr
```

Production tip: ephemeral containers are powerful. Access should be controlled with RBAC because they can expose sensitive runtime context.

---

## 11. Probes: liveness, readiness, startup

Kubernetes probes are health checks executed by the kubelet. They can run commands inside the container or make network requests. Based on probe results, Kubernetes can restart unhealthy containers or stop sending traffic to containers that are not ready. ([Kubernetes][7])

There are three major probes:

| Probe            | Purpose                                                                                 | Example |
| ---------------- | --------------------------------------------------------------------------------------- | --- |
| `startupProbe`   | Protects slow-starting apps. Until it succeeds, liveness/readiness behavior is delayed. | [advanced-liveness.yaml](spec.containers.livenessProbe/advanced-liveness.yaml) |
| `readinessProbe` | Decides whether the Pod should receive traffic from a Service.                          | [readiness.yaml](spec.containers.readinessProbe/readiness.yaml) |
| `livenessProbe`  | Decides whether the container is stuck and should be restarted.                         | [liveness.yaml](spec.containers.livenessProbe/liveness.yaml) |

Example:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: probe-demo
  labels:
    app: probe-demo
spec:
  containers:
    - name: app
      image: nginx:1.27
      ports:
        - containerPort: 80

      startupProbe:
        httpGet:
          path: /
          port: 80
        failureThreshold: 30
        periodSeconds: 2

      readinessProbe:
        httpGet:
          path: /
          port: 80
        initialDelaySeconds: 5
        periodSeconds: 5

      livenessProbe:
        httpGet:
          path: /
          port: 80
        initialDelaySeconds: 15
        periodSeconds: 10
```

Practical guidance:

```text
Use readiness for dependency readiness.
Use liveness only for unrecoverable stuck states.
Use startupProbe for slow boot applications.
Do not make liveness depend on external services like DB, Redis, Kafka, or another API.
```

Bad liveness probe:

```text
/app/health checks database.
Database has a short outage.
Kubernetes restarts every app Pod.
The outage becomes worse.
```

Better:

```text
livenessProbe checks only whether the app process/event loop is alive.
readinessProbe checks whether the app can serve traffic.
```

---

## 12. Resource requests and limits

Resources are one of the most important production parts of a Pod.

```yaml
resources:
  requests:
    cpu: "250m"
    memory: "256Mi"
  limits:
    cpu: "1000m"
    memory: "512Mi"
```

The scheduler uses **requests** to decide where a Pod can fit. It checks whether the sum of requested resources can fit on a node. Actual current usage being low does not matter if requested capacity cannot fit. ([Kubernetes][8])

**Examples:** See [resource-request.yaml](spec.containers.resources/resource-request.yaml), [resource-limit.yaml](spec.containers.resources/resource-limit.yaml), and [memory-request-limit.yaml](spec.containers.resources/memory-request-limit.yaml).

Important behavior:

```text
CPU request = scheduling weight and guaranteed CPU share under contention.
CPU limit = CPU throttling ceiling.
Memory request = scheduling reservation.
Memory limit = hard-ish memory ceiling; exceeding it can cause OOM kill.
```

Kubernetes documentation notes that CPU overuse does not normally kill containers, but memory limit violations can trigger the kernel OOM subsystem and cause the container to be stopped/restarted. ([Kubernetes][8])

Production advice:

```text
Always set memory requests.
Usually set memory limits.
Always set CPU requests.
Be careful with CPU limits for latency-sensitive services.
Use metrics before choosing values.
```

A common senior-level rule:

```text
Memory limit protects the node (prevents OOM issues affecting other Pods).
CPU limit can hurt latency (requests matter more than limits).
Requests drive scheduling and autoscaling quality.
```

CPU throttling happens silently; memory limit violations trigger OOM kills which are visible in logs.

---

## 13. QoS classes

Kubernetes assigns Pods a **Quality of Service** class based on container requests and limits. These classes influence eviction order when a node is under pressure. The classes are `Guaranteed`, `Burstable`, and `BestEffort`; under resource pressure, Kubernetes evicts `BestEffort` first, then `Burstable`, then `Guaranteed`. ([Kubernetes][9])

### Guaranteed

Every container has CPU and memory request equal to limit.

```yaml
resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
```

### Burstable

At least one request exists, but requests and limits are not all equal.

```yaml
resources:
  requests:
    cpu: "250m"
    memory: "256Mi"
  limits:
    cpu: "1000m"
    memory: "512Mi"
```

### BestEffort

No requests and no limits.

```yaml
resources: {}
```

Avoid `BestEffort` for production workloads.

---

## 14. Scheduling Pods

The scheduler assigns Pods to nodes. A Pod is scheduled once in its lifetime; after it is bound to a node, Kubernetes tries to run it there. If it needs replacement, a new Pod is created rather than the same Pod being rescheduled. ([Kubernetes][2])

Basic scheduling controls:

### `nodeSelector`

```yaml
spec:
  nodeSelector:
    kubernetes.io/os: linux
    node-role.kubernetes.io/master: ""
```

Simple label-based node selection. The scheduler will only consider nodes that have **all** the specified labels. This is the simplest scheduling mechanism.

**Example:** See [spec.nodeSelector/simple.yaml](spec.nodeSelector/simple.yaml) directory for examples.

### Tolerations and taints

Taints are applied to nodes to repel Pods. Tolerations are applied to Pods to allow scheduling on tainted nodes.

**Taints** (on nodes):

```bash
kubectl taint nodes master pod-toleration:NoSchedule
```

**Tolerations** (in Pod spec):

```yaml
spec:
  tolerations:
    - key: pod-toleration
      operator: Equal
      value: ""
      effect: NoSchedule
    - key: ""
      operator: Exists
      effect: NoExecute
      tolerationSeconds: 300
```

Common effects:

```text
NoSchedule: do not schedule Pod on tainted node
NoExecute: evict running Pod and do not schedule new Pods
PreferNoSchedule: prefer not to schedule (soft constraint)
```

Operator options:

```text
Equal: key and value must match
Exists: key must exist, ignore value
```

Use case: dedicated node pools for specific workloads (GPU nodes, high-memory nodes, special hardware).

**Example:** See [spec.tolerations/toleration.yaml](spec.tolerations/toleration.yaml) for a tolerations example.

### Topology spread constraints

Ensure Pods are evenly spread across topology domains (zones, regions, nodes) for availability and performance.

```yaml
spec:
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app: api
```

**Parameters:**

```text
maxSkew: maximum difference in Pod count between topology domains (1-3 typical)
topologyKey: node label key (zone, hostname, region)
whenUnsatisfiable: DoNotSchedule (hard) or ScheduleAnyway (soft)
labelSelector: which Pods to count
```

Highly recommended for production to ensure resilience.

**Example:** See [spec.topologySpreadConstraints/topology-spread-constraints.yaml](spec.topologySpreadConstraints/topology-spread-constraints.yaml) for topology spread constraints examples.

### Node affinity

Node affinity is more expressive than `nodeSelector`; it supports required and preferred rules. Required rules must be satisfied, while preferred rules influence scheduling but do not absolutely block scheduling if unmet. ([Kubernetes][10])

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: nodepool
                operator: In
                values:
                  - high-memory
```

**Example:** See [node-affinity.yaml](spec.affinity.nodeAffinity/node-affinity.yaml).

### Pod anti-affinity

Useful to spread replicas across nodes:

```yaml
spec:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchLabels:
                app: api
            topologyKey: kubernetes.io/hostname
```

Production advice:

```text
Use topology spread constraints or anti-affinity for HA.
Avoid hard anti-affinity unless necessary; it can make Pods unschedulable.
Use taints/tolerations for dedicated node pools.
Use requests correctly; scheduling quality depends on them.
```

---

## 15. Security context

Pod security should be defined explicitly. Kubernetes Pod Security Standards define three profiles: `Privileged`, `Baseline`, and `Restricted`. `Restricted` follows current Pod hardening best practices, while `Privileged` is intentionally unrestricted and can bypass normal container isolation mechanisms. ([Kubernetes][11])

Good baseline example:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault

  containers:
    - name: app
      image: nginx:1.27
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
      ports:
        - containerPort: 80
```

**Examples:** See [privileged-simple.yaml](spec.containers.securityContext/privileged-simple.yaml) and [privileged-namespace.yaml](spec.containers.securityContext/privileged-namespace.yaml) for security context examples.

Production checklist:

```text
Do not run as root unless required.
Set runAsNonRoot: true.
Drop Linux capabilities.
Disable privilege escalation.
Use RuntimeDefault seccomp.
Avoid hostNetwork, hostPID, hostIPC unless absolutely necessary.
Avoid privileged containers.
Mount ServiceAccount tokens only when needed.
Use NetworkPolicies.
Use admission policies to enforce standards.
```

---

## 16. Environment variables and configuration

Example:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: env-demo
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo APP_ENV=$APP_ENV && sleep 3600"]
      env:
        - name: APP_ENV
          value: "dev"
```

Usually you should not hardcode config directly in Pod manifests. Use:

```text
ConfigMap for non-sensitive config.
Secret for sensitive config.
Projected volumes when combining config sources.
External secret managers for serious production environments.
```

### Image pull policy

The `imagePullPolicy` determines when Kubernetes pulls the container image from the registry.

```yaml
spec:
  containers:
    - name: app
      image: nginx:1.27
      imagePullPolicy: IfNotPresent
```

**Policies:**

```text
IfNotPresent: pull only if not already on the node (default for versioned images)
Always: always pull from registry (default for 'latest' tag)
Never: use only cached images, fail if not present
```

Usage:

```text
Use Always for CI/CD deployments to get latest image
Use IfNotPresent for development to avoid pull overhead
Use Never for air-gapped environments
```

**Example:** See [spec.containers.imagePullPolicy/image-pull-policy.yaml](spec.containers.imagePullPolicy/image-pull-policy.yaml) for imagePullPolicy example.

### Image pull secrets

For private container registries, use `imagePullSecrets` to provide credentials.

```yaml
spec:
  imagePullSecrets:
    - name: regcred
  containers:
    - name: app
      image: private-registry.example.com/my-app:1.0
```

Create the secret:

```bash
kubectl create secret docker-registry regcred \
  --docker-server=private-registry.example.com \
  --docker-username=myuser \
  --docker-password=mypassword \
  --docker-email=myemail@example.com
```

**Example:** See [spec.imagePullSecrets/image-pull-secrets.yaml](spec.imagePullSecrets/image-pull-secrets.yaml) for imagePullSecrets example.

---

## 17. Labels and selectors

Labels are key-value metadata used by Services, Deployments, NetworkPolicies, monitoring, logging, and operational tooling.

Example:

```yaml
metadata:
  labels:
    app: payment-api
    version: v1
    env: prod
    team: platform
```

Query:

```bash
kubectl get pods -l app=payment-api
kubectl get pods -l env=prod,team=platform
kubectl get pods --show-labels
```

Senior advice: design labels intentionally. Bad labels create painful operations later.

Recommended common labels:

```yaml
app.kubernetes.io/name: payment-api
app.kubernetes.io/instance: payment-api-prod
app.kubernetes.io/version: "1.4.2"
app.kubernetes.io/component: api
app.kubernetes.io/part-of: payment-platform
app.kubernetes.io/managed-by: helm
```

---

## 18. Pod termination

When a Pod is deleted, Kubernetes gives it time to shut down gracefully. The default grace period is 30 seconds. ([Kubernetes][2])

Example:

```yaml
spec:
  terminationGracePeriodSeconds: 60
  containers:
    - name: app
      image: my-app:1.0
      lifecycle:
        preStop:
          exec:
            command: ["sh", "-c", "sleep 10"]
```

**Example:** See [spec.terminationGracePeriodSeconds/simple.yaml](spec.terminationGracePeriodSeconds/simple.yaml) for a termination grace period example.

Set `terminationGracePeriodSeconds` appropriately:

```text
Too low: Pods get killed before finishing requests
Too high: slow pod eviction during node drains
Typical: 30-60 seconds
```

```text
Pod deletion requested.
Pod enters Terminating.
Kubernetes removes it from Service endpoints after readiness changes.
preStop hook runs if configured.
SIGTERM sent to container process.
Application should stop accepting new work.
Application should finish in-flight requests.
After grace period, SIGKILL is sent.
```

Application requirement:

```text
Your app must handle SIGTERM correctly.
```

For Node.js, Go, Java, Python, etc., this means implementing graceful shutdown.

---

## 19. Full production-style Pod example

Normally this would live inside a Deployment template, but as a Pod example:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: api-pod
  labels:
    app.kubernetes.io/name: api
    app.kubernetes.io/component: backend
    env: prod
spec:
  terminationGracePeriodSeconds: 60

  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault

  containers:
    - name: api
      image: ghcr.io/example/api:1.0.0
      imagePullPolicy: IfNotPresent

      ports:
        - name: http
          containerPort: 8080

      env:
        - name: APP_ENV
          value: "production"

      resources:
        requests:
          cpu: "250m"
          memory: "256Mi"
        limits:
          memory: "512Mi"

      startupProbe:
        httpGet:
          path: /startup
          port: http
        failureThreshold: 30
        periodSeconds: 2

      readinessProbe:
        httpGet:
          path: /ready
          port: http
        periodSeconds: 5
        failureThreshold: 3

      livenessProbe:
        httpGet:
          path: /live
          port: http
        periodSeconds: 10
        failureThreshold: 3

      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL

      volumeMounts:
        - name: tmp
          mountPath: /tmp

  volumes:
    - name: tmp
      emptyDir: {}
```

Notice:

```text
No root.
No privilege escalation.
Resources are defined.
Probes are separated by responsibility.
Named port is used.
Writable filesystem is limited to /tmp.
Graceful termination is configured.
```

---

## 20. Debugging Pods like a senior engineer

Start broad:

```bash
kubectl get pods -A
kubectl get pod <pod> -n <ns> -o wide
kubectl describe pod <pod> -n <ns>
```

Check events:

```bash
kubectl get events -n <ns> --sort-by='.lastTimestamp'
```

Check logs:

```bash
kubectl logs <pod> -n <ns>
kubectl logs <pod> -n <ns> -c <container>
kubectl logs <pod> -n <ns> --previous
```

Check YAML/status:

```bash
kubectl get pod <pod> -n <ns> -o yaml
kubectl get pod <pod> -n <ns> -o jsonpath='{.status}'
```

Exec into container:

```bash
kubectl exec -it <pod> -n <ns> -- sh
```

Debug with temporary container:

```bash
kubectl debug -it <pod> -n <ns> --image=nicolaka/netshoot --target=<container> -- bash
```

Check why it is pending:

```bash
kubectl describe pod <pod> -n <ns>
```

Common causes:

```text
Insufficient CPU/memory
Node selector mismatch
Affinity too strict
Taints without tolerations
PVC not bound
Image pull secret missing
Admission policy rejection
```

Check why it crashes:

```bash
kubectl logs <pod> --previous
kubectl describe pod <pod>
kubectl get pod <pod> -o jsonpath='{.status.containerStatuses[*].lastState}'
```

Common causes:

```text
Wrong command or args
Missing environment variables
ConfigMap/Secret missing
App cannot bind port
Permission issue due to non-root user
Read-only filesystem problem
Dependency unavailable
OOMKilled
Bad liveness probe
```

Check OOM:

```bash
kubectl describe pod <pod>
```

Look for:

```text
Reason: OOMKilled
Exit Code: 137
```

---

## 21. Common Pod statuses and what to do

### `Pending`

Likely causes:

```text
No node has enough requested resources.
PVC is not bound.
Node selector/affinity cannot be satisfied.
Taints are blocking scheduling.
Image is still pulling.
```

Commands:

```bash
kubectl describe pod <pod>
kubectl get nodes
kubectl describe nodes
kubectl get pvc
```

### `ImagePullBackOff` / `ErrImagePull`

Likely causes:

```text
Wrong image name.
Wrong tag.
Private registry auth missing.
Registry unavailable.
Image architecture mismatch.
```

Commands:

```bash
kubectl describe pod <pod>
kubectl get secret
kubectl create secret docker-registry ...
```

### `CrashLoopBackOff`

Likely causes:

```text
App exits immediately.
Bad config.
Missing secret.
Wrong command.
Liveness probe killing the app.
Permission error.
```

Commands:

```bash
kubectl logs <pod> --previous
kubectl describe pod <pod>
```

### `RunContainerError`

Likely causes:

```text
Container runtime cannot start the container.
Bad mount.
Invalid command.
SecurityContext conflict.
Volume permission problem.
```

### `CreateContainerConfigError`

Likely causes:

```text
Referenced ConfigMap or Secret does not exist.
Invalid environment variable source.
Bad volume configuration.
```

---

## 22. Pod anti-patterns

Avoid these:

```text
Creating naked Pods for production services.
Using latest image tag.
No resource requests.
No readiness probe.
Liveness probe depends on external DB.
Running as root by default.
Privileged containers without strong reason.
Writing durable data into container filesystem.
Depending on Pod IPs.
Putting unrelated containers in one Pod.
Using sidecars for things better handled by platform tooling.
Making hard affinity rules too strict.
Ignoring graceful shutdown.
```

Better patterns:

```text
Deployment for stateless services.
StatefulSet for stable identity/stateful workloads.
DaemonSet for one Pod per node agents.
Job for one-time execution.
CronJob for scheduled execution.
Service for stable networking.
PVC for durable storage.
ConfigMap/Secret for configuration.
HPA/KEDA for autoscaling.
PDB for disruption control.
NetworkPolicy for traffic control.
```

---

## 23. Senior-level practical tips

Use this mental checklist before shipping a Pod template:

```text
Can it be killed at any time without data loss?
Does it handle SIGTERM?
Does it have readiness, liveness, and maybe startup probes?
Are resource requests realistic?
Can it run as non-root?
Are secrets mounted safely?
Are logs written to stdout/stderr?
Does it avoid local persistent state?
Is the image pinned to a real version?
Does it have labels useful for ownership, monitoring, and selection?
Can I debug it with kubectl logs, describe, exec, and debug?
```

One of the most important production lessons: **Pods are not pets; they are replaceable runtime units**. Design applications so that any Pod can disappear and be replaced without manual intervention.

[1]: https://kubernetes.io/docs/concepts/workloads/pods/ "Pods | Kubernetes"
[2]: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/ "Pod Lifecycle | Kubernetes"
[3]: https://kubernetes.io/docs/concepts/storage/volumes/ "Volumes"
[4]: https://kubernetes.io/docs/concepts/workloads/pods/init-containers/ "Init Containers"
[5]: https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/ "Sidecar Containers"
[6]: https://kubernetes.io/docs/concepts/workloads/pods/ephemeral-containers/ "Ephemeral Containers"
[7]: https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/ "Liveness, Readiness, and Startup Probes"
[8]: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ "Resource Management for Pods and Containers | Kubernetes"
[9]: https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/ "Pod Quality of Service Classes"
[10]: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/ "Assigning Pods to Nodes | Kubernetes"
[11]: https://kubernetes.io/docs/concepts/security/pod-security-standards/ "Pod Security Standards | Kubernetes"





See: https://kubernetes.io/docs/concepts/services-networking/add-entries-to-pod-etc-hosts-with-host-aliases/#adding-additional-entries-with-hostaliases
