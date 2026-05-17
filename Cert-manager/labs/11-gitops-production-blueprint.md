# Lab 11 - GitOps Production Blueprint for cert-manager Platform

## Objective

Turn manual commands into a GitOps-ready, promotion-safe structure for dev/staging/prod.

## Why This Stage Matters

Without declarative promotion:

- Cluster drift accumulates quickly
- Rollbacks are risky
- Issuer and policy changes are hard to audit

## Recommended Repository Layout

```text
clusters/
  dev/
    cert-manager/
      helmrelease.yaml
      issuers/
        local-ca.yaml
        letsencrypt-staging.yaml
  prod/
    cert-manager/
      helmrelease.yaml
      issuers/
        letsencrypt-prod.yaml
platform/
  approver-policy/
  trust-manager/
apps/
  demo-app/
    deployment.yaml
    service.yaml
    ingress.yaml
```

## Step 1 - Define Environment-Specific Issuers

- Dev: local CA or staging ACME
- Prod: production ACME only
- Keep issuer names stable inside each environment

## Step 2 - Separate Ownership Boundaries

- Platform team owns cert-manager, approver-policy, trust-manager, ClusterIssuers
- App teams own Ingress/Certificate manifests within namespace boundaries

## Step 3 - Enforce Ordering

Required sync order:

1. CRDs
2. cert-manager controllers
3. issuers and policies
4. application ingress/certificates

In Flux/Argo CD, use sync waves or explicit dependencies.

## Step 4 - Secrets Strategy

- Do not commit raw DNS tokens
- Use External Secrets or sealed-secrets
- Rotate provider tokens regularly

## Step 5 - SLO and Alerting Baseline

Track at minimum:

- Certificate expiry horizon
- Issuance failure count
- Pending challenge/order duration
- cert-manager controller health

## Step 6 - Upgrade Playbook

For each upgrade:

1. Read release notes
2. Validate CRD migration path
3. Test in dev cluster
4. Promote to staging
5. Promote to production with rollback plan

## Step 7 - Disaster Recovery Drill

Practice restoring:

- Issuer configuration
- ACME account secrets
- Internal CA key material (if self-managed)

Document RPO/RTO expectations.

## Final Validation Checklist

- All cert-manager resources managed from Git
- No manual drift in cluster
- Policy enforcement active
- Trust distribution active
- Renewal and incident runbooks documented

## Exit Criteria

You completed the full program when:

- New app teams can onboard TLS by manifest only
- Issuance is policy-controlled
- Trust distribution is automated
- Upgrades and incidents are runbook-driven
