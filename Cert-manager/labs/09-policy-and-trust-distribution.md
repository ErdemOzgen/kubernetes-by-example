# Lab 09 - Policy Controls and Trust Distribution

## Objective

Add governance (approval policy) and trust bundle distribution (trust-manager) to your cert-manager platform.

## Why This Stage Matters

Without policy and trust distribution:

- Any namespace with permissions may request risky certs
- Private CA trust becomes ad-hoc and inconsistent across workloads

## Part A - approver-policy

### Step A1 - Install approver-policy

Install via Helm (verify latest chart before applying in production):

```bash
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update
helm install cert-manager-approver-policy jetstack/cert-manager-approver-policy \
  -n cert-manager \
  --create-namespace
```

### Step A2 - Create Restrictive CertificateRequestPolicy

Example policy idea:

- Allow only `*.sandbox.example.com`
- Allow only `letsencrypt-staging-dns01`
- Restrict durations/usages

Create policy and RBAC binding according to your tenancy model.

### Step A3 - Run Allow/Deny Tests

1. Request an allowed cert and verify it gets approved.
2. Request a denied cert (wrong DNS suffix or issuer) and verify it remains denied/pending.

Observe:

```bash
kubectl get certificaterequest -n sandbox
kubectl describe certificaterequest -n sandbox
```

## Part B - trust-manager

### Step B1 - Install trust-manager

```bash
helm install trust-manager oci://quay.io/jetstack/charts/trust-manager \
  --namespace cert-manager \
  --create-namespace
```

### Step B2 - Create Bundle from Your Root CA Secret

Assuming root CA secret from earlier labs (`cert-manager/root-ca-secret`):

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: trust.cert-manager.io/v1alpha1
kind: Bundle
metadata:
  name: local-root-bundle
spec:
  sources:
    - secret:
        name: root-ca-secret
        key: tls.crt
        namespace: cert-manager
  target:
    configMap:
      key: ca-bundle.crt
    namespaceSelector:
      matchLabels:
        purpose: cert-manager-labs
EOF
```

### Step B3 - Verify Bundle Propagation

```bash
kubectl get bundle
kubectl describe bundle local-root-bundle
kubectl get configmap -n sandbox | grep local-root-bundle
kubectl get configmap -n sandbox local-root-bundle -o yaml
```

### Step B4 - Consume Bundle from Workload

Mount generated ConfigMap into a test pod and use it as trust store for TLS clients.

## Operational Notes

- Treat policy and trust-manager as platform-level components
- Version and test policies in Git before promoting
- Keep separation between issuer ownership and app team ownership

## Cleanup (optional)

```bash
kubectl delete bundle local-root-bundle --ignore-not-found
# Optional: uninstall charts
# helm uninstall trust-manager -n cert-manager
# helm uninstall cert-manager-approver-policy -n cert-manager
```

## Exit Criteria

You are ready for Lab 10 when:

- You can enforce issuance policy constraints
- You can distribute trust bundles automatically to selected namespaces
