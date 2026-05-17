# Lab 05 - Renewal and Private Key Rotation

## Objective

Practice forced renewal and verify private key rotation behavior in cert-manager >= v1.18.

## Why This Stage Matters

Certificate issuance is easy. Safe lifecycle management (renewal, rotation, app reload behavior) is where production systems fail.

## Assumption

A working certificate exists in namespace `sandbox` (for example from Lab 04).

## Step 1 - Inspect Current Certificate State

```bash
kubectl get certificate -n sandbox
kubectl describe certificate -n sandbox
kubectl get secret -n sandbox
```

If `cmctl` is installed:

```bash
cmctl status certificate -n sandbox <certificate-name>
```

## Step 2 - Capture Current Key Fingerprint

Replace placeholders:

```bash
CERT_NAME=<certificate-name>
SECRET_NAME=<tls-secret-name>

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
kubectl rollout restart deploy -n sandbox <deployment-name>
kubectl rollout status deploy -n sandbox <deployment-name>
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

## Exit Criteria

You are ready for Lab 06 when:

- You can force renewal safely
- You can prove whether private key rotated
- You have a clear app reload strategy
