# Kubernetes Deployments

A **Deployment** is the standard Kubernetes object for running and updating **stateless application workloads**. It manages a set of Pods, usually through ReplicaSets, and lets you declare the desired state: image, replica count, labels, environment, probes, resources, rollout strategy, and update behavior. Kubernetes then reconciles actual cluster state toward that desired state. The official docs describe Deployments as declarative updates for Pods and ReplicaSets, normally for workloads that do not maintain state. ([Kubernetes][1])

Think of it like this:

```text
Deployment
  └── ReplicaSet revision N
        └── Pod
        └── Pod
        └── Pod

When .spec.template changes:

Deployment
  ├── old ReplicaSet revision N      scaled down
  └── new ReplicaSet revision N+1    scaled up
```

A Deployment is **not** the thing that runs your container directly. The runtime chain is:

```text
Deployment controller
    manages
ReplicaSet
    manages
Pods
    run
Containers
```

---

# 1. Why Deployments exist

Without Deployments, you could run raw Pods, but raw Pods are fragile. If the Pod dies, Kubernetes does not automatically recreate it unless another controller owns it.

A Deployment gives you:

| Capability                  | Meaning                                                 |
| --------------------------- | ------------------------------------------------------- |
| Replica management          | Keep N Pods running                                     |
| Self-healing                | Replace failed Pods                                     |
| Rolling updates             | Replace old Pods with new Pods gradually                |
| Rollback                    | Return to previous ReplicaSet revision                  |
| Declarative config          | Store desired state in YAML/Git                         |
| Scaling                     | Change number of replicas                               |
| Progressive rollout control | Pause, resume, watch, undo                              |
| Status tracking             | See whether rollout is progressing, complete, or failed |

Typical use cases include creating ReplicaSets, updating Pod templates, rolling back to earlier revisions, scaling for load, pausing rollouts, and cleaning up older ReplicaSets. ([Kubernetes][1])

---

# 2. Deployment vs Pod vs ReplicaSet

## Pod

A **Pod** is the smallest schedulable unit in Kubernetes. It wraps one or more containers.

You usually do **not** create Pods directly for production application services.

Bad production pattern:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: api
spec:
  containers:
    - name: api
      image: nginx:1.25
```

If this Pod disappears, no Deployment controller is responsible for restoring the desired application state.

---

## ReplicaSet

A **ReplicaSet** ensures a specified number of Pod replicas exist.

But you also usually do **not** create ReplicaSets manually. A Deployment creates and manages ReplicaSets for you. Kubernetes explicitly advises not to manually manage ReplicaSets owned by a Deployment. ([Kubernetes][1])

---

## Deployment

A **Deployment** is the higher-level object you normally use.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: api
          image: nginx:1.25
```

This means:

> “Kubernetes, make sure there are always 3 Pods matching this template.”

### Why `kubectl edit rs` does not persist (when Deployment owns it)

If you directly edit a ReplicaSet, but that ReplicaSet is owned by a Deployment, your change is usually temporary.

Your actual desired state is defined on the Deployment:

```yaml
kind: Deployment
spec:
  replicas: 3
```

Controller chain:

```text
Deployment  --->  ReplicaSet  --->  Pod
replicas: 3      replicas: 3      3 Pods
```

If you run `kubectl edit rs ...` and set the ReplicaSet to `2`, you temporarily get:

```text
Deployment  --->  ReplicaSet  --->  Pod
replicas: 3      replicas: 2      2 Pods
```

Then the Deployment controller reconciles state:

> "Deployment says replicas must be 3. Current ReplicaSet is 2. Scale it back to 3."

That is why the ReplicaSet returns to `3`.

You can verify ownership:

```bash
kubectl get rs
kubectl describe rs nginx-deployment-7c79c4bf97
```

Look for:

```text
Controlled By:  Deployment/nginx-deployment
```

If you want to change replica count, change the Deployment, not the child ReplicaSet.

Correct methods:

```bash
# 1) Imperative scaling
kubectl scale deployment nginx-deployment --replicas=2

# 2) Edit Deployment directly
kubectl edit deployment nginx-deployment

# 3) Declarative YAML + apply
kubectl apply -f deployment.yaml
```

Inside YAML:

```yaml
spec:
  replicas: 2
```

Same principle applies broadly:

```text
If Deployment owns Pods, change Deployment.
If StatefulSet owns Pods, change StatefulSet.
If DaemonSet owns Pods, change DaemonSet.
```

This behavior is Kubernetes reconciliation in action.

---

# 3. Basic Deployment YAML

Create a file:

```bash
mkdir -p k8s-deployment-lab
cd k8s-deployment-lab
```

Create `deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
    tier: frontend
spec:
  replicas: 3

  selector:
    matchLabels:
      app: nginx

  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1

  revisionHistoryLimit: 5
  progressDeadlineSeconds: 120
  minReadySeconds: 5

  template:
    metadata:
      labels:
        app: nginx
        tier: frontend
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          imagePullPolicy: IfNotPresent

          ports:
            - containerPort: 80
              name: http

          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"

          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 3

          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 15
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3
```

Apply it:

```bash
kubectl apply -f deployment.yaml
```

Inspect it:

```bash
kubectl get deployments
kubectl get rs
kubectl get pods -l app=nginx -o wide
kubectl describe deployment nginx-deployment
```

Watch rollout:

```bash
kubectl rollout status deployment/nginx-deployment
```

Kubernetes supports `kubectl rollout status` for Deployments, and the command exits successfully when rollout completes. ([Kubernetes][1])

---

# 4. Deployment YAML explained field by field

## `apiVersion`

```yaml
apiVersion: apps/v1
```

Deployments live under the `apps/v1` API group.

---

## `kind`

```yaml
kind: Deployment
```

This tells the Kubernetes API server which object type you are creating.

---

## `metadata`

```yaml
metadata:
  name: nginx-deployment
  labels:
    app: nginx
    tier: frontend
```

`metadata.name` is the Deployment name. Labels on the Deployment are for selection, grouping, tooling, observability, GitOps, policy engines, and humans.

Important: labels on the **Deployment object** are not automatically the same thing as labels on the **Pods**. Pod labels live under:

```yaml
spec:
  template:
    metadata:
      labels:
```

---

## `spec.replicas`

```yaml
replicas: 3
```

This says: “I want 3 Pods.”

If one Pod dies, the ReplicaSet creates another. If a node disappears, Kubernetes reschedules replacement Pods elsewhere, assuming there is capacity.

If an HPA manages the Deployment, you usually should avoid hard-managing `.spec.replicas` from GitOps in a way that fights the autoscaler. The Kubernetes docs note that when an HPA or similar controller manages scaling, the control plane should manage `.spec.replicas`. ([Kubernetes][1])

---

## `spec.selector`

```yaml
selector:
  matchLabels:
    app: nginx
```

This is one of the most important fields.

It tells the Deployment:

> “These are the Pods I own.”

The selector **must match** the labels in the Pod template:

```yaml
template:
  metadata:
    labels:
      app: nginx
```

In `apps/v1`, `.spec.selector` is required, does not default from Pod template labels, and is immutable after creation. Kubernetes rejects the Deployment if the selector does not match the Pod template labels. ([Kubernetes][1])

Bad example:

```yaml
selector:
  matchLabels:
    app: backend
template:
  metadata:
    labels:
      app: frontend
```

This will fail because selector and template labels do not match.

Senior-engineer rule:

> Design selectors as stable identity labels. Do not put version, commit SHA, or rollout-specific values in the Deployment selector.

Good selector:

```yaml
app.kubernetes.io/name: payment-api
app.kubernetes.io/instance: payment-api-prod
```

Bad selector:

```yaml
version: v1.2.7
commit: abc123
```

Version changes should go into Pod labels, not immutable selectors.

---

## `spec.template`

```yaml
template:
  metadata:
    labels:
      app: nginx
  spec:
    containers:
      - name: nginx
        image: nginx:1.25
```

This is the **Pod template**. A Deployment does not directly say “run containers.” It says “create Pods that look like this template.”

The Pod template has almost the same schema as a normal Pod, except it is nested inside the Deployment and does not include its own `apiVersion` or `kind`. Kubernetes only allows `restartPolicy: Always` for Pods created by Deployments, which is also the default. ([Kubernetes][1])

---

## `spec.strategy`

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1
    maxSurge: 1
```

Deployment update strategies are:

| Strategy        | Behavior                                  |
| --------------- | ----------------------------------------- |
| `RollingUpdate` | Gradually replace old Pods with new Pods  |
| `Recreate`      | Kill old Pods first, then create new Pods |

`RollingUpdate` is the default. `Recreate` causes downtime because existing Pods are terminated before new ones are created. ([Kubernetes][2])

---

## `maxUnavailable`

```yaml
maxUnavailable: 1
```

Maximum number of desired Pods that may be unavailable during rollout.

For 3 replicas and `maxUnavailable: 1`, Kubernetes ensures at least 2 available Pods during update.

It can be an integer:

```yaml
maxUnavailable: 1
```

Or percentage:

```yaml
maxUnavailable: 25%
```

The default is `25%`; percentages for `maxUnavailable` are rounded down. ([Kubernetes][2])

---

## `maxSurge`

```yaml
maxSurge: 1
```

Maximum number of extra Pods that may exist above desired replicas during rollout.

For 3 replicas and `maxSurge: 1`, Kubernetes may temporarily run 4 Pods.

It can also be a percentage:

```yaml
maxSurge: 25%
```

The default is `25%`; percentages for `maxSurge` are rounded up. ([Kubernetes][2])

Important production implication:

> During rollout, your cluster may need extra CPU/memory capacity for surge Pods.

Also, terminating Pods are not counted as available replicas, and you may temporarily observe more Pods and higher resource usage until `terminationGracePeriodSeconds` expires. ([Kubernetes][1])

---

## `revisionHistoryLimit`

```yaml
revisionHistoryLimit: 5
```

This controls how many old ReplicaSets Kubernetes keeps for rollback.

Default is 10. Setting it to `0` removes rollout history and disables rollback. ([Kubernetes][2])

Production guidance:

```yaml
revisionHistoryLimit: 3
```

or:

```yaml
revisionHistoryLimit: 5
```

Usually enough unless you have strict audit or emergency rollback needs.

---

## `progressDeadlineSeconds`

```yaml
progressDeadlineSeconds: 120
```

This tells Kubernetes how long to wait before marking the Deployment as failed to progress.

Common reasons for stalled Deployments include image pull errors, readiness probe failures, insufficient quota, insufficient permissions, limit ranges, and runtime misconfiguration. ([Kubernetes][1])

Important nuance:

> Kubernetes reports the failure condition; it does not automatically roll back the Deployment by itself.

The docs state that Kubernetes takes no action on a stalled Deployment other than reporting the `ProgressDeadlineExceeded` condition. ([Kubernetes][1])

---

## `minReadySeconds`

```yaml
minReadySeconds: 5
```

A Pod must be ready for this many seconds before being considered available.

This is useful when your app becomes “ready” briefly but crashes shortly after. It gives Kubernetes a stability window before continuing rollout.

---

## `resources`

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
```

Requests affect scheduling. Limits affect runtime enforcement.

Senior guidance:

* Always set memory requests.
* Usually set CPU requests.
* Be cautious with CPU limits for latency-sensitive services.
* Use real metrics to tune requests, not guesses.
* Memory limit too low causes `OOMKilled`.
* CPU limit too low causes throttling.

---

## `readinessProbe`

```yaml
readinessProbe:
  httpGet:
    path: /
    port: http
```

Readiness decides whether the Pod should receive traffic.

During rollout, readiness is critical. Kubernetes should not scale down too many old Pods until new Pods are actually ready.

Bad readiness probes cause stuck rollouts.

---

## `livenessProbe`

```yaml
livenessProbe:
  httpGet:
    path: /
    port: http
```

Liveness decides whether Kubernetes should restart the container.

Senior rule:

> Readiness is for traffic eligibility. Liveness is for deadlock recovery. Do not use liveness as a generic health check unless restart is actually the correct recovery action.

Bad liveness probes create restart loops.

---

# 5. What happens when you create a Deployment

Run:

```bash
kubectl apply -f deployment.yaml
```

Then:

```bash
kubectl get deployment nginx-deployment
kubectl get rs
kubectl get pods --show-labels
```

You will see something like:

```text
Deployment: nginx-deployment
ReplicaSet: nginx-deployment-75675f5897
Pods:
  nginx-deployment-75675f5897-abcde
  nginx-deployment-75675f5897-fghij
  nginx-deployment-75675f5897-klmno
```

ReplicaSet names follow a pattern like:

```text
[DEPLOYMENT-NAME]-[HASH]
```

The hash corresponds to the `pod-template-hash` label. Kubernetes adds this label to ReplicaSets and Pods so child ReplicaSets from the same Deployment do not overlap. You should not change the `pod-template-hash` label manually. ([Kubernetes][1])

---

# 6. What triggers a rollout?

A Deployment rollout is triggered when `.spec.template` changes.

Examples that trigger rollout:

```yaml
spec:
  template:
    spec:
      containers:
        - image: nginx:1.26
```

Changing image triggers rollout.

```yaml
spec:
  template:
    metadata:
      labels:
        version: v2
```

Changing Pod template labels triggers rollout.

```yaml
spec:
  template:
    metadata:
      annotations:
        restartedAt: "2026-05-16T12:00:00Z"
```

Changing Pod template annotations triggers rollout.

Examples that do **not** trigger rollout:

```yaml
spec:
  replicas: 5
```

Scaling does not create a new revision.

```yaml
metadata:
  labels:
    owner: platform-team
```

Changing Deployment object metadata outside `.spec.template` does not create new Pods.

The Kubernetes docs explicitly state that a rollout is triggered only when the Deployment Pod template changes; scaling does not trigger a rollout. ([Kubernetes][1])

---

# 7. Hands-on: update image and watch rollout

Update the image:

```bash
kubectl set image deployment/nginx-deployment nginx=nginx:1.26
```

Watch rollout:

```bash
kubectl rollout status deployment/nginx-deployment
```

Watch ReplicaSets:

```bash
kubectl get rs -w
```

Watch Pods:

```bash
kubectl get pods -l app=nginx -w
```

You should see:

1. New ReplicaSet created.
2. New Pods start.
3. New Pods become ready.
4. Old ReplicaSet scales down.
5. Old Pods terminate.
6. Deployment reaches complete state.

Kubernetes creates a new ReplicaSet when the Deployment is updated, scales it up, and scales old ReplicaSets down until the new ReplicaSet reaches the desired replica count. ([Kubernetes][1])

---

# 8. RollingUpdate mechanics with numbers

Suppose:

```yaml
replicas: 4
maxUnavailable: 1
maxSurge: 1
```

Then during rollout:

```text
Desired replicas: 4
Minimum available: 3
Maximum total Pods: 5
```

Possible rollout sequence:

```text
Old RS: 4, New RS: 0
Old RS: 4, New RS: 1   # surge one new Pod
Old RS: 3, New RS: 1   # remove one old Pod
Old RS: 3, New RS: 2
Old RS: 2, New RS: 2
Old RS: 2, New RS: 3
Old RS: 1, New RS: 3
Old RS: 1, New RS: 4
Old RS: 0, New RS: 4
```

Kubernetes’ own example describes this kind of controlled replacement: it does not kill old Pods until enough new Pods are available, and does not create new Pods until enough old Pods have been killed. ([Kubernetes][1])

---

# 9. Rollback

Check rollout history:

```bash
kubectl rollout history deployment/nginx-deployment
```

Rollback to previous revision:

```bash
kubectl rollout undo deployment/nginx-deployment
```

Rollback to a specific revision:

```bash
kubectl rollout undo deployment/nginx-deployment --to-revision=2
```

Watch rollback:

```bash
kubectl rollout status deployment/nginx-deployment
```

Deployment rollback works because old ReplicaSets are retained as revision history. By default, Kubernetes keeps 10 old ReplicaSets, and you can change this with `.spec.revisionHistoryLimit`. ([Kubernetes][2])

To make history more useful, annotate changes:

```bash
kubectl annotate deployment nginx-deployment \
  kubernetes.io/change-cause="Upgrade nginx from 1.25 to 1.26"
```

Then:

```bash
kubectl rollout history deployment/nginx-deployment
```

The `CHANGE-CAUSE` column uses the `kubernetes.io/change-cause` annotation if it is set. ([Kubernetes][1])

---

# 10. Pause and resume rollouts

Pause:

```bash
kubectl rollout pause deployment/nginx-deployment
```

Make multiple changes:

```bash
kubectl set image deployment/nginx-deployment nginx=nginx:1.27
kubectl set resources deployment nginx-deployment \
  --containers=nginx \
  --requests=cpu=200m,memory=256Mi \
  --limits=cpu=1,memory=512Mi
```

Resume:

```bash
kubectl rollout resume deployment/nginx-deployment
```

Watch:

```bash
kubectl rollout status deployment/nginx-deployment
```

Pausing is useful when you want to batch multiple template changes into a single rollout. Kubernetes allows multiple changes while paused and applies them together when resumed. ([Kubernetes][2])

Important:

```text
You cannot roll back a paused Deployment until you resume it.
```

Kubernetes documents this behavior directly. ([Kubernetes][1])

---

# 11. Restarting a Deployment

Sometimes you need to restart Pods without changing the image.

Example: application reads Secret or ConfigMap only at startup.

Use:

```bash
kubectl rollout restart deployment/nginx-deployment
```

This modifies the Pod template annotation, which triggers a new rollout.

You can restart all Deployments in a namespace:

```bash
kubectl rollout restart deployment -n test-namespace
```

Or restart by label selector:

```bash
kubectl rollout restart deployment --selector=app=nginx
```

`kubectl rollout restart` supports restarting Deployments, and the official examples include restarting a single Deployment, all Deployments in a namespace, and Deployments selected by label. ([Kubernetes][3])

---

# 12. Scaling a Deployment

Manual scale:

```bash
kubectl scale deployment nginx-deployment --replicas=5
```

Check:

```bash
kubectl get deployment nginx-deployment
kubectl get pods -l app=nginx
```

Patch scale:

```bash
kubectl patch deployment nginx-deployment \
  -p '{"spec":{"replicas":5}}'
```

Edit YAML:

```yaml
spec:
  replicas: 5
```

Then:

```bash
kubectl apply -f deployment.yaml
```

Important GitOps/HPA warning:

If you manually scale to 5 but your YAML still says 3, the next `kubectl apply -f deployment.yaml` may return it to 3. Kubernetes docs explicitly warn that applying a manifest can overwrite manual scaling. ([Kubernetes][1])

---

# 13. Exposing a Deployment with a Service

A Deployment gives you Pods. It does **not** give you stable networking.

Pods are ephemeral. Their IPs change. To expose them inside the cluster, use a Service.

Create `service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  labels:
    app: nginx
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
    - name: http
      port: 80
      targetPort: http
```

Apply:

```bash
kubectl apply -f service.yaml
```

Check:

```bash
kubectl get svc nginx-service
kubectl get endpoints nginx-service
```

Port-forward for local testing:

```bash
kubectl port-forward svc/nginx-service 8080:80
```

Test:

```bash
curl http://localhost:8080
```

Key point:

```text
Deployment selector chooses Pods for management.
Service selector chooses Pods for networking.
```

They often use the same labels, but they are separate mechanisms.

---

# 14. Production-grade Deployment manifest

Here is a more realistic example for an API service.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-api
  namespace: payments
  labels:
    app.kubernetes.io/name: payment-api
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: payment-platform
    app.kubernetes.io/managed-by: gitops
spec:
  replicas: 4

  selector:
    matchLabels:
      app.kubernetes.io/name: payment-api
      app.kubernetes.io/instance: payment-api-prod

  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1

  minReadySeconds: 10
  revisionHistoryLimit: 5
  progressDeadlineSeconds: 300

  template:
    metadata:
      labels:
        app.kubernetes.io/name: payment-api
        app.kubernetes.io/instance: payment-api-prod
        app.kubernetes.io/component: backend
        app.kubernetes.io/version: "1.8.3"
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"

    spec:
      serviceAccountName: payment-api

      terminationGracePeriodSeconds: 45

      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault

      containers:
        - name: payment-api
          image: registry.example.com/payments/payment-api:1.8.3
          imagePullPolicy: IfNotPresent

          ports:
            - name: http
              containerPort: 8080

          env:
            - name: ENVIRONMENT
              value: "production"
            - name: LOG_LEVEL
              value: "info"
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: payment-api-db
                  key: url

          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
            limits:
              memory: "1Gi"

          readinessProbe:
            httpGet:
              path: /ready
              port: http
            initialDelaySeconds: 10
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 3

          livenessProbe:
            httpGet:
              path: /live
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3

          startupProbe:
            httpGet:
              path: /startup
              port: http
            periodSeconds: 5
            failureThreshold: 30

          lifecycle:
            preStop:
              exec:
                command:
                  - /bin/sh
                  - -c
                  - "sleep 10"

          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
```

Important production choices here:

| Field                                       | Why it matters                                                              |
| ------------------------------------------- | --------------------------------------------------------------------------- |
| `maxUnavailable: 0`                         | Avoids intentionally reducing available replicas during rollout             |
| `maxSurge: 1`                               | Adds one extra Pod during rollout                                           |
| `minReadySeconds: 10`                       | Avoids advancing rollout too quickly                                        |
| `progressDeadlineSeconds: 300`              | Detects stuck rollout                                                       |
| `startupProbe`                              | Protects slow-starting apps from premature liveness restarts                |
| `preStop` + `terminationGracePeriodSeconds` | Gives load balancers/timeouts time to drain                                 |
| `resources.requests`                        | Makes scheduling predictable                                                |
| memory limit only                           | Avoids memory runaway while avoiding CPU throttling if CPU limit is omitted |
| non-root security context                   | Reduces container breakout impact                                           |
| `readOnlyRootFilesystem`                    | Hardens runtime                                                             |

---

# 15. Deployment status

Run:

```bash
kubectl get deployment nginx-deployment
```

Example:

```text
NAME               READY   UP-TO-DATE   AVAILABLE   AGE
nginx-deployment   3/3     3            3           5m
```

Meaning:

| Column       | Meaning                       |
| ------------ | ----------------------------- |
| `READY`      | Ready Pods / desired Pods     |
| `UP-TO-DATE` | Pods matching latest template |
| `AVAILABLE`  | Pods available to users       |
| `AGE`        | Object age                    |

Run:

```bash
kubectl describe deployment nginx-deployment
```

Look at:

```text
Replicas:
Conditions:
OldReplicaSets:
NewReplicaSet:
Events:
```

Deployment lifecycle states include progressing, complete, and failed-to-progress. Kubernetes marks a Deployment progressing when it creates a new ReplicaSet, scales the newest ReplicaSet up, scales old ReplicaSets down, or when new Pods become ready/available. ([Kubernetes][1])

A Deployment is complete when all replicas are updated, all replicas are available, and no old replicas are running. ([Kubernetes][1])

---

# 16. Debugging Deployments

## Fast checklist

```bash
kubectl get deployment
kubectl describe deployment <name>
kubectl get rs
kubectl get pods -l app=<label>
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl logs <pod-name> --previous
kubectl get events --sort-by=.lastTimestamp
```

---

## Debug stuck rollout

```bash
kubectl rollout status deployment/nginx-deployment
```

If stuck:

```bash
kubectl describe deployment nginx-deployment
```

Then inspect Pods:

```bash
kubectl get pods -l app=nginx
kubectl describe pod <bad-pod>
kubectl logs <bad-pod>
kubectl logs <bad-pod> --previous
```

Common causes:

| Symptom                      | Likely cause                                                           |
| ---------------------------- | ---------------------------------------------------------------------- |
| `ImagePullBackOff`           | Wrong image, missing registry secret, registry unavailable             |
| `CrashLoopBackOff`           | App starts then crashes                                                |
| `CreateContainerConfigError` | Bad ConfigMap/Secret/env reference                                     |
| `Pending`                    | Insufficient CPU/memory, node selector issue, taints/tolerations issue |
| `0/1 Ready`                  | Readiness probe failing                                                |
| `OOMKilled`                  | Memory limit too low or memory leak                                    |
| Rollout never finishes       | New Pods never become available                                        |
| Old Pods not terminating     | Long `terminationGracePeriodSeconds`, finalizers, node issues          |

---

## Debug selector problems

Check Deployment selector:

```bash
kubectl get deployment nginx-deployment -o jsonpath='{.spec.selector.matchLabels}'
```

Check Pod labels:

```bash
kubectl get pods --show-labels
```

If selector overlaps with another controller, controllers may fight over Pods. Kubernetes warns that overlapping selectors between controllers can cause unexpected behavior and does not stop you from creating that conflict. ([Kubernetes][1])

---

## Debug ReplicaSets

```bash
kubectl get rs -l app=nginx
```

Example:

```text
NAME                          DESIRED   CURRENT   READY   AGE
nginx-deployment-abc123       0         0         0       20m
nginx-deployment-def456       3         3         3       5m
```

The old ReplicaSet remains with `DESIRED=0` for rollback history.

Inspect ReplicaSet owner:

```bash
kubectl get rs nginx-deployment-def456 -o yaml
```

Look for:

```yaml
ownerReferences:
  - kind: Deployment
    name: nginx-deployment
```

---

# 17. Bad rollout lab

Intentionally break the image:

```bash
kubectl set image deployment/nginx-deployment nginx=nginx:this-tag-does-not-exist
```

Watch:

```bash
kubectl rollout status deployment/nginx-deployment
```

Inspect:

```bash
kubectl get pods
kubectl describe deployment nginx-deployment
kubectl describe pod <bad-pod>
```

You will likely see:

```text
ImagePullBackOff
ErrImagePull
```

Rollback:

```bash
kubectl rollout undo deployment/nginx-deployment
kubectl rollout status deployment/nginx-deployment
```

This is a classic Deployment recovery workflow.

---

# 18. Deployment strategies

## RollingUpdate

Default and most common.

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

Use for:

* Web APIs
* Frontend services
* Stateless backends
* Workers that can tolerate overlap

---

## Recreate

```yaml
strategy:
  type: Recreate
```

Use when old and new versions must not run together.

Examples:

* Legacy app with exclusive lock
* Single-consumer workload without idempotency
* App that cannot tolerate mixed versions

But expect downtime. Kubernetes documents that `Recreate` terminates all existing Pods before creating new ones. ([Kubernetes][1])

---

## Canary with multiple Deployments

Kubernetes Deployments do not provide advanced traffic splitting by themselves. For a basic canary, you can create two Deployments with the same Service selector.

Stable Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-stable
spec:
  replicas: 9
  selector:
    matchLabels:
      app: api
      track: stable
  template:
    metadata:
      labels:
        app: api
        track: stable
    spec:
      containers:
        - name: api
          image: example/api:1.0
```

Canary Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
      track: canary
  template:
    metadata:
      labels:
        app: api
        track: canary
    spec:
      containers:
        - name: api
          image: example/api:1.1
```

Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api
spec:
  selector:
    app: api
  ports:
    - port: 80
      targetPort: 8080
```

This gives roughly 10% canary if all Pods receive equal traffic:

```text
9 stable Pods
1 canary Pod
```

Senior caveat:

> This is replica-ratio canary, not precise traffic canary. For exact traffic percentages, use a service mesh, Gateway API implementation, or progressive delivery controller such as Argo Rollouts or Flagger.

The Kubernetes docs mention canary via multiple Deployments as the Deployment-native pattern. ([Kubernetes][1])

---

# 19. Deployment and ConfigMaps/Secrets

A common trap:

> Updating a ConfigMap or Secret does not automatically restart Deployment Pods unless the app watches the mounted files or you trigger a rollout.

Example ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  APP_MODE: production
```

Deployment env:

```yaml
envFrom:
  - configMapRef:
      name: nginx-config
```

After changing ConfigMap:

```bash
kubectl apply -f configmap.yaml
```

Restart Deployment:

```bash
kubectl rollout restart deployment/nginx-deployment
```

GitOps pattern: put a checksum annotation in the Pod template:

```yaml
template:
  metadata:
    annotations:
      checksum/config: "abc123"
```

When config changes, checksum changes, Pod template changes, rollout starts.

---

# 20. Deployment with HPA

Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: api
          image: example/api:1.0
          resources:
            requests:
              cpu: "200m"
              memory: "256Mi"
```

HPA:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 3
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

Apply:

```bash
kubectl apply -f deployment.yaml
kubectl apply -f hpa.yaml
kubectl get hpa
```

Senior guidance:

* HPA needs resource requests.
* Avoid GitOps constantly forcing `replicas` back to a fixed value.
* Set `minReplicas` high enough for availability.
* Combine with PodDisruptionBudget for voluntary disruptions.

---

# 21. Deployment with PodDisruptionBudget

A Deployment protects against application crashes and rollouts. A **PodDisruptionBudget** helps protect against voluntary disruptions such as node drains.

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: nginx-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: nginx
```

Apply:

```bash
kubectl apply -f pdb.yaml
kubectl get pdb
```

For a 3-replica Deployment:

```text
minAvailable: 2
```

means Kubernetes should avoid voluntarily evicting more than one Pod at a time.

---

# 22. Deployment anti-affinity example

Avoid placing all replicas on the same node:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-spread
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-spread
  template:
    metadata:
      labels:
        app: nginx-spread
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app: nginx-spread
                topologyKey: kubernetes.io/hostname
      containers:
        - name: nginx
          image: nginx:1.25
```

This says:

> Prefer not to schedule multiple `nginx-spread` Pods on the same node.

For stricter spreading, use topology spread constraints.

---

# 23. Deployment topology spread example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 6
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: api
      containers:
        - name: api
          image: example/api:1.0
```

This tries to distribute replicas evenly across nodes.

For zones:

```yaml
topologyKey: topology.kubernetes.io/zone
```

---

# 24. Deployment security hardening

Minimum useful baseline:

```yaml
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: app
          image: example/app:1.0
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
```

Also consider:

* Dedicated `serviceAccountName`
* RBAC least privilege
* No default service account token unless needed
* NetworkPolicies
* Image signing/admission policies
* Read-only root filesystem
* Non-root UID
* No privileged containers
* No hostPath unless absolutely required

---

# 25. Deployment best practices

## 1. Use immutable image tags or digests

Avoid:

```yaml
image: my-api:latest
```

Prefer:

```yaml
image: my-api:1.8.3
```

Even better:

```yaml
image: my-api@sha256:...
```

Reason:

> Kubernetes cannot reason cleanly about what changed if the tag is mutable.

---

## 2. Always define readiness probes

Without readiness probes, Kubernetes may send traffic before your app is actually ready.

---

## 3. Do not make liveness too aggressive

Bad:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  periodSeconds: 1
  failureThreshold: 1
```

This can create cascading restarts.

---

## 4. Set resource requests

Without requests, scheduling quality is poor.

---

## 5. Keep selectors stable

Never use version labels in `.spec.selector`.

---

## 6. Use `maxUnavailable: 0` for critical APIs

Example:

```yaml
rollingUpdate:
  maxUnavailable: 0
  maxSurge: 1
```

But make sure the cluster has spare capacity.

---

## 7. Use `progressDeadlineSeconds`

This makes rollout failure visible.

---

## 8. Combine with PDB and topology spreading

Deployment alone does not guarantee high availability during node maintenance or zone failure.

---

## 9. Use GitOps/server-side apply

Avoid manual drift.

Recommended workflow:

```bash
kubectl diff -f deployment.yaml
kubectl apply -f deployment.yaml
kubectl rollout status deployment/payment-api
```

---

## 10. Do not manually edit child ReplicaSets

Treat ReplicaSets as Deployment-owned implementation detail.

---

# 26. Common mistakes

## Mistake 1: Selector mismatch

```yaml
selector:
  matchLabels:
    app: api
template:
  metadata:
    labels:
      app: backend
```

Result:

```text
API validation error
```

---

## Mistake 2: Overlapping selectors

Two Deployments selecting the same Pods:

```yaml
selector:
  matchLabels:
    app: api
```

This causes controller conflict.

---

## Mistake 3: Using `latest`

```yaml
image: api:latest
```

Hard to audit, hard to rollback, hard to debug.

---

## Mistake 4: No readiness probe

Rollout may continue even though app cannot serve real traffic.

---

## Mistake 5: Too few replicas

For production web APIs, this is fragile:

```yaml
replicas: 1
```

During node drain or rollout, availability is weak.

---

## Mistake 6: `maxUnavailable: 1` with `replicas: 1`

If you have one replica and allow one unavailable Pod, you allow downtime.

For one replica:

```yaml
replicas: 1
strategy:
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

---

## Mistake 7: ConfigMap changed, Pods not restarted

Fix:

```bash
kubectl rollout restart deployment/<name>
```

---

## Mistake 8: Readiness probe depends on external dependency too strictly

Example: readiness fails if database has one transient issue. That can remove all Pods from service and amplify an incident.

Design readiness carefully.

---

# 27. Useful `kubectl` commands

Create:

```bash
kubectl apply -f deployment.yaml
```

List:

```bash
kubectl get deploy
```

Describe:

```bash
kubectl describe deploy nginx-deployment
```

Get YAML:

```bash
kubectl get deploy nginx-deployment -o yaml
```

Get ReplicaSets:

```bash
kubectl get rs
```

Get Pods owned by label:

```bash
kubectl get pods -l app=nginx
```

Watch rollout:

```bash
kubectl rollout status deploy/nginx-deployment
```

History:

```bash
kubectl rollout history deploy/nginx-deployment
```

Undo:

```bash
kubectl rollout undo deploy/nginx-deployment
```

Restart:

```bash
kubectl rollout restart deploy/nginx-deployment
```

Pause:

```bash
kubectl rollout pause deploy/nginx-deployment
```

Resume:

```bash
kubectl rollout resume deploy/nginx-deployment
```

Scale:

```bash
kubectl scale deploy/nginx-deployment --replicas=5
```

Change image:

```bash
kubectl set image deploy/nginx-deployment nginx=nginx:1.26
```

Patch strategy:

```bash
kubectl patch deployment nginx-deployment -p \
  '{"spec":{"strategy":{"rollingUpdate":{"maxUnavailable":0,"maxSurge":1}}}}'
```

Delete:

```bash
kubectl delete deploy nginx-deployment
```

---

# 28. Mental model

A Deployment is a **declarative rollout controller**.

You say:

```text
I want 4 replicas of this Pod template.
Use this update strategy.
Consider Pods available only after this readiness behavior.
Keep this much rollout history.
Fail progress after this deadline.
```

Kubernetes continuously asks:

```text
Do actual Pods match desired Pods?
Is there a new Pod template?
Do I need a new ReplicaSet?
How many old Pods can I remove?
How many new Pods can I add?
Are new Pods ready?
Is the rollout complete or stuck?
```

That reconciliation loop is the heart of Deployments.

---

# 29. When not to use Deployment

Use something else when you need:

| Need                                 | Better object                                                   |
| ------------------------------------ | --------------------------------------------------------------- |
| Stable network identity per Pod      | StatefulSet                                                     |
| Stable persistent identity/storage   | StatefulSet                                                     |
| One Pod per node                     | DaemonSet                                                       |
| Run-to-completion batch job          | Job                                                             |
| Scheduled job                        | CronJob                                                         |
| Bare static system component on node | Static Pod                                                      |
| Advanced canary/blue-green           | Argo Rollouts, Flagger, service mesh, Gateway traffic splitting |

Deployment is excellent for stateless replicated services. It is not the universal workload abstraction.

---

# 30. Minimal hands-on lab summary

Run this sequence:

```bash
kubectl create namespace deploy-lab

kubectl create deployment nginx-deployment \
  --image=nginx:1.25 \
  --replicas=3 \
  -n deploy-lab

kubectl get deploy,rs,pods -n deploy-lab

kubectl rollout status deployment/nginx-deployment -n deploy-lab

kubectl set image deployment/nginx-deployment nginx=nginx:1.26 -n deploy-lab

kubectl rollout status deployment/nginx-deployment -n deploy-lab

kubectl rollout history deployment/nginx-deployment -n deploy-lab

kubectl set image deployment/nginx-deployment nginx=nginx:badtag -n deploy-lab

kubectl get pods -n deploy-lab

kubectl describe deployment nginx-deployment -n deploy-lab

kubectl rollout undo deployment/nginx-deployment -n deploy-lab

kubectl rollout status deployment/nginx-deployment -n deploy-lab

kubectl scale deployment nginx-deployment --replicas=5 -n deploy-lab

kubectl get pods -n deploy-lab

kubectl rollout restart deployment/nginx-deployment -n deploy-lab

kubectl delete namespace deploy-lab
```

That lab teaches:

* Deployment creation
* ReplicaSet ownership
* Pod management
* Rolling update
* Failed rollout
* Rollback
* Scaling
* Restart
* Cleanup

---

The most important  takeaway:

> A Deployment is not just “a YAML that runs Pods.” It is a reconciliation and rollout primitive. Production-quality Deployments depend on correct selectors, stable labels, readiness behavior, resource requests, rollout strategy, failure detection, security context, disruption handling, and observability.

[1]: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ "Deployments | Kubernetes"
[2]: https://kubernetes.io/docs/tasks/run-application/update-deployment-rolling/ "Update a Deployment Without Downtime | Kubernetes"
[3]: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/kubectl_rollout_restart/ "kubectl rollout restart | Kubernetes"
