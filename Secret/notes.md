# Kubernetes Secret

A **Secret** is a Kubernetes object used to store **sensitive data**, such as passwords, tokens, private keys, TLS certificates, registry credentials, and SSH keys. It is similar to a ConfigMap, but it is intended for confidential data. Kubernetes lets Pods consume Secrets as environment variables, mounted files, or image pull credentials. ([Kubernetes][1])

The core mental model:

```text
ConfigMap = non-sensitive configuration
Secret    = sensitive configuration
```

Examples:

```text
DB_PASSWORD
JWT_SIGNING_KEY
GITHUB_TOKEN
TLS_PRIVATE_KEY
DOCKER_REGISTRY_PASSWORD
OAUTH_CLIENT_SECRET
SSH_PRIVATE_KEY
```

Do **not** assume that a Kubernetes Secret is automatically secure just because the object is named `Secret`.

By default, Kubernetes Secrets are stored **unencrypted** in the API server’s underlying datastore, usually `etcd`. Anyone with API access to read Secrets, anyone with direct etcd access, and even users who can create Pods in a namespace may be able to access Secrets in that namespace indirectly. ([Kubernetes][1])

That is the most important senior-level warning.

---

# 1. Basic Secret example

A Secret usually looks like this:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
  namespace: default
type: Opaque
stringData:
  DB_USERNAME: appuser
  DB_PASSWORD: super-secret-password
  JWT_SECRET: very-secret-jwt-signing-key
```

Apply:

```bash
kubectl apply -f secret.yaml
```

Check:

```bash
kubectl get secrets
kubectl get secret app-secret
kubectl describe secret app-secret
```

Output:

```text
NAME         TYPE     DATA   AGE
app-secret   Opaque   3      10s
```

`kubectl describe secret` does **not** show the secret values. It shows metadata and key names/counts.

---

# 2. `data` vs `stringData`

Secrets support two important fields:

```yaml
data:
  KEY: base64-encoded-value

stringData:
  KEY: plain-text-value
```

## `stringData`

This is easier for humans:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
type: Opaque
stringData:
  username: admin
  password: my-password
```

Kubernetes internally converts `stringData` into `data`.

## `data`

This requires base64 encoding:

```bash
echo -n 'admin' | base64
echo -n 'my-password' | base64
```

Example output:

```text
YWRtaW4=
bXktcGFzc3dvcmQ=
```

Then:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
type: Opaque
data:
  username: YWRtaW4=
  password: bXktcGFzc3dvcmQ=
```

Kubernetes requires values under `data` to be base64-encoded strings. `stringData` accepts plain strings and is merged into `data`; if the same key exists in both, `stringData` wins. Kubernetes also notes that `stringData` does not work well with server-side apply. ([Kubernetes][1])

Production advice:

```text
For quick demos:       stringData is fine.
For generated YAML:    data is common.
For GitOps:            do not commit raw secrets.
For server-side apply: avoid relying on stringData.
```

---

# 3. Base64 is not encryption

This is a huge point.

This:

```bash
echo -n 'my-password' | base64
```

Produces:

```text
bXktcGFzc3dvcmQ=
```

And this reverses it:

```bash
echo 'bXktcGFzc3dvcmQ=' | base64 -d
```

Output:

```text
my-password
```

So base64 is only **encoding**, not encryption.

A Kubernetes Secret gives you better object separation and access-control opportunities than putting credentials directly into Pod YAML, but it is not secure enough by default for serious production unless you also configure controls such as RBAC, encryption at rest, audit logging, namespace isolation, and external secret management. Kubernetes’ own good-practices documentation says Secret values are base64-encoded and stored unencrypted by default, but can be configured for encryption at rest. ([Kubernetes][2])

---

# 4. Secret size limit

Individual Kubernetes Secrets are limited to **1 MiB**. This exists to prevent large Secrets from exhausting API server and kubelet memory. ([Kubernetes][1])

Good Secret usage:

```text
password
token
certificate
private key
small config credential bundle
```

Bad Secret usage:

```text
large license files
large JSON documents
database dumps
ML models
binary packages
huge certificate bundles
```

For large sensitive data, use:

```text
Vault
cloud secret manager
encrypted object storage
CSI Secret Store
external mounted volume
application-level encryption
```

---

# 5. Creating Secrets with `kubectl`

## Generic Secret from literals

```bash
kubectl create secret generic app-secret \
  --from-literal=DB_USERNAME=appuser \
  --from-literal=DB_PASSWORD='super-secret-password'
```

Check:

```bash
kubectl get secret app-secret -o yaml
```

You will see base64-encoded values.

Decode one value:

```bash
kubectl get secret app-secret \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
echo
```

## Generic Secret from file

Create files:

```bash
echo -n 'appuser' > username.txt
echo -n 'super-secret-password' > password.txt
```

Create Secret:

```bash
kubectl create secret generic app-secret \
  --from-file=username=username.txt \
  --from-file=password=password.txt
```

The keys are `username` and `password`.

## Generic Secret from env file

```bash
cat > secret.env <<EOF
DB_USERNAME=appuser
DB_PASSWORD=super-secret-password
JWT_SECRET=jwt-secret-value
EOF

kubectl create secret generic app-secret \
  --from-env-file=secret.env
```

Production warning: avoid leaving `secret.env` on disk unprotected or committing it to Git.

---

# 6. Consuming Secret as environment variables

## Specific key with `env`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secret-env-demo
spec:
  containers:
    - name: app
      image: busybox:1.36
      command:
        - sh
        - -c
        - |
          echo "DB_USERNAME=$DB_USERNAME"
          echo "DB_PASSWORD is set but not printing it"
          sleep 3600
      env:
        - name: DB_USERNAME
          valueFrom:
            secretKeyRef:
              name: app-secret
              key: DB_USERNAME
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: app-secret
              key: DB_PASSWORD
```

Apply:

```bash
kubectl apply -f pod-secret-env.yaml
```

Check:

```bash
kubectl logs secret-env-demo
kubectl exec -it secret-env-demo -- printenv | grep DB_
```

This is simple, but there are security tradeoffs.

Environment variables can leak through:

```text
process inspection
debug dumps
application logs
crash reports
/proc access inside the container
accidental printenv
third-party telemetry
```

For highly sensitive values, mounted files are often better than env vars.

---

## Import all Secret keys with `envFrom`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secret-envfrom-demo
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "printenv | sort && sleep 3600"]
      envFrom:
        - secretRef:
            name: app-secret
```

Senior advice:

```text
Use envFrom only for small/simple apps.
Prefer explicit env entries for production-critical workloads.
Avoid accidental key collisions.
Never print all env vars in production logs.
```

---

# 7. Consuming Secret as mounted files

This is one of the cleanest patterns.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secret-volume-demo
spec:
  containers:
    - name: app
      image: busybox:1.36
      command:
        - sh
        - -c
        - |
          echo "Available secret files:"
          ls -l /etc/secrets
          echo "Username:"
          cat /etc/secrets/DB_USERNAME
          echo "Password exists but not printing it"
          sleep 3600
      volumeMounts:
        - name: app-secret-volume
          mountPath: /etc/secrets
          readOnly: true

  volumes:
    - name: app-secret-volume
      secret:
        secretName: app-secret
```

Each key becomes a file:

```text
/etc/secrets/DB_USERNAME
/etc/secrets/DB_PASSWORD
/etc/secrets/JWT_SECRET
```

Kubernetes Secret volumes are mounted read-only. Secret volumes are also backed by `tmpfs`, a RAM-backed filesystem, so they are not written to non-volatile storage by kubelet as normal files. ([Kubernetes][3])

This is why many production systems prefer mounted Secret files for certificates, private keys, and tokens.

---

# 8. Mounting only selected keys

You can choose which keys to mount and what file names they should have:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: selected-secret-demo
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "ls -l /etc/app && sleep 3600"]
      volumeMounts:
        - name: secret-volume
          mountPath: /etc/app
          readOnly: true

  volumes:
    - name: secret-volume
      secret:
        secretName: app-secret
        items:
          - key: DB_PASSWORD
            path: db-password
```

Inside container:

```text
/etc/app/db-password
```

This is useful when your app expects a specific path.

---

# 9. Secret update behavior

This is where many engineers get surprised.

## Secrets used as env vars do not update live

If a container reads a Secret through environment variables, the value is injected at container startup.

Changing the Secret later does not change the already-running process environment.

You need to restart the Pod or roll out the Deployment:

```bash
kubectl rollout restart deployment/my-app
kubectl rollout status deployment/my-app
```

## Secrets mounted as volumes can update

If a Secret is mounted as a volume, Kubernetes can update the mounted files after the Secret changes.

But there are important caveats:

```text
The app must reread or reload the file.
The update is not instant.
subPath mounts do not receive Secret updates.
Some applications read config only once at startup.
```

Kubernetes explicitly documents that a container using a Secret as a `subPath` volume mount will not receive Secret updates. ([Kubernetes][3])

So the correct production question is:

```text
How is the Secret consumed?
```

Not:

```text
Did we update the Secret?
```

---

# 10. Secret with Deployment

In production, Secrets are usually referenced from a Deployment, StatefulSet, DaemonSet, Job, or CronJob.

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

          env:
            - name: DB_USERNAME
              valueFrom:
                secretKeyRef:
                  name: app-secret
                  key: DB_USERNAME
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: app-secret
                  key: DB_PASSWORD

          volumeMounts:
            - name: tls-secret
              mountPath: /etc/tls
              readOnly: true

      volumes:
        - name: tls-secret
          secret:
            secretName: backend-tls
```

Rollout after Secret change:

```bash
kubectl rollout restart deployment/backend
kubectl rollout status deployment/backend
```

For Helm, use checksum annotations, similar to ConfigMaps:

```yaml
spec:
  template:
    metadata:
      annotations:
        checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
```

Conceptually:

```text
Secret changes
  ↓
Pod template annotation changes
  ↓
New ReplicaSet created
  ↓
New Pods start with new Secret value
```

---

# 11. Built-in Secret types

Kubernetes supports several built-in Secret types. The `type` field helps Kubernetes and tools understand the expected content. Built-in types include `Opaque`, ServiceAccount token Secrets, Docker config Secrets, basic-auth Secrets, SSH auth Secrets, TLS Secrets, and bootstrap token Secrets. ([Kubernetes][1])

| Type                                  | Purpose                                |
| ------------------------------------- | -------------------------------------- |
| `Opaque`                              | Arbitrary user-defined secret data     |
| `kubernetes.io/dockerconfigjson`      | Private registry credentials           |
| `kubernetes.io/dockercfg`             | Legacy Docker registry credentials     |
| `kubernetes.io/basic-auth`            | Username/password credentials          |
| `kubernetes.io/ssh-auth`              | SSH private key                        |
| `kubernetes.io/tls`                   | TLS certificate and private key        |
| `kubernetes.io/service-account-token` | Legacy long-lived ServiceAccount token |
| `bootstrap.kubernetes.io/token`       | Cluster bootstrap token                |

Most application credentials use:

```yaml
type: Opaque
```

---

# 12. TLS Secret

TLS Secrets are used heavily with Ingress controllers, cert-manager, service mesh, and internal mTLS setups.

Create from files:

```bash
kubectl create secret tls backend-tls \
  --cert=tls.crt \
  --key=tls.key
```

Equivalent YAML:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: backend-tls
type: kubernetes.io/tls
data:
  tls.crt: <base64-cert>
  tls.key: <base64-key>
```

Kubernetes expects `tls.crt` and `tls.key` keys for `kubernetes.io/tls` Secrets, although it does not fully validate the certificate/key correctness. ([Kubernetes][1])

Example Ingress usage:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: backend-ingress
spec:
  tls:
    - hosts:
        - api.example.com
      secretName: backend-tls
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: backend
                port:
                  number: 80
```

---

# 13. Docker registry Secret / `imagePullSecrets`

For private registries, Kubernetes commonly uses a Secret of type:

```text
kubernetes.io/dockerconfigjson
```

Create:

```bash
kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=myuser \
  --docker-password='mypassword' \
  --docker-email=myemail@example.com
```

Use it in a Pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: private-image-demo
spec:
  imagePullSecrets:
    - name: regcred
  containers:
    - name: app
      image: registry.example.com/myteam/private-app:1.0.0
```

Kubernetes documents `imagePullSecrets` as the recommended approach for Pods that need to pull from private registries; those Secrets must exist in the same namespace as the Pod and be of type `kubernetes.io/dockercfg` or `kubernetes.io/dockerconfigjson`. ([Kubernetes][4])

Common error:

```text
ImagePullBackOff
ErrImagePull
pull access denied
no basic auth credentials
```

Debug:

```bash
kubectl describe pod private-image-demo
kubectl get secret regcred -o yaml
kubectl get secret regcred -n <namespace>
```

---

# 14. ServiceAccount token Secrets

This area changed significantly in modern Kubernetes.

Historically, Kubernetes automatically created long-lived ServiceAccount token Secrets. In Kubernetes v1.22 and later, the recommended approach is to use short-lived, automatically rotating tokens through the TokenRequest API or projected volumes. Kubernetes says ServiceAccount token Secrets are a legacy mechanism and should only be created if TokenRequest cannot be used and the security exposure of a non-expiring token is acceptable. ([Kubernetes][1])

Recommended:

```bash
kubectl create token build-robot
```

With duration:

```bash
kubectl create token build-robot --duration=10m
```

Manual long-lived token Secret, only when you really need it:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: build-robot-secret
  annotations:
    kubernetes.io/service-account.name: build-robot
type: kubernetes.io/service-account-token
```

Kubernetes recommends using TokenRequest instead of manually creating long-lived ServiceAccount token Secrets. ([Kubernetes][5])

Production advice:

```text
Avoid long-lived ServiceAccount token Secrets.
Use short-lived projected tokens.
Set automountServiceAccountToken: false when the app does not need Kubernetes API access.
```

Example:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: no-api-token-demo
spec:
  automountServiceAccountToken: false
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
```

---

# 15. Optional Secrets

By default, if a Pod references a missing Secret, the container will not start. Kubernetes says non-optional Secrets must be available before containers start. ([Kubernetes][1])

You can mark a Secret or key optional.

Environment variable:

```yaml
env:
  - name: OPTIONAL_TOKEN
    valueFrom:
      secretKeyRef:
        name: optional-secret
        key: token
        optional: true
```

Volume:

```yaml
volumes:
  - name: optional-secret-volume
    secret:
      secretName: optional-secret
      optional: true
```

Use optional Secrets carefully.

Good use cases:

```text
optional plugin credentials
local development
backward-compatible migrations
feature-specific integrations
```

Bad use cases:

```text
database password
JWT signing key
payment provider credential
production TLS key
```

For critical security config, fail fast.

---

# 16. Immutable Secrets

You can make a Secret immutable:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secret-v1
type: Opaque
immutable: true
stringData:
  DB_PASSWORD: super-secret-password
```

Once immutable, you cannot edit its data. To rotate, create a new Secret and update workloads to reference it.

Pattern:

```text
app-secret-v1
app-secret-v2
app-secret-2026-05-16
app-secret-<git-sha>
```

This is excellent for GitOps-style deployments and deterministic rollbacks.

---

# 17. Security: what a Secret protects and what it does not

A Kubernetes Secret helps you avoid putting sensitive values directly into:

```text
container images
application code
plain Pod specs
ConfigMaps
command-line arguments
```

But it does **not** automatically protect you from:

```text
over-permissive RBAC
etcd compromise
namespace admin compromise
Pod creation privilege abuse
malicious admission controllers
logs that print secrets
apps exposing env vars
debug containers
node-level compromise
CI/CD leakage
Git history leakage
```

Kubernetes’ good practices recommend encryption at rest and least-privilege access for Secrets. ([Kubernetes][2])

For real production clusters, use:

```text
RBAC least privilege
encryption at rest for Secrets
audit logging
namespace isolation
NetworkPolicies
Pod Security Standards
short-lived credentials
external secret manager
secret rotation process
CI/CD secret scanning
admission control policies
```

---

# 18. Encryption at rest

Kubernetes can encrypt API resource data at rest, including Secrets. This encryption is configured for the kube-apiserver and is separate from filesystem encryption or etcd-level encryption. ([Kubernetes][6])

The important distinction:

```text
Base64 in Secret YAML  ≠ encryption
Kubernetes at-rest encryption = API server encrypts resource data before storing it in etcd
```

High-level encryption configuration usually involves:

```text
EncryptionConfiguration
kube-apiserver --encryption-provider-config
key providers such as aescbc, secretbox, kms, etc.
rotation procedure
verification that old Secrets are rewritten encrypted
```

Senior production advice:

```text
Use cloud KMS where possible.
Avoid manually managing static encryption keys forever.
Rotate encryption keys.
Restrict direct etcd access.
Back up etcd securely.
Treat etcd backups as highly sensitive.
```

---

# 19. RBAC risks

This is one of the biggest Kubernetes privilege escalation paths.

If a user can read Secrets:

```yaml
resources: ["secrets"]
verbs: ["get", "list", "watch"]
```

They can access sensitive values.

But also, if a user can create Pods in a namespace, they may be able to mount Secrets into a Pod and read them indirectly. Kubernetes explicitly warns that anyone authorized to create a Pod in a namespace can use that access to read any Secret in that namespace. ([Kubernetes][1])

Dangerous permission:

```yaml
resources: ["pods"]
verbs: ["create"]
```

Potential attack:

```text
Create Pod
Mount target Secret
Exec/log the secret value
Exfiltrate credential
```

So do not think:

```text
"They cannot get secrets, so they cannot read secrets."
```

If they can create Pods in that namespace, they may still be able to read Secrets indirectly.

---

# 20. Minimal RBAC example for reading one Secret

A tight Role:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: read-app-secret
  namespace: app
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["app-secret"]
    verbs: ["get"]
```

RoleBinding:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-app-secret-binding
  namespace: app
subjects:
  - kind: ServiceAccount
    name: app-reader
    namespace: app
roleRef:
  kind: Role
  name: read-app-secret
  apiGroup: rbac.authorization.k8s.io
```

But usually, application Pods do not need direct Kubernetes API permission to read the Secret. They get the Secret mounted/injected by kubelet. So avoid giving application ServiceAccounts `get secrets` unless the app truly needs API-level secret access.

---

# 21. Debugging Secrets

## Check Secret exists

```bash
kubectl get secret app-secret
kubectl get secret app-secret -n app
```

## Inspect metadata

```bash
kubectl describe secret app-secret -n app
```

## View encoded Secret

```bash
kubectl get secret app-secret -n app -o yaml
```

## Decode one key

```bash
kubectl get secret app-secret -n app \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
echo
```

## Check Pod events

```bash
kubectl describe pod <pod> -n app
```

Look for:

```text
secret "app-secret" not found
couldn't find key DB_PASSWORD in Secret app/app-secret
MountVolume.SetUp failed
CreateContainerConfigError
```

## Check mounted files

```bash
kubectl exec -it <pod> -n app -- ls -l /etc/secrets
kubectl exec -it <pod> -n app -- sh -c 'test -f /etc/secrets/DB_PASSWORD && echo exists'
```

Avoid this in shared environments:

```bash
kubectl exec -it <pod> -- cat /etc/secrets/DB_PASSWORD
```

It may expose the password in terminal scrollback, logs, screen recordings, or shell history.

## Check environment variable exists without printing value

```bash
kubectl exec -it <pod> -n app -- sh -c '[ -n "$DB_PASSWORD" ] && echo "DB_PASSWORD is set"'
```

---

# 22. Common errors and fixes

## `CreateContainerConfigError`

Common cause:

```text
Secret does not exist
Secret key does not exist
Secret is in a different namespace
```

Debug:

```bash
kubectl describe pod <pod> -n <namespace>
kubectl get secret <secret-name> -n <namespace>
kubectl get secret <secret-name> -n <namespace> -o yaml
```

Fix:

```bash
kubectl apply -f secret.yaml
```

Remember: Secret and consuming Pod must be in the same namespace.

---

## `ImagePullBackOff`

Common cause:

```text
Private registry Secret missing
Wrong imagePullSecret name
Wrong namespace
Bad registry credentials
Wrong registry server
```

Debug:

```bash
kubectl describe pod <pod>
kubectl get secret regcred -o yaml
```

Fix:

```yaml
spec:
  imagePullSecrets:
    - name: regcred
```

---

## App still uses old password

Cause:

```text
Secret consumed as env var
Pod was not restarted
Application connection pool still has old credential
Application does not reload mounted file
subPath was used
```

Fix:

```bash
kubectl rollout restart deployment/backend
```

Then verify:

```bash
kubectl rollout status deployment/backend
kubectl get pods -l app=backend
```

---

# 23. Secret rotation pattern

A safe rotation is usually not:

```text
kubectl edit secret app-secret
hope everything updates
```

Better pattern:

```text
1. Create new Secret: app-secret-v2
2. Update Deployment to reference app-secret-v2
3. Roll out new Pods
4. Verify app works
5. Revoke old credential from upstream system
6. Delete old Secret when safe
```

Example:

```yaml
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: app-secret-v2
        key: DB_PASSWORD
```

Roll out:

```bash
kubectl apply -f deployment.yaml
kubectl rollout status deployment/backend
```

This gives you safer rollback:

```text
If app-secret-v2 breaks, roll back to app-secret-v1.
```

For certificates and tokens with expiry, automate rotation using:

```text
cert-manager
External Secrets Operator
Secrets Store CSI Driver
Vault Agent Injector
cloud-native secret managers
custom controller/operator
```

---

# 24. GitOps problem: do not commit raw Secrets

Bad:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
type: Opaque
data:
  DB_PASSWORD: c3VwZXItc2VjcmV0LXBhc3N3b3Jk
```

This is still recoverable:

```bash
echo 'c3VwZXItc2VjcmV0LXBhc3N3b3Jk' | base64 -d
```

Better GitOps options:

```text
Sealed Secrets
SOPS + age/GPG/KMS
External Secrets Operator
Secrets Store CSI Driver
Vault
AWS Secrets Manager
Azure Key Vault
Google Secret Manager
1Password Connect
Doppler or similar platforms
```

A mature production flow:

```text
Secret value lives in external secret manager
Git stores only references/templates
Controller syncs Kubernetes Secret or mounts value directly
Workload receives Secret
Rotation is automated
```

---

# 25. Hands-on lab

Create Secret:

```bash
cat > secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: demo-secret
type: Opaque
stringData:
  DB_USERNAME: appuser
  DB_PASSWORD: super-secret-password
EOF

kubectl apply -f secret.yaml
```

Create Pod using env var and mounted volume:

```bash
cat > pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: secret-lab
spec:
  containers:
    - name: app
      image: busybox:1.36
      command:
        - sh
        - -c
        - |
          echo "DB_USERNAME from env: $DB_USERNAME"
          echo "DB_PASSWORD env is set but not printing"
          echo "Secret files:"
          ls -l /etc/secrets
          echo "Mounted username:"
          cat /etc/secrets/DB_USERNAME
          sleep 3600
      env:
        - name: DB_USERNAME
          valueFrom:
            secretKeyRef:
              name: demo-secret
              key: DB_USERNAME
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: demo-secret
              key: DB_PASSWORD
      volumeMounts:
        - name: secret-volume
          mountPath: /etc/secrets
          readOnly: true
  volumes:
    - name: secret-volume
      secret:
        secretName: demo-secret
EOF

kubectl apply -f pod.yaml
```

Check:

```bash
kubectl logs secret-lab
kubectl exec -it secret-lab -- ls -l /etc/secrets
kubectl exec -it secret-lab -- sh -c '[ -n "$DB_PASSWORD" ] && echo "DB_PASSWORD is set"'
```

Update Secret:

```bash
kubectl patch secret demo-secret \
  --type merge \
  -p '{"stringData":{"DB_PASSWORD":"new-password"}}'
```

Check mounted files later:

```bash
kubectl exec -it secret-lab -- sh -c 'ls -l /etc/secrets && echo files-present'
```

But remember:

```text
Env var value will not change in the already-running container.
Mounted file may update, but the application must reread it.
```

Delete lab:

```bash
kubectl delete pod secret-lab
kubectl delete secret demo-secret
```

---

# 26. Production best practices

Use this checklist:

```text
Never commit raw Kubernetes Secrets to Git.
Remember base64 is not encryption.
Enable encryption at rest for Secrets.
Use least-privilege RBAC.
Avoid giving apps get/list/watch permission on secrets.
Avoid giving users Pod creation rights if they should not access namespace Secrets.
Prefer mounted files for highly sensitive values.
Avoid printing env vars or secret files.
Use short-lived credentials where possible.
Use external secret managers for serious production.
Rotate Secrets regularly.
Use versioned/immutable Secrets for controlled rollouts.
Use checksum annotations or explicit rollout restarts.
Disable automountServiceAccountToken when not needed.
Keep Secrets small; 1 MiB limit applies.
Do not use Secret for large files or dynamic configuration systems.
Protect etcd backups as sensitive data.
Use audit logs to detect suspicious Secret access.
```

My preferred real-world pattern:

```text
Non-sensitive app config       → ConfigMap
Sensitive static credential    → Secret synced from external manager
TLS certs                      → cert-manager-managed TLS Secret
Registry credentials           → imagePullSecret or workload identity
Kubernetes API token           → projected short-lived ServiceAccount token
GitOps secret material         → SOPS/SealedSecrets/external-secrets
High-security dynamic secret   → Vault/cloud secret manager with short TTL
```

---

# 27. Senior-level mental model

A Kubernetes Secret is not a magic vault.

It is:

```text
A Kubernetes API object for distributing small sensitive values to workloads.
```

It is not:

```text
A fully secure secret-management system by itself.
A replacement for Vault or cloud secret managers.
Encrypted just because values are base64-encoded.
Automatically rotated.
Automatically reloaded by your application.
Safe to expose through broad RBAC.
```

The most important operational questions are:

```text
Who can read this Secret?
Who can create Pods in this namespace?
Is encryption at rest enabled?
How is the Secret delivered: env var or file?
How is rotation handled?
Does the application reload or need restart?
Is the value also stored in Git, CI logs, shell history, or etcd backups?
```

If you answer those well, you are using Kubernetes Secrets like a senior engineer.

[1]: https://kubernetes.io/docs/concepts/configuration/secret/ "Secrets | Kubernetes"
[2]: https://kubernetes.io/docs/concepts/security/secrets-good-practices/ "Good practices for Kubernetes Secrets | Kubernetes"
[3]: https://kubernetes.io/docs/concepts/storage/volumes/ "Volumes | Kubernetes"
[4]: https://kubernetes.io/docs/concepts/containers/images/ "Images | Kubernetes"
[5]: https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/ "Configure Service Accounts for Pods | Kubernetes"
[6]: https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/ "Encrypting Confidential Data at Rest | Kubernetes"
