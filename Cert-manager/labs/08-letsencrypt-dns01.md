# Lab 08 - Real Let's Encrypt with DNS-01 (Staging to Production)

## Objective

Issue publicly trusted certificates using DNS-01 in a safe promotion model: staging first, production later.

## Why This Stage Matters

For local k3d on a laptop, HTTP-01 is usually impractical for public issuance. DNS-01 is the production-ready path for wildcard and non-public ingress topologies.

## Security First

- Use least-privilege DNS API tokens
- Store tokens in Kubernetes Secrets
- Separate staging and production issuers
- Never test new DNS automation against production endpoint first

## Step 1 - Create DNS Credential Secret

Example for Cloudflare token (replace with your provider equivalent):

```bash
kubectl -n cert-manager create secret generic cloudflare-api-token \
  --from-literal=api-token='<REPLACE_WITH_TOKEN>'
```

## Step 2 - Create Staging and Production ClusterIssuers

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging-dns01
spec:
  acme:
    email: you@example.com
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: le-staging-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod-dns01
spec:
  acme:
    email: you@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: le-prod-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
EOF
```

Verify readiness:

```bash
kubectl get clusterissuer letsencrypt-staging-dns01 letsencrypt-prod-dns01
kubectl describe clusterissuer letsencrypt-staging-dns01
```

## Step 3 - Issue Staging Certificate

Replace domain with one you control:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: staging-real-domain
  namespace: sandbox
spec:
  secretName: staging-real-domain-tls
  dnsNames:
    - app.example.com
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-staging-dns01
EOF
```

Observe DNS challenge flow:

```bash
kubectl get certificaterequest,order,challenge -n sandbox
kubectl describe challenge -n sandbox
```

## Step 4 - Validate Staging Result

```bash
kubectl get secret -n sandbox staging-real-domain-tls
kubectl get secret -n sandbox staging-real-domain-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/staging.crt
openssl x509 -in /tmp/staging.crt -noout -issuer -subject -dates
```

## Step 5 - Promote to Production Issuer

Update only `issuerRef.name`:

```bash
kubectl patch certificate -n sandbox staging-real-domain \
  --type merge \
  -p '{"spec":{"issuerRef":{"name":"letsencrypt-prod-dns01"}}}'
```

Observe new request:

```bash
kubectl get certificaterequest,order,challenge -n sandbox --sort-by=.metadata.creationTimestamp
```

## Step 6 - Wildcard Certificate (DNS-01 Advantage)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-example
  namespace: sandbox
spec:
  secretName: wildcard-example-tls
  dnsNames:
    - '*.example.com'
    - example.com
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-prod-dns01
EOF
```

## Troubleshooting

```bash
kubectl describe challenge -n sandbox
kubectl logs -n cert-manager deploy/cert-manager --tail=300
```

Common causes:

- DNS token missing permission
- Wrong hosted zone mapping
- Slow DNS propagation
- CAA restrictions

## Cleanup

```bash
kubectl delete certificate -n sandbox staging-real-domain wildcard-example --ignore-not-found
kubectl delete secret -n sandbox staging-real-domain-tls wildcard-example-tls --ignore-not-found
```

## Exit Criteria

You are ready for Lab 09 when:

- Staging issuance succeeds end-to-end
- Production promotion works with minimal spec change
- You can explain DNS-01 challenge propagation dependencies
