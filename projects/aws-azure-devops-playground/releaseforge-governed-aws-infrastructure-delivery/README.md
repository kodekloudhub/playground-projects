# ReleaseForge — Governed AWS Infrastructure Delivery

**Level:** advanced  ·  **Playground:** AWS | Azure DevOps Playground

▶ **[Launch the playground](https://kodekloud.com/cloud-playgrounds/azure-devops, https://kodekloud.com/cloud-playgrounds/aws)** — open it, then copy the files below.

```php
---
id: releaseforge-governed-aws-infrastructure-delivery
title: ReleaseForge — Governed AWS Infrastructure Delivery
playground: AWS Cloud Sandbox and Azure DevOps
playground_link: https://kodekloud.com/cloud-playgrounds/azure-devops, https://kodekloud.com/cloud-playgrounds/aws
difficulty: advanced
estimated_minutes: 180
tags:
  - aws
  - azure-devops
  - terraform
  - oidc
  - cicd
  - security
  - finops
skills:
  - Workload identity federation
  - Self-hosted pipeline agents
  - Versioned Terraform state and native locking
  - Security and cost gates
  - Approved saved-plan deployment
prerequisites:
  - Basic Git, Linux, and Terraform knowledge
  - Access to AWS and Azure DevOps playgrounds
  - An Infracost account and API key
---

# ReleaseForge — Governed AWS Infrastructure Delivery

## Scenario

Your platform team delivers infrastructure for several product teams. Every change needs a security check, a cost estimate, and review before reaching AWS. Reviewers also need proof that the approved plan is the plan that ran.

Build ReleaseForge: an Azure DevOps workflow that obtains short-lived AWS credentials, checks pull requests, and deploys an approved Terraform plan. A private S3 assets bucket is your first infrastructure release.

## What you'll build

An Azure Repos repository, an EC2 pipeline agent, two federated AWS roles, versioned S3 state, and a validation–plan–apply pipeline. Checkov blocks insecure bucket settings, Infracost checks an explicit monthly usage estimate, and an approval protects deployment.

This project implements production delivery patterns using a small workload. It is not a complete enterprise landing zone. You will learn how to extend the pattern across teams and accounts.

## Learning objectives

- Connect Azure Pipelines to AWS without storing AWS access keys.
- Separate planning permissions from deployment permissions.
- Lock and version remote Terraform state.
- Block unsafe and over-budget changes.
- Review and apply the same saved plan.
- Verify a release and clean up its resources.

## Prerequisites

Open both playgrounds in separate tabs and keep them open:

| Environment | Purpose | Launch |
| --- | --- | --- |
| AWS Cloud Sandbox | EC2 agent, IAM, Terraform state, and workload | [Open AWS](https://kodekloud.com/cloud-playgrounds/aws) |
| Azure DevOps | Repos, Pipelines, service connections, and approvals | [Open Azure DevOps](https://kodekloud.com/cloud-playgrounds/azure-devops) |

Create an [Infracost account](https://www.infracost.io/) and obtain an API key from its dashboard. You will store it as a secret variable, not in Git.

## Architecture / overview

~~~text
Azure Repos PR -> validation + Checkov -> OIDC plan role -> plan + cost report
Merge to main -> fresh plan -> approval + exclusive lock -> OIDC apply role
              -> apply saved plan -> private S3 assets bucket

EC2 self-hosted agent: executes the jobs
S3 state bucket: versioned state + native .tflock locking
~~~

The agent has no AWS instance profile and no stored AWS access keys. AWS Toolkit tasks obtain temporary credentials from their OIDC service connections.

## Steps

Run one command block at a time. Paste file-writing blocks from the cat command through the closing EOF line. EOF must start at the beginning of the line. Do not copy terminal prompts or output.

### Task 1 — Prepare AWS and Azure DevOps

Open the AWS Console, select **us-east-1**, and open **CloudShell**:

~~~bash
export AWS_PAGER=""
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
~~~

~~~bash
aws sts get-caller-identity
~~~

Use this region throughout the guide. If you choose another region, change the region values consistently, including the identity bootstrap YAML.

Open the organization and project provided by the Azure DevOps playground. Record their URL and project name; use the existing project rather than creating another organization.

In **Organization settings → Extensions**, check for **AWS Toolkit for Azure DevOps**. If missing, select **Browse marketplace**, find the extension published by **Amazon Web Services**, and install it in this organization. Use an OIDC-capable version.

### Task 2 — Launch the build agent

In AWS, select **EC2 → Instances → Launch instances**:

1. Name: **releaseforge-agent**.
2. AMI: **Ubuntu Server 24.04 LTS**, x86_64.
3. Instance type: **t3.medium**.
4. Create or select a key pair.
5. Choose a public subnet with an internet-gateway route and enable a public IP.
6. Allow SSH only from your current IP.
7. Root volume: **20 GiB gp3**.
8. Advanced details: no IAM instance profile; CPU credits **Standard**.
9. Launch, then use **Connect → EC2 Instance Connect**, or SSH with your key.

Run these commands on EC2 as **ubuntu**, not root:

~~~bash
whoami
~~~

~~~bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl unzip jq git python3-venv python3-pip
~~~

Install AWS CLI:

~~~bash
curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscli.zip
unzip -q /tmp/awscli.zip -d /tmp/releaseforge-awscli
sudo /tmp/releaseforge-awscli/aws/install
~~~

Install pinned Terraform with native S3 locking:

~~~bash
mkdir -p /tmp/releaseforge-terraform
cd /tmp/releaseforge-terraform
curl -fsSLO https://releases.hashicorp.com/terraform/1.14.9/terraform_1.14.9_linux_amd64.zip
curl -fsSLO https://releases.hashicorp.com/terraform/1.14.9/terraform_1.14.9_SHA256SUMS
~~~

~~~bash
grep ' terraform_1.14.9_linux_amd64.zip$' terraform_1.14.9_SHA256SUMS | sha256sum -c -
~~~

Continue only if the checksum reports OK:

~~~bash
unzip -q terraform_1.14.9_linux_amd64.zip
sudo install -m 0755 terraform /usr/local/bin/terraform
~~~

Install pinned Infracost:

~~~bash
mkdir -p /tmp/releaseforge-infracost
cd /tmp/releaseforge-infracost
curl -fsSLO https://github.com/infracost/infracost/releases/download/v0.10.45/infracost-linux-amd64.tar.gz
curl -fsSLO https://github.com/infracost/infracost/releases/download/v0.10.45/infracost-linux-amd64.tar.gz.sha256
~~~

~~~bash
sha256sum -c infracost-linux-amd64.tar.gz.sha256
~~~

~~~bash
tar -xzf infracost-linux-amd64.tar.gz
sudo install -m 0755 infracost-linux-amd64 /usr/local/bin/infracost
~~~

~~~bash
aws --version
terraform version
infracost --version
~~~

Do not run aws configure on this host.

### Task 3 — Register the self-hosted agent

In Azure DevOps:

1. Open **Organization settings → Agent pools → Add pool**.
2. Select **Self-hosted** and name it **releaseforge-linux**.
3. Make it available to your project; do not grant all pipelines access.
4. Open **Agents → New agent → Linux → x64** and copy its download URL.
5. Open **User settings → Personal access tokens → New Token**.
6. Create a short-lived token with **Agent Pools: Read & manage**.

On EC2:

~~~bash
mkdir -p "$HOME/azagent"
cd "$HOME/azagent"
read -r -p 'Paste the Linux x64 agent download URL: ' AGENT_DOWNLOAD_URL
~~~

Paste the URL when prompted, press Enter, then run:

~~~bash
curl -fSL "$AGENT_DOWNLOAD_URL" -o agent.tar.gz
tar -xzf agent.tar.gz
~~~

~~~bash
sudo ./bin/installdependencies.sh
./config.sh
~~~

Answer the prompts with your organization URL, PAT authentication, the registration token, pool **releaseforge-linux**, agent **releaseforge-agent-01**, and default work folder **_work**.

~~~bash
sudo ./svc.sh install ubuntu
sudo ./svc.sh start
~~~

Refresh **Agent pools → releaseforge-linux → Agents**. Confirm **Online**. Revoke the registration PAT after configuration; the agent now uses its own credentials.

### Task 4 — Create the repository

In **Repos → Files → repository selector → New repository**, create **releaseforge-infra** with a README and default branch **main**.

Select **Clone → HTTPS** and copy the URL. Create a separate short-lived PAT with **Code: Read & write** for Git.

On EC2:

~~~bash
cd "$HOME"
read -r -p 'Paste the repository HTTPS URL: ' REPO_URL
~~~

~~~bash
git clone "$REPO_URL" releaseforge-infra
cd "$HOME/releaseforge-infra"
~~~

Use the Code PAT at the password prompt. Do not embed it in a URL or commit it.

~~~bash
git config user.name "ReleaseForge Learner"
git config user.email "learner@example.com"
mkdir -p .azure infra scripts tools
~~~

### Task 5 — Bootstrap versioned state

Return to **AWS CloudShell**. Generate names once:

~~~bash
export RUN_SUFFIX="$(date +%s)-$(openssl rand -hex 3)"
export STATE_BUCKET="releaseforge-state-$AWS_ACCOUNT_ID-$RUN_SUFFIX"
export WORKLOAD_BUCKET="releaseforge-assets-$AWS_ACCOUNT_ID-$RUN_SUFFIX"
export STATE_KEY="releaseforge/production/terraform.tfstate"
~~~

Save these nonsecret values for later tasks:

~~~bash
printf 'export AWS_REGION=%q\nexport AWS_ACCOUNT_ID=%q\nexport STATE_BUCKET=%q\nexport WORKLOAD_BUCKET=%q\nexport STATE_KEY=%q\n' \
  "$AWS_REGION" "$AWS_ACCOUNT_ID" "$STATE_BUCKET" "$WORKLOAD_BUCKET" "$STATE_KEY" \
  > "$HOME/releaseforge-session.env"
~~~

After reconnecting, reload rather than generate new names:

~~~bash
source "$HOME/releaseforge-session.env"
export AWS_PAGER=""
~~~

Create the bucket:

~~~bash
if [ "$AWS_REGION" = us-east-1 ]; then
  aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$AWS_REGION"
else
  aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$AWS_REGION" \
    --create-bucket-configuration "LocationConstraint=$AWS_REGION"
fi
~~~

~~~bash
aws s3api put-bucket-versioning --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled
~~~

~~~bash
aws s3api put-bucket-encryption --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
~~~

~~~bash
aws s3api put-public-access-block --bucket "$STATE_BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
~~~

Deny insecure transport:

~~~bash
cat > /tmp/releaseforge-state-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Deny", "Principal": "*", "Action": "s3:*",
    "Resource": ["arn:aws:s3:::$STATE_BUCKET", "arn:aws:s3:::$STATE_BUCKET/*"],
    "Condition": {"Bool": {"aws:SecureTransport": "false"}}
  }]
}
EOF
~~~

~~~bash
aws s3api put-bucket-policy --bucket "$STATE_BUCKET" \
  --policy file:///tmp/releaseforge-state-policy.json
~~~

This bootstrap bucket remains outside the workload's Terraform configuration.

### Task 6 — Discover the OIDC identities

In **Project settings → Service connections → New service connection → AWS**, create:

| Connection | Role to assume |
| --- | --- |
| aws-releaseforge-plan | arn:aws:iam::YOUR_ACCOUNT_ID:role/iam_role_releaseforge_plan |
| aws-releaseforge-apply | arn:aws:iam::YOUR_ACCOUNT_ID:role/iam_role_releaseforge_apply |

Replace YOUR_ACCOUNT_ID. Leave access key, secret key, and session token empty. Enable **Use OIDC**. Do not grant all pipelines access. Save without verification if offered; the roles do not exist yet.

On EC2:

~~~bash
cd "$HOME/releaseforge-infra"
cat > .azure/oidc-bootstrap.yml <<'EOF'
trigger: none
pool:
  name: releaseforge-linux
steps:
- task: AWSShellScript@1
  displayName: Discover planning identity
  inputs:
    awsCredentials: aws-releaseforge-plan
    regionName: us-east-1
    scriptType: inline
    inlineScript: aws sts get-caller-identity
- task: AWSShellScript@1
  displayName: Discover deployment identity
  condition: always()
  inputs:
    awsCredentials: aws-releaseforge-apply
    regionName: us-east-1
    scriptType: inline
    inlineScript: aws sts get-caller-identity
EOF
~~~

~~~bash
git add .azure/oidc-bootstrap.yml
git commit -m "Add OIDC identity bootstrap"
git push origin main
~~~

In **Pipelines → New pipeline → Azure Repos Git**, select the repository, then **Existing Azure Pipelines YAML file → .azure/oidc-bootstrap.yml**. Run it and authorize this pipeline to the pool and both connections when prompted.

The first run should fail at role assumption. Open each AWS task log and find **OIDC Token generated**. Record its issuer, audience, and subject, not the token itself:

~~~text
issuer:   https://vstoken.dev.azure.com/<organization-GUID>
audience: api://AzureADTokenExchange
subject:  sc://<organization-name>/<project-name>/aws-releaseforge-plan
subject:  sc://<organization-name>/<project-name>/aws-releaseforge-apply
~~~

Use the exact logged claims, including spaces and capitalization. The issuer uses an organization GUID, not the organization name.

### Task 7 — Create scoped AWS roles

In **IAM → Identity providers → Add provider**, select **OpenID Connect**, enter the exact issuer, and use audience **api://AzureADTokenExchange**. If it exists, confirm its audience instead of duplicating it.

In CloudShell:

~~~bash
read -r -p 'Paste the exact issuer: ' OIDC_ISSUER
read -r -p 'Paste the exact planning subject: ' PLAN_SUBJECT
read -r -p 'Paste the exact deployment subject: ' APPLY_SUBJECT
export OIDC_ISSUER PLAN_SUBJECT APPLY_SUBJECT
~~~

Generate exact-match trust policies:

~~~bash
python3 - <<'PY'
import json, os
from pathlib import Path
issuer = os.environ['OIDC_ISSUER'].removeprefix('https://').rstrip('/')
account = os.environ['AWS_ACCOUNT_ID']
for name, subject in [('plan', os.environ['PLAN_SUBJECT']),
                      ('apply', os.environ['APPLY_SUBJECT'])]:
    policy = {'Version': '2012-10-17', 'Statement': [{
        'Effect': 'Allow',
        'Principal': {'Federated': f'arn:aws:iam::{account}:oidc-provider/{issuer}'},
        'Action': 'sts:AssumeRoleWithWebIdentity',
        'Condition': {'StringEquals': {
            f'{issuer}:aud': 'api://AzureADTokenExchange', f'{issuer}:sub': subject}}
    }]}
    Path(f'/tmp/releaseforge-{name}-trust.json').write_text(json.dumps(policy))
PY
~~~

~~~bash
aws iam create-role --role-name iam_role_releaseforge_plan \
  --assume-role-policy-document file:///tmp/releaseforge-plan-trust.json
~~~

~~~bash
aws iam create-role --role-name iam_role_releaseforge_apply \
  --assume-role-policy-document file:///tmp/releaseforge-apply-trust.json
~~~

For repeat runs, inspect existing project roles before changing them. A naming convention does not grant IAM permissions.

Generate permissions scoped to the two bucket names:

~~~bash
python3 - <<'PY'
import json, os
from pathlib import Path
state = f"arn:aws:s3:::{os.environ['STATE_BUCKET']}"
key = f"{state}/{os.environ['STATE_KEY']}"
workload = f"arn:aws:s3:::{os.environ['WORKLOAD_BUCKET']}"
for name in ('plan', 'apply'):
    statements = [
        {'Effect': 'Allow', 'Action': ['s3:ListBucket', 's3:GetBucketLocation'],
         'Resource': state},
        {'Effect': 'Allow', 'Action': ['s3:GetObject'] +
         (['s3:PutObject'] if name == 'apply' else []), 'Resource': key},
        {'Effect': 'Allow', 'Action': ['s3:GetObject', 's3:PutObject', 's3:DeleteObject'],
         'Resource': key + '.tflock'},
        {'Effect': 'Allow', 'Action': ['s3:Get*', 's3:ListBucket'], 'Resource': workload}
    ]
    if name == 'apply':
        statements.append({'Effect': 'Allow', 'Action': [
            's3:CreateBucket', 's3:DeleteBucket', 's3:PutBucketTagging',
            's3:PutBucketVersioning', 's3:PutEncryptionConfiguration',
            's3:PutBucketPublicAccessBlock', 's3:PutBucketOwnershipControls',
            's3:DeleteBucketOwnershipControls'], 'Resource': workload})
    Path(f'/tmp/releaseforge-{name}-permissions.json').write_text(
        json.dumps({'Version': '2012-10-17', 'Statement': statements}))
PY
~~~

The planning role can acquire the state lock but cannot write state or change the workload. Create customer-managed policies, not inline role policies:

~~~bash
export PLAN_POLICY_ARN="$(aws iam create-policy --policy-name releaseforge-plan \
  --policy-document file:///tmp/releaseforge-plan-permissions.json \
  --query Policy.Arn --output text)"
~~~

~~~bash
export APPLY_POLICY_ARN="$(aws iam create-policy --policy-name releaseforge-apply \
  --policy-document file:///tmp/releaseforge-apply-permissions.json \
  --query Policy.Arn --output text)"
~~~

~~~bash
aws iam attach-role-policy --role-name iam_role_releaseforge_plan --policy-arn "$PLAN_POLICY_ARN"
~~~

~~~bash
aws iam attach-role-policy --role-name iam_role_releaseforge_apply --policy-arn "$APPLY_POLICY_ARN"
~~~

Wait briefly for IAM propagation, then rerun the identity pipeline. Both tasks should show the intended assumed-role ARN.

If provider creation or policy attachment is denied, resolve that specific permission before continuing. Do not silently switch to permanent keys or administrator access.

### Task 8 — Write the Terraform workload

On EC2:

~~~bash
cd "$HOME/releaseforge-infra"
cat > .gitignore <<'EOF'
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
reports/
.tools/
*.auto.tfvars
crash.log
EOF
~~~

~~~bash
cat > infra/versions.tf <<'EOF'
terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {}
}
provider "aws" {
  region = var.aws_region
}
EOF
~~~

~~~bash
cat > infra/variables.tf <<'EOF'
variable "aws_region" {
  type = string
}
variable "bucket_name" {
  type = string
}
variable "release_label" {
  type    = string
  default = "release-1"
}
EOF
~~~

~~~bash
cat > infra/main.tf <<'EOF'
resource "aws_s3_bucket" "assets" {
  bucket        = var.bucket_name
  force_destroy = false
  tags = {
    Project     = "ReleaseForge"
    Environment = "production"
    ManagedBy   = "Terraform"
    Release     = var.release_label
  }
}
resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
EOF
~~~

~~~bash
cat > infra/outputs.tf <<'EOF'
output "assets_bucket" {
  value = aws_s3_bucket.assets.id
}
EOF
~~~

~~~bash
terraform -chdir=infra init -backend=false
terraform -chdir=infra fmt
terraform -chdir=infra validate
~~~

Commit the generated infra/.terraform.lock.hcl. Pipeline initialization will refuse to update it automatically.

### Task 9 — Add security and cost gates

Install Checkov in a dedicated environment and lock its resolved dependencies:

~~~bash
python3 -m venv .tools/checkov
.tools/checkov/bin/pip install checkov
.tools/checkov/bin/pip freeze > tools/checkov-requirements.txt
~~~

~~~bash
cat > scripts/setup-checkov.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
python3 -m venv --clear .tools/checkov
.tools/checkov/bin/pip install --requirement tools/checkov-requirements.txt
mkdir -p reports
EOF
~~~

Check encryption, versioning, and all four public-access controls:

~~~bash
.tools/checkov/bin/checkov -d infra --framework terraform \
  --check CKV_AWS_19,CKV_AWS_21,CKV_AWS_53,CKV_AWS_54,CKV_AWS_55,CKV_AWS_56
~~~

All selected checks must pass. This is a focused baseline, not a full compliance audit. Do not use soft-fail.

Add monthly cost assumptions; these do not upload data or generate requests:

~~~bash
cat > infracost-usage.yml <<'EOF'
version: 0.1
resource_usage:
  aws_s3_bucket.assets:
    standard:
      storage_gb: 100
      monthly_tier_1_requests: 100000
      monthly_tier_2_requests: 1000000
EOF
~~~

~~~bash
cat > scripts/check-cost.py <<'EOF'
import json
import os
from decimal import Decimal
from pathlib import Path

report = json.loads(Path('reports/infracost.json').read_text())
raw = report.get('totalMonthlyCost')
if raw is None:
    raise SystemExit('Missing cost estimate; do not treat it as zero.')
cost = Decimal(str(raw))
limit = Decimal(os.environ['COST_LIMIT_USD'])
if not cost.is_finite() or not limit.is_finite() or cost < 0 or limit < 0:
    raise SystemExit('Invalid cost estimate or budget.')
print(f'Estimated monthly workload cost: ${cost}; budget: ${limit}')
if cost > limit:
    raise SystemExit('Monthly workload estimate exceeds the budget.')
EOF
~~~

The estimate covers this Terraform workload, not the separately created agent or state bucket.

### Task 10 — Configure variables and write the pipeline

In **Pipelines → Library → + Variable group**, create **releaseforge-config**:

| Variable | Value |
| --- | --- |
| AWS_REGION | us-east-1 |
| STATE_BUCKET | Task 5 state bucket |
| STATE_KEY | releaseforge/production/terraform.tfstate |
| WORKLOAD_BUCKET | Task 5 workload bucket |
| COST_LIMIT_USD | 10 |
| INFRACOST_API_KEY | Your API key; select the lock icon to make it secret |

Restrict this group to the delivery pipeline. Do not store AWS access keys.

On EC2:

~~~bash
cat > azure-pipelines.yml <<'EOF'
trigger:
  branches:
    include:
    - main
parameters:
- name: operation
  displayName: Operation
  type: string
  default: deploy
  values:
  - deploy
  - destroy
variables:
- group: releaseforge-config
pool:
  name: releaseforge-linux
stages:
- stage: Validate
  jobs:
  - job: Validate
    steps:
    - checkout: self
      clean: true
      persistCredentials: false
    - bash: |
        set -euo pipefail
        test "$(terraform version -json | jq -r .terraform_version)" = "1.14.9"
        terraform -chdir=infra fmt -check -recursive
        terraform -chdir=infra init -backend=false -lockfile=readonly -input=false
        terraform -chdir=infra validate
        bash scripts/setup-checkov.sh
        .tools/checkov/bin/checkov -d infra --framework terraform \
          --check CKV_AWS_19,CKV_AWS_21,CKV_AWS_53,CKV_AWS_54,CKV_AWS_55,CKV_AWS_56 \
          --output junitxml > reports/checkov.xml
      displayName: Validate and enforce security baseline
    - task: PublishTestResults@2
      condition: always()
      inputs:
        testResultsFormat: JUnit
        testResultsFiles: reports/checkov.xml
        failTaskOnFailedTests: true
- stage: Plan
  dependsOn: Validate
  jobs:
  - job: Plan
    steps:
    - checkout: self
      clean: true
      persistCredentials: false
    - task: AWSShellScript@1
      displayName: Create reviewed plan and cost evidence
      inputs:
        awsCredentials: aws-releaseforge-plan
        regionName: $(AWS_REGION)
        scriptType: inline
        inlineScript: |
          set -euo pipefail
          export AWS_PAGER="" TF_IN_AUTOMATION=true
          mkdir -p reports
          aws sts get-caller-identity
          terraform -chdir=infra init -input=false -lockfile=readonly \
            -backend-config="bucket=$STATE_BUCKET" -backend-config="key=$STATE_KEY" \
            -backend-config="region=$AWS_REGION" -backend-config="use_lockfile=true"
          args=()
          if [ "$OPERATION" = destroy ]; then
            test "$SOURCE_BRANCH" = refs/heads/main
            test "$BUILD_REASON" = Manual
            args+=(-destroy)
          fi
          terraform -chdir=infra plan -input=false -lock-timeout=5m \
            -var="aws_region=$AWS_REGION" -var="bucket_name=$WORKLOAD_BUCKET" \
            "${args[@]}" -out=../reports/release.tfplan
          terraform -chdir=infra show -json ../reports/release.tfplan > reports/plan.json
          terraform -chdir=infra show -no-color ../reports/release.tfplan > reports/plan.txt
          if [ "$OPERATION" = deploy ]; then
            jq -e '[.resource_changes[]? | select(.change.actions | index("delete"))] | length == 0' reports/plan.json
          fi
          infracost breakdown --path reports/plan.json --usage-file infracost-usage.yml \
            --format json --out-file reports/infracost.json
          infracost output --path reports/infracost.json --format table > reports/cost.txt
          if [ "$OPERATION" = deploy ]; then
            python3 scripts/check-cost.py
          fi
          sha256sum reports/release.tfplan > reports/plan.sha256
          jq -n --arg commit "$SOURCE_VERSION" --arg operation "$OPERATION" \
            --arg version "$(terraform version -json | jq -r .terraform_version)" \
            --argjson created "$(date +%s)" \
            '{commit:$commit,operation:$operation,terraform:$version,created:$created}' > reports/manifest.json
          cat reports/plan.txt
          cat reports/cost.txt
      env:
        STATE_BUCKET: $(STATE_BUCKET)
        STATE_KEY: $(STATE_KEY)
        WORKLOAD_BUCKET: $(WORKLOAD_BUCKET)
        AWS_REGION: $(AWS_REGION)
        COST_LIMIT_USD: $(COST_LIMIT_USD)
        INFRACOST_API_KEY: $(INFRACOST_API_KEY)
        SOURCE_VERSION: $(Build.SourceVersion)
        SOURCE_BRANCH: $(Build.SourceBranch)
        BUILD_REASON: $(Build.Reason)
        OPERATION: ${{ parameters.operation }}
    - publish: reports
      artifact: reviewed-plan
- stage: Apply
  dependsOn: Plan
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  lockBehavior: sequential
  jobs:
  - deployment: Apply
    environment: releaseforge-production
    strategy:
      runOnce:
        deploy:
          steps:
          - checkout: self
            clean: true
            persistCredentials: false
          - download: none
          - task: DownloadPipelineArtifact@2
            inputs:
              buildType: current
              artifactName: reviewed-plan
              targetPath: $(Build.SourcesDirectory)/reports
          - task: AWSShellScript@1
            displayName: Apply the approved saved plan
            inputs:
              awsCredentials: aws-releaseforge-apply
              regionName: $(AWS_REGION)
              scriptType: inline
              inlineScript: |
                set -euo pipefail
                export AWS_PAGER="" TF_IN_AUTOMATION=true
                cd "$SOURCE_DIRECTORY"
                test "$(jq -r .commit reports/manifest.json)" = "$SOURCE_VERSION"
                test "$(jq -r .terraform reports/manifest.json)" = "$(terraform version -json | jq -r .terraform_version)"
                test "$(jq -r .operation reports/manifest.json)" = "$OPERATION"
                age=$(( $(date +%s) - $(jq -r .created reports/manifest.json) ))
                test "$age" -ge 0
                test "$age" -lt 7200
                sha256sum -c reports/plan.sha256
                aws sts get-caller-identity
                terraform -chdir=infra init -input=false -lockfile=readonly \
                  -backend-config="bucket=$STATE_BUCKET" -backend-config="key=$STATE_KEY" \
                  -backend-config="region=$AWS_REGION" -backend-config="use_lockfile=true"
                terraform -chdir=infra apply -input=false -lock-timeout=5m ../reports/release.tfplan
                if [ "$OPERATION" = deploy ]; then
                  terraform -chdir=infra output
                  aws s3api get-bucket-versioning --bucket "$WORKLOAD_BUCKET"
                  aws s3api get-public-access-block --bucket "$WORKLOAD_BUCKET"
                fi
            env:
              SOURCE_DIRECTORY: $(Build.SourcesDirectory)
              SOURCE_VERSION: $(Build.SourceVersion)
              STATE_BUCKET: $(STATE_BUCKET)
              STATE_KEY: $(STATE_KEY)
              AWS_REGION: $(AWS_REGION)
              WORKLOAD_BUCKET: $(WORKLOAD_BUCKET)
              OPERATION: ${{ parameters.operation }}
EOF
~~~

The planning role needs lock-file writes even though workload access is read-only. Apply never replans. A stale or expired plan needs a new full run and approval.

Plan artifacts contain state-derived information. Restrict artifact access and set a short retention period. Do not publish them publicly.

~~~bash
git add .gitignore infra scripts tools infracost-usage.yml azure-pipelines.yml
git commit -m "Add governed Terraform delivery"
git push origin main
~~~

### Task 11 — Protect deployment before running it

In **Pipelines → Environments → New environment**, create **releaseforge-production** with resource type **None**.

Open **Approvals and checks** and add:

1. **Approvals**: your user. Allow requester approval only for this single-user exercise.
2. **Branch control**: allow **refs/heads/main** and require branch protection.
3. **Exclusive lock**.

Create the delivery pipeline through **Pipelines → New pipeline → Azure Repos Git → releaseforge-infra → Existing YAML → azure-pipelines.yml**. Choose **Save**, not run, when offered. Name it **ReleaseForge Delivery**.

Authorize only this pipeline in the pool, variable group, environment, and both service connections. Remove bootstrap-pipeline access from both connections. On **aws-releaseforge-apply → Approvals and checks**, also add a main-only branch-control check.

In **Repos → Branches → main → Branch policies**:

- Require a reviewer. Allow requester review only for this single-user exercise.
- Add **Build validation → ReleaseForge Delivery → Automatic → Required**.
- Expire validation immediately when main changes.
- Require comments to be resolved.

Azure Repos uses this branch policy for PR triggering; a YAML pr section is not a substitute. Keep service-connection names literal in YAML so checks resolve the intended resources.

For a real team, disable self-approval, require independent reviewers, and assign owners to pipeline and policy changes.

### Task 12 — Deploy the first release

Open **ReleaseForge Delivery → Run pipeline**, choose main and operation **deploy**, then run.

Validate and Plan must pass. Confirm the Plan log shows **iam_role_releaseforge_plan**.

Before approving Apply, open the run's **reviewed-plan** artifact:

1. Review plan.txt: only the workload bucket and its controls should be created.
2. Review cost.txt and infracost.json: the workload estimate must be within budget.
3. Review manifest.json: its commit must match the run and operation must be deploy.
4. Approve the pending environment check.

Apply must show **iam_role_releaseforge_apply** and apply that saved plan. Approve within two hours or rerun for a fresh plan.

### Task 13 — Verify the live infrastructure

In CloudShell:

~~~bash
source "$HOME/releaseforge-session.env"
export AWS_PAGER=""
~~~

~~~bash
aws s3api get-bucket-versioning --bucket "$WORKLOAD_BUCKET"
~~~

Expected: Enabled.

~~~bash
aws s3api get-bucket-encryption --bucket "$WORKLOAD_BUCKET"
~~~

Expected: AES256.

~~~bash
aws s3api get-public-access-block --bucket "$WORKLOAD_BUCKET"
~~~

Expected: all four values true.

~~~bash
aws s3api get-bucket-tagging --bucket "$WORKLOAD_BUCKET"
~~~

Expected: Project=ReleaseForge and Release=release-1.

~~~bash
aws s3api list-object-versions --bucket "$STATE_BUCKET" --prefix "$STATE_KEY" \
  --query 'Versions[].{Key:Key,Version:VersionId,Latest:IsLatest}' --output table
~~~

State must have a version. After completion, no current live .tflock object should remain. Historical lock versions or delete markers are normal.

### Task 14 — Prove the security gate

On EC2:

~~~bash
cd "$HOME/releaseforge-infra"
git checkout main
git pull origin main
git checkout -b test/security-gate
~~~

~~~bash
sed -i 's/block_public_acls       = true/block_public_acls       = false/' infra/main.tf
git add infra/main.tf
git commit -m "Exercise public access gate"
git push origin test/security-gate
~~~

In **Repos → Pull requests → New pull request**, select this branch into main. Required validation should fail at Checkov. Plan and Apply must not run; the live bucket must remain unchanged.

Fix the branch:

~~~bash
sed -i 's/block_public_acls       = false/block_public_acls       = true/' infra/main.tf
git add infra/main.tf
git commit -m "Restore public access protection"
git push origin test/security-gate
~~~

Validation should pass and Apply should be skipped for the PR. Abandon the test PR; it has no workload change to merge.

### Task 15 — Deliver a reviewed update

~~~bash
git checkout main
git pull origin main
git checkout -b feature/release-2
sed -i 's/default = "release-1"/default = "release-2"/' infra/variables.tf
git add infra/variables.tf
git commit -m "Label the second infrastructure release"
git push origin feature/release-2
~~~

Create a PR into main. Review successful security, plan, and cost checks. Approve and complete the PR. The merge triggers a fresh main plan; review and approve that run, not the PR artifact.

In CloudShell:

~~~bash
aws s3api get-bucket-tagging --bucket "$WORKLOAD_BUCKET"
~~~

Expected: Release=release-2. Run main again to confirm a no-change plan.

For a cost-gate test, create another branch with a much higher storage_gb assumption. Its estimate must exceed the budget and prevent Apply. Abandon that PR after checking the failure.

### Task 16 — Clean up through approval

The workload bucket remains empty in this project. Do not upload data before cleanup; force_destroy is deliberately false.

In **ReleaseForge Delivery → Run pipeline**, choose main and **destroy**. Review the destroy artifact and approve only if it deletes the workload resources. Destruction is accepted only for manual main runs. The monthly budget gate applies to deploy, not destroy; cleanup still produces a cost report and requires approval.

Verify deletion in CloudShell:

~~~bash
aws s3api head-bucket --bucket "$WORKLOAD_BUCKET"
~~~

A not-found result confirms deletion. AccessDenied alone does not.

Then:

1. Disable both pipelines and remove the project service connections.
2. On EC2, from $HOME/azagent, run sudo ./svc.sh stop.
3. Remove the agent from its pool and revoke the Git PAT.
4. Terminate only the releaseforge-agent EC2 instance.
5. Detach the two ReleaseForge policies, delete the two roles, then delete those policies in IAM.
6. Delete the OIDC provider only if no other role uses it.
7. Retain state for audit, or download it before deletion. To delete its bucket, use **S3 → bucket → Empty** to remove all versions and delete markers, then delete the bucket.

Do not delete shared identity providers or another project's resources.

## Validation checklist

- [ ] Both playgrounds were used for the live run.
- [ ] The agent is online without AWS access keys or an instance role.
- [ ] Both connections assume their exact OIDC roles.
- [ ] State is private, encrypted, versioned, and natively locked.
- [ ] An unsafe PR fails before infrastructure changes.
- [ ] Cost assumptions are explicit and an over-budget deploy fails.
- [ ] Main deployments require approval and apply the current run's saved plan.
- [ ] The live bucket has the expected protections and release tag.
- [ ] An approved destroy removes only the workload.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Agent offline or job queued | Check the EC2 instance, agent service, and pool authorization. |
| OIDC assumption denied | Compare issuer, audience, exact subject, and role ARN. |
| IAM bootstrap denied | Resolve the specific permission; do not bypass it with administrator access. |
| AWS task unavailable | Install the AWS Toolkit extension in this organization. |
| Native lock unsupported | Check the job runs Terraform 1.14.9, not an old executable. |
| State locked | Inspect active runs before considering force-unlock. |
| Security check fails | Review published test results and fix the resource, not the gate. |
| Missing cost | Check the API key and network access. Missing is not zero. |
| Branch check fails | Use main and configure its branch policies. |
| Saved plan stale or expired | Rerun the full pipeline and review a fresh plan. |
| Bucket not empty during destroy | Remove only project-owned objects and versions after reviewing them. |

## Taking the pattern to production scale

Use separate accounts and state keys for environments, independent reviewers, workload-specific roles, and centrally governed templates. Restrict who can change checks, connections, variables, and branch policies.

Replace this persistent exercise agent with isolated, short-lived agents. Do not run untrusted PR code on a production-credentialed host. The PR planning role reads state: limit it to trusted contributors and use a validation-only workflow for external contributions.

Add full security policy coverage, dependency provenance checks, drift schedules, audit retention, and alerts. Include bootstrap infrastructure in the wider cost inventory. The selected scanner checks and workload estimate are a starting baseline, not complete enterprise controls.

## What you learned

You delivered real AWS infrastructure from Azure DevOps using federation rather than AWS access keys. You separated plan and apply privileges, protected state, blocked unsafe changes, and promoted a saved plan through approval before deployment.

## References

- [AWS–Azure DevOps OIDC federation](https://aws.amazon.com/blogs/modernizing-with-aws/how-to-federate-into-aws-from-azure-devops-using-openid-connect/)
- [AWS Toolkit for Azure DevOps](https://github.com/aws/aws-toolkit-azure-devops)
- [Linux pipeline agents](https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/linux-agent?view=azure-devops)
- [Azure Repos branch policies](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies?view=azure-devops)
- [Pipeline approvals and checks](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/approvals?view=azure-devops)
- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Checkov CLI](https://www.checkov.io/2.Basics/CLI%20Command%20Reference.html)
- [Infracost Azure Pipelines integration](https://www.infracost.io/docs/integrations/azure_pipelines/)
- [Infracost usage parameters](https://github.com/infracost/infracost/blob/master/infracost-usage-example.yml)
- [AWS playground](https://kodekloud.com/cloud-playgrounds/aws)
- [Azure DevOps playground](https://kodekloud.com/cloud-playgrounds/azure-devops)
```
