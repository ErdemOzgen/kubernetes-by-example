# Kubernetes ConfigMap

A **ConfigMap** is a Kubernetes API object used to store **non-confidential configuration data** as key-value pairs. Pods can consume ConfigMaps as environment variables, command-line arguments, or mounted configuration files. The main purpose is to decouple configuration from container images, so the same image can run in dev, test, staging, and production with different runtime configuration. Kubernetes explicitly warns that ConfigMaps do **not** provide secrecy or encryption; sensitive values should go into Secrets or an external secret-management system. ([Kubernetes][1])

Think of it like this:

```text
Container image = application binary/code
ConfigMap       = non-sensitive runtime configuration
Secret          = sensitive runtime configuration
```

Example use cases:

```text
APP_ENV=production
LOG_LEVEL=info
FEATURE_X_ENABLED=true
DATABASE_HOST=postgres.default.svc.cluster.local
nginx.conf
redis.conf
application.yaml
prometheus.yml
```

Do **not** put these in a ConfigMap:

```text
Passwords
API keys
JWT signing keys
Private certificates
Database credentials
OAuth client secrets
```

---

# 1. Basic ConfigMap YAML

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: default
data:
  APP_ENV: "production"
  LOG_LEVEL: "info"
  FEATURE_PAYMENT_ENABLED: "true"
  application.yaml: |
    server:
      port: 8080
    logging:
      level: info
    featureFlags:
      payment: true
```

Apply it:

```bash
kubectl apply -f configmap.yaml
```

Check it:

```bash
kubectl get configmap
kubectl get cm
kubectl describe configmap app-config
kubectl get configmap app-config -o yaml
```

`cm` is the short name for `configmap`.

---

# 2. ConfigMap object structure

A ConfigMap does not use the usual workload-style `spec` field. It mainly has:

```yaml
data:
  key: value

binaryData:
  key: base64-encoded-binary-value

immutable: true
```

The `data` field is for UTF-8 strings. The `binaryData` field is for binary data encoded as base64. Keys must use alphanumeric characters, `-`, `_`, or `.`, and keys in `data` and `binaryData` cannot overlap. Kubernetes also documents that ConfigMaps are not designed for large data; stored data cannot exceed **1 MiB**. ([Kubernetes][1])

Bad usage:

```yaml
data:
  huge-ml-model.bin: "..."
```

Better:

```text
Use a volume, object storage, database, OCI artifact, or dedicated config distribution mechanism.
```

---

# 3. Creating ConfigMaps imperatively

You can create ConfigMaps directly from literals, files, directories, or env files. Kubernetes supports `kubectl create configmap` from local files, directories, and literal values. ([Kubernetes][2])

## From literals

```bash
kubectl create configmap app-config \
  --from-literal=APP_ENV=production \
  --from-literal=LOG_LEVEL=debug
```

View:

```bash
kubectl get cm app-config -o yaml
```

## From a file

Suppose you have:

```bash
cat > application.yaml <<EOF
server:
  port: 8080
logging:
  level: info
EOF
```

Create:

```bash
kubectl create configmap app-config \
  --from-file=application.yaml
```

The key becomes the filename:

```yaml
data:
  application.yaml: |
    server:
      port: 8080
    logging:
      level: info
```

## From a file with a custom key

```bash
kubectl create configmap app-config \
  --from-file=config.yaml=application.yaml
```

Result:

```yaml
data:
  config.yaml: |
    server:
      port: 8080
```

## From an env file

```bash
cat > app.env <<EOF
APP_ENV=production
LOG_LEVEL=info
FEATURE_X=true
EOF
```

Create:

```bash
kubectl create configmap app-config \
  --from-env-file=app.env
```

---

# 4. Consuming ConfigMap as environment variables

There are two main ways.

## Option A: specific key using `env`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: env-demo
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo APP_ENV=$APP_ENV LOG_LEVEL=$LOG_LEVEL && sleep 3600"]
      env:
        - name: APP_ENV
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: APP_ENV
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: LOG_LEVEL
```

Run:

```bash
kubectl apply -f pod-env.yaml
kubectl logs env-demo
```

This is explicit and safer for production because you know exactly which config values are injected.

---

## Option B: import all keys using `envFrom`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: envfrom-demo
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "printenv | sort && sleep 3600"]
      envFrom:
        - configMapRef:
            name: app-config
```

Run:

```bash
kubectl apply -f pod-envfrom.yaml
kubectl logs envfrom-demo
```

Kubernetes documents that `envFrom` creates environment variables from all key-value pairs in the referenced ConfigMap. ([Kubernetes][1])

Senior advice:

```text
Use env for critical production config.
Use envFrom for small internal apps or simple demos.
Avoid dumping huge ConfigMaps into env vars.
Avoid envFrom when key collisions are possible.
```

---

# 5. Consuming ConfigMap as files through a volume

This is one of the most important ConfigMap patterns.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: volume-demo
spec:
  containers:
    - name: app
      image: busybox:1.36
      command:
        - sh
        - -c
        - |
          echo "Reading config file:"
          cat /etc/app-config/application.yaml
          sleep 3600
      volumeMounts:
        - name: config-volume
          mountPath: /etc/app-config

  volumes:
    - name: config-volume
      configMap:
        name: app-config
```

Inside the container:

```bash
kubectl exec -it volume-demo -- sh
ls -l /etc/app-config
cat /etc/app-config/application.yaml
```

Each ConfigMap key becomes a file. Example:

```yaml
data:
  APP_ENV: "production"
  LOG_LEVEL: "info"
  application.yaml: |
    server:
      port: 8080
```

Becomes:

```text
/etc/app-config/APP_ENV
/etc/app-config/LOG_LEVEL
/etc/app-config/application.yaml
```

Kubernetes documents that ConfigMap data can be referenced through a `configMap` volume and consumed by containers as files. ConfigMap volumes are mounted read-only. ([Kubernetes][3])

---

# 6. Mounting only selected keys

You do not always need to mount the whole ConfigMap.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: selected-key-demo
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "cat /etc/config/app.yml && sleep 3600"]
      volumeMounts:
        - name: config-volume
          mountPath: /etc/config

  volumes:
    - name: config-volume
      configMap:
        name: app-config
        items:
          - key: application.yaml
            path: app.yml
```

Now only this file exists:

```text
/etc/config/app.yml
```

This is cleaner when the application expects a specific filename.

---

# 7. Very important: update behavior

ConfigMap update behavior is one of the most misunderstood parts.

## Environment variables do not update live

If a Pod consumes ConfigMap values as environment variables, those values are injected when the container starts.

Example:

```yaml
env:
  - name: LOG_LEVEL
    valueFrom:
      configMapKeyRef:
        name: app-config
        key: LOG_LEVEL
```

If you later change the ConfigMap:

```bash
kubectl edit configmap app-config
```

The already-running container does **not** magically get the new environment variable value.

You need to restart/roll out the Pod:

```bash
kubectl rollout restart deployment/my-app
```

Kubernetes’ ConfigMap update tutorial states that changes to ConfigMaps used as environment variables are available after a subsequent Pod rollout. ([Kubernetes][4])

---

## Volume-mounted ConfigMaps can update

If a ConfigMap is mounted as a volume, Kubernetes can update the mounted files after the kubelet syncs the change. ([Kubernetes][4])

But there are two critical details:

```text
1. The file may update, but your application must reread or reload it.
2. If mounted with subPath, the container will not receive ConfigMap updates.
```

Kubernetes explicitly documents that a container using a ConfigMap through `subPath` will not receive updates when the ConfigMap changes. ([Kubernetes][3])

Bad assumption:

```text
I changed the ConfigMap, so my app behavior changed.
```

Correct assumption:

```text
The mounted file may eventually update, but the app must reload it or the Pod must restart.
```

---

# 8. ConfigMap with Deployment

In production, ConfigMaps are usually consumed by Deployments, StatefulSets, DaemonSets, Jobs, or CronJobs.

Example Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: configmap-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: configmap-app
  template:
    metadata:
      labels:
        app: configmap-app
    spec:
      containers:
        - name: app
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              while true; do
                echo "APP_ENV=$APP_ENV LOG_LEVEL=$LOG_LEVEL"
                sleep 10
              done
          env:
            - name: APP_ENV
              valueFrom:
                configMapKeyRef:
                  name: app-config
                  key: APP_ENV
            - name: LOG_LEVEL
              valueFrom:
                configMapKeyRef:
                  name: app-config
                  key: LOG_LEVEL
```

Apply:

```bash
kubectl apply -f deployment.yaml
```

Change the ConfigMap:

```bash
kubectl edit cm app-config
```

Then restart the Deployment:

```bash
kubectl rollout restart deployment/configmap-app
kubectl rollout status deployment/configmap-app
```

This creates new Pods that read the updated ConfigMap.

---

# 9. Production rollout pattern: checksum annotation

Changing a ConfigMap alone does **not** automatically create a new Deployment rollout, because the Deployment’s Pod template has not changed.

Common production pattern in Helm:

```yaml
spec:
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

Conceptually:

```text
ConfigMap content changes
    ↓
Checksum annotation changes
    ↓
Deployment Pod template changes
    ↓
New ReplicaSet is created
    ↓
Pods roll out safely
```

Without this, many teams change a ConfigMap and wonder why nothing happened.

For manual operations:

```bash
kubectl rollout restart deployment/my-app
```

For GitOps/Helm:

```text
Use checksum annotations.
```

For Kustomize:

```text
Use configMapGenerator.
```

Kustomize has `configMapGenerator`, which can generate ConfigMaps from files or literals, and generated names include a hash-like suffix such as `example-configmap-1-8mbdf7882g`. ([Kubernetes][5])

---

# 10. Immutable ConfigMaps

You can make a ConfigMap immutable:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-v1
immutable: true
data:
  LOG_LEVEL: "info"
```

Once immutable, you cannot modify its `data` or `binaryData`, and you cannot make it mutable again. To change behavior, create a new ConfigMap and update workloads to reference the new name. Kubernetes notes that immutable ConfigMaps are useful for constant configuration and can improve performance because the kubelet does not watch them for changes. ([Kubernetes][4])

Recommended naming style:

```text
app-config-v1
app-config-v2
app-config-2026-05-16
app-config-<git-sha>
```

Example:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-v2
immutable: true
data:
  LOG_LEVEL: "debug"
```

Then update your Deployment:

```yaml
env:
  - name: LOG_LEVEL
    valueFrom:
      configMapKeyRef:
        name: app-config-v2
        key: LOG_LEVEL
```

Production tip:

```text
Immutable ConfigMaps are excellent for GitOps.
Mutable ConfigMaps are convenient for development.
```

---

# 11. Optional ConfigMaps and keys

By default, if a Pod references a missing ConfigMap or missing key, the Pod may fail to start.

You can mark it optional:

```yaml
env:
  - name: OPTIONAL_FEATURE_FLAG
    valueFrom:
      configMapKeyRef:
        name: optional-config
        key: FEATURE_FLAG
        optional: true
```

For volume:

```yaml
volumes:
  - name: optional-config-volume
    configMap:
      name: optional-config
      optional: true
```

Use this carefully.

Good use case:

```text
Optional feature flags
Optional local development config
Backward-compatible migration
```

Bad use case:

```text
Critical DB host
Critical app runtime mode
Critical routing config
```

For critical values, fail fast.

---

# 12. ConfigMap vs Secret

| Topic                | ConfigMap                       | Secret                                                          |
| -------------------- | ------------------------------- | --------------------------------------------------------------- |
| Purpose              | Non-sensitive config            | Sensitive config                                                |
| Encoding             | Plain text strings / binaryData | Base64-encoded fields, but base64 is not encryption             |
| Example              | `LOG_LEVEL=info`                | `DB_PASSWORD=...`                                               |
| Security expectation | Not confidential                | Should be protected by RBAC, encryption at rest, secret tooling |
| Mounted as env       | Yes                             | Yes                                                             |
| Mounted as volume    | Yes                             | Yes                                                             |

Important: Kubernetes Secret values are base64-encoded by default, not automatically “secure” in the cryptographic sense. In real production environments, combine Secrets with:

```text
RBAC
Encryption at rest
External Secrets Operator
Vault / cloud secret manager
Sealed Secrets / SOPS
Short-lived credentials
Least privilege ServiceAccounts
```

---

# 13. ConfigMap volume pitfall: mounting over existing directories

Suppose your image contains:

```text
/etc/nginx/conf.d/default.conf
/etc/nginx/conf.d/security.conf
```

And you mount a ConfigMap here:

```yaml
volumeMounts:
  - name: nginx-config
    mountPath: /etc/nginx/conf.d
```

The mounted volume hides the existing directory contents from the image.

So now you may only see:

```text
/etc/nginx/conf.d/my-config.conf
```

This surprises people a lot.

Safer options:

```text
Mount config into a dedicated directory, for example /etc/app-config.
Use application args to point to that directory.
Build full config directory into ConfigMap intentionally.
Avoid subPath unless you understand the update tradeoff.
```

---

# 14. ConfigMap with nginx example

ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
    server {
      listen 80;

      location / {
        return 200 "Hello from ConfigMap nginx config\n";
      }
    }
```

Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-configmap-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-configmap-demo
  template:
    metadata:
      labels:
        app: nginx-configmap-demo
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
          volumeMounts:
            - name: nginx-config-volume
              mountPath: /etc/nginx/conf.d
      volumes:
        - name: nginx-config-volume
          configMap:
            name: nginx-config
```

Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-configmap-demo
spec:
  selector:
    app: nginx-configmap-demo
  ports:
    - port: 80
      targetPort: 80
```

Test:

```bash
kubectl apply -f nginx-configmap.yaml
kubectl apply -f nginx-deployment.yaml
kubectl apply -f nginx-service.yaml

kubectl port-forward svc/nginx-configmap-demo 8080:80
curl localhost:8080
```

---

# 15. ConfigMap with application.yaml example

This is common for Spring Boot, Micronaut, Quarkus, Python apps, Node.js services, and Go services.

ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
data:
  application.yaml: |
    server:
      port: 8080

    database:
      host: postgres.default.svc.cluster.local
      port: 5432
      name: appdb

    logging:
      level: INFO
```

Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
        - name: backend
          image: ghcr.io/example/backend:1.0.0
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: backend-config
              mountPath: /etc/backend
              readOnly: true
          env:
            - name: CONFIG_PATH
              value: /etc/backend/application.yaml
      volumes:
        - name: backend-config
          configMap:
            name: backend-config
```

Inside the app:

```text
Read CONFIG_PATH=/etc/backend/application.yaml
```

This is cleaner than passing a huge config file through environment variables.

---

# 16. Debugging ConfigMaps

## Check whether the ConfigMap exists

```bash
kubectl get cm -n default
kubectl get cm app-config -n default
```

## Inspect values

```bash
kubectl describe cm app-config
kubectl get cm app-config -o yaml
kubectl get cm app-config -o jsonpath='{.data.LOG_LEVEL}'
```

## Check whether Pod references it correctly

```bash
kubectl describe pod <pod-name>
```

Look for events like:

```text
configmap "app-config" not found
couldn't find key LOG_LEVEL in ConfigMap default/app-config
```

## Check environment variables inside the container

```bash
kubectl exec -it <pod-name> -- printenv | sort
kubectl exec -it <pod-name> -- sh
echo $LOG_LEVEL
```

## Check mounted files

```bash
kubectl exec -it <pod-name> -- ls -l /etc/app-config
kubectl exec -it <pod-name> -- cat /etc/app-config/application.yaml
```

## Check rollout status

```bash
kubectl rollout status deployment/my-app
kubectl rollout history deployment/my-app
kubectl get rs
kubectl get pods -l app=my-app
```

---

# 17. Common errors and fixes

## Error: ConfigMap not found

Symptom:

```text
CreateContainerConfigError
configmap "app-config" not found
```

Check:

```bash
kubectl get cm app-config
kubectl get cm app-config -n <namespace>
```

Fix:

```bash
kubectl apply -f configmap.yaml
```

Also verify namespace:

```bash
kubectl get pod <pod> -o jsonpath='{.metadata.namespace}'
kubectl get cm app-config -n <same-namespace>
```

ConfigMaps and Pods must be in the same namespace. ([Kubernetes][1])

---

## Error: key not found

Symptom:

```text
couldn't find key LOG_LEVEL in ConfigMap default/app-config
```

Check:

```bash
kubectl get cm app-config -o yaml
```

Fix the key name:

```yaml
data:
  LOG_LEVEL: "info"
```

Key names are case-sensitive.

---

## Problem: changed ConfigMap but app still uses old value

Cause depends on how you consume it.

If consumed as environment variable:

```bash
kubectl rollout restart deployment/my-app
```

If consumed as volume:

```text
Check whether the mounted file changed.
Check whether the app rereads/reloads the file.
Check whether you used subPath.
```

Remember: `subPath` mounts do not receive ConfigMap updates. ([Kubernetes][3])

---

## Problem: app cannot write to mounted config file

ConfigMap volumes are read-only. ([Kubernetes][3])

Bad app behavior:

```text
Application reads /etc/app/config.yaml
Application also tries to write back to /etc/app/config.yaml
```

Better:

```text
Mount ConfigMap at /etc/app-config
Write runtime state to /tmp, emptyDir, PVC, or app-specific writable path.
```

---

# 18. Hands-on lab

Create ConfigMap:

```bash
cat > configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo-config
data:
  APP_ENV: "dev"
  LOG_LEVEL: "info"
  app.conf: |
    port=8080
    feature_x=true
EOF

kubectl apply -f configmap.yaml
```

Create Pod:

```bash
cat > pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: configmap-lab
spec:
  containers:
    - name: app
      image: busybox:1.36
      command:
        - sh
        - -c
        - |
          echo "APP_ENV from env: \$APP_ENV"
          echo "LOG_LEVEL from env: \$LOG_LEVEL"
          echo "Config file:"
          cat /etc/config/app.conf
          sleep 3600
      env:
        - name: APP_ENV
          valueFrom:
            configMapKeyRef:
              name: demo-config
              key: APP_ENV
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: demo-config
              key: LOG_LEVEL
      volumeMounts:
        - name: config-volume
          mountPath: /etc/config
  volumes:
    - name: config-volume
      configMap:
        name: demo-config
EOF

kubectl apply -f pod.yaml
```

Check:

```bash
kubectl logs configmap-lab
kubectl exec -it configmap-lab -- printenv | grep -E 'APP_ENV|LOG_LEVEL'
kubectl exec -it configmap-lab -- cat /etc/config/app.conf
```

Update ConfigMap:

```bash
kubectl patch configmap demo-config \
  --type merge \
  -p '{"data":{"LOG_LEVEL":"debug","app.conf":"port=9090\nfeature_x=false\n"}}'
```

Check mounted file:

```bash
kubectl exec -it configmap-lab -- cat /etc/config/app.conf
```

Check env var:

```bash
kubectl exec -it configmap-lab -- printenv | grep LOG_LEVEL
```

Expected lesson:

```text
Mounted file may update.
Environment variable remains old until Pod restart.
```

Restart Pod manually:

```bash
kubectl delete pod configmap-lab
kubectl apply -f pod.yaml
kubectl logs configmap-lab
```

---

# 19. Production best practices

Use this checklist:

```text
Use ConfigMaps only for non-sensitive data.
Keep ConfigMaps small; remember the 1 MiB limit.
Prefer declarative YAML or GitOps over manual kubectl edit.
Use versioned or immutable ConfigMaps for production stability.
Use checksum annotations or Kustomize generators to trigger rollouts.
Do not expect env var updates without restarting Pods.
Do not expect apps to reload files unless they are designed to.
Avoid subPath if you need live updates.
Mount config read-only.
Use clear names: app-config, nginx-config, redis-config, coredns, etc.
Keep ConfigMap and consuming workload in the same namespace.
Avoid putting unrelated app configs into one giant ConfigMap.
Do not mount ConfigMaps over important image directories unless intentional.
```

My preferred production pattern:

```text
Small scalar config      → env vars from ConfigMap
Structured app config   → ConfigMap mounted as file
Sensitive config        → Secret / external secret manager
Frequently changed config → versioned ConfigMap + controlled rollout
Large config/data       → external storage, not ConfigMap
```

---

# 20. Senior-level mental model

A ConfigMap is not a dynamic distributed configuration system by itself.

It is:

```text
A Kubernetes-native way to inject non-sensitive configuration into Pods.
```

It is not:

```text
A secret store
A database
A feature flag platform
A large file store
A guaranteed instant hot-reload mechanism
```

The biggest real-world mistake is this:

```text
"We changed the ConfigMap, so production should now behave differently."
```

The correct engineering question is:

```text
How is the ConfigMap consumed: env var, volume, subPath, generated name, immutable object, Helm checksum, or rollout restart?
```

That detail determines whether your application actually sees the new configuration.

[1]: https://kubernetes.io/docs/concepts/configuration/configmap/ "ConfigMaps | Kubernetes"
[2]: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_configmap/ "kubectl create configmap | Kubernetes"
[3]: https://kubernetes.io/docs/concepts/storage/volumes/ "Volumes | Kubernetes"
[4]: https://kubernetes.io/docs/tutorials/configuration/updating-configuration-via-a-configmap/ "Updating Configuration via a ConfigMap | Kubernetes"
[5]: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/ "Declarative Management of Kubernetes Objects Using Kustomize | Kubernetes"
