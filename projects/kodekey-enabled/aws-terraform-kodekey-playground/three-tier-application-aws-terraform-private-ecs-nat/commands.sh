#!/usr/bin/env bash
set -euo pipefail

If `newgrp` starts a subshell, continue the remaining lab commands inside that shell. Set a region if the previous command prints nothing:

### Task 2 — Obtain KodeKey credentials and prepare the published images

Open [KodeKey](https://kodekloud.com/ai-playgrounds/kodekey), choose **Launch now**, then **Start Playground**. Copy the displayed **Base URL** and **API Key**. Keep the key in a shell variable and do not paste it into a public source file.

### Task 3 — Define Terraform providers, variables, secrets, and the public/private network

Create the foundational Terraform files. The generated `terraform.tfvars` stays local and is ignored by Git.

### Task 4 — Create ECR, IAM, security groups, ALB, RDS, ECS, and outputs

Add the remaining Terraform resources. This stage defines the full AWS dependency graph but does not yet build or publish images.

### Task 5 — Initialize ECR, retag both images, and push them

Create the ECR repositories first, then authenticate Docker to the AWS account. Retag the two published Docker Hub images and push them to ECR. Do not rebuild the images locally.

### Task 6 — Define the ECS task and deploy the three-tier stack

Create the ECS resources and connect the pushed images to the task definition. ECS runs in the dedicated private application subnets without public IPs; the public ALB reaches it internally, and the NAT Gateway provides outbound access. The task definition injects sensitive values with Secrets Manager ARNs and keeps model routing values as ordinary configuration.

Use the required `iam_role_` prefix for the ECS execution and task roles. Attach the standard ECS execution policy, the AWS-managed `AWSSecretsManagerClientReadOnlyAccess` policy, and the S3 task policy.

### Task 7 — Validate the deployment and security boundaries

Wait for the ECS service to become stable, then test the public endpoint, registry state, secret names, and private database DNS record.

Expected result:

- [ ] The ALB returns an HTTP response from the application image.
- [ ] The ECS service has one desired and one running task in a private application subnet.
- [ ] Both ECR repositories contain a `latest` image.
- [ ] Secrets Manager contains the database, KodeKey, and SearXNG secrets.
- [ ] The RDS endpoint resolves privately and is not publicly accessible.
- [ ] The RDS security group allows port 5432 only from the ECS security group.
- [ ] The ECS application subnets route `0.0.0.0/0` through the NAT Gateway.
- [ ] ECS tasks have no public IP address.

## Validation

Expected result:

- [ ] `terraform validate` completes successfully.
- [ ] The ALB responds with an HTTP status code.
- [ ] ECS reports one running task.
- [ ] Both ECR repositories report the `latest` tag.
- [ ] Terraform state contains Secrets Manager references rather than plaintext secret environment values in the ECS task definition.

## References & further learning

- [Docker Engine installation](https://docs.docker.com/engine/install/)
- [Amazon ECR: push an image](https://docs.aws.amazon.com/AmazonECR/latest/userguide/getting-started-cli.html)
- [Amazon ECS task definition parameters](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html)
- [Amazon ECS task execution IAM role](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html)
- [Amazon RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)
- [Terraform AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [KodeKloud KodeKey](https://kodekloud.com/ai-playgrounds/kodekey)
