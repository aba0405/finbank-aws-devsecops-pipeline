# Evidence checklist

Tick these off as you capture them. Each screenshot should show enough context
to prove it's YOUR account and a REAL run (visible resource names, timestamps,
region). Blur account IDs if you like, but leave enough to be credible.

## Phase 0 — Foundation
- [ ] AWS Budgets alarm configured (screenshot)
- [ ] `terraform init` success output
- [ ] Repo tree

## Phase 1 — Container + ECR
- [ ] Local `docker build` + `docker run` hitting /health
- [ ] Image pushed to ECR (console view of the repo + tag)
- [ ] Inspector scan findings on the image

## Phase 2 — Core infra
- [ ] `terraform apply` summary (resources added)
- [ ] ECS service with a RUNNING task
- [ ] App reachable via ALB DNS name (browser + curl)

## Phase 3 — Pipeline + gates
- [ ] Full pipeline run all-green
- [ ] *** Gate BLOCKING a vulnerable image (red pipeline) ***
- [ ] *** Gate BLOCKING a hardcoded secret ***
- [ ] The build logs showing WHY it failed

## Phase 4 — Observability
- [ ] CloudWatch log group with app logs
- [ ] CloudWatch alarm
- [ ] SNS email received on a gate failure

## Phase 5 — Polish
- [ ] Architecture diagram exported into docs/
- [ ] README fully filled in
- [ ] "What broke" section has >=2 real entries
- [ ] Teardown confirmed via cost-check.sh
