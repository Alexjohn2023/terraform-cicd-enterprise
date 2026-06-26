# terraform-cicd-enterprise

> Enterprise-grade AWS CI/CD pipeline using GitHub Actions, Terraform, and HCP Terraform Cloud — with automated security scanning via Checkov and tfsec. The pattern RTP companies like TCS, KPMG, Deloitte, and Duke Health run in production.

![CI](https://github.com/Alexjohn2023/terraform-cicd-enterprise/actions/workflows/ci.yml/badge.svg)
![CD](https://github.com/Alexjohn2023/terraform-cicd-enterprise/actions/workflows/cd.yml/badge.svg)

---

## What This Project Does

This pipeline takes Terraform code from a developer's laptop to running AWS infrastructure — automatically, safely, and with a full audit trail. Zero manual AWS console clicks. Zero security violations.

```
Code push → Scan → Validate → Plan → Approve → Deploy → Verify
```

---

## Pipeline Features

| Feature | Details |
|---------|---------|
| **Checkov security scan** | 20/20 checks passing — runs on every PR before terraform init |
| **tfsec security scan** | 0 issues detected — deep module-level analysis on every PR |
| **CI on every PR** | Terraform fmt check + validate — posts results as PR comment |
| **Plan on every PR** | Plans dev, staging, and prod in parallel — posts all 3 as PR comments |
| **Auto deploy dev** | Merges to develop trigger automatic dev deployment |
| **Auto deploy staging** | Merges to main trigger automatic staging deployment |
| **Manual approval gate** | Prod deployment pauses and requires human approval |
| **OIDC authentication** | No static AWS keys stored anywhere |
| **Nightly drift detection** | Runs every night — opens GitHub Issue if drift found |
| **Remote state** | HCP Terraform Cloud — isolated state per environment |

---

## Security Controls Enforced

Checkov and tfsec run on every PR and enforce these controls automatically:

| Control | Check | Status |
|---------|-------|--------|
| No SSH from 0.0.0.0/0 | CKV_AWS_24 | ✅ Enforced |
| EBS encrypted at rest | CKV_AWS_8 | ✅ Enforced |
| IMDSv2 only — no IMDSv1 | CKV_AWS_79 | ✅ Enforced |
| Detailed monitoring enabled | CKV_AWS_126 | ✅ Enforced |
| IAM role attached to EC2 | CKV2_AWS_41 | ✅ Enforced |
| Security group descriptions | CKV_AWS_23 | ✅ Enforced |
| EBS optimization enabled | CKV_AWS_135 | ✅ Enforced |
| No hardcoded AWS keys | CKV_AWS_41 | ✅ Enforced |

---

## Architecture

```
terraform-cicd-enterprise/
├── .github/
│   └── workflows/
│       ├── ci.yml     ← Checkov + tfsec + fmt + validate on every PR
│       └── cd.yml     ← Plan, deploy, approval gate, drift detection
├── modules/
│   └── ec2/           ← Reusable EC2 module (instance + security group + IAM role)
├── .checkov.yaml      ← Checkov skip rules with documented justifications
├── main.tf            ← TFC backend + AWS provider + environment config
├── variables.tf       ← Input variables
└── outputs.tf         ← Output values
```

---

## Infrastructure Deployed

| Environment | Instance Type | Count | Trigger |
|-------------|--------------|-------|---------|
| dev | t2.micro | 1 | Push to develop |
| staging | t2.micro | 1 | Push to main |
| prod | t2.small | 2 | Manual approval required |

---

## The CI Pipeline

Every pull request runs these checks in order:

```
PR opened
  ↓
✅ Checkov — 20/20 security checks
  ↓
✅ tfsec — 0 issues detected
  ↓
✅ terraform fmt check
  ↓
✅ terraform init
  ↓
✅ terraform validate
  ↓
✅ terraform plan (dev + staging + prod in parallel)
  ↓
Posts plan output as PR comments
```

A PR with any security violation or formatting issue cannot merge.

---

## How OIDC Authentication Works

Instead of storing permanent AWS credentials in GitHub Secrets, this project uses OIDC:

1. GitHub generates a short-lived token per pipeline run
2. AWS verifies the token came from this specific repository
3. AWS grants temporary credentials for that run only
4. Run ends — credentials expire automatically
5. No permanent keys stored anywhere

```yaml
- name: Configure AWS via OIDC
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: us-east-1
```

---

## The Approval Gate

Production deployments never happen automatically. The pipeline pauses, emails the reviewer, and waits for manual sign-off:

```
deploy-staging ✅ → deploy-prod ⏸️ WAITING → ✅ approved → apply
```

Configured via GitHub Environments with required reviewers on the `prod` environment.

---

## Drift Detection

Every night at 6am UTC the pipeline runs `terraform plan -detailed-exitcode` against all three environments. Exit code 2 means drift detected. The pipeline automatically opens a GitHub Issue.

```yaml
schedule:
  - cron: '0 6 * * *'
```

---

## Setup Requirements

### GitHub Secrets

| Secret | Description |
|--------|-------------|
| `TF_API_TOKEN` | HCP Terraform Cloud API token |
| `AWS_ROLE_ARN` | IAM Role ARN for dev/staging (OIDC) |
| `AWS_ROLE_ARN_PROD` | IAM Role ARN for prod (least privilege) |

### GitHub Environments

Create three environments under Repo → Settings → Environments:

- `dev` — no protection rules
- `staging` — no protection rules
- `prod` — required reviewer: your GitHub username

### HCP Terraform Cloud

- Organization: your TFC org name
- Create three workspaces tagged `cicd-enterprise`: dev, staging, prod
- Add AWS credentials as environment variables in each workspace

### AWS OIDC Setup

```bash
# Create OIDC Identity Provider
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Create IAM role
aws iam create-role \
  --role-name GitHubActions-TerraformDeploy \
  --assume-role-policy-document file://trust-policy.json

# Attach EC2 permissions
aws iam attach-role-policy \
  --role-name GitHubActions-TerraformDeploy \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
```

---

## Errors Encountered and Fixed

| Error | Cause | Fix |
|-------|-------|-----|
| Credentials could not be loaded | AWS_ROLE_ARN was placeholder | Update secret with real IAM role ARN |
| Workspace "default" does not exist | TFC has no default workspace | Set TF_WORKSPACE env var before init |
| No valid credential sources | TFC runs apply on its own servers | Add AWS creds to TFC workspace variables |
| Checkov CKV_AWS_24 | SSH open to 0.0.0.0/0 | Restrict to 10.0.0.0/8 |
| Checkov CKV_AWS_79 | IMDSv1 enabled | Add metadata_options block with http_tokens = required |
| Checkov CKV_AWS_8 | EBS not encrypted | Add root_block_device with encrypted = true |
| tfsec aws-ec2-no-public-egress-sgr | Egress to 0.0.0.0/0 | Documented skip — required for AWS API calls |
| em dash in description | AWS rejects special characters | Replace with regular hyphen |

---

## Destroying Resources

Always destroy infrastructure before deleting workspaces:

```bash
terraform workspace select dev
terraform destroy -auto-approve

terraform workspace select staging
terraform destroy -auto-approve

terraform workspace select prod
terraform destroy -auto-approve

# Verify
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=cicd-enterprise" \
            "Name=instance-state-name,Values=running" \
  --output table
```

---

## Full Walkthrough

Step-by-step documentation including every command, every error, and every fix:

**Medium:** [Building a Production-Grade CI/CD Pipeline with Terraform, GitHub Actions and HCP Terraform Cloud](https://medium.com/@alex2020global)

**Medium:** [Two Layers of Security Scanning — Checkov and tfsec in Practice](https://medium.com/@alex2020global)

---

## Tech Stack

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat&logo=terraform&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat&logo=github-actions&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-FF9900?style=flat&logo=amazonaws&logoColor=white)
![HCP Terraform](https://img.shields.io/badge/HCP_Terraform-7B42BC?style=flat&logo=terraform&logoColor=white)
![Checkov](https://img.shields.io/badge/Checkov-4A90E2?style=flat&logo=prisma&logoColor=white)
![tfsec](https://img.shields.io/badge/tfsec-00ADEF?style=flat&logo=aqua&logoColor=white)

---

## Author

**Alexander Njoku** | Cloud/DevOps Engineer | Raleigh, NC

- LinkedIn: [@alex2020global](https://linkedin.com/in/alex2020global)
- Medium: [@alex2020global](https://medium.com/@alex2020global)
- Portfolio: [zandersworldview.com](https://zandersworldview.com)
- GitHub: [Alexjohn2023](https://github.com/Alexjohn2023)

---

## Project Roadmap

- ✅ **Project 6** — Remote Terraform CI/CD with GitHub Actions
- ✅ **Project 6.1** — Policy as Code — Checkov + tfsec
- 🔄 **Project 6.2** — Sentinel policy enforcement
- 🔄 **Project 6.3** — OPA policy engine
- 📋 **Project 7** — Jenkins parallel pipeline
- 📋 **Project 8** — Docker + ECR containerization
- 📋 **Project 9** — Ansible configuration management
- 📋 **Project 10** — Prometheus + Grafana monitoring
- 📋 **Project 11** — Kubernetes + EKS
