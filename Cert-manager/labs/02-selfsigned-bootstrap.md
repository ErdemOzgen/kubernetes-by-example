# Lab 02 - SelfSigned Bootstrap and Certificate Introspection

## Objective

Issue your first certificate using a `SelfSigned` ClusterIssuer and inspect every generated artifact.

## Why This Stage Matters

You learn cert-manager object flow without external dependencies:

- `Certificate` -> `CertificateRequest` -> `Secret`
- SAN behavior
- TLS secret shape (`tls.crt`, `tls.key`, optional `ca.crt`)

## Step 1 - Create SelfSigned ClusterIssuer

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-bootstrap
spec:
  selfSigned: {}
EOF

kubectl get clusterissuer selfsigned-bootstrap
kubectl describe clusterissuer selfsigned-bootstrap
```

### What Step 1 does in practice

This creates a cluster-scoped signing source named `selfsigned-bootstrap`.

- `ClusterIssuer` means it is available across namespaces.
- `selfSigned: {}` means certificates are signed with their own private key.
- This is ideal for local bootstrapping and learning object flow.

What to validate after apply:

- `kubectl get clusterissuer selfsigned-bootstrap` shows the resource exists.
- `kubectl describe clusterissuer selfsigned-bootstrap` should eventually show a Ready condition.

Important limitation:

- Self-signed certificates are not publicly trusted by browsers or public clients by default.

## Step 2 - Request a Local Certificate

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-selfsigned
  namespace: sandbox
spec:
  secretName: app-selfsigned-tls
  commonName: app.localhost
  dnsNames:
    - app.localhost
    - api.localhost
  issuerRef:
    kind: ClusterIssuer
    name: selfsigned-bootstrap
  privateKey:
    algorithm: RSA
    size: 2048
  usages:
    - digital signature
    - key encipherment
    - server auth
EOF
```

### What Step 2 does in practice

This asks cert-manager to issue and maintain a TLS certificate for local hosts.

- `secretName: app-selfsigned-tls` is where cert-manager stores `tls.crt` and `tls.key`.
- `dnsNames` is the most important identity field for hostname verification.
- `issuerRef` points to the Step 1 issuer (`selfsigned-bootstrap`).
- `privateKey` defines key algorithm and size.
- `usages` constrains certificate purpose to server-side TLS.

Behind the scenes, cert-manager performs:

1. `Certificate` accepted by API admission.
2. `CertificateRequest` generated.
3. Certificate signed using the selected issuer.
4. Secret materialized in `sandbox/app-selfsigned-tls`.

Field-level guidance:

- Keep SANs in `dnsNames` aligned with real request hosts.
- Use stable `secretName` so Ingress and apps can reference it predictably.
- In modern TLS clients, SANs are authoritative and more important than `commonName`.

## Practical Example - NGINX with cert-manager Managed TLS

A ready manifest is provided here:

- [Cert-manager/labs/manifests/nginx-selfsigned-cert-manager.yaml](Cert-manager/labs/manifests/nginx-selfsigned-cert-manager.yaml)

This manifest includes:

- NGINX `Deployment`
- `Service`
- cert-manager `Certificate`
- `Ingress` using Traefik and the issued TLS secret

Apply flow:

```bash
echo "127.0.0.1 nginx.localhost" | sudo tee -a /etc/hosts
kubectl apply -f Cert-manager/labs/manifests/nginx-selfsigned-cert-manager.yaml
kubectl wait --for=condition=Ready certificate/nginx-selfsigned-cert -n sandbox --timeout=180s
curl -vk https://nginx.localhost:8443/
```

Traffic flow (k3d + Traefik + cert-manager TLS):

```text
Client (curl/browser)
  -> https://nginx.localhost:8443
  -> Host port 8443
  -> k3d loadbalancer :443
  -> Traefik Ingress (TLS terminates using nginx-selfsigned-tls)
  -> Service nginx-selfsigned :80
  -> Pod nginx-selfsigned (containerPort 80)
```

Strict trust check with exported cert:

```bash
kubectl get secret -n sandbox nginx-selfsigned-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/nginx-selfsigned.crt
curl --cacert /tmp/nginx-selfsigned.crt https://nginx.localhost:8443/
```

## Step 3 - Inspect Lifecycle Objects

```bash
kubectl get certificate -n sandbox app-selfsigned
kubectl describe certificate -n sandbox app-selfsigned
kubectl get certificaterequest -n sandbox
kubectl describe certificaterequest -n sandbox
kubectl get secret -n sandbox app-selfsigned-tls -o yaml
```

## Step 4 - Decode and Inspect Certificate

```bash
kubectl get secret -n sandbox app-selfsigned-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/app-selfsigned.crt
kubectl get secret -n sandbox app-selfsigned-tls -o jsonpath='{.data.tls\.key}' | base64 -d > /tmp/app-selfsigned.key

openssl x509 -in /tmp/app-selfsigned.crt -text -noout
openssl x509 -in /tmp/app-selfsigned.crt -noout -issuer -subject -dates
```

What to verify in output:

- Subject/SAN includes `app.localhost` and `api.localhost`
- Key usage includes TLS server usage
- Issuer equals Subject for self-signed cert

## Step 5 - Negative Test (Intentional Mismatch)

Request certificate for one hostname and test another.

```bash
echo "127.0.0.1 wrong.localhost" | sudo tee -a /etc/hosts
```

Later, when this cert is used by Ingress for `wrong.localhost`, hostname verification should fail (unless insecure flag used).

## Troubleshooting Commands

```bash
kubectl get events -n sandbox --sort-by=.lastTimestamp
kubectl logs -n cert-manager deploy/cert-manager --tail=200
kubectl describe certificaterequest -n sandbox
```

## Cleanup

```bash
kubectl delete certificate -n sandbox app-selfsigned
kubectl delete clusterissuer selfsigned-bootstrap
kubectl delete secret -n sandbox app-selfsigned-tls --ignore-not-found
```

## Exit Criteria

You are ready for Lab 03 when:

- You can explain each object generated from a `Certificate`
- You verified SANs in X.509 output
- You understand why browsers do not trust self-signed certs by default
