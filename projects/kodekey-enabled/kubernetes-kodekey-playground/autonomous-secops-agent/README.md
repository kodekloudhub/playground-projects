# Autonomous SecOps Agent

**Level:** advanced  ·  **Playground:** Kubernetes | KodeKey Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-kubernetes-single-node-latest, https://kodekloud.com/ai-playgrounds/kodekey)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

```yaml
---
# ─── Metadata (read by the playground for listing & filtering) ───
id: autonomous-secops-agent
title: Autonomous SecOps Agent
playground: Kubernetes single-node (latest)
playground_link: https://kodekloud.com/playgrounds/playground-kubernetes-single-node-latest, https://kodekloud.com/ai-playgrounds/kodekey
difficulty: advanced
estimated_minutes: 60
tags:
  - kubernetes
  - security
  - python
  - ai
  - rbac
skills:
  - Kubernetes log streaming
  - least-privilege RBAC
  - rule-based and AI-assisted detection
  - ConfigMaps and Secrets
prerequisites:
  - Advanced understanding of Kubernetes Pods and Deployments
  - Intermediate Python and HTTP knowledge
  - Familiarity with RBAC authorization
---

# Autonomous SecOps Agent for Log Anomaly Detection

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

- Playground: **{{ playground }}** (open it before starting)
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

### Task 1 — Deploy the target gateway and Gotify

Create the target application and notification sink:

```bash
cat << 'EOF' > target-infra.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-gateway-target
  labels:
    app: web-gateway
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-gateway
  template:
    metadata:
      labels:
        app: web-gateway
    spec:
      containers:
        - name: nginx
          image: nginx:1.25-alpine
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web-gateway-svc
spec:
  type: NodePort
  selector:
    app: web-gateway
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ops-notifier
  labels:
    app: ops-notifier
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ops-notifier
  template:
    metadata:
      labels:
        app: ops-notifier
    spec:
      containers:
        - name: gotify
          image: gotify/server:latest
          ports:
            - containerPort: 80
          env:
            - name: GOTIFY_DEFAULTUSER_PASS
              value: "SecOpsAdmin2026!"
---
apiVersion: v1
kind: Service
metadata:
  name: ops-notifier-svc
spec:
  selector:
    app: ops-notifier
  ports:
    - port: 80
      targetPort: 80
EOF

kubectl apply -f target-infra.yaml
kubectl wait --for=condition=available deployment/web-gateway-target --timeout=60s
kubectl wait --for=condition=available deployment/ops-notifier --timeout=60s
```

> **Why:** This creates both sides of the event pipeline: Nginx produces telemetry and Gotify receives the resulting security report.

### Task 2 — Grant only pod and pod-log access

Create and apply the agent's namespace-scoped RBAC policy:

```bash
cat << 'EOF' > secops-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: secops-agent-sa
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: log-streamer-role
  namespace: default
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: secops-agent-rbac-bind
  namespace: default
subjects:
  - kind: ServiceAccount
    name: secops-agent-sa
    namespace: default
roleRef:
  kind: Role
  name: log-streamer-role
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f secops-rbac.yaml
kubectl auth can-i get pods --as=system:serviceaccount:default:secops-agent-sa
kubectl auth can-i get pods/log --as=system:serviceaccount:default:secops-agent-sa
kubectl auth can-i get secrets --as=system:serviceaccount:default:secops-agent-sa
```

Expected results are `yes`, `yes`, and `no`.

### Task 3 — Open Gotify on port 8085 and create the app token

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

### Task 4 — Obtain KodeKey credentials and create configuration

Open [KodeKey](https://kodekloud.com/ai-playgrounds/kodekey), choose **Launch now**, then **Start Playground**. Copy the displayed Base URL and API Key. Keep them in shell variables; do not write the key into a manifest or source file.

```bash
export KK_API_KEY="paste-your-kodekey-api-key-here"
export KK_BASE_URL="paste-your-kodekey-base-url-here"
export GOTIFY_SERVER_TOKEN="paste-your-gotify-application-token-here"

cat << EOF > secops-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: secops-agent-config
data:
  TARGET_NAMESPACE: "default"
  LABEL_SELECTOR: "app=web-gateway"
  AI_MODEL_NAME: "gpt-6-luna"
  NOTIFIER_URL: "http://ops-notifier-svc/message"
---
apiVersion: v1
kind: Secret
metadata:
  name: secops-agent-secret
type: Opaque
data:
  ai-api-key: $(printf %s "$KK_API_KEY" | base64 -w 0)
  ai-base-url: $(printf %s "$KK_BASE_URL" | base64 -w 0)
  gotify-token: $(printf %s "$GOTIFY_SERVER_TOKEN" | base64 -w 0)
EOF

kubectl apply -f secops-config.yaml
```

> **Why:** Runtime configuration and credentials can change independently, and the Secret prevents tokens from being embedded in the agent image.

### Task 5 — Create the streaming agent

Create the Python source with a local signature filter and a five-minute Gotify cooldown. The cooldown key is derived from the normalized alert title and incident class, so model retries do not fire duplicate notifications while failed deliveries remain retryable.

```bash
mkdir -p secops-build
cat << 'EOF' > secops-build/stream_agent.py
import hashlib
import json
import os
import re
import sys
import time
import urllib.request
from threading import Lock, Thread

from kubernetes import client, config
from smolagents import OpenAIServerModel, ToolCallingAgent

try:
    config.load_incluster_config()
except Exception as exc:
    print(f"Failed to load cluster credentials: {exc}", flush=True)
    sys.exit(1)

v1 = client.CoreV1Api()
NAMESPACE = os.getenv("TARGET_NAMESPACE", "default")
SELECTOR = os.getenv("LABEL_SELECTOR", "app=web-gateway")
NOTIFIER_URL = os.getenv("NOTIFIER_URL")
GOTIFY_TOKEN = os.getenv("GOTIFY_TOKEN")
AI_API_KEY = os.getenv("AI_API_KEY")
AI_BASE_URL = os.getenv("AI_BASE_URL")
AI_MODEL_NAME = os.getenv("AI_MODEL_NAME", "gpt-6-luna")
DEDUPE_SECONDS = 300
_dedupe_lock = Lock()
_last_alert = {}
_claimed_incidents = set()

ATTACK_SIGNATURES = [
    re.compile(r"\.\./", re.I),
    re.compile(r"%2f", re.I),
    re.compile(r"UNION\s+SELECT", re.I),
    re.compile(r"SELECT.*FROM", re.I),
]

def classify_incident(line):
    """Return a deterministic incident class before any AI call is made."""
    if re.search(r"UNION\s+SELECT|SELECT.*FROM", line, re.I):
        return "sql-injection"
    if re.search(r"\.\./|%2f", line, re.I):
        return "path-traversal"
    if re.search(r"(?:403|404|499)", line, re.I):
        return "reconnaissance"
    return None

def claim_incident(incident_class):
    """Allow one AI investigation per incident class in this run."""
    with _dedupe_lock:
        if incident_class in _claimed_incidents:
            return False
        _claimed_incidents.add(incident_class)
        return True

def alert_key(title, message, incident_class):
    normalized = re.sub(r"\s+", " ", message).lower()
    return hashlib.sha256(f"{title.lower()}|{incident_class}|{normalized[:200]}".encode()).hexdigest()

def send_gotify(title, message, incident_class):
    if not NOTIFIER_URL or not GOTIFY_TOKEN:
        return "Notifier configuration is incomplete."
    key = alert_key(title, message, incident_class)
    with _dedupe_lock:
        if time.time() - _last_alert.get(key, 0) < DEDUPE_SECONDS:
            return "Duplicate alert suppressed during cooldown."
        _last_alert[key] = time.time()
    payload = json.dumps({"title": title, "message": message, "priority": 7}).encode()
    request = urllib.request.Request(
        f"{NOTIFIER_URL}?token={GOTIFY_TOKEN}",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            if response.status == 200:
                return "Alert delivered to Gotify."
            with _dedupe_lock:
                _last_alert.pop(key, None)
            return f"Gotify returned HTTP {response.status}."
    except Exception as exc:
        with _dedupe_lock:
            _last_alert.pop(key, None)
        return f"Gotify delivery failed: {exc}"

def investigate(raw_line, pod_name, incident_class):
    model = OpenAIServerModel(model_id=AI_MODEL_NAME, api_base=AI_BASE_URL, api_key=AI_API_KEY)

    agent = ToolCallingAgent(tools=[], model=model)
    prompt = (
        f"Analyze this suspicious log line from pod {pod_name}: {raw_line}. "
        "Describe the attack and mitigation. Use the exact title 'SecOps Web Log Anomaly'. "
        "The notification is dispatched by the host process exactly once."
    )
    report = agent.run(prompt)
    print(send_gotify("SecOps Web Log Anomaly", str(report), incident_class), flush=True)

def monitor(pod_name):
    stream = v1.read_namespaced_pod_log(
        name=pod_name,
        namespace=NAMESPACE,
        follow=True,
        tail_lines=0,
        _preload_content=False,
    )
    for raw_line in iter(stream.readline, b""):
        line = raw_line.decode("utf-8", errors="replace").strip()
        incident_class = classify_incident(line)
        if incident_class and claim_incident(incident_class):
            Thread(
                target=investigate,
                args=(line, pod_name, incident_class),
                daemon=True,
            ).start()

def main():
    pods = v1.list_namespaced_pod(namespace=NAMESPACE, label_selector=SELECTOR)
    if not pods.items:
        print("No matching target pods found.", flush=True)
        return
    threads = [Thread(target=monitor, args=(pod.metadata.name,), daemon=True) for pod in pods.items]
    for thread in threads:
        thread.start()
    while True:
        time.sleep(1)

if __name__ == "__main__":
    main()
EOF
```

> **Why:** The regex stage is cheap and immediate; only matching events reach the model, and the notification cooldown makes alert delivery idempotent for the lab's incident window.

### Task 6 — Mount and run the agent in Kubernetes

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

### Task 7 — Generate an incident and verify the end-to-end alert

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

# Blog Version
## Build an AI-Assisted SecOps Agent for Kubernetes Logs with KodeKey
Imagine you manage an e-commerce application running on Kubernetes. Its web gateway starts receiving requests with unusual file paths and SQL-like query strings. You want to spot these requests as they arrive and turn them into reports your operations team can review.
This project connects Kubernetes logs, Python, an AI model through KodeKey, and a notification dashboard. Local rules select suspicious log entries. The model explains them, and the Python application sends the explanation to Gotify.
In this complete walkthrough, you will create every manifest, add the full Python source, deploy the application, and send test requests through it. Run the steps in order in the playground terminal.
The project is called an autonomous SecOps agent because it monitors and reports automatically. Its actions stop at sending a notification: a person reviews the report and decides what to do next.
## What you'll build
You will deploy two Nginx pods as the target application and Gotify as the notification dashboard. A Python agent inside the cluster will use a dedicated ServiceAccount with namespace-scoped access to pods and pod logs.
The agent checks new log lines with regular expressions before sending selected entries to a model through KodeKey. The Python process then sends the model's report to Gotify.
The supplied implementation investigates each incident class at most once per Python process run. It also contains a five-minute cooldown in its notification function. We will explain how those two controls interact in Step 5.

| Component | Its job |
| ---| --- |
| Nginx | Receive test requests and produce logs |
| Kubernetes API | Provide access to pod logs |
| Python agent | Read logs, classify entries, call the model, and send notifications |
| KodeKey | Connect the agent to its selected AI model |
| Gotify | Display the reports |

## What you will learn
By the end you will be able to:
*   Stream pod logs continuously with the Kubernetes Python client.
*   Configure namespace-scoped RBAC for a log-reading workload and identify how to reduce its permissions further.
*   Separate fast rule-based detection from slower AI investigation.
*   Store non-sensitive configuration in a ConfigMap and credentials in a Secret.
*   Deliver and verify security notifications through Gotify.
## Before you begin
Allow about **60 minutes**. This is an **advanced** project: you should understand Kubernetes Pods and Deployments, be comfortable reading Python and HTTP requests, and know the basics of RBAC authorization.
You will need:
*   The [KodeKloud Kubernetes single-node Playground](https://kodekloud.com/playgrounds/playground-kubernetes-single-node-latest), opened before you start.
*   `kubectl` access to that cluster.
*   Familiarity with Kubernetes YAML manifests.
*   Access to [KodeKey](https://kodekloud.com/ai-playgrounds/kodekey).
*   A Bash terminal with `curl`, `base64`, and `jq` for the supplied commands.
Use the playground's Linux terminal. The commands below assume the `default` namespace, and the `base64 -w 0` option uses GNU base64. Set your current namespace before continuing:

```cpp
kubectl config set-context --current --namespace=default
```

## How the pieces work together
The Nginx Deployment generates access logs. At startup, `secops-intelligence-agent` discovers the matching pods and starts following their logs through the Kubernetes API. It applies local rules, asks the model to explain selected entries, and sends reports to the internal Gotify Service. You open Gotify in the browser through a port-forward on port `8085`.

```elixir
Nginx pods -> Kubernetes pod-log API -> regex filter -> KodeKey model -> Gotify
                                      ^
                              least-privilege RBAC
```

## Step 1: Deploy Nginx and Gotify
Start by creating the web server and notification dashboard. This manifest creates two Nginx replicas, a NodePort Service on port `30080`, one Gotify replica, and an internal Service for Gotify:

```yaml
cat << 'EOF' > target-infra.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-gateway-target
  labels:
    app: web-gateway
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-gateway
  template:
    metadata:
      labels:
        app: web-gateway
    spec:
      containers:
        - name: nginx
          image: nginx:1.25-alpine
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web-gateway-svc
spec:
  type: NodePort
  selector:
    app: web-gateway
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ops-notifier
  labels:
    app: ops-notifier
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ops-notifier
  template:
    metadata:
      labels:
        app: ops-notifier
    spec:
      containers:
        - name: gotify
          image: gotify/server:latest
          ports:
            - containerPort: 80
          env:
            - name: GOTIFY_DEFAULTUSER_PASS
              value: "SecOpsAdmin2026!"
---
apiVersion: v1
kind: Service
metadata:
  name: ops-notifier-svc
spec:
  selector:
    app: ops-notifier
  ports:
    - port: 80
      targetPort: 80
EOF

kubectl apply -f target-infra.yaml
kubectl wait --for=condition=available deployment/web-gateway-target --timeout=60s
kubectl wait --for=condition=available deployment/ops-notifier --timeout=60s
```

Nginx now provides the logs that the agent will read, and Gotify provides a place to display reports. The two `kubectl wait` commands wait for the Deployments to become available.
The Gotify password in this manifest is a shared lab credential. Use it only in this disposable exercise. The manifest does not configure persistent storage for Gotify, so this setup is not intended to retain alerts reliably across pod replacement.
## Step 2: Give the agent access to pods and pod logs
The agent needs a Kubernetes identity and permission to read logs. Create a ServiceAccount, a Role, and a RoleBinding in the `default` namespace:

```yaml
cat << 'EOF' > secops-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: secops-agent-sa
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: log-streamer-role
  namespace: default
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: secops-agent-rbac-bind
  namespace: default
subjects:
  - kind: ServiceAccount
    name: secops-agent-sa
    namespace: default
roleRef:
  kind: Role
  name: log-streamer-role
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f secops-rbac.yaml
kubectl auth can-i get pods --as=system:serviceaccount:default:secops-agent-sa
kubectl auth can-i get pods/log --as=system:serviceaccount:default:secops-agent-sa
kubectl auth can-i get secrets --as=system:serviceaccount:default:secops-agent-sa
```

The expected results are `yes`, `yes`, and `no`. The agent can read pod information and logs, but this Role does not allow it to read Secret objects through the Kubernetes API.
The Role is limited to the namespace, not to the `app=web-gateway` label. That label will control which pods the Python code selects. The supplied Role includes `get`, `list`, and `watch`; the actual code below uses `list` for pods and `get` for pod logs. Reducing it to those operations would make the policy more tightly scoped. See the [Kubernetes RBAC documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) for how Roles and log subresources work.
## Step 3: Open Gotify and create an application token
Start the port-forward:

```haskell
kubectl port-forward deployment/ops-notifier 8085:80 --address 0.0.0.0 &
sleep 3
```

In the KodeKloud UI, click the top-right `...` menu, choose **View Port**, enter `8085`, and click **Open Port**. Log in to Gotify with `admin` and `SecOpsAdmin2026!`, open **Apps**, create an application named `SecOps Streaming Broker`, and copy its generated token.
Alternatively, create the application from the terminal with this API request. This is another way to create an app, not a read-only check: running it after creating the app in the dashboard creates another app. Copy the token returned for the app you choose to use:

```rust
curl -s -X POST http://localhost:8085/application \
  -H 'Content-Type: application/json' \
  -u 'admin:SecOpsAdmin2026!' \
  -d '{"name":"SecOps Streaming Broker","description":"AI Pipeline Ingestion Node"}'
```

Gotify keeps its internal ClusterIP Service, while the port-forward lets you reach it through port `8085`. The `--address 0.0.0.0` option listens on all interfaces so the playground can expose the forwarded port; it does not itself secure the connection.
Keep the Gotify application token for the next step. It lets the agent send messages through the [Gotify message API](https://gotify.net/docs/pushmsg).
## Step 4: Add KodeKey and notification settings
Open [KodeKey](https://kodekloud.com/ai-playgrounds/kodekey), choose **Launch now**, then **Start Playground**. Copy the displayed Base URL and API Key.
Replace the three placeholder values below with your KodeKey API key, base URL, and Gotify application token. The command first puts them in shell variables, then writes them as base64-encoded values into the Secret section of `secops-config.yaml`.
That generated file contains recoverable credentials. Keep it out of source control. Base64 is an encoding, not encryption, as the [Kubernetes Secrets documentation](https://kubernetes.io/docs/concepts/configuration/secret/) explains.
The example selects `gpt-6-luna`. Check that this model ID is available with your KodeKey, or use an available model compatible with the smolagents integration.

```yaml
export KK_API_KEY="paste-your-kodekey-api-key-here"
export KK_BASE_URL="paste-your-kodekey-base-url-here"
export GOTIFY_SERVER_TOKEN="paste-your-gotify-application-token-here"

cat << EOF > secops-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: secops-agent-config
data:
  TARGET_NAMESPACE: "default"
  LABEL_SELECTOR: "app=web-gateway"
  AI_MODEL_NAME: "gpt-6-luna"
  NOTIFIER_URL: "http://ops-notifier-svc/message"
---
apiVersion: v1
kind: Secret
metadata:
  name: secops-agent-secret
type: Opaque
data:
  ai-api-key: $(printf %s "$KK_API_KEY" | base64 -w 0)
  ai-base-url: $(printf %s "$KK_BASE_URL" | base64 -w 0)
  gotify-token: $(printf %s "$GOTIFY_SERVER_TOKEN" | base64 -w 0)
EOF

kubectl apply -f secops-config.yaml
```

The ConfigMap holds the namespace, pod selector, model name, and notification URL. The Secret holds the API key, base URL, and Gotify token. This keeps the credentials out of the Python source and container image.
This application uses one model at a time. KodeKey lets you experiment with other supported models using the same API key. Later, you can change `AI_MODEL_NAME` and restart the agent to compare its reports. The base URL is configuration rather than a secret, but it is stored in the Secret here to preserve the project's setup.
## Step 5: Write the complete Python agent
Now create the source directory and the complete Python application. It connects to the cluster, classifies log lines, asks the model for a report, and sends that report to Gotify. The full source is below:

```python
mkdir -p secops-build
cat << 'EOF' > secops-build/stream_agent.py
import hashlib
import json
import os
import re
import sys
import time
import urllib.request
from threading import Lock, Thread

from kubernetes import client, config
from smolagents import OpenAIServerModel, ToolCallingAgent

try:
    config.load_incluster_config()
except Exception as exc:
    print(f"Failed to load cluster credentials: {exc}", flush=True)
    sys.exit(1)

v1 = client.CoreV1Api()
NAMESPACE = os.getenv("TARGET_NAMESPACE", "default")
SELECTOR = os.getenv("LABEL_SELECTOR", "app=web-gateway")
NOTIFIER_URL = os.getenv("NOTIFIER_URL")
GOTIFY_TOKEN = os.getenv("GOTIFY_TOKEN")
AI_API_KEY = os.getenv("AI_API_KEY")
AI_BASE_URL = os.getenv("AI_BASE_URL")
AI_MODEL_NAME = os.getenv("AI_MODEL_NAME", "gpt-6-luna")
DEDUPE_SECONDS = 300
_dedupe_lock = Lock()
_last_alert = {}
_claimed_incidents = set()

ATTACK_SIGNATURES = [
    re.compile(r"\.\./", re.I),
    re.compile(r"%2f", re.I),
    re.compile(r"UNION\s+SELECT", re.I),
    re.compile(r"SELECT.*FROM", re.I),
]

def classify_incident(line):
    """Return a deterministic incident class before any AI call is made."""
    if re.search(r"UNION\s+SELECT|SELECT.*FROM", line, re.I):
        return "sql-injection"
    if re.search(r"\.\./|%2f", line, re.I):
        return "path-traversal"
    if re.search(r"(?:403|404|499)", line, re.I):
        return "reconnaissance"
    return None

def claim_incident(incident_class):
    """Allow one AI investigation per incident class in this run."""
    with _dedupe_lock:
        if incident_class in _claimed_incidents:
            return False
        _claimed_incidents.add(incident_class)
        return True

def alert_key(title, message, incident_class):
    normalized = re.sub(r"\s+", " ", message).lower()
    return hashlib.sha256(f"{title.lower()}|{incident_class}|{normalized[:200]}".encode()).hexdigest()

def send_gotify(title, message, incident_class):
    if not NOTIFIER_URL or not GOTIFY_TOKEN:
        return "Notifier configuration is incomplete."
    key = alert_key(title, message, incident_class)
    with _dedupe_lock:
        if time.time() - _last_alert.get(key, 0) < DEDUPE_SECONDS:
            return "Duplicate alert suppressed during cooldown."
        _last_alert[key] = time.time()
    payload = json.dumps({"title": title, "message": message, "priority": 7}).encode()
    request = urllib.request.Request(
        f"{NOTIFIER_URL}?token={GOTIFY_TOKEN}",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            if response.status == 200:
                return "Alert delivered to Gotify."
            with _dedupe_lock:
                _last_alert.pop(key, None)
            return f"Gotify returned HTTP {response.status}."
    except Exception as exc:
        with _dedupe_lock:
            _last_alert.pop(key, None)
        return f"Gotify delivery failed: {exc}"

def investigate(raw_line, pod_name, incident_class):
    model = OpenAIServerModel(model_id=AI_MODEL_NAME, api_base=AI_BASE_URL, api_key=AI_API_KEY)

    agent = ToolCallingAgent(tools=[], model=model)
    prompt = (
        f"Analyze this suspicious log line from pod {pod_name}: {raw_line}. "
        "Describe the attack and mitigation. Use the exact title 'SecOps Web Log Anomaly'. "
        "The notification is dispatched by the host process exactly once."
    )
    report = agent.run(prompt)
    print(send_gotify("SecOps Web Log Anomaly", str(report), incident_class), flush=True)

def monitor(pod_name):
    stream = v1.read_namespaced_pod_log(
        name=pod_name,
        namespace=NAMESPACE,
        follow=True,
        tail_lines=0,
        _preload_content=False,
    )
    for raw_line in iter(stream.readline, b""):
        line = raw_line.decode("utf-8", errors="replace").strip()
        incident_class = classify_incident(line)
        if incident_class and claim_incident(incident_class):
            Thread(
                target=investigate,
                args=(line, pod_name, incident_class),
                daemon=True,
            ).start()

def main():
    pods = v1.list_namespaced_pod(namespace=NAMESPACE, label_selector=SELECTOR)
    if not pods.items:
        print("No matching target pods found.", flush=True)
        return
    threads = [Thread(target=monitor, args=(pod.metadata.name,), daemon=True) for pod in pods.items]
    for thread in threads:
        thread.start()
    while True:
        time.sleep(1)

if __name__ == "__main__":
    main()
EOF
```

Here is how the code works:
1. **Connect to Kubernetes.** `load_incluster_config()` uses the credentials mounted for the Pod's ServiceAccount. This script is designed to run inside the cluster.
2. **Find the target pods.** `main()` lists pods matching `app=web-gateway` and starts one monitoring thread for each pod.
3. **Read new logs.** `follow=True` keeps each log stream open, and `tail_lines=0` skips existing log history.
4. **Classify each entry.** `classify_incident()` looks for SQL-like strings, traversal-like paths, or the numbers `403`, `404`, and `499`.
5. **Select an investigation.** `claim_incident()` records the class before launching an investigation thread.
6. **Generate a report.** `OpenAIServerModel` connects through KodeKey. `ToolCallingAgent` receives no operational tools; the prompt asks it to explain the log line and suggest mitigation.
7. **Send the notification.** The Python process calls `send_gotify()` after the model returns. It sends a report titled `SecOps Web Log Anomaly` with priority `7`.
The model connection uses `model_id`, `api_base`, and `api_key`, as described in the [smolagents model reference](https://huggingface.co/docs/smolagents/reference/models).
A few details matter when interpreting the results:
*   **The classifier is a simple lab example.** `%2f` may occur in legitimate requests. The status-like numbers are matched anywhere in a log line, not specifically in the HTTP status field. A match needs review and does not prove an attack succeeded.
*   **The** **`ATTACK_SIGNATURES`** **list is not used by the monitoring loop.** The active rules are inside `classify_incident()`.
*   **Each incident class is investigated at most once per process run.** `_claimed_incidents` is never cleared while the process is running. This control is shared across the monitored pods.
*   **The five-minute cooldown is a separate control.** Its key combines the lowercased title, incident class, and first 200 characters of the normalized message. Because the earlier class check blocks later investigations, the current flow does not produce a fresh report for the same class every five minutes.
*   **Failed delivery does not trigger an automatic retry.** The send function removes its cooldown entry after a reported failure, but the incident class stays claimed. Model failures also leave the class claimed.
*   **Log streams do not reconnect automatically.** Pods are discovered only at startup. If a pod is replaced or a stream breaks, restart the agent to discover the current pods again.
The raw log line is external input included in the prompt. Use the report as an explanation to review, not as an instruction to execute automatically.
## Step 6: Run the agent in Kubernetes
Create a ConfigMap containing `stream_agent.py`, then append the agent Deployment to the same manifest. The Deployment mounts the source at `/app` and runs it using the dedicated ServiceAccount:

```yaml
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

The container installs `kubernetes` and `smolagents[openai]` at startup, then runs the Python script. This requires package-network access. The dependencies are unpinned in the supplied project, so versions can change between runs.
The ConfigMap supplies ordinary environment variables, and the Secret supplies the three credential-related values. Kubernetes can inject these values without granting the application permission to read Secret objects through the API.
A completed rollout shows that the Deployment is available, but this manifest has no application readiness probe. Package installation and log-stream setup may still be in progress. Check the startup logs before sending test requests:

```haskell
kubectl logs deployment/secops-intelligence-agent --tail=60
```

If you later edit the model setting, apply the ConfigMap again and restart the Deployment to load the changed environment:

```haskell
kubectl apply -f secops-config.yaml
kubectl rollout restart deployment/secops-intelligence-agent
kubectl rollout status deployment/secops-intelligence-agent --timeout=120s
```

## Step 7: Generate test requests and check the alerts
Once the agent has started following logs, send these attack-shaped requests to the Nginx NodePort in your playground. Then inspect the agent output and retrieve Gotify messages:

```perl
curl -s "http://localhost:30080/index.html?file=../../../../etc/passwd" >/dev/null
curl -s "http://localhost:30080/login.php?query=UNION%20SELECT%20username,%20password%20FROM%20users" >/dev/null

AGENT_POD=$(kubectl get pods -l tier=security-ops -o jsonpath='{.items[0].metadata.name}')
kubectl logs "$AGENT_POD" --tail=40
curl -s -u 'admin:SecOpsAdmin2026!' http://localhost:8085/message | jq .
```

These requests create suspicious-looking log entries. They do not demonstrate a successful path traversal or SQL injection exploit: the target is a basic Nginx server.
Allow time for the model and notification request to complete, then check Gotify in the browser on port `8085`. A successful send prints `Alert delivered to Gotify.` in the agent log. If you queried messages immediately, run the check again after the investigation has finished.
Run the same request twice to observe the incident-class check. After the first entry claims a class, subsequent entries in that class are skipped for the remainder of the process run. This early skip is silent; the monitor does not print a duplicate-suppression message for it.
The separate `Duplicate alert suppressed during cooldown.` message belongs to `send_gotify()`. Repeating these HTTP requests does not normally reach that branch because the earlier class check prevents another investigation.
If `localhost:30080` is unavailable in your cluster's NodePort configuration, find the node's reachable address and use that address with port `30080`. If the agent missed requests during startup, send them again after it is running. If an investigation failed after claiming a class, restarting the agent clears the in-memory claims so you can repeat the lab test.
## Step 8: Validate the complete setup

```cs
kubectl get deployment secops-intelligence-agent -o jsonpath='{.spec.template.spec.serviceAccountName}'
kubectl get role log-streamer-role -o jsonpath='{.rules[*].resources}'
kubectl get pods -l tier=security-ops
curl -s -u 'admin:SecOpsAdmin2026!' http://localhost:8085/message | jq '.messages | length'
```

Check the following:
*   The agent Deployment uses `secops-agent-sa`.
*   The Role lists only the `pods` and `pods/log` resources.
*   The agent Pod is running, and its logs show the result of notification delivery after a successful model call. The supplied code does not explicitly print every intercepted request.
*   Gotify contains a report from the test, and repeating the same incident class does not start another investigation during the current process run.
The message-count command shows how many messages the API returns; it does not by itself prove that the model interpreted an event correctly. Open the report and compare it with the test request you sent.
## What you have built
You now have the components of a streaming log-monitoring project: Nginx produces logs, Python reads them through the Kubernetes API, local rules select entries, a model through KodeKey explains them, and Gotify displays the reports.
You also configured namespace-scoped permissions, mounted Python source through a ConfigMap, supplied credentials through a Secret, and opened the notification dashboard on port `8085`. You examined both the incident-class check and the separate notification cooldown, including their limits.
To continue learning, keep a sample log entry and prompt fixed, then try another compatible model through KodeKey using the same API key. Compare whether each report explains the evidence clearly and suggests relevant next steps.
This project is a starting point for experimentation. Timed incident tracking, reliable retries, proper access-log parsing, and stream reconnection would be useful next improvements.
## References & further learning
*   [Kubernetes pod and container logs](https://kubernetes.io/docs/concepts/cluster-administration/logging/)
*   [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
*   [Kubernetes ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
*   [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
*   [Gotify API documentation](https://gotify.net/api-docs)
*   [Hugging Face smolagents documentation](https://huggingface.co/docs/smolagents/en/index)
*   [KodeKloud KodeKey](https://kodekloud.com/ai-playgrounds/kodekey)
*   [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
