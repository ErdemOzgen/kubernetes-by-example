# Kubernetes DaemonSet 

A **DaemonSet** ensures that **one Pod runs on every eligible node**, or on every eligible node matching a selector/affinity rule. When nodes are added, the DaemonSet controller adds Pods to them. When nodes are removed, those Pods are garbage-collected. Deleting the DaemonSet also cleans up the Pods it created. ([Kubernetes][1])

The mental model:

```text
DaemonSet
  ├── node-1 → daemon-pod
  ├── node-2 → daemon-pod
  ├── node-3 → daemon-pod
  └── node-N → daemon-pod
```

A Deployment answers:

```text
“Run 5 replicas somewhere in the cluster.”
```

A DaemonSet answers:

```text
“Run 1 replica on each eligible node.”
```

---

# 1. Why DaemonSets exist

DaemonSets are for **node-level functionality**.

Typical use cases:

```text
Every node needs a logging agent.
Every node needs a monitoring agent.
Every node needs a CNI/networking component.
Every node needs a storage agent.
Every GPU node needs a device plugin.
Every node needs a security/EDR agent.
```

Official Kubernetes examples include storage daemons, log collection daemons, and node monitoring daemons. ([Kubernetes][1])

Real-world examples:

| Use case                | Common DaemonSet                        |
| ----------------------- | --------------------------------------- |
| Networking              | Cilium, Calico, Flannel                 |
| Logging                 | Fluent Bit, Fluentd, Vector             |
| Monitoring              | Prometheus Node Exporter, Datadog Agent |
| Security                | Falco, runtime security agents          |
| Storage                 | Ceph, Longhorn node components          |
| GPU                     | NVIDIA device plugin                    |
| Service mesh/node proxy | Some node-local proxy agents            |

---

# 2. DaemonSet vs Deployment

## Deployment

Use a Deployment when you care about **replica count**, not exact node placement.

```text
Run 6 copies of my frontend anywhere.
```

Example:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 6
```

Kubernetes decides which nodes get the Pods.

---

## DaemonSet

Use a DaemonSet when you care that **each node has its own local Pod**.

```text
Run one log collector on every node.
```

Example:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
```

The DaemonSet controller tries to place one Pod on every eligible node.

Kubernetes explicitly recommends Deployments for stateless services where scaling and rolling updates matter more than host-level placement, and DaemonSets when a copy must run on all or certain hosts for node-level functionality. ([Kubernetes][1])

---

# 3. DaemonSet object structure

A minimal DaemonSet:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: node-agent
  template:
    metadata:
      labels:
        app: node-agent
    spec:
      containers:
        - name: node-agent
          image: busybox:1.37
          command:
            - sh
            - -c
            - while true; do echo "running on $(hostname)"; sleep 10; done
```

Important fields:

```text
apiVersion: apps/v1
kind: DaemonSet
metadata
spec.selector
spec.template
spec.template.metadata.labels
spec.template.spec.containers
```

A DaemonSet requires `.spec.template`; that template uses the same schema as a Pod template, except it is nested and does not have its own `apiVersion` or `kind`. The Pod template must use `restartPolicy: Always`, or omit it because `Always` is the default. ([Kubernetes][1])

---

# 4. Hands-on lab: create a basic DaemonSet

Create a namespace:

```bash
kubectl create namespace daemonset-lab
```

Create `daemonset-basic.yaml`:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-echo
  namespace: daemonset-lab
  labels:
    app: node-echo
spec:
  selector:
    matchLabels:
      app: node-echo
  template:
    metadata:
      labels:
        app: node-echo
    spec:
      containers:
        - name: node-echo
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              while true; do
                echo "DaemonSet pod running on node: ${NODE_NAME}"
                sleep 10
              done
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
          resources:
            requests:
              cpu: "20m"
              memory: "32Mi"
            limits:
              cpu: "100m"
              memory: "64Mi"
```

Apply:

```bash
kubectl apply -f daemonset-basic.yaml
```

Check DaemonSet:

```bash
kubectl get daemonset -n daemonset-lab
```

Shortcut:

```bash
kubectl get ds -n daemonset-lab
```

Check Pods:

```bash
kubectl get pods -n daemonset-lab -o wide
```

Expected behavior:

```text
One node-echo Pod per eligible node.
```

If your cluster has 3 worker nodes, you should generally see 3 DaemonSet Pods.

View logs:

```bash
kubectl logs -n daemonset-lab -l app=node-echo --tail=20
```

Get one Pod per node:

```bash
kubectl get pods -n daemonset-lab -l app=node-echo -o wide
```

---

# 5. Core reconciliation logic

The DaemonSet controller continuously compares:

```text
desired state:
  every eligible node should have one matching Pod

actual state:
  which nodes currently have matching Pods?
```

Then it reconciles:

| Situation                  | DaemonSet behavior                        |
| -------------------------- | ----------------------------------------- |
| New node added             | Creates a Pod for that node               |
| Node removed               | Pod is garbage-collected                  |
| Pod deleted manually       | Creates replacement Pod                   |
| Node label starts matching | Creates Pod on that node                  |
| Node label stops matching  | Deletes Pod from that node                |
| DaemonSet deleted          | Deletes owned Pods                        |
| Pod template changed       | Updates Pods according to update strategy |

Kubernetes documents that if node labels change, the DaemonSet promptly adds Pods to newly matching nodes and deletes Pods from newly not-matching nodes. ([Kubernetes][1])

---

# 6. Selector rules

A DaemonSet has a selector:

```yaml
spec:
  selector:
    matchLabels:
      app: node-echo
```

And the Pod template has labels:

```yaml
template:
  metadata:
    labels:
      app: node-echo
```

These must match.

Bad:

```yaml
spec:
  selector:
    matchLabels:
      app: node-agent
  template:
    metadata:
      labels:
        app: different-agent
```

This is rejected by the Kubernetes API because the selector must match `.spec.template.metadata.labels`. The DaemonSet selector is immutable after creation, because changing it can orphan Pods. ([Kubernetes][1])

Senior rule:

```text
Keep DaemonSet selectors stable.
Do not put version, image tag, commit SHA, or rollout-specific labels in selectors.
```

Good selector labels:

```yaml
app.kubernetes.io/name: node-agent
app.kubernetes.io/component: logging-agent
```

Bad selector labels:

```yaml
version: v1.2.3
commit: abc123
```

---

# 7. How DaemonSet Pods are scheduled

Modern DaemonSet scheduling is subtle.

The DaemonSet controller determines eligible nodes. For each eligible node, it creates a Pod and injects node affinity targeting that specific node. The default scheduler then usually binds that Pod to the target node by setting `.spec.nodeName`. ([Kubernetes][1])

Conceptually:

```text
DaemonSet controller:
  node-1 eligible? yes → create Pod with affinity to node-1
  node-2 eligible? yes → create Pod with affinity to node-2
  node-3 eligible? no  → no Pod

Scheduler:
  bind each DaemonSet Pod to its intended node
```

You can inspect this:

```bash
POD=$(kubectl get pod -n daemonset-lab -l app=node-echo -o jsonpath='{.items[0].metadata.name}')

kubectl get pod "$POD" -n daemonset-lab -o yaml | less
```

Look for:

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchFields:
              - key: metadata.name
                operator: In
                values:
                  - target-node-name
```

That node affinity is added by Kubernetes to tie the Pod to a specific node.

---

# 8. Run DaemonSet only on selected nodes

By default, a DaemonSet runs on all eligible nodes. To restrict it, use:

```text
nodeSelector
nodeAffinity
taints/tolerations
```

Kubernetes says that if you set `.spec.template.spec.nodeSelector`, the DaemonSet controller creates Pods only on matching nodes; similarly, node affinity restricts DaemonSet Pods to matching nodes. If neither is specified, the DaemonSet targets all nodes. ([Kubernetes][1])

---

## Example: run only on logging nodes

Label a node:

```bash
kubectl get nodes
kubectl label node <node-name> node-role.example.com/logging=true
```

Create `daemonset-node-selector.yaml`:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: logging-agent
  namespace: daemonset-lab
spec:
  selector:
    matchLabels:
      app: logging-agent
  template:
    metadata:
      labels:
        app: logging-agent
    spec:
      nodeSelector:
        node-role.example.com/logging: "true"
      containers:
        - name: agent
          image: busybox:1.37
          command:
            - sh
            - -c
            - while true; do echo "logging agent on ${NODE_NAME}"; sleep 10; done
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
```

Apply:

```bash
kubectl apply -f daemonset-node-selector.yaml
kubectl get pods -n daemonset-lab -l app=logging-agent -o wide
```

Only the labeled node should get a Pod.

Remove label:

```bash
kubectl label node <node-name> node-role.example.com/logging-
```

Watch the Pod disappear:

```bash
kubectl get pods -n daemonset-lab -l app=logging-agent -w
```

---

# 9. Node affinity version

`nodeSelector` is simple. `nodeAffinity` is more expressive.

Kubernetes node affinity supports hard rules with `requiredDuringSchedulingIgnoredDuringExecution` and soft preferences with `preferredDuringSchedulingIgnoredDuringExecution`; `IgnoredDuringExecution` means that if labels change after scheduling, the running Pod continues to run. ([Kubernetes][2])

Example: run only on Linux nodes with SSD storage:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: storage-agent
  namespace: daemonset-lab
spec:
  selector:
    matchLabels:
      app: storage-agent
  template:
    metadata:
      labels:
        app: storage-agent
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.io/os
                    operator: In
                    values:
                      - linux
                  - key: storage.example.com/type
                    operator: In
                    values:
                      - ssd
      containers:
        - name: storage-agent
          image: busybox:1.37
          command:
            - sh
            - -c
            - while true; do echo "storage agent running"; sleep 10; done
```

Label one node:

```bash
kubectl label node <node-name> storage.example.com/type=ssd
```

Apply:

```bash
kubectl apply -f storage-agent.yaml
kubectl get pods -n daemonset-lab -l app=storage-agent -o wide
```

---

# 10. Taints and tolerations with DaemonSets

Taints repel Pods from nodes. Tolerations let Pods tolerate matching taints, but they do not force scheduling by themselves. Kubernetes describes taints as the opposite of affinity: nodes repel Pods unless those Pods tolerate the taint. ([Kubernetes][3])

Example taint:

```bash
kubectl taint nodes <node-name> dedicated=infra:NoSchedule
```

A normal Pod without toleration will not schedule there.

A DaemonSet can tolerate it:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: infra-agent
  namespace: daemonset-lab
spec:
  selector:
    matchLabels:
      app: infra-agent
  template:
    metadata:
      labels:
        app: infra-agent
    spec:
      tolerations:
        - key: dedicated
          operator: Equal
          value: infra
          effect: NoSchedule
      containers:
        - name: infra-agent
          image: busybox:1.37
          command:
            - sh
            - -c
            - while true; do echo "infra agent"; sleep 10; done
```

Remove taint:

```bash
kubectl taint nodes <node-name> dedicated=infra:NoSchedule-
```

Important DaemonSet-specific behavior: Kubernetes automatically adds several tolerations to DaemonSet Pods, including tolerations for not-ready, unreachable, disk pressure, memory pressure, PID pressure, unschedulable, and, for host-networked Pods, network-unavailable. This is why DaemonSet Pods can run on nodes that ordinary application Pods would avoid. ([Kubernetes][1])

That behavior is important for system agents. For example, a CNI DaemonSet may need to start before the node is fully ready; otherwise, the node might never become ready because networking is not installed yet. ([Kubernetes][1])

---

# 11. DaemonSets and control-plane nodes

Many clusters taint control-plane nodes with something like:

```text
node-role.kubernetes.io/control-plane:NoSchedule
```

A DaemonSet will not run there unless it tolerates that taint.

Example:

```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

Full example:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: control-plane-agent
  namespace: daemonset-lab
spec:
  selector:
    matchLabels:
      app: control-plane-agent
  template:
    metadata:
      labels:
        app: control-plane-agent
    spec:
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      containers:
        - name: agent
          image: busybox:1.37
          command:
            - sh
            - -c
            - while true; do echo "control plane capable agent"; sleep 10; done
```

For critical cluster agents like networking, logging, or monitoring, you often need this. For normal workload agents, you may intentionally avoid control-plane nodes.

---

# 12. DaemonSet update strategies

DaemonSets support two update strategies:

```text
RollingUpdate
OnDelete
```

`RollingUpdate` is the default. With `RollingUpdate`, Kubernetes kills old DaemonSet Pods and creates new ones automatically in a controlled fashion. With `OnDelete`, updating the template does not automatically replace existing Pods; new Pods are created only when old Pods are manually deleted. ([Kubernetes][4])

---

## RollingUpdate example

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-echo
  namespace: daemonset-lab
spec:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 0
  selector:
    matchLabels:
      app: node-echo
  template:
    metadata:
      labels:
        app: node-echo
    spec:
      containers:
        - name: node-echo
          image: busybox:1.37
          command:
            - sh
            - -c
            - while true; do echo "v1 running on ${NODE_NAME}"; sleep 10; done
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
```

Apply:

```bash
kubectl apply -f daemonset-basic.yaml
```

Update the command or image:

```bash
kubectl set image daemonset/node-echo node-echo=busybox:1.36 -n daemonset-lab
```

Watch rollout:

```bash
kubectl rollout status daemonset/node-echo -n daemonset-lab
kubectl get pods -n daemonset-lab -l app=node-echo -w
```

Check history:

```bash
kubectl rollout history daemonset/node-echo -n daemonset-lab
```

Rollback:

```bash
kubectl rollout undo daemonset/node-echo -n daemonset-lab
```

---

## `maxUnavailable`

```yaml
updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1
```

This means Kubernetes may make at most one DaemonSet Pod unavailable during the rollout.

For node agents, this is usually safer than replacing many agents simultaneously.

---

## `maxSurge`

```yaml
updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

This allows Kubernetes to temporarily run an extra DaemonSet Pod on a node during update, depending on support and constraints. The Kubernetes rolling update docs list `maxUnavailable`, `minReadySeconds`, and `maxSurge` as fields you may set for DaemonSet rolling updates. ([Kubernetes][4])

Senior caution:

```text
maxSurge for DaemonSets can be dangerous for hostPort, hostPath lock files, device plugins, CNI agents, or agents that assume one process per node.
```

If your daemon cannot tolerate two copies on the same node, keep:

```yaml
maxSurge: 0
```

---

## OnDelete example

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: manual-agent
  namespace: daemonset-lab
spec:
  updateStrategy:
    type: OnDelete
  selector:
    matchLabels:
      app: manual-agent
  template:
    metadata:
      labels:
        app: manual-agent
    spec:
      containers:
        - name: manual-agent
          image: busybox:1.37
          command:
            - sh
            - -c
            - while true; do echo "manual update agent"; sleep 10; done
```

Apply:

```bash
kubectl apply -f manual-agent.yaml
```

Change image in YAML and re-apply:

```bash
kubectl apply -f manual-agent.yaml
```

Existing Pods will not be replaced automatically. Delete one manually:

```bash
kubectl delete pod <manual-agent-pod> -n daemonset-lab
```

The recreated Pod uses the new template.

Use `OnDelete` when you need strict manual control, usually for sensitive node-level agents.

---

# 13. DaemonSet with hostPath

Many DaemonSets need node filesystem access.

Example: read host logs.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: host-log-reader
  namespace: daemonset-lab
spec:
  selector:
    matchLabels:
      app: host-log-reader
  template:
    metadata:
      labels:
        app: host-log-reader
    spec:
      containers:
        - name: reader
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              while true; do
                echo "Node: ${NODE_NAME}"
                ls -la /host/var/log | head
                sleep 30
              done
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
          volumeMounts:
            - name: host-var-log
              mountPath: /host/var/log
              readOnly: true
          securityContext:
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
      volumes:
        - name: host-var-log
          hostPath:
            path: /var/log
            type: Directory
```

Apply:

```bash
kubectl apply -f host-log-reader.yaml
kubectl logs -n daemonset-lab -l app=host-log-reader --tail=50
```

Senior caution:

```text
hostPath is powerful and risky.
Treat it as node-level privilege.
Make it readOnly whenever possible.
Avoid mounting /, /var/lib/kubelet, /run/containerd, or /var/run/docker.sock unless absolutely necessary.
```

---

# 14. DaemonSet with hostNetwork

Network agents often need host networking.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-http-agent
  namespace: daemonset-lab
spec:
  selector:
    matchLabels:
      app: node-http-agent
  template:
    metadata:
      labels:
        app: node-http-agent
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
        - name: server
          image: hashicorp/http-echo:1.0
          args:
            - "-listen=:18080"
            - "-text=hello from node"
          ports:
            - name: http
              containerPort: 18080
              hostPort: 18080
```

With `hostNetwork: true`, the Pod uses the node’s network namespace. With `hostPort`, the port is exposed on each node.

Senior caution:

```text
hostNetwork means the Pod shares the node network namespace.
Port conflicts become node-level conflicts.
NetworkPolicy may not behave the same way as for normal Pods depending on CNI implementation.
Use only when you need node-level networking.
```

---

# 15. Communicating with DaemonSet Pods

Kubernetes lists several communication patterns for DaemonSet Pods: push to another service, node IP plus known port, DNS using a headless Service, or a normal Service with the same Pod selector. ([Kubernetes][1])

## Pattern 1: Push model

Most logging/monitoring agents work this way.

```text
DaemonSet Pod → sends logs/metrics → backend
```

No Service needed.

---

## Pattern 2: NodeIP + hostPort

Useful for node-local agents.

```text
curl http://<node-ip>:18080
```

Downside: clients need node IP knowledge.

---

## Pattern 3: Headless Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: node-echo-headless
  namespace: daemonset-lab
spec:
  clusterIP: None
  selector:
    app: node-echo
  ports:
    - name: dummy
      port: 80
      targetPort: 80
```

This gives DNS records for the backing Pods.

---

## Pattern 4: Normal Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: node-echo
  namespace: daemonset-lab
spec:
  selector:
    app: node-echo
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

This load-balances to one of the DaemonSet Pods, which may be fine for some agents but wrong for node-local semantics.

---

# 16. DaemonSets and node drain

This is important operationally.

When you drain a node:

```bash
kubectl drain <node-name>
```

you usually need:

```bash
kubectl drain <node-name> --ignore-daemonsets
```

Kubernetes documents that `kubectl drain` alone does not actually drain DaemonSet Pods because the DaemonSet controller would immediately replace missing Pods; DaemonSet Pods also tolerate the unschedulable taint, so they can run on nodes being drained. ([Kubernetes][5])

Typical maintenance flow:

```bash
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
# perform maintenance
kubectl uncordon <node-name>
```

Meaning:

```text
Application Pods are evicted.
DaemonSet Pods usually remain.
Node-level agents keep running.
```

This is desirable for logging, monitoring, CNI, and storage components.

---

# 17. DaemonSet status fields

Run:

```bash
kubectl get ds -n daemonset-lab
```

Example output:

```text
NAME        DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
node-echo   3         3         3       3            3           <none>          10m
```

Meaning:

| Field           | Meaning                                  |
| --------------- | ---------------------------------------- |
| `DESIRED`       | Number of nodes that should run a Pod    |
| `CURRENT`       | Number of Pods currently created         |
| `READY`         | Number of Pods reporting Ready           |
| `UP-TO-DATE`    | Number of Pods matching current template |
| `AVAILABLE`     | Number of Pods available                 |
| `NODE SELECTOR` | Restriction, if any                      |

More detail:

```bash
kubectl describe ds node-echo -n daemonset-lab
```

Look at:

```text
Desired Number of Nodes Scheduled
Current Number of Nodes Scheduled
Number of Nodes Scheduled with Up-to-date Pods
Number of Nodes Misscheduled
Pods Status
Events
```

A **misscheduled** Pod is a DaemonSet Pod running on a node where it should no longer run, often due to changed labels, selectors, or affinity.

---

# 18. Debugging DaemonSets

Start with:

```bash
kubectl get ds -A
kubectl describe ds <name> -n <namespace>
kubectl get pods -n <namespace> -l <selector> -o wide
kubectl describe pod <pod> -n <namespace>
kubectl logs <pod> -n <namespace>
kubectl logs <pod> -n <namespace> --previous
kubectl get events -n <namespace> --sort-by=.lastTimestamp
```

---

## Problem: DaemonSet not running on every node

Check desired count:

```bash
kubectl get ds <name> -n <namespace>
```

Check nodes:

```bash
kubectl get nodes --show-labels
```

Check selectors:

```bash
kubectl get ds <name> -n <namespace> -o yaml
```

Look for:

```yaml
spec:
  template:
    spec:
      nodeSelector:
      affinity:
      tolerations:
```

Common causes:

| Symptom                             | Likely cause                                  |
| ----------------------------------- | --------------------------------------------- |
| Desired count lower than node count | Node selector/affinity excludes nodes         |
| Pod Pending                         | Insufficient resources or taint not tolerated |
| Pod CrashLoopBackOff                | Agent process crashing                        |
| Pod not on control plane            | Missing control-plane toleration              |
| Pod not on Windows/Linux nodes      | OS selector mismatch                          |
| ImagePullBackOff                    | Bad image or registry auth                    |
| CreateContainerConfigError          | Bad ConfigMap/Secret/env/volume               |
| Permission denied                   | SecurityContext/hostPath permissions          |
| Port conflict                       | hostPort already used on node                 |

---

## Problem: Pod is Pending

```bash
kubectl describe pod <pod> -n <namespace>
```

Look at Events:

```text
0/3 nodes are available
node(s) had untolerated taint
Insufficient cpu
Insufficient memory
didn't match Pod's node affinity/selector
```

Then inspect node taints:

```bash
kubectl describe node <node-name> | grep -i taint -A2
```

Inspect node labels:

```bash
kubectl get node <node-name> --show-labels
```

---

## Problem: rollout stuck

```bash
kubectl rollout status ds/<name> -n <namespace>
kubectl describe ds <name> -n <namespace>
kubectl get pods -n <namespace> -l app=<label> -o wide
```

Likely causes:

```text
New Pod cannot start.
Readiness probe fails.
Image cannot pull.
hostPort conflict.
hostPath missing.
New version crashes.
maxUnavailable too conservative for current cluster state.
```

---

## Problem: DaemonSet Pod manually deleted

Try:

```bash
kubectl delete pod <pod> -n daemonset-lab
```

Then:

```bash
kubectl get pods -n daemonset-lab -l app=node-echo -w
```

The DaemonSet controller recreates it.

This is exactly why DaemonSets are preferred over manually creating one Pod per node. Kubernetes notes that bare Pods can be tied to nodes, but DaemonSets replace Pods deleted or terminated due to node failure or disruptive maintenance. ([Kubernetes][1])

---

# 19. Production-grade DaemonSet example: logging agent

This example is closer to a real production logging DaemonSet.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-log-agent
  namespace: observability
  labels:
    app.kubernetes.io/name: node-log-agent
    app.kubernetes.io/component: logging
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: node-log-agent

  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1

  minReadySeconds: 10

  template:
    metadata:
      labels:
        app.kubernetes.io/name: node-log-agent
        app.kubernetes.io/component: logging
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "2020"
        prometheus.io/path: "/metrics"

    spec:
      serviceAccountName: node-log-agent
      priorityClassName: system-node-critical

      tolerations:
        - operator: Exists

      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault

      containers:
        - name: agent
          image: fluent/fluent-bit:3.1
          imagePullPolicy: IfNotPresent

          ports:
            - name: metrics
              containerPort: 2020

          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              memory: "512Mi"

          volumeMounts:
            - name: varlog
              mountPath: /var/log
              readOnly: true
            - name: containers
              mountPath: /var/lib/docker/containers
              readOnly: true

          readinessProbe:
            httpGet:
              path: /api/v1/health
              port: metrics
            initialDelaySeconds: 10
            periodSeconds: 10

          livenessProbe:
            httpGet:
              path: /api/v1/health
              port: metrics
            initialDelaySeconds: 30
            periodSeconds: 30

          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL

      volumes:
        - name: varlog
          hostPath:
            path: /var/log
            type: Directory
        - name: containers
          hostPath:
            path: /var/lib/docker/containers
            type: DirectoryOrCreate
```

Notes:

```text
serviceAccountName: use least-privilege RBAC.
priorityClassName: useful for critical node agents.
tolerations: often needed for infra nodes/control-plane nodes.
hostPath: required for host logs, but security-sensitive.
resources.requests: prevents scheduling surprises.
limits.memory: prevents runaway memory usage.
readiness/liveness: useful if the agent exposes health endpoints.
```

Be careful with:

```yaml
tolerations:
  - operator: Exists
```

This tolerates every taint. It is common for cluster-critical agents, but too broad for ordinary agents.

---

# 20. RBAC for DaemonSet agents

Many DaemonSets need Kubernetes API access.

Example ServiceAccount and RBAC:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: node-log-agent
  namespace: observability
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-log-agent
rules:
  - apiGroups: [""]
    resources: ["pods", "namespaces", "nodes"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: node-log-agent
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: node-log-agent
subjects:
  - kind: ServiceAccount
    name: node-log-agent
    namespace: observability
```

Then in the DaemonSet:

```yaml
spec:
  template:
    spec:
      serviceAccountName: node-log-agent
```

Senior rule:

```text
Do not run node agents with cluster-admin unless unavoidable.
Give them read/watch/list only where possible.
```

---

# 21. Security hardening

DaemonSets are often privileged because they run node-level agents. That makes them high-risk.

Baseline hardening:

```yaml
securityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
containers:
  - name: agent
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
```

But some agents legitimately need more:

| Need                | Possible setting                              |
| ------------------- | --------------------------------------------- |
| CNI plugin          | `privileged: true`, host networking, hostPath |
| Node exporter       | host filesystem mounts, sometimes hostPID     |
| eBPF security agent | privileged or specific capabilities           |
| Storage plugin      | hostPath, device access, privileged           |
| GPU plugin          | device plugin sockets, hostPath               |

Senior guidance:

```text
Start least-privileged.
Add hostPath, capabilities, hostPID, hostNetwork, or privileged only when the agent requires them.
Document why each privilege is needed.
```

Very sensitive settings:

```yaml
privileged: true
hostPID: true
hostIPC: true
hostNetwork: true
hostPath:
  path: /
capabilities:
  add:
    - SYS_ADMIN
```

These can effectively grant node-level power.

---

# 22. DaemonSet and priority

For critical node agents, use a PriorityClass.

Example:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: node-agent-critical
value: 1000000
globalDefault: false
description: "Priority for critical node agents"
```

Then:

```yaml
spec:
  template:
    spec:
      priorityClassName: node-agent-critical
```

Kubernetes notes that if it is important for a DaemonSet Pod to run on each node, setting a higher `priorityClassName` can be desirable so the Pod can preempt lower-priority Pods if needed. ([Kubernetes][1])

Do not abuse this. If every team marks its DaemonSet critical, priority loses meaning and you can evict important workloads unnecessarily.

---

# 23. DaemonSet and resources

DaemonSets consume resources on **every node**.

If your DaemonSet requests:

```yaml
requests:
  cpu: "200m"
  memory: "256Mi"
```

and you have 100 nodes, the cluster-wide reserved capacity is:

```text
20 CPU cores
25.6 Gi memory
```

This is correct if the agent needs it, but many teams forget the multiplication effect.

Senior checklist:

```text
Multiply requests by node count.
Account for control-plane and infra nodes.
Keep CPU limits optional or carefully tuned.
Use memory limits to contain leaks.
Monitor per-node overhead.
```

---

# 24. DaemonSet with OS-specific scheduling

Mixed Linux/Windows clusters require OS selection.

Linux-only:

```yaml
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/os: linux
```

Windows-only:

```yaml
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/os: windows
```

This matters because Linux images will not run on Windows nodes and vice versa.

---

# 25. DaemonSet with GPU nodes

Label GPU nodes:

```bash
kubectl label node <node-name> accelerator=nvidia
```

DaemonSet:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: gpu-node-agent
  namespace: daemonset-lab
spec:
  selector:
    matchLabels:
      app: gpu-node-agent
  template:
    metadata:
      labels:
        app: gpu-node-agent
    spec:
      nodeSelector:
        accelerator: nvidia
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
      containers:
        - name: gpu-node-agent
          image: busybox:1.37
          command:
            - sh
            - -c
            - while true; do echo "gpu node agent"; sleep 10; done
```

Use this pattern for GPU-specific node agents, not general cluster agents.

---

# 26. DaemonSet vs StatefulSet

Use DaemonSet when:

```text
One per node.
Node-local responsibility.
Pod identity is tied to node, not ordinal.
```

Use StatefulSet when:

```text
Stable identity.
Stable network name.
Stable persistent volume claim per replica.
Replica identity matters.
```

Examples:

| Workload                  | Object      |
| ------------------------- | ----------- |
| Fluent Bit on every node  | DaemonSet   |
| Prometheus Node Exporter  | DaemonSet   |
| Cassandra cluster         | StatefulSet |
| Kafka brokers             | StatefulSet |
| Web API                   | Deployment  |
| One backup agent per node | DaemonSet   |

---

# 27. DaemonSet vs static Pods

Static Pods are created directly by kubelet from files on a node. They do not depend on the API server for initial creation and are useful for cluster bootstrapping. However, they cannot be managed like normal Kubernetes API resources. Kubernetes notes that static Pods cannot be managed with `kubectl` or other Kubernetes API clients, while DaemonSets use the normal Kubernetes management model. ([Kubernetes][1])

Use static Pods for:

```text
kube-apiserver
kube-controller-manager
kube-scheduler
etcd in kubeadm-style clusters
```

Use DaemonSets for:

```text
CNI
logging
monitoring
security
storage agents
device plugins
```

---

# 28. Common mistakes

## Mistake 1: Expecting `replicas`

DaemonSet has no `replicas`.

Bad:

```yaml
spec:
  replicas: 3
```

DaemonSet scale is determined by eligible node count.

---

## Mistake 2: Running on all nodes accidentally

No selector or affinity:

```yaml
spec:
  template:
    spec:
      containers:
        - name: agent
```

This runs on every eligible node.

For expensive/special agents, use:

```yaml
nodeSelector:
  node-role.example.com/logging: "true"
```

---

## Mistake 3: Missing control-plane toleration

If you expect the agent to run on control-plane nodes, add the correct toleration.

---

## Mistake 4: hostPort conflicts

If a DaemonSet uses:

```yaml
hostPort: 9100
```

only one process per node can bind that port. If something else already uses it, the Pod may fail.

---

## Mistake 5: Too much privilege

Bad default:

```yaml
securityContext:
  privileged: true
```

Only use privileged mode when necessary.

---

## Mistake 6: Using `operator: Exists` toleration everywhere

This tolerates every taint:

```yaml
tolerations:
  - operator: Exists
```

Acceptable for critical infra agents. Dangerous for ordinary workload agents.

---

## Mistake 7: Ignoring resource multiplication

A tiny-looking request becomes large across hundreds of nodes.

---

## Mistake 8: Assuming DaemonSet Pods disappear on drain

They usually do not. Use:

```bash
kubectl drain <node-name> --ignore-daemonsets
```

Kubernetes specifically requires `--ignore-daemonsets` for draining nodes that have DaemonSet-managed Pods. ([Kubernetes][5])

---

# 29. Useful commands

List DaemonSets:

```bash
kubectl get daemonsets -A
kubectl get ds -A
```

Describe:

```bash
kubectl describe ds <name> -n <namespace>
```

Get Pods:

```bash
kubectl get pods -n <namespace> -l app=<label> -o wide
```

Watch Pods:

```bash
kubectl get pods -n <namespace> -l app=<label> -w
```

Show YAML:

```bash
kubectl get ds <name> -n <namespace> -o yaml
```

Update image:

```bash
kubectl set image ds/<name> <container-name>=<image> -n <namespace>
```

Rollout status:

```bash
kubectl rollout status ds/<name> -n <namespace>
```

Rollout history:

```bash
kubectl rollout history ds/<name> -n <namespace>
```

Rollback:

```bash
kubectl rollout undo ds/<name> -n <namespace>
```

Restart:

```bash
kubectl rollout restart ds/<name> -n <namespace>
```

Delete:

```bash
kubectl delete ds <name> -n <namespace>
```

Orphan Pods while deleting DaemonSet:

```bash
kubectl delete ds <name> -n <namespace> --cascade=orphan
```

Kubernetes says that if you delete a DaemonSet with `--cascade=orphan`, its Pods remain; a later DaemonSet with the same selector can adopt them. ([Kubernetes][1])

---

# 30. Full hands-on scenario

## Step 1: Create namespace

```bash
kubectl create namespace daemonset-lab
```

## Step 2: Create DaemonSet

```bash
cat > node-echo.yaml <<'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-echo
  namespace: daemonset-lab
spec:
  selector:
    matchLabels:
      app: node-echo
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      labels:
        app: node-echo
    spec:
      containers:
        - name: node-echo
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              while true; do
                echo "v1 running on node ${NODE_NAME}"
                sleep 10
              done
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
          resources:
            requests:
              cpu: "20m"
              memory: "32Mi"
            limits:
              cpu: "100m"
              memory: "64Mi"
EOF
```

```bash
kubectl apply -f node-echo.yaml
```

## Step 3: Verify one Pod per node

```bash
kubectl get nodes
kubectl get ds -n daemonset-lab
kubectl get pods -n daemonset-lab -l app=node-echo -o wide
```

## Step 4: Delete a Pod and watch it return

```bash
POD=$(kubectl get pods -n daemonset-lab -l app=node-echo -o jsonpath='{.items[0].metadata.name}')

kubectl delete pod "$POD" -n daemonset-lab

kubectl get pods -n daemonset-lab -l app=node-echo -w
```

## Step 5: Update image

```bash
kubectl set image ds/node-echo node-echo=busybox:1.36 -n daemonset-lab
kubectl rollout status ds/node-echo -n daemonset-lab
```

## Step 6: Check rollout history

```bash
kubectl rollout history ds/node-echo -n daemonset-lab
```

## Step 7: Roll back

```bash
kubectl rollout undo ds/node-echo -n daemonset-lab
kubectl rollout status ds/node-echo -n daemonset-lab
```

## Step 8: Restrict to one labeled node

Label one node:

```bash
kubectl label node <node-name> daemonset-lab=true
```

Patch DaemonSet:

```bash
kubectl patch ds node-echo -n daemonset-lab --type='merge' -p '
{
  "spec": {
    "template": {
      "spec": {
        "nodeSelector": {
          "daemonset-lab": "true"
        }
      }
    }
  }
}'
```

Check:

```bash
kubectl get ds -n daemonset-lab
kubectl get pods -n daemonset-lab -l app=node-echo -o wide
```

Now only the labeled node should run the Pod.

## Step 9: Cleanup

```bash
kubectl delete namespace daemonset-lab
kubectl label node <node-name> daemonset-lab-
```

---

# 31. Senior-engineer mental model

A DaemonSet is not “a Deployment with one Pod per node.” It is a **node-synchronized controller**.

It continuously asks:

```text
Which nodes are eligible?
Does every eligible node have exactly one matching Pod?
Are any Pods running where they should not?
Did the Pod template change?
Should I replace old Pods now or wait for manual deletion?
Do the Pods tolerate the node’s taints?
Do node labels still match?
```

Use a DaemonSet when the workload’s lifecycle is tied to the **node**, not to arbitrary application replica count.

Best senior-level summary:

```text
Deployment = replica-oriented application controller.
DaemonSet = node-oriented infrastructure controller.
StatefulSet = identity-oriented stateful controller.
Job/CronJob = completion-oriented batch controller.
```

For production, treat DaemonSets as privileged infrastructure by default: they often touch host networking, host filesystems, node identity, logs, devices, or runtime internals. Design their selectors, tolerations, resource requests, update strategy, and security context carefully.

---

# 22. Using Deployment and DaemonSet together

A **Deployment** and a **DaemonSet** can coexist in the same cluster and namespace. They serve distinct roles:

```text
Deployment = run the application as N replicas anywhere in the cluster
DaemonSet  = run one agent/side component on every eligible node
```

The most common combined pattern:

```text
Web/API app        → Deployment
Log/monitor agent  → DaemonSet
Service            → exposes Deployment Pods to the rest of the cluster
```

---

## 22.1 Core difference revisited

### Deployment

A Deployment says:

```text
"Run 3 copies of this application somewhere in the cluster."
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  labels:
    app: web-app
spec:
  replicas: 3

  selector:
    matchLabels:
      app: web-app

  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports:
            - containerPort: 80
```

The key field is `replicas: 3`. Kubernetes schedules those 3 Pods wherever capacity exists:

```text
Deployment
  └── ReplicaSet
        ├── web-app Pod   (node-1 or node-2 or node-3)
        ├── web-app Pod
        └── web-app Pod
```

---

### DaemonSet

A DaemonSet says:

```text
"Run exactly one copy of this Pod on every eligible node."
```

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
  labels:
    app: node-agent
spec:
  selector:
    matchLabels:
      app: node-agent

  template:
    metadata:
      labels:
        app: node-agent
    spec:
      containers:
        - name: agent
          image: busybox:1.36
          command:
            - /bin/sh
            - -c
          args:
            - |
              while true; do
                echo "Node agent running on ${NODE_NAME}"
                sleep 30
              done
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
```

There is no `replicas` field. Pod count equals node count:

```text
2 nodes  →  2 DaemonSet Pods
5 nodes  →  5 DaemonSet Pods
10 nodes → 10 DaemonSet Pods
```

---

## 22.2 Side-by-side comparison

| Property                     | Deployment                       | DaemonSet                                            |
| ---------------------------- | -------------------------------- | ---------------------------------------------------- |
| Purpose                      | Run application workload         | Run node-level agent or infrastructure component     |
| Pod count                    | Controlled by `replicas`         | One per eligible node                                |
| Managed through ReplicaSet   | Yes                              | No                                                   |
| Typical workloads            | Web app, API, frontend, backend  | Log collector, metrics agent, CNI plugin, security agent |
| New node added               | Scheduler may place a Pod there  | DaemonSet controller automatically places a Pod      |
| Guaranteed one Pod per node  | No                               | Yes, on every eligible node                          |

---

## 22.3 Combined example manifest

Save as `deployment-daemonset-demo.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  labels:
    app: web-app
    component: frontend
spec:
  replicas: 3

  selector:
    matchLabels:
      app: web-app

  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1

  template:
    metadata:
      labels:
        app: web-app
        component: frontend
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          imagePullPolicy: IfNotPresent

          ports:
            - name: http
              containerPort: 80

          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 5
            periodSeconds: 5

          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 15
            periodSeconds: 10

---
apiVersion: v1
kind: Service
metadata:
  name: web-app-service
  labels:
    app: web-app
spec:
  type: ClusterIP

  selector:
    app: web-app

  ports:
    - name: http
      port: 80
      targetPort: http

---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
  labels:
    app: node-agent
spec:
  selector:
    matchLabels:
      app: node-agent

  updateStrategy:
    type: RollingUpdate

  template:
    metadata:
      labels:
        app: node-agent
    spec:
      containers:
        - name: node-agent
          image: busybox:1.36
          imagePullPolicy: IfNotPresent

          command:
            - /bin/sh
            - -c

          args:
            - |
              while true; do
                echo "Node agent running on node: ${NODE_NAME}"
                echo "Trying to reach web-app-service..."
                wget -qO- http://web-app-service.default.svc.cluster.local || true
                sleep 30
              done

          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
```

Apply and inspect:

```bash
kubectl apply -f deployment-daemonset-demo.yaml

kubectl get deployments
kubectl get daemonsets
kubectl get pods -o wide
kubectl get svc
```

---

## 22.4 Expected cluster state

On a 3-node cluster:

```text
Deployment web-app   → DESIRED: 3
DaemonSet node-agent → DESIRED: 3
```

```bash
kubectl get pods -o wide
```

Example output:

```text
NAME                     READY   STATUS    NODE
web-app-xxxx             1/1     Running   worker-1
web-app-yyyy             1/1     Running   worker-2
web-app-zzzz             1/1     Running   worker-3
node-agent-abcde         1/1     Running   worker-1
node-agent-fghij         1/1     Running   worker-2
node-agent-klmno         1/1     Running   worker-3
```

```text
web-app    pods → owned by Deployment (via ReplicaSet)
node-agent pods → owned by DaemonSet
```

---

## 22.5 How the DaemonSet Pod reaches the Deployment Pods

The node-agent container calls:

```bash
wget -qO- http://web-app-service.default.svc.cluster.local
```

Traffic path:

```text
node-agent Pod
    ↓
web-app-service  (ClusterIP Service)
    ↓
one of the web-app Deployment Pods
```

The DaemonSet Pod uses **Service DNS**, not a direct Pod IP. Pod IPs are ephemeral; Service DNS is stable.

Short form (when in the same namespace):

```bash
wget -qO- http://web-app-service
```

Full DNS name:

```text
web-app-service.default.svc.cluster.local
               ^^^^^^^
               namespace name
```

---

## 22.6 Why the Service only selects Deployment Pods

The Service selector is:

```yaml
selector:
  app: web-app
```

Deployment Pod labels:

```yaml
labels:
  app: web-app        ← matched
```

DaemonSet Pod labels:

```yaml
labels:
  app: node-agent     ← not matched
```

Result:

```text
Service backend → web-app Pods only
node-agent Pods → not in the Service endpoint list
```

This is intentional. The Service exposes application workload, not infrastructure agents.

---

## 22.7 Are Deployment and DaemonSet linked to each other?

No. There is no owner relationship:

```text
Deployment → DaemonSet   ✗
DaemonSet  → Deployment  ✗
```

They are independent controllers. Their cooperation is by design, not by direct coupling:

```text
Deployment  = business / application workload
DaemonSet   = node-level infrastructure workload
```

A common real-world example:

```text
my-api Deployment
  └─ produces logs to stdout

fluent-bit DaemonSet
  └─ reads /var/log/containers on each node
  └─ ships logs to Elasticsearch / Loki / Splunk / Kafka
```

---

## 22.8 Log collection with hostPath (real pattern)

Production DaemonSets for logging typically mount the host log directory:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-agent
spec:
  selector:
    matchLabels:
      app: log-agent

  template:
    metadata:
      labels:
        app: log-agent
    spec:
      containers:
        - name: log-agent
          image: busybox:1.36
          command:
            - /bin/sh
            - -c
          args:
            - |
              while true; do
                echo "Container logs on this node:"
                ls -lah /var/log/containers || true
                sleep 60
              done

          volumeMounts:
            - name: container-logs
              mountPath: /var/log/containers
              readOnly: true

      volumes:
        - name: container-logs
          hostPath:
            path: /var/log/containers
            type: DirectoryOrCreate
```

Architecture:

```text
Node 1
├── app Pod       (stdout → /var/log/containers/...)
├── app Pod
└── log-agent DaemonSet Pod
      └── reads /var/log/containers read-only
      └── ships to central logging system

Node 2
├── app Pod
└── log-agent DaemonSet Pod
      └── reads /var/log/containers read-only
```

Security note: `hostPath` is powerful and must be used carefully. Always mount read-only when possible, drop all capabilities, and run as non-root.

---

## 22.9 Scaling difference

Scale the Deployment:

```bash
kubectl scale deployment web-app --replicas=5
kubectl get pods -l app=web-app -o wide
```

Deployment Pod count becomes 5. The DaemonSet is unaffected:

```bash
kubectl get daemonset node-agent
kubectl get pods -l app=node-agent -o wide
```

On a 3-node cluster:

```text
web-app Pods:    5   (controlled by replicas)
node-agent Pods: 3   (controlled by node count)
```

---

## 22.10 Rolling update for both controllers

Deployment image update:

```bash
kubectl set image deployment/web-app nginx=nginx:1.26
kubectl rollout status deployment/web-app
```

DaemonSet image update:

```bash
kubectl set image daemonset/node-agent node-agent=busybox:1.37
kubectl rollout status daemonset/node-agent
```

Both support `RollingUpdate` strategy but each controller manages it independently.

---

## 22.11 Summary

Deployment YAML shape:

```yaml
spec:
  replicas: 3
  selector:
  template:
```

DaemonSet YAML shape:

```yaml
spec:
  selector:
  template:
```

No `replicas` field in DaemonSet.

Typical production topology:

```text
API Deployment          → business logic
Frontend Deployment     → UI serving
Worker Deployment       → background jobs
Redis StatefulSet       → stateful data store
Fluent Bit DaemonSet    → node-level log shipping
Node Exporter DaemonSet → node-level metrics
CNI Plugin DaemonSet    → node-level networking
Ingress Controller      → Deployment or DaemonSet depending on traffic model
```

Mental model:

```text
Deployment = app workload   (how many replicas do I need?)
DaemonSet  = node workload  (does every node have this agent?)
```

[1]: https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/ "DaemonSet | Kubernetes"
[2]: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/ "Assigning Pods to Nodes | Kubernetes"
[3]: https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/ "Taints and Tolerations | Kubernetes"
[4]: https://kubernetes.io/docs/tasks/manage-daemon/update-daemon-set/ "Perform a Rolling Update on a DaemonSet | Kubernetes"
[5]: https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/ "Safely Drain a Node | Kubernetes"
