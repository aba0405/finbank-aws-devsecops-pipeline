# FinBank Digital — AWS-Native DevSecOps Pipeline

> **Securing a financial institution's CI/CD pipeline by automating security
> validation before production deployment — and proving the gates actually block bad code.**

A production-style, AWS-native DevSecOps pipeline built entirely with Terraform.
It builds a containerized application, runs layered security scans, **enforces
gates that stop non-compliant releases**, deploys compliant images to ECS
Fargate, and alerts the team automatically when a gate blocks a deploy.

![A blocked deploy triggers an automatic alert](docs/screenshots/phase4-alert-email.png)

---

## The business problem

**FinBank Digital** (a fictional financial services company) runs online banking,
personal loans, and digital payments, shipping 10-15 releases a week. Before this
project, its delivery process had failed in ways that are common - and expensive -
for regulated companies:

- A vulnerable Docker image reached production.
- Hardcoded AWS credentials were committed to Git.
- Failed deployments caused customer-facing downtime.
- Security review was manual, so releases were slow and audits took weeks.
- Under deadline pressure, developers bypassed security checks.

**The mandate:** design an AWS-native DevSecOps pipeline that automatically scans
infrastructure, application code, and container images, and **enforces security
gates that block non-compliant releases before they reach production.**

This project solves exactly that, and - importantly - **demonstrates the gates
working by deliberately trying to push bad code through them.**

## Architecture

![Architecture](docs/screenshots/architecture.png)

```
Developer -> GitHub -> CodePipeline (V2)
                        |
                        |- 1. Source            (GitHub via CodeConnection)
                        |- 2. SAST / SCA scan   (Amazon Inspector - SourceCodeScan)
                        |- 3. Build + push      (CodeBuild -> ECR; git-secrets gate)
                        |- 4. Image scan        (Amazon Inspector - ECRImageScan)
                        |- 5. Deploy            (ECS Fargate, rolling)
                        |
        CloudWatch + SNS + EventBridge  <- alerts on any gate failure
```

| Layer | Service | Purpose |
|-------|---------|---------|
| Source | GitHub + CodeConnection | Application + IaC source of truth |
| Orchestration | CodePipeline (V2) | Drives the stages end to end |
| SAST / SCA | Amazon Inspector (SourceCodeScan) | Source + dependency vulnerability gate |
| Secrets | git-secrets (in CodeBuild) | Blocks hardcoded credentials |
| Build | CodeBuild | Builds + pushes the container image |
| Image scan | Amazon Inspector (ECRImageScan) | Container image vulnerability gate |
| Registry | Amazon ECR + Inspector enhanced scanning | Stores + continuously scans images |
| Runtime | Amazon ECS Fargate | Runs the app (no servers to manage) |
| Delivery | ECS deploy action | Rolling deploy of the scanned image |
| Observability | CloudWatch + SNS + EventBridge | Dashboards, alarms, failure alerts |
| Identity | IAM | Least-privilege roles per component |

Everything is defined in **Terraform** (AWS provider v6, VPC module v6.6.1),
region `us-east-1`.

## Proof it works - and proof it blocks

The most valuable evidence here is the pipeline **failing on purpose**. Three
distinct gate behaviors were demonstrated with real scanner output:

### 1. Compliant build deploys
A clean image (baseline: 2 Critical / 8 High) passes all gates and deploys to ECS.

![App live via ALB](docs/screenshots/phase2-app-live-via-alb.png)

### 2. Vulnerable dependencies blocked
A branch with deliberately outdated packages (Flask 0.12.2, PyYAML 3.13, etc.)
produced **3 Critical / 20 High** findings - far over threshold. The SAST/SCA gate
stopped the pipeline before any image was built. Real scanner output from the run:

```
---------Vulnerability analysis --------
Critical severity vulnerabilities found: 3
High severity vulnerabilities found: 20
Medium severity vulnerabilities found: 18
------- Action Failed -------
20 high vulnerabilities found which is more than threshold: 10.
```

### 3. Hardcoded secret blocked
A branch with a hardcoded AWS access key was caught by git-secrets at
`app/insecure_config.py:16`, failing the build before an image was produced.

![Pipeline blocked at Build stage](docs/screenshots/phase3e-gate-blocks-secret.png)

![git-secrets caught the AWS key](docs/screenshots/phase3e-secret-scan-log.png)

### 4. The gate caught real vulnerability drift
On the first full pipeline run, the image gate blocked a deploy - not because of a
code change, but because the base image had accumulated one additional High-severity
CVE (7 -> 8) between the baseline and the run. **Vulnerability posture degrades over
time even when code is frozen** - exactly why gates matter.

### 5. A blocked deploy triggers an automatic alert
When a gate fails, EventBridge catches the FAILED pipeline state and SNS emails the
team - closing the loop from detection to notification. (Screenshot at top of this README.)

### Observability dashboard
![Dashboard](docs/screenshots/phase4-dashboard.png)

## Key design decisions (and their tradeoffs)

Real engineering is about tradeoffs, not perfection. The deliberate choices here:

- **Calibrated gate thresholds, not zero-tolerance.** The image gate is set to the
  known baseline (2C / 8H) and blocks anything worse, rather than a naive "fail on
  any finding" that teams inevitably disable. *Tradeoff:* a vuln at/under baseline
  could pass; production would add CVE denylists and drive the baseline down.
- **Public subnets, no NAT gateway.** Saves ~$32/mo. *Tradeoff:* tasks have public
  IPs. Mitigated with tight security groups - the task SG only accepts traffic from
  the ALB SG, so tasks are never directly reachable. Production would use private
  subnets + NAT or VPC endpoints.
- **Layered scanners.** Amazon Inspector for SAST/SCA and image scanning; git-secrets
  for secret detection. No single tool does everything well - a real pipeline layers
  tools for what each does best.
- **Least-privilege IAM throughout.** Separate scoped service roles for CodeBuild,
  CodePipeline, and the ECS task (which is empty - the app makes no AWS calls).
  Service-linked roles for ELB/ECS/Inspector scoped by name + condition key.

## What broke and what I learned

This section is the honest record of building it - every wall hit and resolved.

- **~10 IAM permission walls**, resolved by scoping least-privilege incrementally
  rather than granting `*`. Each wall taught a specific lesson about how AWS services
  interlock (e.g. enhanced ECR scanning is powered by Inspector v2 and needs its own
  service-linked role).
- **The 10-managed-policies-per-user IAM limit.** Ten incremental phase policies were
  refactored into three function-scoped policies (each under the 6 KB size cap).
- **InspectorScan requires a CodePipeline V2 pipeline** - the Terraform default is V1.
- **The pipeline role needed CloudWatch Logs permissions** for the managed scan
  actions to write logs - distinct from the CodeBuild project's role.
- **Image-tag mismatch:** the scanner couldn't find SHA-tagged images
  (`MANIFEST_UNKNOWN`). Fixed by pushing a moving `:latest` tag for the scanner/deploy
  to target, switching ECR to MUTABLE, keeping SHA tags for traceability.
- **git-secrets needs a git repo** - CodePipeline delivers source as a plain S3
  bundle with no `.git`, so the buildspec runs `git init` first.
- **git-secrets allow-lists AWS's own example key** (`AKIAIOSFODNN7EXAMPLE`), so the
  first secret demo silently passed. Swapped to a non-allowlisted realistic fake key.
  *Lesson: scanner allowlists cause false negatives - test gates with inputs that
  aren't on the tool's built-in exceptions.*
- **Security-group descriptions reject `>`** - AWS validates them server-side.

## Reproduce it

```bash
cd terraform/environments/dev
terraform init
terraform apply    # set alert_email + github_repo in terraform.tfvars first
```

Then complete two one-time manual steps (both are auth grants Terraform can't do):
the GitHub CodeConnection (Developer Tools -> Connections -> confirm), and the SNS
email subscription (click the confirmation link AWS emails you).

## Cost & teardown

Runs on a personal AWS account. Standing cost is small (ALB ~$16/mo, one Fargate
task ~$9/mo, alarms ~$0.30/mo) - but everything tears down cleanly:

```bash
./scripts/cost-check.sh   # what's billable and running
terraform destroy         # remove it all between sessions
```

## Repository layout

```
app/                    Flask app + non-root Dockerfile
buildspec/              CodeBuild buildspec (git-secrets + build/push)
terraform/
  environments/dev/     the deployable stack (network, ecs, alb, pipeline, observability)
  modules/
    ecr/                ECR + enhanced scanning module
    iam/                least-privilege policies
      consolidated/     the three function-scoped policies actually attached
docs/screenshots/       evidence of every phase
scripts/                cost-check + teardown
```

The `vulnerable-demo` and `secret-demo` branches are retained as gate-test evidence.
`main` is always clean of demo artifacts.

---

## Related work

This is **Project 1 of 2**. Project 2 re-implements the same security gates with an
**open-source stack** (Trivy, Checkov, Gitleaks, Semgrep) on GitHub Actions - the
tooling most teams actually run - to contrast AWS-native vs. open-source approaches.

---

*Built as a hands-on DevSecOps portfolio project. Every screenshot is from a real
run in my own AWS account.*