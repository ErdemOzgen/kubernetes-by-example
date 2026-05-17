# Lab 01 - Install and Validate cert-manager

## Objective

Install cert-manager with Helm (OCI chart), enable CRDs, and validate the control-plane components.

## Why This Stage Matters

Every downstream lab depends on a healthy webhook and CRD registration. If this stage is unstable, all issuer and certificate flows will fail intermittently.

## Prerequisites

Complete Lab 00 and verify:

```bash
kubectl config current-context
kubectl get nodes
```

## Step 1 - Add Namespace and Install

```bash
helm install \
  cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.20.2 \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

If the release already exists:

```bash
helm upgrade \
  cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.20.2 \
  --namespace cert-manager \
  --set crds.enabled=true
```

## Step 2 - Wait for Readiness

```bash
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=180s
```

## Step 3 - Verify API Surface

```bash
kubectl get crds | grep cert-manager
kubectl api-resources | grep cert-manager
kubectl get validatingwebhookconfiguration | grep cert-manager
kubectl get mutatingwebhookconfiguration | grep cert-manager
```

Expected:

- CRDs for `certificates`, `certificaterequests`, `issuers`, `clusterissuers`, `orders`, `challenges`
- Webhook configurations present


## Step 4 - Verify Runtime Components

```bash
kubectl get pods -n cert-manager -o wide
kubectl get deploy -n cert-manager
kubectl describe deploy cert-manager -n cert-manager
kubectl describe deploy cert-manager-webhook -n cert-manager
kubectl describe deploy cert-manager-cainjector -n cert-manager
```

### Runtime Deep Dive - What Your Running Pods Actually Do

From your output, all three core pods are healthy:

- `cert-manager-...` -> main controller
- `cert-manager-webhook-...` -> admission + API conversion webhook
- `cert-manager-cainjector-...` -> CA bundle injector for webhook trust wiring

Your status line interpretation:

- `READY 1/1`: container is running and passing readiness checks.
- `STATUS Running`: Kubernetes has started the container and it is not crashing.
- `RESTARTS 0`: no crash loop or OOM restart so far.
- `AGE ~2m`: fresh deployment, still in early steady state.
- `NODE k3d-dev-agent-0`: all control-plane pods are currently scheduled on your single worker node.

#### 1) `cert-manager` (controller)

This is the brain of cert-manager. It runs reconciliation loops for cert-manager CRDs and drives certificate lifecycle end-to-end.

Primary responsibilities:

- Watches `Certificate`, `CertificateRequest`, `Issuer`, `ClusterIssuer`, `Order`, and `Challenge` resources.
- Creates key pairs and CSRs when certificates are requested.
- Communicates with issuer backends (SelfSigned, CA, ACME, and external issuers).
- Writes/updates target TLS Secrets (`tls.crt`, `tls.key`, optional `ca.crt`).
- Handles renewals and re-issuance when cert spec changes or expiry window is reached.
- Performs garbage collection and status condition updates so `kubectl describe` reflects progress.

Operationally important note:

- If this pod is down, existing certificates continue to be used by workloads, but no new issuance or renewal workflow progresses.

#### 2) `cert-manager-webhook`

This is the policy and schema gate for cert-manager resources at Kubernetes API admission time.

Primary responsibilities:

- Validates incoming cert-manager objects (required fields, allowed combinations, structural checks).
- Converts API versions when needed.
- Rejects invalid manifests before they enter etcd, reducing broken states.

Operationally important note:

- If webhook is unavailable, creating or updating cert-manager CRDs can fail with internal webhook/admission errors.
- This is why webhook readiness is a hard prerequisite before running labs that apply `Issuer`/`Certificate` manifests.

#### 3) `cert-manager-cainjector`

This component wires trust between Kubernetes API server and webhook endpoints by injecting CA bundles.

Primary responsibilities:

- Injects `caBundle` data into `ValidatingWebhookConfiguration`, `MutatingWebhookConfiguration`, CRDs, and APIService objects that require trust configuration.
- Keeps bundles synchronized after certificate rotation.
- Ensures API server TLS validation succeeds when calling admission webhooks.

Operationally important note:

- If cainjector is broken, webhook TLS trust can drift and admission calls may fail even if the webhook pod itself is running.

#### How They Work Together (Control Flow)

1. You apply a `Certificate` (or an annotated `Ingress` that generates one).
2. Webhook validates object correctness at admission time.
3. Controller reconciles the request, talks to issuer, and writes the TLS Secret.
4. Cainjector keeps webhook trust materials (`caBundle`) correct so admission keeps working over time.

In short: webhook protects correctness, controller performs issuance, cainjector protects trust wiring.

#### Fast Health Checks You Should Keep Using

```bash
kubectl get pods -n cert-manager -o wide
kubectl logs -n cert-manager deploy/cert-manager --tail=200
kubectl logs -n cert-manager deploy/cert-manager-webhook --tail=200
kubectl logs -n cert-manager deploy/cert-manager-cainjector --tail=200
kubectl get validatingwebhookconfiguration,mutatingwebhookconfiguration | grep cert-manager
```

Healthy signal set:

- All three deployments have available replicas.
- No continuous error loops in logs.
- Webhook configurations exist and are not flapping.

## Step 5 - Quick Smoke Test: API Admission

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: smoke-selfsigned
  namespace: sandbox
spec:
  selfSigned: {}
EOF

kubectl get issuer -n sandbox smoke-selfsigned
```

Delete smoke resource:

```bash
kubectl delete issuer -n sandbox smoke-selfsigned
```

## Deep Verification

Inspect logs for webhook/admission issues:

```bash
kubectl logs -n cert-manager deploy/cert-manager-webhook --tail=200
kubectl logs -n cert-manager deploy/cert-manager --tail=200
```

## Common Failure Patterns and Fixes

1. Error: no matches for kind Issuer
- Cause: CRDs missing.
- Fix: reinstall/upgrade with `--set crds.enabled=true`.

2. Internal error calling webhook
- Cause: webhook not ready or CA bundle injection lag.
- Fix: wait rollouts and retry apply.

3. Image pull or timeout
- Cause: network / registry connectivity.
- Fix: check node internet path and Pod events.

## Exit Criteria

You are ready for Lab 02 when:

- All cert-manager pods are Running/Ready
- CRDs are registered
- Creating a trivial Issuer works
