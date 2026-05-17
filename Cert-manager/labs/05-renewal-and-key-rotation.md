# Lab 05 - Renewal and Private Key Rotation

## Objective

Practice forced renewal and verify private key rotation behavior in cert-manager >= v1.18.

## Why This Stage Matters

Certificate issuance is easy. Safe lifecycle management (renewal, rotation, app reload behavior) is where production systems fail.

## Standalone Mode (No Previous Labs Required)

This lab can be run on a fresh k3d cluster without completing earlier labs.

Default resources used by this lab:

- Certificate: `renewal-demo-cert`
- TLS Secret: `renewal-demo-tls`
- Deployment: `renewal-nginx`
- Service: `renewal-nginx`
- Ingress: `renewal-nginx`
- Hostname: `renewal.localhost`
- Issuer: `renewal-selfsigned`

## Step 0 - Standalone Bootstrap

Create namespace and install cert-manager if not already installed:

```bash
kubectl create ns sandbox --dry-run=client -o yaml | kubectl apply -f -

if ! helm -n cert-manager status cert-manager >/dev/null 2>&1; then
  helm install \
    cert-manager oci://quay.io/jetstack/charts/cert-manager \
    --version v1.20.2 \
    --namespace cert-manager \
    --create-namespace \
    --set crds.enabled=true
fi

kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=180s
```

Apply standalone bootstrap resources for this lab:

```bash
echo "127.0.0.1 renewal.localhost" | sudo tee -a /etc/hosts
kubectl apply -f Cert-manager/labs/manifests/05-renewal-standalone-bootstrap.yaml
kubectl wait --for=condition=Ready certificate/renewal-demo-cert -n sandbox --timeout=180s
curl -vk https://renewal.localhost:8443/
```

Set reusable variables for the rest of the lab:

```bash
CERT_NAME=renewal-demo-cert
SECRET_NAME=renewal-demo-tls
DEPLOY_NAME=renewal-nginx
```

## Step 1 - Inspect Current Certificate State

```bash
kubectl get certificate -n sandbox
kubectl describe certificate -n sandbox
kubectl get secret -n sandbox
```

If `cmctl` is installed:

```bash
cmctl status certificate -n sandbox ${CERT_NAME}
```

## Step 2 - Capture Current Key Fingerprint

Use the defaults from Step 0:

```bash
kubectl get secret -n sandbox ${SECRET_NAME} -o jsonpath='{.data.tls\.key}' | base64 -d > /tmp/before.key
openssl pkey -in /tmp/before.key -pubout -outform pem | openssl sha256
```

## Step 3 - Trigger Renewal

Preferred:

```bash
cmctl renew -n sandbox ${CERT_NAME}
```

Alternative (annotation-based trigger):

```bash
kubectl annotate certificate -n sandbox ${CERT_NAME} cert-manager.io/renew-reason=manual-$(date +%s) --overwrite
```

Observe:

```bash
kubectl describe certificate -n sandbox ${CERT_NAME}
kubectl get certificaterequest -n sandbox --sort-by=.metadata.creationTimestamp
```

## Step 4 - Compare Key Material After Renewal

```bash
kubectl get secret -n sandbox ${SECRET_NAME} -o jsonpath='{.data.tls\.key}' | base64 -d > /tmp/after.key
openssl pkey -in /tmp/after.key -pubout -outform pem | openssl sha256
```

Interpretation:

- Different fingerprint: key rotated
- Same fingerprint: key reused (policy or config may enforce reuse)

## Step 5 - Validate New Certificate Dates

```bash
kubectl get secret -n sandbox ${SECRET_NAME} -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/after.crt
openssl x509 -in /tmp/after.crt -noout -issuer -subject -dates -serial
```

## Step 6 - Application Reload Strategy Drill

Questions to answer in your cluster:

1. Does your app automatically reload cert files from mounted volumes?
2. If not, what restart policy do you use (manual rollout, reloader, checksum annotation)?

Run practical check:

```bash
kubectl rollout restart deploy -n sandbox ${DEPLOY_NAME}
kubectl rollout status deploy -n sandbox ${DEPLOY_NAME}
```

## Failure Injection

Force impossible renew window values and observe controller behavior (on a test cert only):

```yaml
spec:
  duration: 2h
  renewBefore: 3h
```

Expected: validation or reconciliation errors depending on version and policy.

## Troubleshooting

```bash
kubectl describe certificate -n sandbox ${CERT_NAME}
kubectl describe certificaterequest -n sandbox
kubectl logs -n cert-manager deploy/cert-manager --tail=200
```

## Cleanup

Default cleanup (remove only Lab 05 standalone resources):

```bash
kubectl delete ingress -n sandbox renewal-nginx --ignore-not-found
kubectl delete certificate -n sandbox renewal-demo-cert --ignore-not-found
kubectl delete secret -n sandbox renewal-demo-tls --ignore-not-found
kubectl delete deploy,svc -n sandbox renewal-nginx --ignore-not-found
kubectl delete clusterissuer renewal-selfsigned --ignore-not-found
rm -f /tmp/before.key /tmp/after.key /tmp/after.crt
```

Optional full cleanup (only if this cluster is dedicated to this lab):

```bash
kubectl delete ns sandbox --ignore-not-found
# Optional: remove cert-manager as well
# helm uninstall cert-manager -n cert-manager
# kubectl delete ns cert-manager --ignore-not-found
```

## Exit Criteria

You are ready for Lab 06 when:

- You can force renewal safely
- You can prove whether private key rotated
- You have a clear app reload strategy
