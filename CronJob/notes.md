# Kubernetes CronJob —  deep dive

A **CronJob** is the Kubernetes controller for **scheduled Jobs**. It creates Kubernetes `Job` objects on a repeating schedule, and each Job then creates Pod(s) to run the actual task. Kubernetes describes a CronJob as similar to one line in a Unix crontab: it runs a Job periodically according to a cron expression. ([Kubernetes][1])

Mental model:

```text
CronJob
  └── schedule: "0 2 * * *"
        └── creates Job at scheduled time
              └── creates Pod
                    └── runs container command
                    └── exits
```

A Job answers:

```text
Run this task once until completion.
```

A CronJob answers:

```text
Run this Job repeatedly according to this schedule.
```

---

# 1. CronJob vs Job

## Job

A **Job** is one execution.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: one-time-backup
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: backup
          image: busybox:1.37
          command: ["sh", "-c", "echo backup; sleep 5"]
```

Use a Job for:

```text
Run database migration once.
Run data import once.
Run security scan once.
Run batch process once.
```

---

## CronJob

A **CronJob** creates Jobs repeatedly.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nightly-backup
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: backup
              image: busybox:1.37
              command: ["sh", "-c", "echo backup; sleep 5"]
```

Use a CronJob for:

```text
Run backup every night.
Run cleanup every hour.
Generate reports every Monday.
Rotate temporary data every day.
Run scheduled vulnerability scans.
```

Kubernetes’ official examples include scheduled tasks such as backups and report generation. ([Kubernetes][1])

---

# 2. CronJob controller chain

The object ownership flow is:

```text
CronJob controller
  creates
Job
  creates
Pod
  runs
Container
```

So a CronJob does **not** directly manage Pods. It creates Jobs, and the Job controller manages Pods. Kubernetes explicitly notes that the CronJob is only responsible for creating Jobs matching its schedule; the Job is responsible for Pod management. ([Kubernetes][1])

Practical consequence:

```bash
kubectl get cronjob
kubectl get jobs
kubectl get pods
```

You debug CronJob scheduling at the CronJob layer, retry/completion behavior at the Job layer, and runtime failure at the Pod/container layer.

---

# 3. Minimal CronJob YAML

Create `cronjob-basic.yaml`:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: hello-cron
spec:
  schedule: "* * * * *"

  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: hello
              image: busybox:1.37
              command:
                - sh
                - -c
                - |
                  echo "CronJob execution started"
                  date
                  sleep 5
                  echo "CronJob execution completed"
```

Apply:

```bash
kubectl apply -f cronjob-basic.yaml
```

Check CronJob:

```bash
kubectl get cronjob
```

Shortcut:

```bash
kubectl get cj
```

Watch Jobs:

```bash
kubectl get jobs --watch
```

Check Pods:

```bash
kubectl get pods
```

Get logs from a Job:

```bash
kubectl logs job/<job-name>
```

Kubernetes’ own CronJob tutorial uses the same flow: create the CronJob, check the CronJob, watch Jobs, then inspect Pods and logs. ([Kubernetes][2])

---

# 4. CronJob YAML structure

A typical production CronJob looks like this:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: report-generator
  namespace: reporting
spec:
  schedule: "0 6 * * *"
  timeZone: "Etc/UTC"

  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 600
  suspend: false

  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3

  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 1800
      ttlSecondsAfterFinished: 86400

      template:
        spec:
          restartPolicy: Never
          containers:
            - name: report-generator
              image: registry.example.com/reporting/report-generator:1.4.2
              command:
                - sh
                - -c
                - |
                  set -euo pipefail
                  ./generate-report
```

Main sections:

| Field                          | Meaning                                       |
| ------------------------------ | --------------------------------------------- |
| `spec.schedule`                | Cron expression                               |
| `spec.timeZone`                | Time zone for schedule evaluation             |
| `spec.concurrencyPolicy`       | What to do when previous Job is still running |
| `spec.startingDeadlineSeconds` | Maximum delay allowed for missed schedule     |
| `spec.suspend`                 | Pause future executions                       |
| `successfulJobsHistoryLimit`   | How many successful Jobs to retain            |
| `failedJobsHistoryLimit`       | How many failed Jobs to retain                |
| `jobTemplate`                  | Template for Jobs created by the CronJob      |

---

# 5. `spec.schedule`

This is required:

```yaml
spec:
  schedule: "0 2 * * *"
```

Kubernetes CronJobs use standard cron-style five-field syntax:

```text
# ┌───────────── minute        0 - 59
# │ ┌───────────── hour        0 - 23
# │ │ ┌───────────── day month 1 - 31
# │ │ │ ┌───────────── month   1 - 12
# │ │ │ │ ┌───────────── weekday 0 - 6, Sunday to Saturday
# │ │ │ │ │
# * * * * *
```

The Kubernetes docs state that `.spec.schedule` is required and follows cron syntax. They also document that `?` has the same meaning as `*`, and macros such as `@hourly`, `@daily`, `@weekly`, `@monthly`, and `@yearly` are supported. ([Kubernetes][1])

Common schedules:

```yaml
# Every minute
schedule: "* * * * *"

# Every 5 minutes
schedule: "*/5 * * * *"

# Every hour at minute 0
schedule: "0 * * * *"

# Every day at 02:00
schedule: "0 2 * * *"

# Every Monday at 03:00
schedule: "0 3 * * 1"

# First day of every month at midnight
schedule: "0 0 1 * *"

# Using macro
schedule: "@daily"
```

Senior note:

```text
Use explicit schedules like "0 2 * * *" in production.
Macros are convenient, but explicit schedules are easier to audit.
```

---

# 6. `spec.timeZone`

By default, if no time zone is specified, the kube-controller-manager interprets the schedule relative to its local time zone. Since Kubernetes v1.27, `.spec.timeZone` is stable and lets you specify a valid time zone such as `Etc/UTC`. ([Kubernetes][1])

Recommended production pattern:

```yaml
spec:
  schedule: "0 2 * * *"
  timeZone: "Etc/UTC"
```

Or, for a business-local schedule:

```yaml
spec:
  schedule: "0 8 * * 1-5"
  timeZone: "Europe/Amsterdam"
```

Important:

```yaml
# Bad: not officially supported
schedule: "CRON_TZ=Europe/Amsterdam 0 8 * * *"
```

Kubernetes says `CRON_TZ` or `TZ` inside `.spec.schedule` is not officially supported; use `.spec.timeZone` instead. ([Kubernetes][1])

Senior recommendation:

```text
Use Etc/UTC for infrastructure jobs.
Use a business time zone only when the business requirement is explicitly local-time based.
```

Examples:

```text
Database backup       → UTC
Certificate scan      → UTC
Monthly invoice run   → Europe/Amsterdam, if business requires local month boundaries
Compliance report     → business time zone, if required by policy
```

---

# 7. `spec.jobTemplate`

This is required. It defines the Job that the CronJob creates. Kubernetes states that `.spec.jobTemplate` has the same schema as a Job spec, except it is nested and does not include `apiVersion` or `kind`. ([Kubernetes][1])

CronJob:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cleanup
spec:
  schedule: "0 * * * *"
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: cleanup
              image: busybox:1.37
              command: ["sh", "-c", "echo cleanup"]
```

The nested `jobTemplate.spec` is essentially the Job spec:

```yaml
jobTemplate:
  spec:
    backoffLimit: 2
    activeDeadlineSeconds: 600
    ttlSecondsAfterFinished: 3600
    template:
      spec:
        restartPolicy: Never
        containers:
          - name: worker
            image: ...
```

Senior note:

```text
Most reliability controls for the actual execution live inside jobTemplate.spec, not directly on the CronJob.
```

---

# 8. `restartPolicy`

Inside the Job Pod template, use:

```yaml
restartPolicy: Never
```

or:

```yaml
restartPolicy: OnFailure
```

For most production CronJobs, prefer:

```yaml
restartPolicy: Never
```

Why?

```text
Each failed attempt becomes easier to inspect as its own failed Pod.
Job retry behavior is clearer.
Logs and events are easier to correlate.
```

Example:

```yaml
jobTemplate:
  spec:
    backoffLimit: 2
    template:
      spec:
        restartPolicy: Never
        containers:
          - name: task
            image: busybox:1.37
            command: ["sh", "-c", "exit 1"]
```

Use `OnFailure` when retrying inside the same Pod is acceptable.

---

# 9. `concurrencyPolicy`

This is one of the most important CronJob fields.

```yaml
spec:
  concurrencyPolicy: Forbid
```

Supported values:

| Policy    | Behavior                                                        |
| --------- | --------------------------------------------------------------- |
| `Allow`   | Default. New Jobs may run while previous Jobs are still running |
| `Forbid`  | Skip new run if previous run is still active                    |
| `Replace` | Delete/replace currently running Job with a new one             |

Kubernetes documents these three policies and clarifies that they apply only to Jobs created by the same CronJob. Different CronJobs can still run concurrently. ([Kubernetes][1])

---

## `Allow`

```yaml
concurrencyPolicy: Allow
```

Behavior:

```text
02:00 Job starts
02:05 next schedule arrives
02:00 Job still running
02:05 Job also starts
```

Use when:

```text
Jobs are independent.
Overlapping executions are safe.
Workload is idempotent and concurrency-safe.
```

Example use cases:

```text
Metrics snapshot
Independent report generation
Polling external APIs with safe deduplication
```

Risk:

```text
A slow job can pile up overlapping executions and overload the cluster or external systems.
```

---

## `Forbid`

```yaml
concurrencyPolicy: Forbid
```

Behavior:

```text
02:00 Job starts
02:05 next schedule arrives
02:00 Job still running
02:05 Job is skipped
```

Use when:

```text
Only one execution should run at a time.
Skipping is better than overlap.
Task is not safe to run concurrently.
```

Good for:

```text
Backups
Database maintenance
Report generation
Cleanup jobs
ETL jobs with shared output
```

Senior default:

```yaml
concurrencyPolicy: Forbid
```

This is usually the safest production default.

---

## `Replace`

```yaml
concurrencyPolicy: Replace
```

Behavior:

```text
02:00 Job starts
02:05 next schedule arrives
02:00 Job still running
02:00 Job is replaced by 02:05 Job
```

Use when:

```text
Only latest run matters.
Old work is obsolete.
```

Good for:

```text
Periodic cache refresh
Cluster inventory snapshot
Short-lived reconciliation task
```

Dangerous for:

```text
Database migrations
Backups
Financial processing
Non-interrupt-safe jobs
```

Senior note:

```text
Use Replace only if the task is interrupt-safe.
```

---

# 10. `startingDeadlineSeconds`

This field controls how late Kubernetes may start a missed schedule.

```yaml
spec:
  startingDeadlineSeconds: 600
```

Meaning:

```text
If the scheduled time was missed, Kubernetes may still create the Job for up to 600 seconds.
After that, skip that occurrence.
```

Kubernetes documents that after the deadline is missed, that particular Job occurrence is skipped, future occurrences are still scheduled, and missed deadlines are treated as failed Jobs. If the field is not specified, occurrences have no deadline. ([Kubernetes][1])

Example:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup
spec:
  schedule: "0 2 * * *"
  startingDeadlineSeconds: 1800
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: backup
              image: busybox:1.37
              command: ["sh", "-c", "echo backup"]
```

Interpretation:

```text
Scheduled at 02:00.
If controller notices at 02:10, Job can start.
If controller notices at 03:00, that run is skipped.
```

Important caveat:

```yaml
startingDeadlineSeconds: 5
```

This is usually bad. Kubernetes warns that if `startingDeadlineSeconds` is less than 10 seconds, the CronJob may not schedule because the CronJob controller checks every 10 seconds. ([Kubernetes][1])

Recommended values:

```yaml
# Frequent job, tolerate 1 minute delay
startingDeadlineSeconds: 60

# Hourly job, tolerate 10 minutes delay
startingDeadlineSeconds: 600

# Nightly backup, tolerate 1 hour delay
startingDeadlineSeconds: 3600
```

Senior rule:

```text
Set startingDeadlineSeconds deliberately.
Do not leave it unset for high-frequency CronJobs unless catch-up behavior is truly desired.
```

---

# 11. Missed schedules

CronJobs are approximate scheduled controllers, not hard real-time schedulers. Kubernetes states that a CronJob creates a Job approximately once per scheduled execution, but in some circumstances two Jobs might be created or no Job might be created; therefore, Jobs should be idempotent. ([Kubernetes][1])

A schedule can be missed because:

```text
Controller manager was down.
API server was unavailable.
CronJob was suspended.
Previous Job was still running and concurrencyPolicy was Forbid.
Cluster was overloaded.
There was clock skew.
```

Kubernetes also documents a 100 missed-schedule guard: if there are more than 100 missed schedules, the controller does not start the Job and logs an error. ([Kubernetes][1])

Example risky schedule:

```yaml
schedule: "* * * * *"
startingDeadlineSeconds: null
concurrencyPolicy: Allow
```

If the controller is unavailable for a long time, this can create unpleasant catch-up behavior or missed-start issues.

Better:

```yaml
schedule: "* * * * *"
startingDeadlineSeconds: 60
concurrencyPolicy: Forbid
```

---

# 12. `suspend`

You can pause future executions:

```yaml
spec:
  suspend: true
```

Or via command:

```bash
kubectl patch cronjob nightly-backup \
  -p '{"spec":{"suspend":true}}'
```

Resume:

```bash
kubectl patch cronjob nightly-backup \
  -p '{"spec":{"suspend":false}}'
```

Kubernetes says `suspend: true` stops subsequent executions but does not affect Jobs that already started. It also warns that suspended executions count as missed Jobs; when you unsuspend without a starting deadline, missed Jobs may be scheduled immediately. ([Kubernetes][1])

Production-safe suspend pattern:

```yaml
spec:
  suspend: true
  startingDeadlineSeconds: 300
```

Senior warning:

```text
If you suspend a frequent CronJob for a long time and later unsuspend it without a deadline, you may trigger immediate catch-up behavior.
```

---

# 13. Job history limits

CronJob-level history limits control how many completed Job objects are retained.

```yaml
successfulJobsHistoryLimit: 3
failedJobsHistoryLimit: 1
```

Kubernetes defaults are:

```text
successfulJobsHistoryLimit: 3
failedJobsHistoryLimit: 1
```

Setting either to `0` means Kubernetes does not keep that type of finished Job. ([Kubernetes][1])

Examples:

```yaml
# Keep very little history
successfulJobsHistoryLimit: 1
failedJobsHistoryLimit: 3
```

```yaml
# High-volume frequent CronJob
successfulJobsHistoryLimit: 0
failedJobsHistoryLimit: 1
```

```yaml
# Audit-sensitive task
successfulJobsHistoryLimit: 10
failedJobsHistoryLimit: 10
```

Senior note:

```text
History limits clean up Job objects created by the CronJob.
Job-level ttlSecondsAfterFinished is another cleanup mechanism.
Use both carefully.
```

---

# 14. `ttlSecondsAfterFinished`

This lives inside the Job template:

```yaml
jobTemplate:
  spec:
    ttlSecondsAfterFinished: 3600
```

It means:

```text
After each created Job reaches Complete or Failed, delete it after 3600 seconds.
```

Example:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: hourly-cleanup
spec:
  schedule: "0 * * * *"
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      ttlSecondsAfterFinished: 3600
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: cleanup
              image: busybox:1.37
              command: ["sh", "-c", "echo cleanup"]
```

Practical approach:

```text
Use history limits for CronJob-owned Job retention.
Use ttlSecondsAfterFinished for hard cleanup after a time window.
Make sure your log pipeline exports logs before TTL deletes Pods.
```

---

# 15. Manual trigger from CronJob

You often need to test a CronJob without waiting for the schedule.

Command:

```bash
kubectl create job manual-run \
  --from=cronjob/nightly-backup
```

With namespace:

```bash
kubectl create job manual-run-$(date +%s) \
  --from=cronjob/nightly-backup \
  -n backups
```

Kubernetes’ kubectl reference documents `kubectl create cronjob`, and Kubernetes task docs show CronJobs create Jobs that can be watched and inspected. The `kubectl create job --from=cronjob/...` pattern is the standard operational way to manually trigger a CronJob template. ([Kubernetes][3])

Check:

```bash
kubectl get jobs -n backups
kubectl logs job/manual-run-<id> -n backups
```

Senior use case:

```text
Before enabling a production CronJob, create a manual Job from it and validate:
- image pulls
- secrets/configs
- RBAC
- command path
- runtime
- logs
- resource requests
```

---

# 16. Production-grade CronJob: database backup

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: backups
  labels:
    app.kubernetes.io/name: postgres-backup
    app.kubernetes.io/component: backup
spec:
  schedule: "0 2 * * *"
  timeZone: "Etc/UTC"

  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 3600
  suspend: false

  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 5

  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 7200
      ttlSecondsAfterFinished: 86400

      template:
        metadata:
          labels:
            app.kubernetes.io/name: postgres-backup
            app.kubernetes.io/component: backup
        spec:
          restartPolicy: Never
          serviceAccountName: postgres-backup

          securityContext:
            runAsNonRoot: true
            seccompProfile:
              type: RuntimeDefault

          containers:
            - name: backup
              image: registry.example.com/platform/postgres-backup:1.2.0
              imagePullPolicy: IfNotPresent

              command:
                - sh
                - -c
                - |
                  set -euo pipefail
                  echo "Starting PostgreSQL backup"
                  ./backup.sh
                  echo "Backup completed"

              env:
                - name: DATABASE_URL
                  valueFrom:
                    secretKeyRef:
                      name: postgres-backup-secret
                      key: database-url
                - name: BACKUP_BUCKET
                  value: "s3://company-prod-backups/postgres"

              resources:
                requests:
                  cpu: "500m"
                  memory: "512Mi"
                limits:
                  memory: "1Gi"

              securityContext:
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities:
                  drop:
                    - ALL
```

Why these choices matter:

| Field                            | Reason                                           |
| -------------------------------- | ------------------------------------------------ |
| `timeZone: Etc/UTC`              | Avoid controller-local-time ambiguity            |
| `concurrencyPolicy: Forbid`      | Prevent overlapping backups                      |
| `startingDeadlineSeconds: 3600`  | Backup can start up to 1 hour late               |
| `backoffLimit: 2`                | Retry transient failures, avoid endless attempts |
| `activeDeadlineSeconds: 7200`    | Kill backup if it exceeds 2 hours                |
| `ttlSecondsAfterFinished: 86400` | Keep Job/Pod metadata for 1 day                  |
| `failedJobsHistoryLimit: 5`      | Preserve failure history                         |
| `restartPolicy: Never`           | Easier debugging per failed attempt              |

Senior backup notes:

```text
Backups must be externally verified.
A successful Pod exit does not guarantee restorable backup.
Add restore tests, checksum validation, and alerting.
```

---

# 17. Production-grade CronJob: scheduled security scan

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nightly-image-scan
  namespace: security
  labels:
    app.kubernetes.io/name: nightly-image-scan
    app.kubernetes.io/component: scanner
spec:
  schedule: "30 1 * * *"
  timeZone: "Etc/UTC"

  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 1800

  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 5

  jobTemplate:
    spec:
      backoffLimit: 1
      activeDeadlineSeconds: 3600
      ttlSecondsAfterFinished: 172800

      template:
        spec:
          restartPolicy: Never
          serviceAccountName: image-scanner

          containers:
            - name: scanner
              image: registry.example.com/security/image-scanner:3.8.1
              command:
                - sh
                - -c
                - |
                  set -euo pipefail
                  ./scan-registry \
                    --registry registry.example.com \
                    --output /tmp/report.json
                  ./upload-report /tmp/report.json

              env:
                - name: SCANNER_TOKEN
                  valueFrom:
                    secretKeyRef:
                      name: scanner-token
                      key: token

              resources:
                requests:
                  cpu: "1"
                  memory: "1Gi"
                limits:
                  memory: "2Gi"
```

Senior note:

```text
Scheduled security scans should emit machine-readable findings.
Do not rely only on Pod logs.
Push results to your vulnerability management or SIEM pipeline.
```

---

# 18. CronJob for cleanup

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: temp-object-cleanup
  namespace: platform
spec:
  schedule: "*/30 * * * *"
  timeZone: "Etc/UTC"

  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 300

  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 3

  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 600
      ttlSecondsAfterFinished: 3600

      template:
        spec:
          restartPolicy: Never
          serviceAccountName: temp-object-cleanup
          containers:
            - name: cleanup
              image: registry.example.com/platform/cleanup:2.0.0
              command:
                - sh
                - -c
                - |
                  set -euo pipefail
                  ./cleanup --older-than 24h
              resources:
                requests:
                  cpu: "100m"
                  memory: "128Mi"
                limits:
                  memory: "256Mi"
```

Why `Forbid`?

```text
If cleanup takes longer than 30 minutes, starting another cleanup can cause duplicate deletes, lock contention, or unnecessary API load.
```

---

# 19. CronJob with ConfigMap

ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: report-config
  namespace: reporting
data:
  REPORT_TYPE: "daily"
  OUTPUT_FORMAT: "json"
```

CronJob:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-report
  namespace: reporting
spec:
  schedule: "0 6 * * *"
  timeZone: "Etc/UTC"
  concurrencyPolicy: Forbid

  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: report
              image: busybox:1.37
              envFrom:
                - configMapRef:
                    name: report-config
              command:
                - sh
                - -c
                - |
                  echo "type=$REPORT_TYPE format=$OUTPUT_FORMAT"
```

Apply:

```bash
kubectl apply -f configmap.yaml
kubectl apply -f cronjob.yaml
```

Important:

```text
If you change the ConfigMap, future Jobs use the new ConfigMap values.
Already-created Jobs/Pods do not get rewritten by the CronJob.
```

Kubernetes explicitly states that modifying an existing CronJob affects only new Jobs after the modification; Jobs and Pods that have already started continue unchanged. ([Kubernetes][1])

---

# 20. CronJob with Secret

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: token-refresh
  namespace: platform
spec:
  schedule: "*/15 * * * *"
  timeZone: "Etc/UTC"
  concurrencyPolicy: Forbid

  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 300
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: refresh
              image: registry.example.com/platform/token-refresh:1.0.0
              env:
                - name: API_TOKEN
                  valueFrom:
                    secretKeyRef:
                      name: external-api-token
                      key: token
              command:
                - sh
                - -c
                - |
                  ./refresh-token
```

Senior warning:

```text
Never print secrets in CronJob logs.
CronJob-created Pods may remain for debugging depending on history/TTL settings.
```

---

# 21. CronJob with persistent volume

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: filesystem-backup
  namespace: backups
spec:
  schedule: "0 3 * * *"
  timeZone: "Etc/UTC"
  concurrencyPolicy: Forbid

  jobTemplate:
    spec:
      backoffLimit: 1
      activeDeadlineSeconds: 3600
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: backup
              image: busybox:1.37
              command:
                - sh
                - -c
                - |
                  tar czf /backup/data-$(date +%Y%m%d%H%M%S).tar.gz /data
              volumeMounts:
                - name: data
                  mountPath: /data
                  readOnly: true
                - name: backup
                  mountPath: /backup
          volumes:
            - name: data
              persistentVolumeClaim:
                claimName: app-data-pvc
            - name: backup
              persistentVolumeClaim:
                claimName: backup-pvc
```

Senior cautions:

```text
ReadWriteOnce PVCs may bind Jobs to specific nodes.
Backups from live filesystems can be inconsistent.
Database backups should use database-native snapshot/dump mechanisms.
For object storage backups, prefer writing directly to S3/GCS/Azure Blob.
```

---

# 22. RBAC for CronJobs

If a CronJob needs Kubernetes API access, use a dedicated ServiceAccount.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cleanup-sa
  namespace: platform
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cleanup-role
  namespace: platform
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cleanup-binding
  namespace: platform
subjects:
  - kind: ServiceAccount
    name: cleanup-sa
    namespace: platform
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: cleanup-role
```

CronJob:

```yaml
spec:
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: cleanup-sa
```

Senior rule:

```text
A scheduled task is still production code.
Do not give CronJobs cluster-admin unless absolutely necessary.
```

---

# 23. Security hardening

Baseline hardened CronJob Pod template:

```yaml
jobTemplate:
  spec:
    template:
      spec:
        restartPolicy: Never
        serviceAccountName: my-cronjob
        automountServiceAccountToken: false

        securityContext:
          runAsNonRoot: true
          seccompProfile:
            type: RuntimeDefault

        containers:
          - name: task
            image: registry.example.com/task:1.0.0
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop:
                  - ALL
```

Use:

```yaml
automountServiceAccountToken: false
```

when the CronJob does not need Kubernetes API access.

Add resources:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    memory: "256Mi"
```

Senior security checklist:

```text
Use immutable image tags or digests.
Use dedicated ServiceAccount.
Disable service account token if not needed.
Drop Linux capabilities.
Run as non-root.
Avoid hostPath.
Avoid privileged mode.
Avoid leaking secrets into logs.
Keep failed Job logs only as long as needed.
```

---

# 24. CronJob status

Check CronJobs:

```bash
kubectl get cronjobs
```

Example output:

```text
NAME             SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
nightly-backup   0 2 * * *     Etc/UTC    False     0        12h             10d
```

Useful columns:

| Column          | Meaning                         |
| --------------- | ------------------------------- |
| `SCHEDULE`      | Cron expression                 |
| `TIMEZONE`      | Schedule time zone              |
| `SUSPEND`       | Whether future runs are paused  |
| `ACTIVE`        | Number of currently active Jobs |
| `LAST SCHEDULE` | Last scheduled execution        |
| `AGE`           | Object age                      |

Describe:

```bash
kubectl describe cronjob nightly-backup
```

Look for:

```text
Schedule
Concurrency Policy
Suspend
Successful Job History Limit
Failed Job History Limit
Starting Deadline Seconds
Active Jobs
Last Schedule Time
Events
```

---

# 25. Debugging CronJobs

Use this layered approach:

```bash
kubectl get cronjob -n <namespace>
kubectl describe cronjob <name> -n <namespace>

kubectl get jobs -n <namespace>
kubectl get jobs -n <namespace> --sort-by=.metadata.creationTimestamp

kubectl get pods -n <namespace> -l job-name=<job-name>
kubectl describe job <job-name> -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl logs job/<job-name> -n <namespace>

kubectl get events -n <namespace> --sort-by=.lastTimestamp
```

---

## Problem: CronJob does not create Jobs

Check:

```bash
kubectl describe cronjob <name> -n <namespace>
```

Common causes:

| Symptom                 | Likely cause                                        |
| ----------------------- | --------------------------------------------------- |
| `SUSPEND=True`          | CronJob is suspended                                |
| No `LAST SCHEDULE`      | Schedule not reached yet                            |
| No Jobs after schedule  | Invalid schedule/time zone/controller issue         |
| Missed runs             | `startingDeadlineSeconds` too small                 |
| Skipped runs            | `concurrencyPolicy: Forbid` and previous Job active |
| Too many missed starts  | Controller downtime or high-frequency schedule      |
| Job created then failed | Debug Job/Pod layer                                 |

Check suspend:

```bash
kubectl get cronjob <name> -n <namespace> \
  -o jsonpath='{.spec.suspend}'
```

Resume:

```bash
kubectl patch cronjob <name> -n <namespace> \
  -p '{"spec":{"suspend":false}}'
```

---

## Problem: Job exists but Pod failed

```bash
kubectl describe job <job-name> -n <namespace>
kubectl get pods -n <namespace> -l job-name=<job-name>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

Common Pod failures:

| Status                       | Meaning                                        |
| ---------------------------- | ---------------------------------------------- |
| `ImagePullBackOff`           | Bad image/tag/registry credentials             |
| `CreateContainerConfigError` | Bad ConfigMap/Secret/env/volume reference      |
| `CrashLoopBackOff`           | Usually with `restartPolicy: OnFailure`        |
| `Error`                      | Container exited non-zero                      |
| `OOMKilled`                  | Memory limit too low or memory leak            |
| `Pending`                    | Scheduling/resource/taint/affinity/quota issue |

---

## Problem: CronJob overlaps executions

Check:

```bash
kubectl get jobs -n <namespace>
kubectl get cronjob <name> -n <namespace> -o yaml
```

If you see multiple active Jobs from the same CronJob and that is not safe, set:

```yaml
concurrencyPolicy: Forbid
```

or, if latest execution should replace previous work:

```yaml
concurrencyPolicy: Replace
```

---

## Problem: CronJob creates too many Jobs

Possible causes:

```text
Schedule too frequent.
Job runs too long.
concurrencyPolicy is Allow.
History limits too high.
ttlSecondsAfterFinished missing.
Controller catching up after missed schedules.
```

Mitigation:

```yaml
schedule: "*/15 * * * *"
concurrencyPolicy: Forbid
startingDeadlineSeconds: 300
successfulJobsHistoryLimit: 1
failedJobsHistoryLimit: 3
jobTemplate:
  spec:
    ttlSecondsAfterFinished: 3600
    activeDeadlineSeconds: 900
```

---

# 26. CronJob modification behavior

If you update a CronJob, already-created Jobs do not change. Only future Jobs use the new template. Kubernetes documents this explicitly. ([Kubernetes][1])

Example:

```bash
kubectl set image cronjob/nightly-backup backup=my-backup:2.0.0
```

This affects future Jobs only.

Existing running Job:

```text
continues with old image
```

Future Job:

```text
uses new image
```

Senior deployment workflow:

```bash
kubectl apply -f cronjob.yaml
kubectl create job test-run-$(date +%s) --from=cronjob/nightly-backup
kubectl logs job/test-run-<id>
```

---

# 27. CronJob naming limit

CronJob names need extra care. Kubernetes uses the CronJob name as part of the generated Job name, appending 11 characters. Because Job names are limited to 63 characters, CronJob names must be no longer than 52 characters. ([Kubernetes][1])

Bad:

```yaml
metadata:
  name: extremely-long-production-database-backup-cronjob-for-platform-team
```

Better:

```yaml
metadata:
  name: pg-backup-prod
```

Senior naming pattern:

```text
<system>-<task>-<env>
```

Examples:

```text
pg-backup-prod
image-scan-nightly
cleanup-temp-hourly
billing-report-daily
```

---

# 28. Hands-on lab: basic CronJob

Create namespace:

```bash
kubectl create namespace cronjob-lab
```

Create file:

```bash
cat > cronjob-basic.yaml <<'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: hello-cron
  namespace: cronjob-lab
spec:
  schedule: "* * * * *"
  timeZone: "Etc/UTC"
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 60
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 2

  jobTemplate:
    spec:
      backoffLimit: 1
      activeDeadlineSeconds: 60
      ttlSecondsAfterFinished: 600
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: hello
              image: busybox:1.37
              command:
                - sh
                - -c
                - |
                  echo "Started at $(date)"
                  sleep 5
                  echo "Finished at $(date)"
EOF
```

Apply:

```bash
kubectl apply -f cronjob-basic.yaml
```

Watch:

```bash
kubectl get cronjob -n cronjob-lab
kubectl get jobs -n cronjob-lab --watch
```

Get logs:

```bash
JOB=$(kubectl get jobs -n cronjob-lab \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1:].metadata.name}')

kubectl logs job/$JOB -n cronjob-lab
```

---

# 29. Hands-on lab: manual trigger

```bash
kubectl create job manual-hello-$(date +%s) \
  --from=cronjob/hello-cron \
  -n cronjob-lab
```

Check:

```bash
kubectl get jobs -n cronjob-lab
kubectl get pods -n cronjob-lab
```

Logs:

```bash
kubectl logs job/<manual-job-name> -n cronjob-lab
```

Use this before enabling important CronJobs in production.

---

# 30. Hands-on lab: concurrencyPolicy behavior

Create a CronJob that runs longer than its schedule interval:

```bash
cat > cronjob-long-allow.yaml <<'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: long-allow
  namespace: cronjob-lab
spec:
  schedule: "* * * * *"
  concurrencyPolicy: Allow
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      activeDeadlineSeconds: 300
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: long-task
              image: busybox:1.37
              command:
                - sh
                - -c
                - |
                  echo "Starting long task at $(date)"
                  sleep 120
                  echo "Finished at $(date)"
EOF
```

Apply:

```bash
kubectl apply -f cronjob-long-allow.yaml
```

Watch:

```bash
kubectl get jobs -n cronjob-lab -w
```

You should see overlapping Jobs.

Now patch to `Forbid`:

```bash
kubectl patch cronjob long-allow -n cronjob-lab \
  -p '{"spec":{"concurrencyPolicy":"Forbid"}}'
```

Now new executions are skipped while the previous one is active.

---

# 31. Hands-on lab: suspend and resume

Suspend:

```bash
kubectl patch cronjob hello-cron -n cronjob-lab \
  -p '{"spec":{"suspend":true}}'
```

Check:

```bash
kubectl get cronjob hello-cron -n cronjob-lab
```

Resume:

```bash
kubectl patch cronjob hello-cron -n cronjob-lab \
  -p '{"spec":{"suspend":false}}'
```

Senior note:

```text
For frequent CronJobs, combine suspend/resume with startingDeadlineSeconds to avoid unexpected catch-up.
```

---

# 32. Hands-on lab: failed CronJob

```bash
cat > cronjob-fail.yaml <<'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: failing-cron
  namespace: cronjob-lab
spec:
  schedule: "* * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 5

  jobTemplate:
    spec:
      backoffLimit: 2
      ttlSecondsAfterFinished: 1800
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: fail
              image: busybox:1.37
              command:
                - sh
                - -c
                - |
                  echo "I will fail"
                  exit 1
EOF
```

Apply:

```bash
kubectl apply -f cronjob-fail.yaml
```

Debug:

```bash
kubectl get jobs -n cronjob-lab
kubectl describe cronjob failing-cron -n cronjob-lab

FAILED_JOB=$(kubectl get jobs -n cronjob-lab \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1:].metadata.name}')

kubectl describe job $FAILED_JOB -n cronjob-lab
kubectl logs job/$FAILED_JOB -n cronjob-lab
```

---

# 33. Observability for CronJobs

CronJobs are easy to create and easy to forget. Production CronJobs need observability.

Track:

```text
Was the Job created?
Did the Job start?
Did it complete?
How long did it run?
Did it retry?
Did it miss schedule?
Did it overlap?
Did it produce expected output?
```

Useful metadata labels:

```yaml
metadata:
  labels:
    app.kubernetes.io/name: nightly-backup
    app.kubernetes.io/component: scheduled-task
    platform.example.com/owner: platform-team
```

Useful Job template labels:

```yaml
jobTemplate:
  metadata:
    labels:
      cronjob.example.com/type: backup
  spec:
    template:
      metadata:
        labels:
          cronjob.example.com/type: backup
```

Useful app logs:

```text
cronjob_name
job_name
pod_name
scheduled_time
start_time
end_time
duration_ms
records_processed
backup_size_bytes
exit_reason
```

Since Kubernetes v1.32, Jobs created by CronJobs get the annotation `batch.kubernetes.io/cronjob-scheduled-timestamp`, which records the originally scheduled creation time in RFC3339 format. ([Kubernetes][1])

Check it:

```bash
kubectl get job <job-name> -o jsonpath='{.metadata.annotations.batch\.kubernetes\.io/cronjob-scheduled-timestamp}'
```

---

# 34. Alerting recommendations

Alert on:

```text
CronJob has not succeeded within expected interval.
Job failed.
Job duration exceeded threshold.
Job is still active after expected runtime.
Too many failed Jobs retained.
No Job created after schedule.
Backup file missing after successful Job.
```

Example Prometheus-style intent:

```text
Alert if nightly backup CronJob has no successful Job in 26 hours.
Alert if any critical CronJob Job fails.
Alert if active Job age exceeds activeDeadlineSeconds expectation.
```

Senior rule:

```text
Do not alert only on Pod failure.
Alert on business outcome: backup exists, report uploaded, scan completed, data exported.
```

---

# 35. CronJob reliability model

CronJobs are not exactly-once systems.

Kubernetes says CronJob scheduling is approximate and there are circumstances where two Jobs might be created or no Job might be created, so the Job should be idempotent. ([Kubernetes][1])

Design assumptions:

```text
A scheduled execution may run once.
It may run late.
It may be skipped.
It may overlap if allowed.
It may be retried.
It may be duplicated.
It may be interrupted.
```

Therefore, your CronJob logic should be:

```text
Idempotent
Retry-safe
Concurrency-safe
Interrupt-safe
Observable
Bounded by deadlines
```

Bad backup script:

```bash
upload backup.tar.gz
```

Better:

```bash
upload backup-${TIMESTAMP}.tar.gz
verify checksum
write metadata marker
avoid overwriting previous successful backup
```

Bad report script:

```bash
INSERT INTO reports VALUES (...)
```

Better:

```bash
UPSERT report for date
use unique key on report_date
make rerun safe
```

Bad cleanup script:

```bash
delete everything matching prefix
```

Better:

```bash
delete only objects older than threshold
dry-run support
emit deleted count
rate limit API calls
```

---

# 36. Common mistakes

## Mistake 1: Using `Allow` by default for unsafe jobs

Bad:

```yaml
concurrencyPolicy: Allow
```

for:

```text
backup
migration
cleanup
billing export
shared-output report
```

Better:

```yaml
concurrencyPolicy: Forbid
```

---

## Mistake 2: No deadline

Bad:

```yaml
jobTemplate:
  spec:
    template:
      spec:
        containers:
          - name: task
```

Better:

```yaml
jobTemplate:
  spec:
    activeDeadlineSeconds: 1800
```

Without a deadline, a broken Job may run far longer than expected.

---

## Mistake 3: No history/TTL cleanup

Bad:

```yaml
spec:
  schedule: "* * * * *"
```

For frequent CronJobs, this creates many Jobs and Pods over time.

Better:

```yaml
successfulJobsHistoryLimit: 1
failedJobsHistoryLimit: 3
jobTemplate:
  spec:
    ttlSecondsAfterFinished: 3600
```

---

## Mistake 4: Local time ambiguity

Bad:

```yaml
schedule: "0 2 * * *"
```

with no clear understanding of controller-manager time.

Better:

```yaml
schedule: "0 2 * * *"
timeZone: "Etc/UTC"
```

---

## Mistake 5: Too-short `startingDeadlineSeconds`

Bad:

```yaml
startingDeadlineSeconds: 5
```

Kubernetes warns values below 10 seconds may not schedule because the controller checks every 10 seconds. ([Kubernetes][1])

Better:

```yaml
startingDeadlineSeconds: 60
```

or more depending on schedule.

---

## Mistake 6: Expecting CronJob updates to affect running Jobs

Bad assumption:

```text
I updated the CronJob image, so the currently running Job uses the new image.
```

Correct:

```text
Only future Jobs use the updated template.
```

Kubernetes documents that existing Jobs and Pods continue unchanged after CronJob modification. ([Kubernetes][1])

---

## Mistake 7: Long CronJob name

Bad:

```yaml
metadata:
  name: production-platform-nightly-postgresql-database-backup-cronjob
```

Better:

```yaml
metadata:
  name: pg-backup-prod
```

CronJob names should be 52 characters or less because the controller appends characters to generated Job names. ([Kubernetes][1])

---

## Mistake 8: Treating CronJob success as business success

A Pod can exit `0` even though:

```text
backup file is corrupt
report is empty
external upload silently failed
scan found no targets because auth failed
```

Application logic must validate business outcome before exiting `0`.

---

# 37. Useful commands

Create CronJob imperatively:

```bash
kubectl create cronjob hello \
  --image=busybox:1.37 \
  --schedule="*/1 * * * *" \
  -- date
```

The official kubectl reference supports `kubectl create cronjob NAME --image=image --schedule=... -- [COMMAND] [args...]`. ([Kubernetes][3])

List:

```bash
kubectl get cronjobs
kubectl get cj
kubectl get cronjobs -A
```

Describe:

```bash
kubectl describe cronjob <name> -n <namespace>
```

Show YAML:

```bash
kubectl get cronjob <name> -n <namespace> -o yaml
```

List Jobs created by CronJob:

```bash
kubectl get jobs -n <namespace>
```

Get latest Job:

```bash
kubectl get jobs -n <namespace> \
  --sort-by=.metadata.creationTimestamp
```

Logs from a Job:

```bash
kubectl logs job/<job-name> -n <namespace>
```

Manual trigger:

```bash
kubectl create job <manual-job-name> \
  --from=cronjob/<cronjob-name> \
  -n <namespace>
```

Suspend:

```bash
kubectl patch cronjob <name> -n <namespace> \
  -p '{"spec":{"suspend":true}}'
```

Resume:

```bash
kubectl patch cronjob <name> -n <namespace> \
  -p '{"spec":{"suspend":false}}'
```

Delete CronJob:

```bash
kubectl delete cronjob <name> -n <namespace>
```

Kubernetes says deleting a CronJob removes the Jobs and Pods it created and prevents future Jobs. ([Kubernetes][2])

---

# 38. Full hands-on sequence

```bash
kubectl create namespace cronjob-lab
```

Create a safe one-minute CronJob:

```bash
cat > cronjob-safe.yaml <<'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: safe-cron
  namespace: cronjob-lab
spec:
  schedule: "* * * * *"
  timeZone: "Etc/UTC"
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 60
  suspend: false
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 3

  jobTemplate:
    spec:
      backoffLimit: 1
      activeDeadlineSeconds: 120
      ttlSecondsAfterFinished: 600
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: task
              image: busybox:1.37
              command:
                - sh
                - -c
                - |
                  set -e
                  echo "scheduled task started at $(date)"
                  sleep 10
                  echo "scheduled task completed at $(date)"
EOF

kubectl apply -f cronjob-safe.yaml
```

Watch it create Jobs:

```bash
kubectl get cronjob -n cronjob-lab
kubectl get jobs -n cronjob-lab --watch
```

Inspect latest Job:

```bash
JOB=$(kubectl get jobs -n cronjob-lab \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1:].metadata.name}')

kubectl describe job "$JOB" -n cronjob-lab
kubectl logs job/"$JOB" -n cronjob-lab
```

Manually trigger:

```bash
kubectl create job manual-safe-$(date +%s) \
  --from=cronjob/safe-cron \
  -n cronjob-lab
```

Suspend:

```bash
kubectl patch cronjob safe-cron -n cronjob-lab \
  -p '{"spec":{"suspend":true}}'
```

Resume:

```bash
kubectl patch cronjob safe-cron -n cronjob-lab \
  -p '{"spec":{"suspend":false}}'
```

Cleanup:

```bash
kubectl delete namespace cronjob-lab
```

---

# 39.  mental model

A CronJob is a **schedule controller**, not a task execution engine.

It continuously asks:

```text
Is it time to create a Job?
Was a scheduled time missed?
Is the CronJob suspended?
Is another Job still running?
What does concurrencyPolicy require?
Is the missed run still within startingDeadlineSeconds?
How many successful/failed Jobs should be retained?
```

Then each created Job asks:

```text
How many Pods should run?
Did the Pod succeed?
Did it fail?
Should it retry?
Has backoffLimit been exceeded?
Has activeDeadlineSeconds been exceeded?
```

Best summary:

```text
CronJob = schedule
Job = completion/retry
Pod = runtime execution
Container = actual command
```

Production-grade CronJobs should almost always define:

```yaml
spec:
  schedule: "..."
  timeZone: "Etc/UTC"
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: <sane value>
  successfulJobsHistoryLimit: <small number>
  failedJobsHistoryLimit: <enough for debugging>
  jobTemplate:
    spec:
      backoffLimit: <controlled retry>
      activeDeadlineSeconds: <max runtime>
      ttlSecondsAfterFinished: <cleanup window>
      template:
        spec:
          restartPolicy: Never
          containers:
            - resources:
                requests:
                  cpu: ...
                  memory: ...
                limits:
                  memory: ...
```

The senior-level rule:

```text
Every CronJob must be designed as at-least-once, maybe-late, maybe-skipped, maybe-duplicated, and maybe-interrupted.
```

So the workload must be idempotent, bounded, observable, retry-safe, and safe under the chosen concurrency policy.

[1]: https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/ "CronJob | Kubernetes"
[2]: https://kubernetes.io/docs/tasks/job/automated-tasks-with-cron-jobs/ "Running Automated Tasks with a CronJob | Kubernetes"
[3]: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_cronjob/ "kubectl create cronjob | Kubernetes"
