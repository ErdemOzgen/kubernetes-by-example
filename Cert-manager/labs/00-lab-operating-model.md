# Lab 00 - Operating Model for cert-manager on Your k3d Cluster

This lab defines the shared conventions used by all following labs.

## Objective

Create a repeatable, low-friction workflow so every next lab can run on your exact k3d topology.

## Your k3d Topology (from bin scripts)

From your scripts in `bin/`:

- Cluster name: `dev`
- API server: `localhost:6550`
- HTTP via load balancer: `localhost:8080 -> :80`
- HTTPS via load balancer: `localhost:8443 -> :443`
- Registry from host: `localhost:5111`
- Registry from inside cluster: `dev-registry:5000`

## Why This Matters

Most cert-manager lab failures are not cert-manager issues. They are usually:

- Context mismatch (wrong kube-context)
- Hostname mismatch (certificate SAN does not match request host)
- Wrong traffic path (Ingress class or LB mapping)
- Trust mismatch (root CA not trusted on the client)

## Prerequisites

Install locally:

- Docker
- k3d
- kubectl
- helm
- openssl
- jq
- cmctl (recommended)

Optional but useful:

- yq
- k9s

## Bootstrap Cluster

```bash
cd /home/erdem/k8s/kubernetes-by-example
./bin/k3dup.sh
kubectl config use-context k3d-dev
kubectl cluster-info
```

## Baseline Validation

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get ingressclass
kubectl get svc -A
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

Expected baseline:

- One server node + one agent node
- Traefik running in `kube-system`
- IngressClass available (usually `traefik`)
- k3d load balancer exposing host `8080` and `8443`

## Shared Namespace and Labels

Use one namespace for iterative labs:

```bash
kubectl create ns sandbox --dry-run=client -o yaml | kubectl apply -f -
kubectl label ns sandbox purpose=cert-manager-labs --overwrite
```

## Local Hostname Strategy

You can safely use `*.localhost` names for local TLS experiments.

Add hosts entries for deterministic name resolution:

```bash
echo "127.0.0.1 app.localhost" | sudo tee -a /etc/hosts
echo "127.0.0.1 api.localhost" | sudo tee -a /etc/hosts
echo "127.0.0.1 wildcard.localhost" | sudo tee -a /etc/hosts
```

## Shared Debug Commands

Use these in every lab:

```bash
kubectl get events -A --sort-by=.lastTimestamp | tail -n 50
kubectl get certificate,certificaterequest,order,challenge -A
kubectl logs -n cert-manager deploy/cert-manager --tail=200
kubectl logs -n cert-manager deploy/cert-manager-webhook --tail=200
kubectl logs -n cert-manager deploy/cert-manager-cainjector --tail=200
```

## Cleanup Strategy

Soft cleanup (keep cluster):

```bash
kubectl delete ns sandbox --ignore-not-found
```

Hard cleanup (reset everything):

```bash
cd /home/erdem/k8s/kubernetes-by-example
./bin/k3ddown.sh
```

## Exit Criteria

You are ready for Lab 01 when:

- You can access the `k3d-dev` context
- Traefik is healthy
- `sandbox` namespace exists
- `app.localhost` resolves to `127.0.0.1`
