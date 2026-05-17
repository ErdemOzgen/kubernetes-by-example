# Collected YAML Manifests from Lab Markdown Files

This directory contains YAML content extracted from markdown labs under `Cert-manager/labs`.

## Source Mapping

- `01-smoke-selfsigned-issuer.yaml` <- `01-install-cert-manager.md`
- `02-selfsigned-clusterissuer.yaml` <- `02-selfsigned-bootstrap.md`
- `02-app-selfsigned-certificate.yaml` <- `02-selfsigned-bootstrap.md`
- `03-root-ca-bootstrap.yaml` <- `03-private-ca-and-ingress-tls.md`
- `03-local-ca-clusterissuer.yaml` <- `03-private-ca-and-ingress-tls.md`
- `03-hello-workload.yaml` <- `03-private-ca-and-ingress-tls.md`
- `03-app-localhost-certificate.yaml` <- `03-private-ca-and-ingress-tls.md`
- `03-hello-ingress-tls.yaml` <- `03-private-ca-and-ingress-tls.md`
- `04-recreate-ca-issuers.yaml` <- `04-ingress-annotation-automation.md`
- `04-hello-auto-workload.yaml` <- `04-ingress-annotation-automation.md`
- `04-hello-auto-annotated-ingress.yaml` <- `04-ingress-annotation-automation.md`
- `05-failure-injection-renew-window-snippet.yaml` <- `05-renewal-and-key-rotation.md` (partial snippet)
- `06-broken-issuerref-certificate.yaml` <- `06-troubleshooting-playbook.md`
- `07-pebble-stack.yaml` <- `07-acme-pebble-local.md`
- `07-pebble-acme-clusterissuer.yaml` <- `07-acme-pebble-local.md`
- `07-hello-pebble-app.yaml` <- `07-acme-pebble-local.md`
- `08-letsencrypt-dns01-clusterissuers.yaml` <- `08-letsencrypt-dns01.md`
- `08-staging-real-domain-certificate.yaml` <- `08-letsencrypt-dns01.md`
- `08-wildcard-example-certificate.yaml` <- `08-letsencrypt-dns01.md`
- `09-local-root-bundle.yaml` <- `09-policy-and-trust-distribution.md`
- `10-csi-cert-demo-pod.yaml` <- `10-csi-driver-and-workload-identity.md`

## Notes

- Existing manifest files already present in `Cert-manager/labs/manifests` were not modified.
- Some markdown examples are operational commands rather than full YAML resources.
- `05-failure-injection-renew-window-snippet.yaml` is intentionally partial and must be merged into a full Certificate spec for real use.
