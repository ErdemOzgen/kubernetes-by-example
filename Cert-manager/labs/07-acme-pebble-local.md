# Lab 07 - Local ACME with Pebble on k3d

## Objective

Run a local ACME server (Pebble) and exercise ACME flows without consuming public Let's Encrypt rate limits.

## Why This Stage Matters

You can test ACME object behavior (`Order`, `Challenge`) in a controlled environment before touching real DNS/provider credentials.

## Important Note

HTTP-01 validation in public Let's Encrypt requires port 80 reachability from the internet. This lab avoids that by using a local ACME endpoint.

## Step 1 - Deploy Pebble in Cluster

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: pebble
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pebble
  namespace: pebble
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pebble
  template:
    metadata:
      labels:
        app: pebble
    spec:
      containers:
        - name: pebble
          image: ghcr.io/letsencrypt/pebble:latest
          env:
            - name: PEBBLE_VA_NOSLEEP
              value: "1"
            - name: PEBBLE_WFE_NONCEREJECT
              value: "0"
          ports:
            - containerPort: 14000
            - containerPort: 15000
---
apiVersion: v1
kind: Service
metadata:
  name: pebble
  namespace: pebble
spec:
  selector:
    app: pebble
  ports:
    - name: acme
      port: 14000
      targetPort: 14000
    - name: mgmt
      port: 15000
      targetPort: 15000
EOF
```

Verify:

```bash
kubectl get pods,svc -n pebble
```

## Step 2 - Create ACME ClusterIssuer Pointing to Pebble

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: pebble-acme
spec:
  acme:
    email: devnull@localhost
    server: https://pebble.pebble.svc.cluster.local:14000/dir
    skipTLSVerify: true
    privateKeySecretRef:
      name: pebble-acme-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik
EOF
```

For local Pebble labs, `skipTLSVerify: true` is the fastest way to avoid test-CA trust and hostname mismatch issues. Use this only in local/dev labs, not in production.

Because Pebble uses a test CA, configure cert-manager controller trust for Pebble CA only if needed in your setup. If issuer stays NotReady with TLS errors, inspect controller logs and switch to an alternative local ACME setup that includes trusted CA wiring.

## Step 3 - Create App + Annotated Ingress for ACME

```bash
echo "127.0.0.1 pebble.localhost" | sudo tee -a /etc/hosts

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-pebble
  namespace: sandbox
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello-pebble
  template:
    metadata:
      labels:
        app: hello-pebble
    spec:
      containers:
        - name: hello
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: hello-pebble
  namespace: sandbox
spec:
  selector:
    app: hello-pebble
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-pebble
  namespace: sandbox
  annotations:
    cert-manager.io/cluster-issuer: pebble-acme
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - pebble.localhost
      secretName: pebble-localhost-tls
  rules:
    - host: pebble.localhost
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: hello-pebble
                port:
                  number: 80
EOF
```

## Step 4 - Observe ACME Objects

```bash
kubectl get certificate,certificaterequest,order,challenge -n sandbox
kubectl describe order -n sandbox
kubectl describe challenge -n sandbox
```

## Step 5 - Validate Result

```bash
kubectl get secret -n sandbox pebble-localhost-tls
curl -vk https://pebble.localhost:8443/
```

## Troubleshooting

```bash
kubectl logs -n cert-manager deploy/cert-manager --tail=300
kubectl logs -n pebble deploy/pebble --tail=200
kubectl describe clusterissuer pebble-acme
```

## Cleanup

```bash
kubectl delete ingress,svc,deploy -n sandbox hello-pebble
kubectl delete clusterissuer pebble-acme
kubectl delete secret -n sandbox pebble-localhost-tls --ignore-not-found
kubectl delete ns pebble
```

## Exit Criteria

You are ready for Lab 08 when:

- You can read ACME lifecycle from `Order` and `Challenge`
- You can diagnose solver routing and issuer readiness problems

## End-of-Lab Cleanup (Consolidated)

Use this section if you want one final cleanup block at the end of the lab.

Standard cleanup (keeps cert-manager installed):

```bash
kubectl delete ingress,svc,deploy -n sandbox hello-pebble --ignore-not-found
kubectl delete certificate,certificaterequest,order,challenge -n sandbox --all --ignore-not-found
kubectl delete secret -n sandbox pebble-localhost-tls --ignore-not-found
kubectl delete clusterissuer pebble-acme --ignore-not-found
kubectl delete ns pebble --ignore-not-found
```

Optional full reset (only if this cluster is dedicated to this lab):

```bash
kubectl delete ns sandbox --ignore-not-found
# Optional: remove cert-manager as well
# helm uninstall cert-manager -n cert-manager
# kubectl delete ns cert-manager --ignore-not-found
```

Optional host cleanup:

```bash
# Remove local hostname if no longer needed
# sudo sed -i '/pebble.localhost/d' /etc/hosts
```
