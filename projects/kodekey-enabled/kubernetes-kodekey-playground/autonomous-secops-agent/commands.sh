#!/usr/bin/env bash
set -euo pipefail

## Steps

### Task 1 — Deploy the target gateway and Gotify

Create the target application and notification sink:

> **Why:** This creates both sides of the event pipeline: Nginx produces telemetry and Gotify receives the resulting security report.

### Task 2 — Grant only pod and pod-log access

Create and apply the agent's namespace-scoped RBAC policy:

Expected results are `yes`, `yes`, and `no`.

### Task 3 — Open Gotify on port 8085 and create the app token

Start the port-forward:

In the KodeKloud UI, click the top-right `...` menu, choose **View Port**, enter `8085`, and click **Open Port**. Log in to Gotify with `admin` and `SecOpsAdmin2026!`, open **Apps**, create an application named `SecOps Streaming Broker`, and copy its generated token.

You can also verify the application API by creating a new terminal session:

> **Why:** The browser port is deliberately `8085`, while Gotify remains ClusterIP-only inside Kubernetes.

### Task 4 — Obtain KodeKey credentials and create configuration

Open [KodeKey](https://kodekloud.com/ai-playgrounds/kodekey), choose **Launch now**, then **Start Playground**. Copy the displayed Base URL and API Key. Keep them in shell variables; do not write the key into a manifest or source file.

> **Why:** Runtime configuration and credentials can change independently, and the Secret prevents tokens from being embedded in the agent image.

### Task 5 — Create the streaming agent

Create the Python source with a local signature filter and a five-minute Gotify cooldown. The cooldown key is derived from the normalized alert title and incident class, so model retries do not fire duplicate notifications while failed deliveries remain retryable.

> **Why:** The regex stage is cheap and immediate; only matching events reach the model, and the notification cooldown makes alert delivery idempotent for the lab's incident window.

### Task 6 — Mount and run the agent in Kubernetes

Create a ConfigMap from the source and deploy it with the dedicated ServiceAccount:

### Task 7 — Generate an incident and verify the end-to-end alert

Send attack-shaped requests to the NodePort, inspect the agent log, and check Gotify in the browser on port `8085`:

Run the same request twice if you want to test deduplication. The Gotify dashboard should contain one notification for the alert class during the five-minute cooldown, while the agent log reports the second attempt as suppressed.

## Validation

Expected result:

- [ ] The agent ServiceAccount is `secops-agent-sa`.
- [ ] The Role contains only `pods` and `pods/log` resources.
- [ ] The agent pod is running and logs the intercepted request.
- [ ] Gotify contains an alert, with duplicate sends suppressed during the cooldown.

## What you learned

You built a real-time Kubernetes log pipeline with least-privilege access, separated deterministic detection from AI investigation, injected configuration through Kubernetes primitives, exposed Gotify safely through port `8085`, and made notification delivery idempotent for repeated detection or model retries.

## References & further learning

- Kubernetes pod and container logs: https://kubernetes.io/docs/concepts/cluster-administration/logging/
- Kubernetes RBAC: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- Kubernetes ConfigMaps: https://kubernetes.io/docs/concepts/configuration/configmap/
- Kubernetes Secrets: https://kubernetes.io/docs/concepts/configuration/secret/
- Gotify API documentation: https://gotify.net/api-docs
- Hugging Face smolagents documentation: https://huggingface.co/docs/smolagents/en/index
- KodeKloud KodeKey: https://kodekloud.com/ai-playgrounds/kodekey
- Kubernetes Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
