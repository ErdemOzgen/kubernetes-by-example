# cert-manager Hands-on Labs for Your k3d Setup

This directory contains a practical, staged cert-manager learning path tailored to your k3d scripts in `bin/`.

## Environment Assumptions

- Cluster: `dev`
- API: `localhost:6550`
- HTTP ingress: `localhost:8080`
- HTTPS ingress: `localhost:8443`
- Host registry: `localhost:5111`
- In-cluster registry: `dev-registry:5000`

## Recommended Execution Order

1. `00-lab-operating-model.md`
2. `01-install-cert-manager.md`
3. `02-selfsigned-bootstrap.md`
4. `03-private-ca-and-ingress-tls.md`
5. `04-ingress-annotation-automation.md`
6. `05-renewal-and-key-rotation.md`
7. `06-troubleshooting-playbook.md`
8. `07-acme-pebble-local.md`
9. `08-letsencrypt-dns01.md`
10. `09-policy-and-trust-distribution.md`
11. `10-csi-driver-and-workload-identity.md`
12. `11-gitops-production-blueprint.md`

## Fast Start

```bash
cd /home/erdem/k8s/kubernetes-by-example
./bin/k3dup.sh
kubectl config use-context k3d-dev
kubectl create ns sandbox --dry-run=client -o yaml | kubectl apply -f -
```

Then start with Lab 00.
