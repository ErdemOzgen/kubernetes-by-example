# Kubernetes Job 

A **Job** is the Kubernetes workload object for **run-to-completion work**. Unlike a Deployment, DaemonSet, or StatefulSet, a Job is not trying to keep an application running forever. It starts one or more Pods, waits until the required number of Pods finish successfully, and then marks itself **Complete**. If Pods fail, the Job controller can retry them according to retry policy. Kubernetes describes Jobs as one-off tasks that run to completion and stop. ([Kubernetes][1])

Mental model:

```text
Deployment  = keep N Pods running forever
DaemonSet   = keep 1 Pod running on every eligible node
StatefulSet = keep stable stateful replicas running
Job         = run task until success or failure
CronJob     = create Jobs on a schedule
```

---

# 1. What a Job is for

Use a Job for tasks like:

```text
Database migration
One-time data import
Batch processing
Image/video processing
Report generation
Backup execution
ETL task
ML training task
Security scan
CI/CD test runner
One-off maintenance task
```

A Job creates Pods and keeps retrying execution until the specified number of successful completions is reached; deleting the Job also deletes the Pods it created. ([Kubernetes][1])

---

# 2. Job vs Deployment

## Deployment

A Deployment is for long-running services:

```text
Run this web API continuously.
If a Pod dies, replace it forever.
```

Example:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 3
```

Use it for:

```text
Web APIs
Frontend apps
Long-running workers
Stateless services
```

---

## Job

A Job is for finite execution:

```text
Run this script until it succeeds.
Then stop.
```

Example:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: myapp:1.0
          command: ["python", "manage.py", "migrate"]
```

Use it for:

```text
One-time or bounded work
Tasks with a clear success/failure result
Batch jobs
Parallel processing
```

---

# 3. Minimal Job YAML

Create `job-basic.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: hello-job
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
              echo "Job started"
              date
              sleep 5
              echo "Job completed"
```

Apply:

```bash
kubectl apply -f job-basic.yaml
```

Check:

```bash
kubectl get jobs
kubectl get pods
kubectl logs job/hello-job
```

Expected lifecycle:

```text
Pod starts
Container runs command
Container exits with code 0
Pod phase becomes Succeeded
Job condition becomes Complete
```

Check detailed status:

```bash
kubectl describe job hello-job
```

Delete:

```bash
kubectl delete job hello-job
```

### Repository example: `simple.yaml`

This is the actual file in the `Job/` directory:

```yaml
---
# https://kubernetes.io/docs/concepts/workloads/controllers/jobs-run-to-completion/
apiVersion: batch/v1
kind: Job
metadata:
  name: jobs-simple-job
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - command: ["perl", "-Mbignum=bpi", "-wle", "print bpi(2000)"]
          image: perl
          name: jobs-simple-container
```

**What this does:**

| Field | Detail |
|---|---|
| `image: perl` | Uses the official Perl image from Docker Hub |
| `command` | Runs a one-liner that computes π to 2000 decimal places using the `bignum` module |
| `restartPolicy: Never` | If the container fails, the Job controller creates a new Pod instead of restarting in place |
| No `completions` or `parallelism` | Defaults to 1 completion, 1 Pod at a time — the simplest Job pattern |
| No `ttlSecondsAfterFinished` | The Job and its Pod persist after completion until manually deleted |

**The computation:**

```text
perl -Mbignum=bpi -wle 'print bpi(2000)'
```

- `-Mbignum=bpi` imports the `bpi` function which computes π with arbitrary precision
- `bpi(2000)` returns π to 2000 decimal places
- The output goes to stdout and is captured in Pod logs

**Apply and retrieve the result:**

```bash
kubectl apply -f simple.yaml

# Wait for the Job to complete
kubectl get job jobs-simple-job

# Read the computed value of π
kubectl logs job/jobs-simple-job

# Clean up
kubectl delete -f simple.yaml
```

**Expected output (first few digits):**

```text
3.14159265358979323846264338327950288419716939937510...
```

The Job prints 2000 digits of π, then exits 0. The Pod phase becomes `Succeeded` and the Job condition becomes `Complete`.

---

# 4. Job object structure

A Job usually looks like this:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: example-job
spec:
  completions: 1
  parallelism: 1
  backoffLimit: 3
  activeDeadlineSeconds: 300
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: busybox:1.37
          command: ["sh", "-c", "echo work && sleep 10"]
```

Important fields:

| Field                     | Meaning                                    |
| ------------------------- | ------------------------------------------ |
| `spec.template`           | Pod template used by the Job               |
| `restartPolicy`           | Must be `Never` or `OnFailure` for Jobs    |
| `completions`             | Number of successful Pods required         |
| `parallelism`             | Maximum number of Pods running at once     |
| `backoffLimit`            | Retry budget before Job fails              |
| `activeDeadlineSeconds`   | Maximum wall-clock runtime                 |
| `ttlSecondsAfterFinished` | Cleanup delay after completion/failure     |
| `completionMode`          | `NonIndexed` or `Indexed`                  |
| `podFailurePolicy`        | Advanced failure classification            |
| `backoffLimitPerIndex`    | Per-index retry budget for Indexed Jobs    |
| `successPolicy`           | Advanced success criteria for Indexed Jobs |

---

# 5. `restartPolicy`: `Never` vs `OnFailure`

For Jobs, the Pod template restart policy should be either:

```yaml
restartPolicy: Never
```

or:

```yaml
restartPolicy: OnFailure
```

The Kubernetes Job docs explicitly call out that if a container fails and `restartPolicy: OnFailure` is used, the Pod stays on the node and the container is restarted locally; if the whole Pod fails or `restartPolicy: Never` is used, the Job controller creates a new Pod. ([Kubernetes][1])

---

## `restartPolicy: Never`

```yaml
restartPolicy: Never
```

Behavior:

```text
Container fails
Pod becomes Failed
Job controller creates a new Pod
Old failed Pod remains visible for debugging
```

This is usually better for debugging because you can inspect each failed attempt as a separate Pod.

Example:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: never-retry-job
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: fail
          image: busybox:1.37
          command: ["sh", "-c", "echo failing && exit 1"]
```

---

## `restartPolicy: OnFailure`

```yaml
restartPolicy: OnFailure
```

Behavior:

```text
Container fails
Same Pod remains
Container restarts inside same Pod
Job retry accounting includes container restarts
```

Example:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: onfailure-job
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: maybe-fail
          image: busybox:1.37
          command: ["sh", "-c", "echo attempt && exit 1"]
```

Senior recommendation:

```text
Use restartPolicy: Never for most batch/CI/ETL/migration jobs.
Use restartPolicy: OnFailure only when retrying inside the same Pod is acceptable.
```

---

# 6. Job status

Run:

```bash
kubectl get jobs
```

Example:

```text
NAME        STATUS     COMPLETIONS   DURATION   AGE
hello-job   Complete   1/1           7s         1m
```

Useful commands:

```bash
kubectl describe job hello-job
kubectl get job hello-job -o yaml
kubectl get pods -l job-name=hello-job
kubectl logs job/hello-job
```

A Job has two terminal conditions: `Complete` for success and `Failed` for failure. Kubernetes marks a Job failed for reasons such as exceeding `backoffLimit`, exceeding `activeDeadlineSeconds`, failed indexes in Indexed Jobs, exceeding `maxFailedIndexes`, or matching a `podFailurePolicy` rule with `FailJob`. ([Kubernetes][1])

---

# 7. Non-parallel Job

This is the simplest Job.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: simple-backup
spec:
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
              echo "Taking backup"
              sleep 10
              echo "Backup complete"
```

Apply:

```bash
kubectl apply -f simple-backup.yaml
```

Watch:

```bash
kubectl get pods -l job-name=simple-backup -w
```

Logs:

```bash
kubectl logs job/simple-backup
```

If both `completions` and `parallelism` are unset, Kubernetes defaults both to `1`. ([Kubernetes][1])

---

# 8. Fixed completion count Job

Use this when you need **N successful completions**.

Example: process 10 independent chunks, running 3 at a time.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: fixed-completion-job
spec:
  completions: 10
  parallelism: 3
  backoffLimit: 4
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              echo "Processing one unit of work"
              sleep $((RANDOM % 10 + 1))
              echo "Done"
```

Apply:

```bash
kubectl apply -f fixed-completion-job.yaml
```

Watch:

```bash
kubectl get job fixed-completion-job -w
kubectl get pods -l job-name=fixed-completion-job -w
```

Meaning:

```text
completions: 10  → need 10 successful Pods total
parallelism: 3   → run at most 3 Pods at the same time
```

For fixed completion count Jobs, Kubernetes considers the Job complete when `.spec.completions` Pods have succeeded; when `.spec.parallelism` is set, Kubernetes limits how many Pods run concurrently. ([Kubernetes][1])

---

# 9. Work queue Job

Use this when Pods pull work from an external queue.

Example:

```text
Queue has 1 million messages.
Run 20 workers.
Each worker pulls messages until queue is empty.
When one worker exits successfully, no new Pods are started.
Remaining workers finish and exit.
```

Manifest:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: queue-worker-job
spec:
  parallelism: 5
  backoffLimit: 3
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              echo "Pretend to pull tasks from queue"
              sleep $((RANDOM % 20 + 5))
              echo "Queue appears empty; exiting successfully"
```

Important: for work queue Jobs, leave `completions` unset and set `parallelism`. Kubernetes documents that work queue Jobs do not specify `.spec.completions`, default to `.spec.parallelism`, and the Pods coordinate among themselves or through an external service to determine what work remains. ([Kubernetes][1])

Senior rule:

```text
For work queue Jobs, your application must implement queue coordination correctly.
Kubernetes does not distribute individual work items for you.
```

---

# 10. `parallelism`

```yaml
parallelism: 5
```

This controls the maximum number of Pods the Job should run at once.

Example:

```yaml
spec:
  completions: 100
  parallelism: 10
```

Meaning:

```text
Need 100 successful completions.
Run up to 10 at a time.
```

Actual parallelism may be lower than requested if the cluster lacks resources, quotas block Pod creation, the Job controller throttles creation after failures, or remaining completions are fewer than the requested parallelism. Kubernetes also notes that setting `parallelism: 0` effectively pauses the Job until it is increased. ([Kubernetes][1])

Pause a Job:

```bash
kubectl patch job fixed-completion-job -p '{"spec":{"parallelism":0}}'
```

Resume with 3 workers:

```bash
kubectl patch job fixed-completion-job -p '{"spec":{"parallelism":3}}'
```

---

# 11. `completions`

```yaml
completions: 10
```

This controls how many successful Pod completions are needed.

Patterns:

```yaml
# One successful Pod required
completions: 1
parallelism: 1
```

```yaml
# Ten total successes, three at a time
completions: 10
parallelism: 3
```

```yaml
# Work queue pattern: no completions field
parallelism: 5
```

Senior warning:

```text
completions is not the same as replicas.
A completed Pod does not keep running.
```

---

# 12. `backoffLimit`

```yaml
backoffLimit: 3
```

This is the retry budget before Kubernetes considers the Job failed.

Example failing Job:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: failing-job
spec:
  backoffLimit: 3
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
```

Apply:

```bash
kubectl apply -f failing-job.yaml
```

Watch:

```bash
kubectl get pods -l job-name=failing-job -w
kubectl describe job failing-job
```

Kubernetes defaults `.spec.backoffLimit` to `6`, unless `backoffLimitPerIndex` is specified for an Indexed Job. Failed Pods are recreated using exponential backoff starting at 10 seconds, then 20 seconds, 40 seconds, and so on, capped at six minutes. ([Kubernetes][1])

Important:

```text
backoffLimit counts retries, not business-level attempts.
With restartPolicy: OnFailure, container restarts can count.
With restartPolicy: Never, failed Pods count.
```

---

# 13. `activeDeadlineSeconds`

```yaml
activeDeadlineSeconds: 300
```

This is the maximum wall-clock runtime for the whole Job.

Example:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: timeout-job
spec:
  activeDeadlineSeconds: 20
  backoffLimit: 10
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: slow
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              echo "Starting long task"
              sleep 300
```

After 20 seconds, Kubernetes terminates running Pods and marks the Job failed with reason `DeadlineExceeded`. The Job-level `activeDeadlineSeconds` applies to total Job duration and takes precedence over `backoffLimit`. ([Kubernetes][1])

Senior rule:

```text
Use activeDeadlineSeconds for bounded jobs.
Do not allow broken ETL, scans, migrations, or tests to run forever.
```

### Repository example: `spec.activeDeadlineSeconds/timeout.yaml`

This is the actual file in the `Job/spec.activeDeadlineSeconds/` directory:

```yaml
---
# https://kubernetes.io/docs/concepts/workloads/controllers/jobs-run-to-completion/
apiVersion: batch/v1
kind: Job
metadata:
  name: jobs-timeout-job
spec:
  activeDeadlineSeconds: 100
  template:
    spec:
      restartPolicy: Never
      containers:
        - command: ["perl", "-Mbignum=bpi", "-wle", "print bpi(2000)"]
          image: perl
          name: jobs-timeout-container
```

**What this does:**

| Field | Detail |
|---|---|
| `activeDeadlineSeconds: 100` | Kubernetes will terminate the Job and its Pods if they have not finished within 100 seconds |
| Same `perl bpi(2000)` command as `simple.yaml` | On a fast node this normally finishes well under 100 s; on a slow or cold node it may be killed |
| No `ttlSecondsAfterFinished` | The Job object persists after it finishes or times out |

**Two possible outcomes:**

```text
Fast node  → Job finishes before deadline  → status: Complete
Slow node  → Deadline exceeded             → status: Failed, reason: DeadlineExceeded
```

**Apply and observe:**

```bash
kubectl apply -f spec.activeDeadlineSeconds/timeout.yaml

# Watch the Job status in real time
kubectl get job jobs-timeout-job -w

# If it times out, describe shows the reason
kubectl describe job jobs-timeout-job

# Clean up
kubectl delete -f spec.activeDeadlineSeconds/timeout.yaml
```

**Describe output when deadline is exceeded:**

```text
Conditions:
  Type    Status  Reason
  ----    ------  ------
  Failed  True    DeadlineExceeded
```

---

# 14. Cleanup with `ttlSecondsAfterFinished`

By default, completed Jobs and their Pods may remain so you can inspect status and logs. But in production, thousands of completed Jobs can put pressure on the API server.

Use:

```yaml
ttlSecondsAfterFinished: 600
```

Example:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: cleanup-demo
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: task
          image: busybox:1.37
          command: ["sh", "-c", "echo done"]
```

This makes the Job eligible for automatic deletion 300 seconds after it reaches `Complete` or `Failed`. The TTL controller deletes the Job cascadingly, including dependent Pods. ([Kubernetes][2])

Production recommendation:

```text
Always set ttlSecondsAfterFinished for unmanaged one-off Jobs.
Use longer TTL for debugging-heavy jobs.
Use shorter TTL for high-volume jobs.
```

Example values:

```yaml
# Keep for 10 minutes
ttlSecondsAfterFinished: 600

# Keep for 1 hour
ttlSecondsAfterFinished: 3600

# Keep for 1 day
ttlSecondsAfterFinished: 86400
```

### Repository example: `spec.ttlSecondsAfterFinished/timetolive.yaml`

This is the actual file in the `Job/spec.ttlSecondsAfterFinished/` directory:

```yaml
---
# https://kubernetes.io/docs/concepts/workloads/controllers/jobs-run-to-completion/
apiVersion: batch/v1
kind: Job
metadata:
  name: jobs-timetolive-job
spec:
  ttlSecondsAfterFinished: 100
  template:
    spec:
      containers:
        - command: ["perl", "-Mbignum=bpi", "-wle", "print bpi(2000)"]
          image: perl
          name: jobs-timetolive-container
      restartPolicy: Never
```

**What this does:**

| Field | Detail |
|---|---|
| `ttlSecondsAfterFinished: 100` | 100 seconds after the Job reaches `Complete` or `Failed`, the TTL controller automatically deletes it along with its Pods |
| Same `perl bpi(2000)` command | Job finishes quickly on most nodes |
| No `activeDeadlineSeconds` | The Job can run as long as it needs to complete |

**Lifecycle with TTL:**

```text
0s    → Job created, Pod starts
~30s  → Computation finishes, Pod exits 0
~30s  → Job status: Complete
~130s → TTL expires, Job and Pod are automatically deleted
```

**Apply and watch the automatic cleanup:**

```bash
kubectl apply -f spec.ttlSecondsAfterFinished/timetolive.yaml

# Watch until the Job disappears on its own
kubectl get job jobs-timetolive-job -w

# After ~100 seconds past completion it will no longer exist
kubectl get job jobs-timetolive-job
# Error from server (NotFound): ...
```

**Key difference from `simple.yaml`:**

```text
simple.yaml        → Job persists forever after completion (manual cleanup needed)
timetolive.yaml    → Job auto-deletes 100 seconds after it finishes
```

In production, always set `ttlSecondsAfterFinished` for any Job that is not managed by a CronJob, to prevent resource accumulation in the API server.

---

# 15. Indexed Jobs

An **Indexed Job** gives each completion a stable numeric index.

Use it when each worker should process a deterministic shard:

```text
index 0 → process shard 0
index 1 → process shard 1
index 2 → process shard 2
...
```

Example:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: indexed-job
spec:
  completions: 5
  parallelism: 2
  completionMode: Indexed
  backoffLimit: 3
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: python:3.12-alpine
          command:
            - python3
            - -c
            - |
              import os, time
              index = os.environ["JOB_COMPLETION_INDEX"]
              print(f"Processing shard {index}")
              time.sleep(5)
              print(f"Finished shard {index}")
```

Apply:

```bash
kubectl apply -f indexed-job.yaml
```

Logs:

```bash
kubectl logs -l job-name=indexed-job --prefix=true
```

For Indexed Jobs, Pods receive indexes from `0` to `.spec.completions - 1`; the index is exposed through the Pod annotation, Pod label in newer clusters, hostname pattern, and `JOB_COMPLETION_INDEX` environment variable. The Job is complete when one Pod for every index succeeds. ([Kubernetes][1])

Senior use cases:

```text
ML training shards
Integration test suites
Static data partitions
File chunk processing
Parameter sweep simulations
Distributed batch workers
```

---

# 16. `NonIndexed` vs `Indexed`

## `NonIndexed`

Default mode.

```yaml
completionMode: NonIndexed
```

or simply omit it.

Meaning:

```text
Any successful Pod counts.
All completions are equivalent.
```

Use when every worker does the same type of work.

---

## `Indexed`

```yaml
completionMode: Indexed
```

Meaning:

```text
Each Pod has a specific index.
Each index must succeed once.
```

Use when workers need deterministic assignment.

Kubernetes marks `NonIndexed` as the default completion mode. In `Indexed` mode, the Job is complete only when every required index has one successful Pod. ([Kubernetes][1])

---

# 17. `backoffLimitPerIndex`

For Indexed Jobs, normal `backoffLimit` is global. One bad index can consume the whole retry budget. `backoffLimitPerIndex` fixes that.

Example:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: indexed-backoff-job
spec:
  completions: 10
  parallelism: 3
  completionMode: Indexed
  backoffLimitPerIndex: 1
  maxFailedIndexes: 2
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: python:3.12-alpine
          command:
            - python3
            - -c
            - |
              import os, sys
              i = int(os.environ["JOB_COMPLETION_INDEX"])
              print(f"index={i}")
              if i in [2, 7]:
                  print("intentional failure")
                  sys.exit(1)
              print("success")
```

Meaning:

```text
Each index gets 1 tolerated failure.
If more than 2 indexes fail, fail the whole Job.
```

`backoffLimitPerIndex` is stable in Kubernetes v1.33. It lets you specify tolerated Pod failures per index, and `maxFailedIndexes` can cap how many failed indexes are allowed before the entire Job terminates. ([Kubernetes][1])

Senior use case:

```text
Run 100 test suites.
Suite 17 fails consistently.
Do not let suite 17 consume the global retry budget.
Let the other suites run.
```

---

# 18. `podFailurePolicy`

`podFailurePolicy` lets you classify failures.

Example problem:

```text
Exit code 1 = transient error, retry
Exit code 42 = application bug, fail Job immediately
Node eviction = infrastructure disruption, ignore for retry budget
```

Example:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pod-failure-policy-job
spec:
  completions: 5
  parallelism: 2
  backoffLimit: 6
  podFailurePolicy:
    rules:
      - action: FailJob
        onExitCodes:
          containerName: worker
          operator: In
          values: [42]
      - action: Ignore
        onPodConditions:
          - type: DisruptionTarget
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: bash:5
          command: ["bash", "-c"]
          args:
            - |
              echo "simulate non-retriable bug"
              exit 42
```

Important requirements:

```text
podFailurePolicy requires restartPolicy: Never.
Rules are evaluated in order.
When a rule matches, later rules are ignored.
```

Kubernetes documents `podFailurePolicy` as stable from v1.31 and says it can handle Pod failures based on container exit codes and Pod conditions. Supported actions include `FailJob`, `Ignore`, `Count`, and `FailIndex`; the field requires `restartPolicy: Never`. ([Kubernetes][1])

Senior use cases:

```text
Do not retry permanent bugs.
Do not count node disruption as application failure.
Fail one index instead of the whole Indexed Job.
Control expensive retry behavior.
```

---

# 19. `successPolicy`

`successPolicy` is for Indexed Jobs where “success” does not necessarily mean every index succeeded.

Example use cases:

```text
Simulation where any one successful candidate is enough
Leader-worker job where leader success determines overall success
Hyperparameter search where first good result is sufficient
```

Example:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: success-policy-job
spec:
  completions: 5
  parallelism: 5
  completionMode: Indexed
  successPolicy:
    rules:
      - succeededIndexes: 0,2-4
        succeededCount: 1
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: python:3.12-alpine
          command:
            - python3
            - -c
            - |
              import os, sys
              i = int(os.environ["JOB_COMPLETION_INDEX"])
              print(f"index={i}")
              if i == 2:
                  sys.exit(0)
              sys.exit(1)
```

Meaning:

```text
If any one of indexes 0, 2, 3, or 4 succeeds, the overall Job can be marked successful.
```

Kubernetes supports `.spec.successPolicy` for Indexed Jobs, allowing success based on `succeededIndexes`, `succeededCount`, or both. If both a success policy and a terminating policy such as `backoffLimit` or `podFailurePolicy` apply, Kubernetes respects the terminating policy and ignores the success policy. ([Kubernetes][1])

---

# 20. Job lifecycle

A typical successful Job lifecycle:

```text
1. User creates Job
2. Job controller creates Pod(s)
3. Scheduler assigns Pod(s) to nodes
4. Kubelet starts containers
5. Containers exit with code 0
6. Pods become Succeeded
7. Job increments succeeded count
8. Required completions reached
9. Job condition becomes Complete
10. Optional TTL cleanup deletes Job and Pods
```

A failed Job lifecycle:

```text
1. User creates Job
2. Pod starts
3. Container exits non-zero
4. Pod becomes Failed, or container restarts depending on restartPolicy
5. Job retries according to backoffLimit
6. Retry budget exhausted
7. Job condition becomes Failed
8. Running Pods are terminated
9. Optional TTL cleanup deletes Job and Pods
```

When a Job completes, Kubernetes does not create more Pods, but usually keeps completed Pods so you can inspect logs and diagnostics; deleting the Job deletes the Pods it created. ([Kubernetes][1])

---

# 21. Hands-on lab: successful Job

Create namespace:

```bash
kubectl create namespace job-lab
```

Create Job:

```bash
cat > job-success.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: success-job
  namespace: job-lab
spec:
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
              echo "Starting successful job"
              sleep 5
              echo "Finished successfully"
EOF
```

Apply:

```bash
kubectl apply -f job-success.yaml
```

Watch:

```bash
kubectl get jobs -n job-lab -w
```

Check Pod:

```bash
kubectl get pods -n job-lab -l job-name=success-job
```

Logs:

```bash
kubectl logs job/success-job -n job-lab
```

Describe:

```bash
kubectl describe job success-job -n job-lab
```

---

# 22. Hands-on lab: failing Job and retries

Create:

```bash
cat > job-fail.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: fail-job
  namespace: job-lab
spec:
  backoffLimit: 2
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
              echo "This job will fail"
              exit 1
EOF
```

Apply:

```bash
kubectl apply -f job-fail.yaml
```

Watch:

```bash
kubectl get pods -n job-lab -l job-name=fail-job -w
```

Inspect:

```bash
kubectl describe job fail-job -n job-lab
kubectl get pods -n job-lab -l job-name=fail-job
```

Logs from failed Pods:

```bash
for pod in $(kubectl get pods -n job-lab -l job-name=fail-job -o name); do
  echo "---- $pod ----"
  kubectl logs -n job-lab "$pod" || true
done
```

Expected:

```text
Multiple failed Pods
Job eventually Failed
Reason related to BackoffLimitExceeded
```

---

# 23. Hands-on lab: parallel Job

Create:

```bash
cat > job-parallel.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: parallel-job
  namespace: job-lab
spec:
  completions: 8
  parallelism: 3
  backoffLimit: 3
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              echo "Worker started on $(hostname)"
              sleep $((RANDOM % 10 + 1))
              echo "Worker completed"
EOF
```

Apply:

```bash
kubectl apply -f job-parallel.yaml
```

Watch:

```bash
kubectl get job parallel-job -n job-lab -w
```

In another terminal:

```bash
kubectl get pods -n job-lab -l job-name=parallel-job -w
```

Expected:

```text
At most 3 Pods running concurrently.
Eventually 8 successful completions.
```

---

# 24. Hands-on lab: Indexed Job

Create:

```bash
cat > job-indexed.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: indexed-job
  namespace: job-lab
spec:
  completions: 6
  parallelism: 3
  completionMode: Indexed
  backoffLimit: 3
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: python:3.12-alpine
          command:
            - python3
            - -c
            - |
              import os, time
              idx = os.environ["JOB_COMPLETION_INDEX"]
              print(f"Processing shard {idx}")
              time.sleep(3)
              print(f"Completed shard {idx}")
EOF
```

Apply:

```bash
kubectl apply -f job-indexed.yaml
```

Watch:

```bash
kubectl get pods -n job-lab -l job-name=indexed-job -w
```

Show indexes:

```bash
kubectl get pods -n job-lab -l job-name=indexed-job \
  -o custom-columns=NAME:.metadata.name,INDEX:.metadata.annotations.batch\\.kubernetes\\.io/job-completion-index,PHASE:.status.phase
```

Logs:

```bash
kubectl logs -n job-lab -l job-name=indexed-job --prefix=true
```

---

# 25. Job with ConfigMap

Create ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: job-config
data:
  INPUT_PATH: "/data/input"
  OUTPUT_PATH: "/data/output"
```

Job:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: config-job
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: busybox:1.37
          envFrom:
            - configMapRef:
                name: job-config
          command:
            - sh
            - -c
            - |
              echo "Input: $INPUT_PATH"
              echo "Output: $OUTPUT_PATH"
```

Apply:

```bash
kubectl apply -f configmap.yaml
kubectl apply -f config-job.yaml
```

---

# 26. Job with Secret

Secret:

```bash
kubectl create secret generic db-secret \
  --from-literal=DATABASE_URL='postgres://user:password@db:5432/app'
```

Job:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: migration-job
spec:
  backoffLimit: 1
  activeDeadlineSeconds: 300
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: myapp:1.0.0
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: db-secret
                  key: DATABASE_URL
          command:
            - sh
            - -c
            - |
              echo "Running migration"
              ./migrate
```

Senior warning:

```text
Do not print secrets in Job logs.
Completed Job Pods can preserve logs until cleanup.
```

---

# 27. Job with PVC

Use this when a Job needs persistent input/output.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pvc-processing-job
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: processor
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              echo "processing" > /work/output.txt
              cat /work/output.txt
          volumeMounts:
            - name: workdir
              mountPath: /work
      volumes:
        - name: workdir
          persistentVolumeClaim:
            claimName: workdir-pvc
```

Be careful with parallel Jobs and shared PVCs:

```text
ReadWriteOnce volumes may not mount across multiple nodes.
Concurrent writers can corrupt output unless the app handles locking.
For parallel output, prefer object storage or per-index output paths.
```

---

# 28. Job selector: usually do not set it

For Jobs, you normally do **not** set `.spec.selector`.

Bad unnecessary pattern:

```yaml
spec:
  selector:
    matchLabels:
      app: my-job
```

Usually correct:

```yaml
spec:
  template:
    spec:
      containers:
        - name: worker
```

The Kubernetes Job docs say `.spec.selector` is optional and that in almost all cases you should not specify it manually. ([Kubernetes][1])

Senior rule:

```text
Let Kubernetes generate Job selectors unless you have a very specific controller-level reason.
Manual Job selectors can cause adoption/conflict bugs.
```

---

# 29. Job vs CronJob

A Job runs now. A CronJob creates Jobs on a schedule.

```text
Job     = run once
CronJob = run repeatedly according to cron schedule
```

Example CronJob:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nightly-backup
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      backoffLimit: 3
      ttlSecondsAfterFinished: 3600
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
                  echo "nightly backup"
```

Kubernetes describes CronJobs as objects that create Jobs on a repeating schedule, useful for regular actions such as backups and report generation. ([Kubernetes][3])

Use Job when:

```text
Run migration once now.
Run scan once now.
Run batch import once now.
```

Use CronJob when:

```text
Run backup every night.
Run cleanup every hour.
Generate reports every Monday.
```

---

# 30. Production-grade Job example: database migration

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: payment-db-migration-20260516
  namespace: payments
  labels:
    app.kubernetes.io/name: payment-api
    app.kubernetes.io/component: migration
    app.kubernetes.io/part-of: payment-platform
spec:
  backoffLimit: 1
  activeDeadlineSeconds: 600
  ttlSecondsAfterFinished: 86400

  template:
    metadata:
      labels:
        app.kubernetes.io/name: payment-api
        app.kubernetes.io/component: migration
    spec:
      restartPolicy: Never
      serviceAccountName: payment-migration

      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault

      containers:
        - name: migrate
          image: registry.example.com/payments/payment-api:1.8.3
          imagePullPolicy: IfNotPresent

          command:
            - sh
            - -c
            - |
              set -euo pipefail
              echo "Starting database migration"
              ./bin/migrate up
              echo "Migration complete"

          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: payment-db
                  key: url

          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              memory: "512Mi"

          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
```

Why these choices matter:

| Field                            | Reason                                          |
| -------------------------------- | ----------------------------------------------- |
| `backoffLimit: 1`                | Avoid repeatedly applying a dangerous migration |
| `activeDeadlineSeconds: 600`     | Bound migration runtime                         |
| `ttlSecondsAfterFinished: 86400` | Keep status/logs for 1 day                      |
| `restartPolicy: Never`           | Make failed attempts visible                    |
| dedicated `serviceAccountName`   | Least privilege                                 |
| resource requests                | Predictable scheduling                          |
| memory limit                     | Prevent runaway memory                          |
| non-root security                | Reduce runtime risk                             |

Senior migration rule:

```text
Jobs can retry.
Database migrations must be idempotent or retry-safe.
If not idempotent, use very low backoffLimit and app-level locking.
```

---

# 31. Production-grade Job example: parallel scan

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: artifact-security-scan
  namespace: security
spec:
  completions: 20
  parallelism: 5
  completionMode: Indexed
  backoffLimitPerIndex: 2
  maxFailedIndexes: 3
  activeDeadlineSeconds: 7200
  ttlSecondsAfterFinished: 86400

  template:
    spec:
      restartPolicy: Never
      serviceAccountName: scanner

      containers:
        - name: scanner
          image: registry.example.com/security/scanner:2.4.1
          command:
            - sh
            - -c
            - |
              set -euo pipefail
              echo "Running scan shard ${JOB_COMPLETION_INDEX}"
              ./scanner --shard "${JOB_COMPLETION_INDEX}" --total-shards 20

          env:
            - name: SCAN_TARGET
              value: "artifact-registry-prod"

          resources:
            requests:
              cpu: "1"
              memory: "1Gi"
            limits:
              memory: "2Gi"
```

This is a good Indexed Job pattern:

```text
20 shards total
5 concurrent workers
Each shard has independent retry budget
Fail entire Job if more than 3 shards fail
```

---

# 32. Debugging Jobs

Start with:

```bash
kubectl get jobs -A
kubectl describe job <job-name> -n <namespace>
kubectl get pods -n <namespace> -l job-name=<job-name>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
kubectl get events -n <namespace> --sort-by=.lastTimestamp
```

For all Pods of a Job:

```bash
kubectl logs job/<job-name> -n <namespace>
```

For failed Pods:

```bash
kubectl get pods -n <namespace> -l job-name=<job-name> \
  --field-selector=status.phase=Failed
```

Inspect status:

```bash
kubectl get job <job-name> -n <namespace> -o yaml
```

Look at:

```yaml
status:
  active:
  succeeded:
  failed:
  conditions:
```

---

# 33. Common Job failure modes

| Symptom                             | Likely cause                                       |
| ----------------------------------- | -------------------------------------------------- |
| `ImagePullBackOff`                  | Wrong image, bad tag, missing registry secret      |
| `CrashLoopBackOff` with `OnFailure` | Container keeps failing inside same Pod            |
| Many `Error` Pods                   | `restartPolicy: Never` and command exits non-zero  |
| `BackoffLimitExceeded`              | Retry budget exhausted                             |
| `DeadlineExceeded`                  | `activeDeadlineSeconds` exceeded                   |
| Pod `Pending`                       | No resources, taints, node selector, quota         |
| `CreateContainerConfigError`        | Bad ConfigMap/Secret/env reference                 |
| `OOMKilled`                         | Memory limit too low or memory leak                |
| Job never completes                 | Command never exits, queue workers not terminating |
| Job completed but logs gone         | TTL cleanup or Pod deletion                        |
| Parallel Job corrupts output        | Non-idempotent writes or shared storage conflict   |

---

# 34. Debugging `BackoffLimitExceeded`

```bash
kubectl describe job failing-job
```

Look for:

```text
BackoffLimitExceeded
```

Then inspect Pods:

```bash
kubectl get pods -l job-name=failing-job
```

Logs:

```bash
for pod in $(kubectl get pods -l job-name=failing-job -o name); do
  echo "---- $pod ----"
  kubectl logs "$pod" || true
done
```

Common root causes:

```text
Script exits non-zero
Missing env var
Database unavailable
Permission denied
Command path wrong
Image missing dependency
OOMKilled
```

---

# 35. Debugging `Pending` Jobs

```bash
kubectl describe pod <pod-name>
```

Look at events:

```text
Insufficient cpu
Insufficient memory
node(s) had untolerated taint
didn't match Pod's node affinity/selector
exceeded quota
```

Check quota:

```bash
kubectl get resourcequota -n <namespace>
kubectl describe resourcequota -n <namespace>
```

Check node resources:

```bash
kubectl describe nodes
```

Check taints:

```bash
kubectl describe node <node-name> | grep -i taints -A2
```

---

# 36. Debugging Jobs with multiple Pods

For a fixed completion count or Indexed Job:

```bash
kubectl get pods -l job-name=<job-name> \
  -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,NODE:.spec.nodeName,START:.status.startTime
```

For Indexed Jobs:

```bash
kubectl get pods -l job-name=<job-name> \
  -o custom-columns=NAME:.metadata.name,INDEX:.metadata.annotations.batch\\.kubernetes\\.io/job-completion-index,PHASE:.status.phase
```

Logs with prefixes:

```bash
kubectl logs -l job-name=<job-name> --prefix=true
```

---

# 37. Idempotency and retries

This is one of the most important senior-level Job topics.

Kubernetes may start the same logical work more than once. Even with `parallelism: 1`, `completions: 1`, and `restartPolicy: Never`, the same program can sometimes be started twice; if multiple completions and parallelism are used, multiple Pods can run concurrently, so the workload must tolerate concurrency. ([Kubernetes][1])

Therefore, Job workloads should be:

```text
Idempotent
Retry-safe
Concurrency-safe
Interrupt-safe
Observable
Bounded by deadlines
```

Bad migration script:

```bash
INSERT INTO users VALUES (...);
ALTER TABLE payments ADD COLUMN status TEXT;
```

Better:

```bash
CREATE TABLE IF NOT EXISTS ...
ALTER TABLE ... ADD COLUMN IF NOT EXISTS ...
Use migration locks
Record migration version
Make operations transactional where possible
```

Bad batch output:

```text
Every Pod writes to /output/result.json
```

Better:

```text
Pod index 0 writes /output/shard-0.json
Pod index 1 writes /output/shard-1.json
Aggregator combines results later
```

---

# 38. Jobs and observability

For production Jobs, always think about:

```text
How do I know it started?
How do I know it succeeded?
How do I know which shard failed?
Where are logs stored after TTL cleanup?
Do metrics include duration, success/failure, retries, records processed?
Is alerting based on Job failure?
```

Useful labels:

```yaml
metadata:
  labels:
    app.kubernetes.io/name: artifact-scanner
    app.kubernetes.io/component: batch
    batch.example.com/job-type: security-scan
```

Useful log fields:

```text
job_name
pod_name
completion_index
attempt
input_range
records_processed
duration_ms
exit_reason
```

Useful metrics:

```text
job_duration_seconds
job_records_processed_total
job_failed_records_total
job_retry_count
job_shard_success_total
job_shard_failure_total
```

---

# 39. Jobs and resource management

A parallel Job can consume a lot of capacity quickly.

Example:

```yaml
parallelism: 50
resources:
  requests:
    cpu: "1"
    memory: "2Gi"
```

Cluster impact:

```text
50 CPU cores requested
100 Gi memory requested
```

Senior checklist:

```text
Set requests.
Set memory limits.
Use ResourceQuota per namespace.
Use LimitRange defaults.
Use PriorityClass carefully.
Use parallelism to control blast radius.
Use activeDeadlineSeconds to avoid zombie cost.
```

---

# 40. Jobs and security

Baseline secure Job template:

```yaml
spec:
  template:
    spec:
      serviceAccountName: job-runner
      restartPolicy: Never
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: worker
          image: example/worker:1.0.0
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
```

But if the Job needs Kubernetes API access, keep `automountServiceAccountToken` enabled and grant minimal RBAC.

Example RBAC:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: job-runner
  namespace: batch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: job-runner
  namespace: batch
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: job-runner
  namespace: batch
subjects:
  - kind: ServiceAccount
    name: job-runner
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: job-runner
```

Senior rule:

```text
Do not run Jobs with cluster-admin just because they are temporary.
Temporary privileged Jobs are still privileged workloads.
```

---

# 41. Common mistakes

## Mistake 1: Using Deployment for finite work

Bad:

```yaml
kind: Deployment
```

for:

```text
database migration
one-time import
batch conversion
```

Use Job.

---

## Mistake 2: Not setting `ttlSecondsAfterFinished`

Completed Jobs accumulate.

Better:

```yaml
ttlSecondsAfterFinished: 3600
```

Kubernetes recommends setting TTL for finished Jobs, especially unmanaged Jobs, because lingering Jobs and Pods can cause API server pressure and cluster degradation. ([Kubernetes][1])

---

## Mistake 3: Dangerous retries

Bad:

```yaml
backoffLimit: 10
```

for non-idempotent migration.

Better:

```yaml
backoffLimit: 1
```

and make the migration script safe.

---

## Mistake 4: No deadline

Bad:

```yaml
spec:
  template:
    spec:
      containers:
        - command: ["./scan-everything"]
```

Better:

```yaml
activeDeadlineSeconds: 3600
```

---

## Mistake 5: Parallel workers writing same output

Bad:

```text
all workers write result.json
```

Better:

```text
worker index writes result-${JOB_COMPLETION_INDEX}.json
```

---

## Mistake 6: Assuming exactly-once execution

Kubernetes Jobs are not exactly-once execution systems.

Better assumption:

```text
At-least-once execution.
Possibly duplicate starts.
Application must be idempotent.
```

---

## Mistake 7: Setting manual selectors

Usually avoid:

```yaml
spec:
  selector:
```

Let Kubernetes generate the selector.

---

## Mistake 8: Using `OnFailure` and losing attempt visibility

With `OnFailure`, failures happen as restarts inside one Pod. With `Never`, each failed attempt is usually inspectable as its own Pod.

For debugging-heavy jobs:

```yaml
restartPolicy: Never
```

---

# 42. Useful commands

Create Job imperatively:

```bash
kubectl create job hello --image=busybox:1.37 -- echo "hello"
```

Create from CronJob:

```bash
kubectl create job manual-backup --from=cronjob/nightly-backup
```

List:

```bash
kubectl get jobs
kubectl get jobs -A
```

Watch:

```bash
kubectl get job <name> -w
```

Describe:

```bash
kubectl describe job <name>
```

Get Pods:

```bash
kubectl get pods -l job-name=<name>
```

Logs:

```bash
kubectl logs job/<name>
```

Logs all matching Pods:

```bash
kubectl logs -l job-name=<name> --prefix=true
```

Delete Job and Pods:

```bash
kubectl delete job <name>
```

Delete only completed Jobs:

```bash
kubectl delete job --field-selector status.successful=1
```

Patch parallelism:

```bash
kubectl patch job <name> -p '{"spec":{"parallelism":5}}'
```

Suspend Job:

```bash
kubectl patch job <name> -p '{"spec":{"suspend":true}}'
```

Resume Job:

```bash
kubectl patch job <name> -p '{"spec":{"suspend":false}}'
```

The Kubernetes docs note that suspending a Job deletes its active Pods until the Job is resumed. ([Kubernetes][1])

---

# 43. Full hands-on sequence

Run:

```bash
kubectl create namespace job-lab
```

Create a successful Job:

```bash
kubectl create job hello-job \
  --image=busybox:1.37 \
  -n job-lab \
  -- sh -c 'echo hello; sleep 3; echo done'
```

Watch:

```bash
kubectl get jobs -n job-lab -w
```

Logs:

```bash
kubectl logs job/hello-job -n job-lab
```

Create a failing Job:

```bash
cat > fail-job.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: fail-job
  namespace: job-lab
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: fail
          image: busybox:1.37
          command: ["sh", "-c", "echo fail; exit 1"]
EOF

kubectl apply -f fail-job.yaml
```

Inspect:

```bash
kubectl get pods -n job-lab -l job-name=fail-job
kubectl describe job fail-job -n job-lab
```

Create a parallel Indexed Job:

```bash
cat > indexed-job.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: indexed-job
  namespace: job-lab
spec:
  completions: 5
  parallelism: 2
  completionMode: Indexed
  backoffLimit: 2
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: python:3.12-alpine
          command:
            - python3
            - -c
            - |
              import os, time
              idx = os.environ["JOB_COMPLETION_INDEX"]
              print(f"worker index={idx}")
              time.sleep(3)
              print(f"done index={idx}")
EOF

kubectl apply -f indexed-job.yaml
```

Watch:

```bash
kubectl get jobs -n job-lab -w
kubectl get pods -n job-lab -l job-name=indexed-job -w
```

Clean up:

```bash
kubectl delete namespace job-lab
```

---

# 44. Senior-engineer mental model

A Job is a **completion controller**.

It continuously asks:

```text
How many completions are required?
How many Pods are currently active?
How many Pods succeeded?
How many Pods failed?
Should I create more Pods?
Should I retry?
Has the retry budget been exhausted?
Has the deadline been exceeded?
Can I mark the Job Complete or Failed?
Should TTL cleanup remove it?
```

Best summary:

```text
Job = run finite work reliably.
completions = how many successes are needed.
parallelism = how many Pods may run at once.
backoffLimit = how many failures are tolerated.
activeDeadlineSeconds = how long the Job may run.
ttlSecondsAfterFinished = how long to keep it after it ends.
completionMode: Indexed = deterministic shard assignment.
podFailurePolicy = classify failures intelligently.
```

For production, the most important rule is:

```text
Design every Job as at-least-once, retryable, interruptible, and observable.
```

A Job is not an exactly-once transaction engine. Kubernetes can retry, reschedule, duplicate-start, or terminate Pods. Your application logic must handle that safely.

[1]: https://kubernetes.io/docs/concepts/workloads/controllers/job/ "Jobs | Kubernetes"
[2]: https://kubernetes.io/docs/concepts/workloads/controllers/ttlafterfinished/ "Automatic Cleanup for Finished Jobs | Kubernetes"
[3]: https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/ "CronJob | Kubernetes"
