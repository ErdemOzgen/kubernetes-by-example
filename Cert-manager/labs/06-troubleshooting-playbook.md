# Lab 06 - Troubleshooting Playbook (Break and Fix)

## Objective

Build fast diagnosis habits by intentionally creating common cert-manager failures and fixing them.

## Why This Stage Matters

Production incidents are rarely solved from logs first. Start with object conditions and events, then drill into controller logs.

## Golden Workflow

1. `kubectl describe` target object
2. Check related child objects (`CertificateRequest`, `Order`, `Challenge`)
3. Check events
4. Check controller logs

## Baseline Commands

```bash
kubectl describe certificate -n sandbox <cert>
kubectl describe certificaterequest -n sandbox <cr>
kubectl describe issuer -n sandbox <issuer>
kubectl describe clusterissuer <clusterissuer>
kubectl get events -n sandbox --sort-by=.lastTimestamp
kubectl logs -n cert-manager deploy/cert-manager --tail=200
```

ACME-specific:

```bash
kubectl get orders,challenges -A
kubectl describe order -n sandbox <order>
kubectl describe challenge -n sandbox <challenge>
```

## Failure Scenario A - Wrong issuerRef

Create cert with non-existing issuer:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: broken-issuerref
  namespace: sandbox
spec:
  secretName: broken-issuerref-tls
  dnsNames:
    - broken.localhost
  issuerRef:
    name: does-not-exist
    kind: ClusterIssuer
EOF
```

Expected symptom:

- Certificate not ready
- Event says issuer not found

Fix:

- Correct `issuerRef.name`
- Re-apply

## Failure Scenario B - Ingress host and SAN mismatch

1. Create cert SAN for `app.localhost`
2. Use it on Ingress host `mismatch.localhost`

Expected symptom:

- TLS handshake succeeds but hostname verification fails for strict clients

Fix:

- Align Ingress host and cert SAN exactly

## Failure Scenario C - Wrong IngressClass

Set `ingressClassName` to non-existing class.

Expected symptom:

- No route via Traefik
- ACME HTTP-01 (if used) fails to validate

Fix:

```bash
kubectl get ingressclass
kubectl edit ingress -n sandbox <name>
```

## Failure Scenario D - Secret deleted unexpectedly

Delete TLS Secret used by active Ingress.

Expected symptom:

- Temporary TLS degradation until cert-manager reconciles

Fix path:

- Confirm owning `Certificate` still exists
- Watch secret recreation

```bash
kubectl get secret -n sandbox -w
```

## Failure Scenario E - Webhook Unavailable

Simulate by scaling webhook deployment down:

```bash
kubectl scale deploy cert-manager-webhook -n cert-manager --replicas=0
```

Try creating a cert-manager resource (should fail admission).

Recover:

```bash
kubectl scale deploy cert-manager-webhook -n cert-manager --replicas=1
kubectl rollout status deploy/cert-manager-webhook -n cert-manager
```

## Structured Debug Checklist

Use this sequence during incidents:

1. Scope: which namespace, which certificate, which host?
2. State: Ready condition? Last failure reason?
3. Graph: issuer -> cert -> certrequest -> order/challenge -> secret
4. Runtime: cert-manager/webhook/cainjector logs
5. Networking: Ingress path and class
6. Trust: CA chain and client trust store

## Cleanup

```bash
kubectl delete certificate -n sandbox broken-issuerref --ignore-not-found
kubectl delete secret -n sandbox broken-issuerref-tls --ignore-not-found
```

## Exit Criteria

You are ready for Lab 07 when:

- You can identify root cause from `describe` + events alone in common cases
- You can recover from webhook downtime and bad issuer references
