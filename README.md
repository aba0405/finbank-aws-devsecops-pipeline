# FinBank Digital — AWS-Native DevSecOps Pipeline

> Securing a financial institution's CI/CD pipeline by automating security
> validation **before** production deployment.

![Pipeline status](docs/screenshots/placeholder-pipeline-green.png)
<!-- Replace with a real screenshot of a successful pipeline run -->

---

## The business problem

**FinBank Digital** is a (fictional) financial services company running online
banking, personal loans, and digital payments. It ships 10–15 releases a week.
Before this project, the delivery process had failed in ways that are common —
and costly — for regulated companies:

- A vulnerable Docker image reached production.
- Hardcoded AWS credentials were committed to Git.
- Failed deployments caused customer-facing downtime.
- Security review was manual, so releases were slow and audits took weeks.
- Under deadline pressure, developers bypassed security checks.

**Mandate from the CTO:** design an AWS-native DevSecOps pipeline that
automatically scans infrastructure, application code, and container images, and
**enforces security gates that block non-compliant releases** before they reach
production.

## What this pipeline does

1. Builds the application container.
2. Runs layered security scans (SAST, secrets, IaC, dependencies).
3. Enforces a **quality gate** — the build fails if a gate is tripped.
4. Pushes only gate-passing images to Amazon ECR, where Inspector scans them.
5. Deploys compliant images to Amazon ECS Fargate via CodeDeploy.
6. Monitors deployments in CloudWatch and alerts via SNS.
7. Runs on least-privilege IAM throughout.

## Architecture

<!-- Insert exported architecture diagram here -->
![Architecture](docs/screenshots/architecture.png)

| Layer | Service | Purpose |
|-------|---------|---------|
| Source | GitHub | Application + IaC source of truth |
| Orchestration | AWS CodePipeline | Drives the stages end to end |
| Build & scan | AWS CodeBuild | Builds image, runs security scans |
| Registry | Amazon ECR + Inspector | Stores + scans container images |
| Runtime | Amazon ECS Fargate | Runs the app (no servers to manage) |
| Delivery | AWS CodeDeploy | Controlled deploy to ECS |
| Observability | CloudWatch + SNS | Logs, alarms, alerts |
| Identity | IAM | Least-privilege roles per component |

## Proof it works (and proof it blocks)

The most important evidence in this repo is the pipeline **failing on purpose**.

| Evidence | Screenshot |
|----------|-----------|
| Successful end-to-end run | `docs/screenshots/pipeline-success.png` |
| **Gate blocking a vulnerable image** | `docs/screenshots/gate-blocked-vuln.png` |
| **Gate blocking a hardcoded secret** | `docs/screenshots/gate-blocked-secret.png` |
| ECR image with Inspector findings | `docs/screenshots/ecr-inspector.png` |
| App running behind the ALB | `docs/screenshots/app-live.png` |
| CloudWatch logs from the task | `docs/screenshots/cloudwatch-logs.png` |
| SNS alert email on gate failure | `docs/screenshots/sns-alert.png` |

## How to reproduce

<!-- Fill in as we build. Keep commands copy-pasteable. -->
```bash
# 1. Provision infrastructure
cd terraform/environments/dev
terraform init
terraform apply

# 2. Trigger the pipeline
git push origin main
```

## What broke and what I changed

<!--
This section is the differentiator. As we build, log the real problems you hit
and how you diagnosed them. Examples of the kind of entry to write:
- "First Fargate task kept restarting; health check hit / but the app only
   serves /health. Fixed the target group health check path."
- "Inspector showed a HIGH finding in the base image; rebuilt on -slim and it
   dropped from N to M findings."
Interviewers ask 'tell me about a time something didn't work' -- this is your
prepared, honest answer.
-->

_(populated during the build)_

## Cost & teardown

This runs on a personal AWS account. To avoid surprise charges:

```bash
./scripts/cost-check.sh   # see what's billable and running
./scripts/teardown.sh     # destroy everything between sessions
```

## Security notes

- No long-lived credentials in the repo; CodeBuild/CodePipeline assume IAM roles.
- Container runs as a non-root user.
- IAM roles are scoped per component (build, deploy, task execution, task).

---

*Part of my enterprise cloud security portfolio.*
