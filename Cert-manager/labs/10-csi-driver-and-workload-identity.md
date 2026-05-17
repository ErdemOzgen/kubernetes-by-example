# Lab 10 - cert-manager CSI Driver and Workload Certificate Identity

## Objective

Issue pod-mounted certificates through cert-manager CSI driver without storing key material in Kubernetes Secrets.

## Why This Stage Matters

For high-security workloads, minimizing private key persistence in cluster API objects reduces leakage risk.

## Step 1 - Install CSI Driver

```bash
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update
helm install cert-manager-csi-driver jetstack/cert-manager-csi-driver \
  --namespace cert-manager \
  --create-namespace
```

Verify:

```bash
kubectl get pods -n cert-manager | grep csi
```

## Step 2 - Ensure Issuer Exists

Use an existing issuer from previous labs (for example `local-ca-issuer`), or create a dedicated one.

## Step 3 - Deploy Pod with CSI Volume

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: csi-cert-demo
  namespace: sandbox
spec:
  serviceAccountName: default
  containers:
    - name: app
      image: nginx:1.27-alpine
      volumeMounts:
        - name: tls
          mountPath: /tls
          readOnly: true
  volumes:
    - name: tls
      csi:
        driver: csi.cert-manager.io
        readOnly: true
        volumeAttributes:
          csi.cert-manager.io/issuer-kind: ClusterIssuer
          csi.cert-manager.io/issuer-name: local-ca-issuer
          csi.cert-manager.io/dns-names: csi-demo.localhost
          csi.cert-manager.io/common-name: csi-demo.localhost
EOF
```

## Step 4 - Validate Mounted Files

```bash
kubectl exec -n sandbox csi-cert-demo -- ls -l /tls
kubectl exec -n sandbox csi-cert-demo -- sh -c "openssl x509 -in /tls/tls.crt -noout -subject -issuer -dates"
```

Expected files:

- `/tls/tls.crt`
- `/tls/tls.key`
- `/tls/ca.crt` (depending on issuer chain)

## Step 5 - Rotation Behavior Check

Delete and recreate pod; verify new leaf certificate identity or serial behavior as expected.

```bash
kubectl delete pod -n sandbox csi-cert-demo
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: csi-cert-demo
  namespace: sandbox
spec:
  serviceAccountName: default
  containers:
    - name: app
      image: nginx:1.27-alpine
      volumeMounts:
        - name: tls
          mountPath: /tls
          readOnly: true
  volumes:
    - name: tls
      csi:
        driver: csi.cert-manager.io
        readOnly: true
        volumeAttributes:
          csi.cert-manager.io/issuer-kind: ClusterIssuer
          csi.cert-manager.io/issuer-name: local-ca-issuer
          csi.cert-manager.io/dns-names: csi-demo.localhost
          csi.cert-manager.io/common-name: csi-demo.localhost
EOF
```

## Design Considerations

- CSI is strong for ephemeral identity and mTLS workloads
- Secret-based certificates are usually better for Ingress termination workflows
- Combine with policy controls for tenant safety

## Cleanup

```bash
kubectl delete pod -n sandbox csi-cert-demo --ignore-not-found
# Optional
# helm uninstall cert-manager-csi-driver -n cert-manager
```

## Exit Criteria

You are ready for Lab 11 when:

- You can mount certs into pods via CSI
- You understand when CSI is preferable over Secret-based flows
