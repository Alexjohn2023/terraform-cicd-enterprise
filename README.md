# terraform-cicd-enterprise

> Enterprise-grade AWS CI/CD pipeline using GitHub Actions, Terraform, and HCP Terraform Cloud — the pattern RTP companies like TCS, KPMG, Deloitte, and Duke Health run in production.

![CI](https://github.com/Alexjohn2023/terraform-cicd-enterprise/actions/workflows/ci.yml/badge.svg)
![CD](https://github.com/Alexjohn2023/terraform-cicd-enterprise/actions/workflows/cd.yml/badge.svg)

---

## What This Project Does

This pipeline takes Terraform code from a developer's laptop to running AWS infrastructure — automatically, safely, and with a full audit trail. Zero manual AWS console clicks.

```
Code push → Validate → Plan (all 3 envs) → Approve → Deploy → Verify
```

---

## Pipeline Features

| Feature | Details |
|---------|---------|
| **CI on every PR** | Terraform fmt check + validate — posts results as PR comment |
| **Plan on every PR** | Plans dev, staging, and prod in parallel — posts all 3 as PR comments |
| **Auto deploy dev** | Merges to develop trigger automatic dev deployment |
| **Auto deploy staging** | Merges to main trigger automatic staging deployment |
| **Manual approval gate** | Prod deployment pauses and requires human approval |
| **OIDC authentication** | No static AWS keys stored anywhere |
| **Nightly drift detection** | Runs every night — opens GitHub Issue if drift found |
| **Remote state** | HCP Terraform Cloud — isolated state per environment |

---

## Architecture

```
GitHub Repository
├── .github/workflows/
│   ├── ci.yml          ← Format check + validate on every PR
│   └── cd.yml          ← Plan, deploy, drift detection
├── modules/
│   └── ec2/            ← Reusable EC2 module (instance + security group)
├── main.tf             ← TFC backend + AWS provider + environment config
├── variables.tf        ← Input variables
└── outputs.tf          ← Output values
```

---

## Infrastructure Deployed

| Environment | Instance Type | Count | Trigger |
|-------------|--------------|-------|---------|
| dev | t2.micro | 1 | Push to develop |
| staging | t2.micro | 1 | Push to main |
| prod | t2.small | 2 | Manual approval required |

---

## How OIDC Authentication Works

Instead of storing permanent AWS credentials in GitHub Secrets, this project uses OIDC (OpenID Connect):

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

Production deployments never happen automatically. The pipeline pauses, emails the reviewer, and waits for manual sign-off before applying any changes to prod.

```
deploy-staging ✅ → deploy-prod ⏸️ WAITING FOR APPROVAL → ✅ approved → apply
```

Configured via GitHub Environments with required reviewers on the `prod` environment.

---

## Drift Detection

Every night at 6am UTC the pipeline runs `terraform plan -detailed-exitcode` against all three environments. If exit code 2 is returned (changes detected), the pipeline automatically opens a GitHub Issue.

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

# Create IAM role with trust policy scoped to your repo
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

Real projects break. Here is what failed during this build and exactly how each was fixed:

| Error | Cause | Fix |
|-------|-------|-----|
| Credentials could not be loaded | AWS_ROLE_ARN was placeholder | Update secret with real IAM role ARN |
| Workspace "default" does not exist | TFC has no default workspace | Set `TF_WORKSPACE` env var before init |
| No valid credential sources | TFC runs apply on its own servers | Add AWS creds to TFC workspace variables |
| No existing workspaces | TFC org had no tagged workspaces | Create dev/staging/prod workspaces via CLI |
| Protected branch rejected push | Branch protection working correctly | Create PR — this is the right behavior |
| git push rejected — fetch first | Remote had commits not pulled locally | `git fetch origin && git reset --hard origin/develop` |

---

## Destroying Resources

Always destroy infrastructure before deleting workspaces:

```bash
# Destroy each environment
terraform workspace select dev
terraform destroy -auto-approve

terraform workspace select staging
terraform destroy -auto-approve

terraform workspace select prod
terraform destroy -auto-approve

# Verify nothing is running
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=cicd-enterprise" \
            "Name=instance-state-name,Values=running" \
  --output table
```

---

## Full Walkthrough

Detailed step-by-step documentation including every command, every error, and every fix:

**Medium:** [Building a Production-Grade CI/CD Pipeline with Terraform, GitHub Actions & HCP Terraform Cloud](https://medium.com/@alex2020global)

---

## Tech Stack

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat&logo=terraform&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat&logo=github-actions&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-FF9900?style=flat&logo=amazonaws&logoColor=white)
![HCP Terraform](https://img.shields.io/badge/HCP_Terraform-7B42BC?style=flat&logo=terraform&logoColor=white)

---

## Author

**Alexander Njoku** | Cloud/DevOps Engineer | Raleigh, NC

- LinkedIn: [@alex2020global](https://linkedin.com/in/alex2020global)
- Medium: [@alex2020global](https://medium.com/@alex2020global)
- Portfolio: [zandersworldview.com](https://zandersworldview.com)
- GitHub: [Alexjohn2023](https://github.com/Alexjohn2023)
