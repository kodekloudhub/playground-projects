# AI Security Log Monitor

## Project info

- **ID:** autonomous-secops-agent
- **Title:** Autonomous SecOps Agent
- **Playground:** Kubernetes single-node (latest)
- **Playground link:** [https://kodekloud.com/playgrounds/playground-kubernetes-single-node-latest](https://kodekloud.com/playgrounds/playground-kubernetes-single-node-latest), [https://kodekloud.com/ai-playgrounds/kodekey](https://kodekloud.com/ai-playgrounds/kodekey)
- **Difficulty:** advanced
- **Estimated minutes:** 60
- **Tags:**
  - kubernetes
  - security
  - python
  - ai
  - rbac
- **Skills:**
  - Kubernetes log streaming
  - least-privilege RBAC
  - rule-based and AI-assisted detection
  - ConfigMaps and Secrets
- **Prerequisites:**
  - Advanced understanding of Kubernetes Pods and Deployments
  - Intermediate Python and HTTP knowledge
  - Familiarity with RBAC authorization

## Scenario

An e-commerce platform is receiving path traversal, SQL injection, and reconnaissance requests against its web gateway. Batch log analysis is too slow for an active incident, so the security team needs a lightweight agent that can stream Kubernetes logs, identify suspicious activity quickly, and send an actionable notification to the operations team.

## What you'll build

You will deploy an Nginx target and a Gotify notification sink, grant a dedicated ServiceAccount only the permissions needed to read pod logs, and run a Python agent inside the cluster. The agent uses a fast regex pre-filter before asking a KodeKey-hosted model to explain the incident and send one Gotify alert for each detection window.

## Learning objectives

By the end you will be able to:

- Stream pod logs continuously with the Kubernetes Python client.
- Apply least-privilege RBAC to a workload that reads pod logs.
- Separate fast rule-based detection from slower AI investigation.
- Store non-sensitive configuration in a ConfigMap and credentials in a Secret.
- Deliver and verify security notifications through Gotify.

## Prerequisites

- Playground: **Kubernetes single-node (latest)** (open it before starting)
- `kubectl` access to the single-node cluster
- Basic Python, HTTP, and Kubernetes manifest knowledge

## Architecture / overview

The Nginx Deployment generates access logs. The `secops-intelligence-agent` Deployment discovers matching pods, follows their logs through the Kubernetes API, applies local attack signatures, and sends AI-generated reports to the internal Gotify Service. Gotify is exposed to the browser through port `8085`.

```text
Nginx pods -> Kubernetes pod-log API -> regex filter -> KodeKey model -> Gotify
                                      ^
                              least-privilege RBAC
```

## Steps

### Task 1 - Deploy the target gateway and Gotify

Create the target application and notification sink:

> 📄 **[`target-infra.yaml`](./target-infra.yaml)**

```bash
kubectl apply -f target-infra.yaml
kubectl wait --for=condition=available deployment/web-gateway-target --timeout=60s
kubectl wait --for=condition=available deployment/ops-notifier --timeout=60s
```

> **Why:** This creates both sides of the event pipeline: Nginx produces telemetry and Gotify receives the resulting security report.

### Task 2 - Grant only pod and pod-log access

Create and apply the agent's namespace-scoped RBAC policy:

> 📄 **[`secops-rbac.yaml`](./secops-rbac.yaml)**

```bash
kubectl apply -f secops-rbac.yaml
kubectl auth can-i get pods --as=system:serviceaccount:default:secops-agent-sa
kubectl auth can-i get pods/log --as=system:serviceaccount:default:secops-agent-sa
kubectl auth can-i get secrets --as=system:serviceaccount:default:secops-agent-sa
```

Expected results are `yes`, `yes`, and `no`.

### Task 3 - Open Gotify on port 8085 and create the app token

Start the port-forward:

```bash
kubectl port-forward deployment/ops-notifier 8085:80 --address 0.0.0.0 &
sleep 3
```

In the KodeKloud UI, click the top-right `...` menu, choose **View Port**, enter `8085`, and click **Open Port**. Log in to Gotify with `admin` and `SecOpsAdmin2026!`, open **Apps**, create an application named `SecOps Streaming Broker`, and copy its generated token.

You can also verify the application API by creating a new terminal session:

```bash
curl -s -X POST http://localhost:8085/application \
  -H 'Content-Type: application/json' \
  -u 'admin:SecOpsAdmin2026!' \
  -d '{"name":"SecOps Streaming Broker","description":"AI Pipeline Ingestion Node"}'
```

> **Why:** The browser port is deliberately `8085`, while Gotify remains ClusterIP-only inside Kubernetes.

### Task 4 - Obtain KodeKey credentials and create configuration

Open [KodeKey](https://kodekloud.com/ai-playgrounds/kodekey), choose **Launch now**, then **Start Playground**. Copy the displayed Base URL and API Key. Keep them in shell variables; do not write the key into a manifest or source file.

```bash
export KK_API_KEY="paste-your-kodekey-api-key-here"
export KK_BASE_URL="paste-your-kodekey-base-url-here"
export GOTIFY_SERVER_TOKEN="paste-your-gotify-application-token-here"
```

> 📄 **[`secops-config.yaml`](./secops-config.yaml)**

```bash
kubectl apply -f secops-config.yaml
```

> **Why:** Runtime configuration and credentials can change independently, and the Secret prevents tokens from being embedded in the agent image.

### Task 5 - Create the streaming agent

Create the Python source with a local signature filter and a five-minute Gotify cooldown. The cooldown key is derived from the normalized alert title and incident class, so model retries do not fire duplicate notifications while failed deliveries remain retryable.

```bash
mkdir -p secops-build
```

> 📄 **[`secops-build/stream_agent.py`](./secops-build/stream_agent.py)**

> **Why:** The regex stage is cheap and immediate; only matching events reach the model, and the notification cooldown makes alert delivery idempotent for the lab's incident window.

### Task 6 - Mount and run the agent in Kubernetes

Create a ConfigMap from the source and deploy it with the dedicated ServiceAccount:

```bash
kubectl create configmap secops-script-source \
  --from-file=stream_agent.py=secops-build/stream_agent.py \
  --dry-run=client -o yaml > agent-runtime.yaml

cat << 'EOF' >> agent-runtime.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secops-intelligence-agent
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      tier: security-ops
  template:
    metadata:
      labels:
        tier: security-ops
    spec:
      serviceAccountName: secops-agent-sa
      containers:
        - name: python-streamer
          image: python:3.13-slim
          command: ["/bin/sh", "-c"]
          args:
            - pip install --no-cache-dir kubernetes "smolagents[openai]" && python -u /app/stream_agent.py
          envFrom:
            - configMapRef:
                name: secops-agent-config
          env:
            - name: AI_API_KEY
              valueFrom:
                secretKeyRef:
                  name: secops-agent-secret
                  key: ai-api-key
            - name: AI_BASE_URL
              valueFrom:
                secretKeyRef:
                  name: secops-agent-secret
                  key: ai-base-url
            - name: GOTIFY_TOKEN
              valueFrom:
                secretKeyRef:
                  name: secops-agent-secret
                  key: gotify-token
          volumeMounts:
            - name: source-volume
              mountPath: /app
      volumes:
        - name: source-volume
          configMap:
            name: secops-script-source
EOF

kubectl apply -f agent-runtime.yaml
kubectl rollout status deployment/secops-intelligence-agent --timeout=120s
```

### Task 7 - Generate an incident and verify the end-to-end alert

Send attack-shaped requests to the NodePort, inspect the agent log, and check Gotify in the browser on port `8085`:

```bash
curl -s "http://localhost:30080/index.html?file=../../../../etc/passwd" >/dev/null
curl -s "http://localhost:30080/login.php?query=UNION%20SELECT%20username,%20password%20FROM%20users" >/dev/null

AGENT_POD=$(kubectl get pods -l tier=security-ops -o jsonpath='{.items[0].metadata.name}')
kubectl logs "$AGENT_POD" --tail=40
curl -s -u 'admin:SecOpsAdmin2026!' http://localhost:8085/message | jq .
```

Run the same request twice if you want to test deduplication. The Gotify dashboard should contain one notification for the alert class during the five-minute cooldown, while the agent log reports the second attempt as suppressed.

## Validation

```bash
kubectl get deployment secops-intelligence-agent -o jsonpath='{.spec.template.spec.serviceAccountName}'
kubectl get role log-streamer-role -o jsonpath='{.rules[*].resources}'
kubectl get pods -l tier=security-ops
curl -s -u 'admin:SecOpsAdmin2026!' http://localhost:8085/message | jq '.messages | length'
```

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
```

```

---

## Files in this folder

The steps above reference these ready-to-use files (copy them onto the playground):

- [`secops-build/stream_agent.py`](./secops-build/stream_agent.py)
- [`secops-config.yaml`](./secops-config.yaml)
- [`secops-rbac.yaml`](./secops-rbac.yaml)
- [`target-infra.yaml`](./target-infra.yaml)
