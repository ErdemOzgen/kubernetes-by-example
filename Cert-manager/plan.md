# cert-manager with k3d - Structured Hands-on Lab Program

This file is now the master index. The practical roadmap has been split into executable lab subsections under `Cert-manager/labs/`, aligned with your k3d scripts in `bin/`.

## Environment profile used by all labs

- Cluster: `dev`
- API: `localhost:6550`
- HTTP ingress: `localhost:8080`
- HTTPS ingress: `localhost:8443`
- Host registry: `localhost:5111`
- In-cluster registry: `dev-registry:5000`

## Run order (hands-on subsections)

1. `Cert-manager/labs/00-lab-operating-model.md`
2. `Cert-manager/labs/01-install-cert-manager.md`
3. `Cert-manager/labs/02-selfsigned-bootstrap.md`
4. `Cert-manager/labs/03-private-ca-and-ingress-tls.md`
5. `Cert-manager/labs/04-ingress-annotation-automation.md`
6. `Cert-manager/labs/05-renewal-and-key-rotation.md`
7. `Cert-manager/labs/06-troubleshooting-playbook.md`
8. `Cert-manager/labs/07-acme-pebble-local.md`
9. `Cert-manager/labs/08-letsencrypt-dns01.md`
10. `Cert-manager/labs/09-policy-and-trust-distribution.md`
11. `Cert-manager/labs/10-csi-driver-and-workload-identity.md`
12. `Cert-manager/labs/11-gitops-production-blueprint.md`

## Note

The original long-form roadmap is kept below as reference material.

---

Below is a **hands-on cert-manager learning roadmap for k3d**, written in English and aligned with your script.

Your script is a good base because it exposes k3d’s internal Ingress ports `80` and `443` to your host as `8080` and `8443`, and k3d documents this exact `HOST:CONTAINER@loadbalancer` pattern for exposing Ingress traffic through the k3d load balancer. k3s also ships Traefik as the default Ingress controller, which is useful for the first labs. ([K3D][1])

---

# cert-manager with k3d: Hands-on Learning Roadmap


## 1.2 TLS and PKI fundamentals

Learn:

* TLS handshake
* X.509 certificate
* Common Name vs SAN
* DNS SAN
* IP SAN
* URI SAN
* Root CA
* Intermediate CA
* Server certificate
* Client certificate
* Certificate chain
* Trust store
* Public vs private trust
* PEM vs DER
* PKCS#1, PKCS#8, PKCS#12
* RSA, ECDSA, Ed25519
* Key usage and extended key usage
* `tls.crt`, `tls.key`, `ca.crt`

Kubernetes Ingress TLS expects a TLS Secret containing `tls.crt` and `tls.key`, and the Ingress TLS host must match the certificate identity. ([Kubernetes][3])

Useful commands:

```bash
openssl x509 -in tls.crt -text -noout
openssl x509 -in tls.crt -noout -issuer -subject -dates
openssl verify -CAfile ca.crt tls.crt
kubectl get secret my-tls -o yaml
```

---

# 2. k3d environment track

## 2.1 Understand your script

Your current script creates:

* k3d cluster: `dev`
* one agent node
* API server exposed on host port `6550`
* HTTP Ingress exposed as `localhost:8080`
* HTTPS Ingress exposed as `localhost:8443`
* local registry exposed as `localhost:5111`
* in-cluster registry name usable as `dev-registry:5000`

k3d’s registry docs explain that local registry references differ between your host and cluster: from your host you push to the mapped localhost port, while workloads inside k3d refer to the registry by the registry container name and port. ([K3D][4])

## 2.2 Add useful verification commands

After running your script:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get ingressclass
kubectl get svc -A
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

Expected topics to understand:

* k3d load balancer container
* k3s Traefik
* containerd image pull behavior
* local registry vs in-cluster registry naming
* host networking vs cluster networking

---

# 3. cert-manager installation track

## 3.1 Learn installation methods

Study:

* Static manifest install
* Helm install
* OCI Helm chart
* CRD lifecycle
* Helm upgrade behavior
* Why cert-manager should not be embedded as a sub-chart

The official docs recommend Helm as a first-class installation method and currently show `v1.20.2` as the latest chart version in the docs I found. They also warn not to install cert-manager as a sub-chart because it manages non-namespaced resources and should be installed exactly once. ([cert-manager][5])

Recommended local install:

```bash
helm install \
  cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.20.2 \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

Verify:

```bash
kubectl get pods -n cert-manager
kubectl get crds | grep cert-manager
kubectl api-resources | grep cert-manager
kubectl get validatingwebhookconfiguration | grep cert-manager
kubectl get mutatingwebhookconfiguration | grep cert-manager
```

## 3.2 Learn cert-manager components

Learn what these do:

* `cert-manager-controller`
* `cert-manager-webhook`
* `cert-manager-cainjector`
* `startupapicheck`
* `acmesolver`

Important concept: `cainjector` populates `caBundle` fields for resources such as webhook configurations, CRDs, and API services, allowing the Kubernetes API server to verify webhook serving certificates. ([cert-manager][6])

Hands-on:

```bash
kubectl get deploy -n cert-manager
kubectl describe deploy cert-manager -n cert-manager
kubectl describe deploy cert-manager-webhook -n cert-manager
kubectl describe deploy cert-manager-cainjector -n cert-manager
kubectl logs -n cert-manager deploy/cert-manager
```

---

# 4. Core cert-manager CRD track

## 4.1 Learn these resources first

Essential resources:

* `Issuer`
* `ClusterIssuer`
* `Certificate`
* `CertificateRequest`
* `Secret`

ACME-specific resources:

* `Order`
* `Challenge`

Policy and trust resources:

* `CertificateRequestPolicy`
* `Bundle`

Issuer resources represent certificate authorities that can sign certificate requests. Every cert-manager `Certificate` needs a referenced `Issuer` or `ClusterIssuer` that is ready. ([cert-manager][7])

## 4.2 Learn `Certificate`

A `Certificate` is the human-friendly certificate request. cert-manager creates a private key and `CertificateRequest`, obtains a signed certificate from an issuer, and stores the certificate and key in the configured Secret. It also renews before expiry. ([cert-manager][8])

Study fields:

* `spec.secretName`
* `spec.dnsNames`
* `spec.ipAddresses`
* `spec.uris`
* `spec.commonName`
* `spec.issuerRef`
* `spec.duration`
* `spec.renewBefore`
* `spec.privateKey`
* `spec.usages`
* `spec.isCA`
* `spec.secretTemplate`

Hands-on:

```bash
kubectl get certificates -A
kubectl describe certificate -n sandbox
kubectl get certificaterequests -A
kubectl describe certificaterequest -n sandbox
kubectl get secret -n sandbox
```

## 4.3 Learn `CertificateRequest`

`CertificateRequest` is the lower-level request object containing the CSR. It is usually created by controllers, not manually by humans, and its status reflects whether the request was issued, pending, failed, approved, or denied. ([cert-manager][9])

Hands-on:

```bash
kubectl get certificaterequests -A
kubectl describe certificaterequest -n sandbox
kubectl get certificaterequest -n sandbox -o yaml
```

---

# 5. SelfSigned Issuer track

## 5.1 Learn what SelfSigned is and is not

A `SelfSigned` issuer does not represent a real CA; it signs a certificate using its own private key. It is useful for quick tests and for bootstrapping a private root CA, but for normal private PKI you should move to a `CA` issuer. ([cert-manager][10])

Hands-on lab:

1. Create namespace.
2. Create `SelfSigned` `ClusterIssuer`.
3. Create a test `Certificate`.
4. Inspect the generated Secret.
5. Decode and inspect the certificate.

Topics to master:

* Why browsers do not trust self-signed certs
* Why self-signed is useful for bootstrap
* Difference between encryption and trust
* How SANs appear in the certificate
* Why `ca.crt` matters

---

# 6. Private CA Issuer track

## 6.1 Bootstrap your own CA

Learn:

* Root CA certificate
* CA private key
* Intermediate CA
* `isCA: true`
* `CA` issuer
* Secret placement rules
* Namespace-scoped `Issuer` vs cluster-scoped `ClusterIssuer`

The cert-manager docs show the pattern: use `SelfSigned` to bootstrap a root certificate, store it in a Secret, and then use that root as a `CA` issuer. ([cert-manager][10])

Hands-on labs:

1. Create root CA with SelfSigned.
2. Create `CA` `Issuer`.
3. Issue an app server certificate.
4. Use it in an Ingress.
5. Import the root CA into your local trust store.
6. Test HTTPS with `curl`.

Example verification:

```bash
kubectl get certificate -A
kubectl get secret -n sandbox app-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > tls.crt
kubectl get secret -n sandbox app-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
openssl x509 -in tls.crt -text -noout
curl --cacert ca.crt https://app.localhost:8443
```

Important: CA issuers are powerful but require production planning around rotation, trust distribution, and disaster recovery. The official docs explicitly warn that CA issuers are generally for demos or advanced users with PKI tooling and experience. ([cert-manager][11])

---

# 7. Ingress TLS track with Traefik on k3d

## 7.1 Learn manual Ingress TLS first

Before using automation, create:

* Deployment
* Service
* TLS Secret
* Ingress with `spec.tls`

Study:

* `IngressClass`
* Traefik routing
* SNI
* host-based routing
* TLS termination
* Secret reference
* local hostname resolution

For k3d:

```bash
echo "127.0.0.1 app.localhost" | sudo tee -a /etc/hosts
```

Test:

```bash
curl -vk https://app.localhost:8443
curl --cacert ca.crt https://app.localhost:8443
```

## 7.2 Learn cert-manager Ingress integration

cert-manager can create certificates from annotated Ingress resources. Ingress annotations can point to an `Issuer` or `ClusterIssuer`, and cert-manager can also configure HTTP-01 solver behavior through annotations. ([cert-manager][12])

Hands-on:

* Create an Ingress with `cert-manager.io/issuer`
* Create an Ingress with `cert-manager.io/cluster-issuer`
* Watch generated `Certificate`
* Watch generated `CertificateRequest`
* Inspect Secret
* Delete Secret and observe recovery
* Change DNS names and observe re-issuance

Commands:

```bash
kubectl get ingress -A
kubectl get certificate -A
kubectl describe certificate -n sandbox
kubectl describe ingress -n sandbox
```

---

# 8. ACME track

## 8.1 Learn ACME concepts

Study:

* ACME account
* ACME server directory URL
* ACME account private key Secret
* Order
* Authorization
* Challenge
* Solver
* HTTP-01
* DNS-01
* Let’s Encrypt staging vs production
* Rate limits
* Public DNS requirements

cert-manager supports ACME issuers such as Let’s Encrypt. For ACME issuance, it creates `Order` and `Challenge` resources and must prove ownership of the requested DNS names. ([cert-manager][13])

## 8.2 HTTP-01

HTTP-01 uses your Ingress or Gateway configuration. cert-manager creates solver resources that answer the ACME validation request. ([cert-manager][14])

Critical for your k3d setup:

* Your local `localhost:8080 -> cluster:80` mapping is good for local testing.
* Public Let’s Encrypt HTTP-01 requires the domain to be reachable on public port `80`.
* Let’s Encrypt states that HTTP-01 can only be done on port `80`; arbitrary ports are not allowed. ([Let's Encrypt][15])

So for real Let’s Encrypt HTTP-01 on k3d, you need one of:

* public server forwarding `:80` to your machine
* router port forwarding `:80 -> localhost:8080`
* tunnel that supports HTTP validation
* cloud VM running k3d
* use DNS-01 instead
* use Pebble for local ACME practice

## 8.3 DNS-01

DNS-01 proves domain control by creating a TXT record under `_acme-challenge.<domain>`. It supports wildcard certificates and can validate domains whose web servers are not publicly exposed, but it requires DNS automation credentials and careful security handling. ([Let's Encrypt][15])

cert-manager DNS-01 configuration is placed on the `Issuer` or `ClusterIssuer`, and each issuer can have multiple DNS-01 providers or multiple solver configurations. ([cert-manager][16])

Study providers:

* Cloudflare
* Route53
* Google Cloud DNS
* Azure DNS
* DigitalOcean DNS
* RFC2136
* webhook-based DNS providers

Hands-on:

1. Use a real domain.
2. Create DNS API token with minimum privileges.
3. Store token in Kubernetes Secret.
4. Create `ClusterIssuer`.
5. Issue normal certificate.
6. Issue wildcard certificate.
7. Inspect `Order` and `Challenge`.

## 8.4 Pebble local ACME lab

For local k3d, use Pebble after you understand the core objects. Let’s Encrypt’s own docs say the staging environment is useful for testing but not ideal for CI/development environments, and they point to Pebble as a small ACME server purpose-built for CI and development. ([Let's Encrypt][17])

Learn:

* Pebble ACME server
* fake CA
* local DNS mapping
* cert-manager ACME issuer pointing to Pebble
* HTTP-01 solver behavior without burning Let’s Encrypt limits

---

# 9. Renewal and private key rotation track

Learn:

* `duration`
* `renewBefore`
* renewal window
* re-issuance triggers
* `cmctl renew`
* private key rotation
* Secret replacement behavior
* application reload strategy

Important current behavior: cert-manager changed the default private key rotation policy in v1.18.0; for cert-manager `>= v1.18.0`, the default is `rotationPolicy: Always`. ([cert-manager][8])

Hands-on:

```bash
cmctl status certificate app-cert -n sandbox
cmctl renew app-cert -n sandbox
kubectl describe certificate app-cert -n sandbox
kubectl get secret app-tls -n sandbox -o yaml
```

Study app reload options:

* app watches mounted Secret
* pod restart on Secret change
* Reloader controller
* checksum annotation rollout
* sidecar reload pattern

---

# 10. Troubleshooting track

## 10.1 Learn the troubleshooting workflow

cert-manager troubleshooting starts with `kubectl describe`; the docs recommend it as the first tool because it shows resource status and recent events, while logs are verbose and usually secondary. ([cert-manager][18])

Core commands:

```bash
kubectl describe certificate -n sandbox app-cert
kubectl describe certificaterequest -n sandbox
kubectl describe issuer -n sandbox
kubectl describe clusterissuer
kubectl get events -n sandbox --sort-by=.lastTimestamp
kubectl logs -n cert-manager deploy/cert-manager
```

For ACME:

```bash
kubectl get orders -A
kubectl get challenges -A
kubectl describe order -n sandbox
kubectl describe challenge -n sandbox
```

## 10.2 Failure cases to intentionally create

Practice breaking and fixing:

* Wrong `issuerRef`
* Missing Secret
* Invalid DNS name
* Ingress host mismatch
* Wrong IngressClass
* HTTP-01 path not routed
* DNS-01 token missing permissions
* DNS propagation delay
* expired CA
* webhook not ready
* CRDs not installed
* namespace mismatch
* RBAC denied
* app does not reload updated cert

---

# 11. Security and multi-tenancy track

Learn:

* Namespace-scoped `Issuer` vs cluster-scoped `ClusterIssuer`
* Who can create `Certificate`
* Who can read TLS Secrets
* Secret leakage risk
* DNS API token scoping
* ACME account private key protection
* Avoiding wildcard overuse
* Key algorithm policy
* Certificate duration policy
* Approval workflow
* Policy as code

## 11.1 approver-policy

`approver-policy` evaluates `CertificateRequest` resources and can approve or deny them based on policies. A request must match policy selection and RBAC binding; if no matching policy approves it, it may remain unprocessed. ([cert-manager][19])

Hands-on:

* Install approver-policy.
* Create policy allowing only specific DNS suffixes.
* Bind policy to a namespace/service account.
* Try allowed and denied certificates.
* Inspect `CertificateRequest` conditions.

Topics:

* `CertificateRequestPolicy`
* RBAC binding
* namespace tenancy
* allowed DNS names
* allowed issuers
* allowed durations
* allowed key usages

---

# 12. Trust distribution track

## 12.1 trust-manager

cert-manager issues certificates; trust-manager distributes trust bundles. It introduces a cluster-scoped `Bundle` resource that combines CA sources and writes resulting bundles to targets for workloads. ([cert-manager][20])

Learn:

* Why issuing certs is not enough
* Trust bundle distribution
* Root CA rotation
* ConfigMap target
* namespace selection
* application trust store injection
* public trust vs private trust
* avoiding baked CA bundles in images

Hands-on:

1. Install trust-manager.
2. Create private CA.
3. Create `Bundle`.
4. Sync CA bundle to namespaces.
5. Mount bundle into app.
6. Verify app trusts private certificate.

---

# 13. CSI driver track

The cert-manager CSI driver lets Pods request and mount certificates directly without creating a `Certificate` resource or intermediate Secret. This is useful for ephemeral certificates and mTLS, especially when you want private keys to stay node-local. ([cert-manager][21])

Learn:

* CSI ephemeral volumes
* per-pod certificates
* no Secret storage
* pod startup dependency on issuance
* mTLS use cases
* ServiceAccount-based request identity
* integration with approver-policy

Hands-on:

* Install `cert-manager-csi-driver`.
* Create Pod with CSI volume.
* Mount certs at `/tls`.
* Inspect mounted files.
* Restart Pod and observe new identity.
* Compare with Secret-based `Certificate`.

---

# 14. Gateway API track

After Ingress, learn Gateway API integration:

* `Gateway`
* `HTTPRoute`
* `TLSRoute`
* listeners
* certificateRefs
* cert-manager Gateway annotations
* HTTP-01 with Gateway solver
* migration from Ingress to Gateway API

This is increasingly important for modern Kubernetes networking, but learn Ingress first because it is simpler and maps directly to your k3d Traefik setup.

---

# 15. External issuers track

Learn cert-manager issuer ecosystem:

* ACME
* CA
* SelfSigned
* Vault
* Venafi / CyberArk Certificate Manager
* external issuer controllers
* webhook issuers
* cloud private CA issuers
* SPIFFE/SPIRE-related integrations

Topics:

* issuer groups
* issuer kinds
* external CRDs
* controller ownership
* operational boundaries
* auditability

---

# 16. Observability and operations track

Learn:

* cert-manager metrics
* Prometheus scraping
* alerting on certificate expiration
* alerting on failed issuance
* controller logs
* Kubernetes Events
* audit logs
* SLOs for certificate issuance
* backup and restore
* disaster recovery for CA private keys
* CRD upgrades
* Helm upgrades
* version compatibility

Practice:

```bash
kubectl get certificates -A
kubectl get certificaterequests -A
kubectl get orders -A
kubectl get challenges -A
kubectl top pods -n cert-manager
kubectl logs -n cert-manager deploy/cert-manager --tail=200
```

---

# 17. GitOps track

Learn how to manage cert-manager declaratively:

* HelmRelease / Flux
* Argo CD Application
* CRD installation order
* sync waves
* dependency ordering
* Sealed Secrets / External Secrets
* DNS token management
* promotion from staging to production
* environment-specific issuers
* policy separation

The cert-manager docs explicitly mention continuous deployment with tools such as Flux and Argo CD, or rendering Helm templates into manifests. ([cert-manager][22])

Recommended structure:

```text
clusters/
  dev/
    cert-manager/
      helmrelease.yaml
      issuers/
        selfsigned.yaml
        ca.yaml
        letsencrypt-staging.yaml
  prod/
    cert-manager/
      helmrelease.yaml
      issuers/
        letsencrypt-prod.yaml
platform/
  trust-manager/
  approver-policy/
apps/
  demo-app/
    deployment.yaml
    service.yaml
    ingress.yaml
    certificate.yaml
```

---

# 18. Recommended hands-on sequence

## Phase 1 — Local foundation

1. Create k3d cluster using your script.
2. Verify Traefik Ingress works over `localhost:8080`.
3. Deploy a simple app.
4. Expose it through Ingress.
5. Add manual TLS Secret.
6. Test with `curl -k https://app.localhost:8443`.

## Phase 2 — Install cert-manager

1. Install cert-manager with Helm.
2. Inspect CRDs.
3. Inspect controller, webhook, cainjector.
4. Create namespace `sandbox`.
5. Verify webhook admission works.

## Phase 3 — SelfSigned

1. Create SelfSigned `ClusterIssuer`.
2. Create `Certificate`.
3. Inspect generated Secret.
4. Decode certificate.
5. Use certificate in an Ingress.

## Phase 4 — Private CA

1. Bootstrap root CA.
2. Create CA `ClusterIssuer`.
3. Issue app certificate.
4. Trust the root locally.
5. Access app with valid local trust.
6. Rotate app cert manually with `cmctl`.

## Phase 5 — Ingress automation

1. Annotate Ingress with issuer.
2. Let cert-manager create the `Certificate`.
3. Inspect owner flow.
4. Delete Secret and observe re-issuance.
5. Change host and observe new request.

## Phase 6 — ACME local

1. Run Pebble or another local ACME server.
2. Configure ACME `Issuer`.
3. Test HTTP-01 flow locally.
4. Inspect `Order` and `Challenge`.

## Phase 7 — ACME real domain

1. Use Let’s Encrypt staging.
2. Try HTTP-01 only if public port `80` reaches your Ingress.
3. Try DNS-01 with a DNS provider API.
4. Move to production issuer only after staging works.
5. Monitor renewal.

## Phase 8 — Production-grade controls

1. Install approver-policy.
2. Restrict allowed DNS names.
3. Install trust-manager.
4. Distribute private CA bundle.
5. Add monitoring and alerts.
6. Convert everything to GitOps.

---

# 19. Complete topic checklist

Use this as your study checklist:

* [ ] k3d cluster creation
* [ ] k3d load balancer port mapping
* [ ] k3d local registry
* [ ] k3s Traefik Ingress
* [ ] Kubernetes TLS Secret
* [ ] Kubernetes Ingress TLS
* [ ] TLS handshake
* [ ] X.509 certificate fields
* [ ] SANs
* [ ] Root and intermediate CAs
* [ ] Public vs private trust
* [ ] cert-manager installation
* [ ] cert-manager CRDs
* [ ] cert-manager controller
* [ ] cert-manager webhook
* [ ] cert-manager cainjector
* [ ] Issuer
* [ ] ClusterIssuer
* [ ] Certificate
* [ ] CertificateRequest
* [ ] Order
* [ ] Challenge
* [ ] SelfSigned issuer
* [ ] CA issuer
* [ ] ACME issuer
* [ ] HTTP-01 solver
* [ ] DNS-01 solver
* [ ] Let’s Encrypt staging
* [ ] Let’s Encrypt production
* [ ] Pebble local ACME
* [ ] Ingress annotations
* [ ] Ingress shim
* [ ] Certificate renewal
* [ ] Private key rotation
* [ ] `cmctl`
* [ ] Debugging with `kubectl describe`
* [ ] Events-based troubleshooting
* [ ] RBAC for certificate requests
* [ ] Secret security
* [ ] DNS API token security
* [ ] approver-policy
* [ ] trust-manager
* [ ] cert-manager CSI driver
* [ ] Gateway API integration
* [ ] external issuers
* [ ] metrics and alerting
* [ ] GitOps installation
* [ ] upgrade strategy
* [ ] backup and disaster recovery

---

# 20. Best first practical path for you

Given your k3d script, I would follow this exact order:

1. **SelfSigned certificate**
2. **Private CA bootstrap**
3. **CA-signed Ingress TLS on `https://app.localhost:8443`**
4. **Ingress annotation automation**
5. **Certificate renewal and rotation**
6. **Troubleshooting broken certs**
7. **Pebble ACME**
8. **Real Let’s Encrypt DNS-01**
9. **approver-policy**
10. **trust-manager**
11. **CSI driver for mTLS-style workloads**
12. **GitOps production model**

That order gives you fast local feedback first, then production-grade ACME and policy topics after the cert-manager control flow is clear.

[1]: https://k3d.io/v5.8.3/usage/exposing_services/ "Exposing Services - k3d"
[2]: https://cert-manager.io/docs/ "cert-manager - cert-manager Documentation"
[3]: https://kubernetes.io/docs/concepts/services-networking/ingress/ "Ingress | Kubernetes"
[4]: https://k3d.io/v5.8.3/usage/registries/ "Using Image Registries - k3d"
[5]: https://cert-manager.io/docs/installation/helm/ "Helm - cert-manager Documentation"
[6]: https://cert-manager.io/docs/concepts/ca-injector/ "CA Injector - cert-manager Documentation"
[7]: https://cert-manager.io/docs/concepts/issuer/ "Issuer - cert-manager Documentation"
[8]: https://cert-manager.io/docs/usage/certificate/ "Certificate resource - cert-manager Documentation"
[9]: https://cert-manager.io/docs/usage/certificaterequest/ "CertificateRequest resource - cert-manager Documentation"
[10]: https://cert-manager.io/docs/configuration/selfsigned/ "SelfSigned - cert-manager Documentation"
[11]: https://cert-manager.io/docs/configuration/ca/ "CA - cert-manager Documentation"
[12]: https://cert-manager.io/docs/usage/ingress/ "Annotated Ingress resource - cert-manager Documentation"
[13]: https://cert-manager.io/docs/concepts/acme-orders-challenges/ "ACME Orders and Challenges - cert-manager Documentation"
[14]: https://cert-manager.io/docs/configuration/acme/http01/ "HTTP01 - cert-manager Documentation"
[15]: https://letsencrypt.org/docs/challenge-types/ "
Challenge Types -  Let's Encrypt
"
[16]: https://cert-manager.io/docs/configuration/acme/dns01/ "DNS01 - cert-manager Documentation"
[17]: https://letsencrypt.org/docs/staging-environment/ "
Staging Environment -  Let's Encrypt
"
[18]: https://cert-manager.io/docs/troubleshooting/ "Troubleshooting - cert-manager Documentation"
[19]: https://cert-manager.io/docs/policy/approval/approver-policy/ "approver-policy - cert-manager Documentation"
[20]: https://cert-manager.io/docs/trust/trust-manager/ "trust-manager - cert-manager Documentation"
[21]: https://cert-manager.io/docs/usage/csi-driver/ "csi-driver - cert-manager Documentation"
[22]: https://cert-manager.io/docs/installation/continuous-deployment-and-gitops/?utm_source=chatgpt.com "Continuous Deployment"
