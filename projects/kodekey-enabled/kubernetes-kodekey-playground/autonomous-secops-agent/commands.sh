#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f target-infra.yaml
kubectl wait --for=condition=available deployment/web-gateway-target --timeout=60s
kubectl wait --for=condition=available deployment/ops-notifier --timeout=60s

kubectl apply -f secops-rbac.yaml
kubectl auth can-i get pods --as=system:serviceaccount:default:secops-agent-sa
kubectl auth can-i get pods/log --as=system:serviceaccount:default:secops-agent-sa
kubectl auth can-i get secrets --as=system:serviceaccount:default:secops-agent-sa

kubectl port-forward deployment/ops-notifier 8085:80 --address 0.0.0.0 &
sleep 3

curl -s -X POST http://localhost:8085/application \
  -H 'Content-Type: application/json' \
  -u 'admin:SecOpsAdmin2026!' \
  -d '{"name":"SecOps Streaming Broker","description":"AI Pipeline Ingestion Node"}'

export KK_API_KEY="paste-your-kodekey-api-key-here"
export KK_BASE_URL="paste-your-kodekey-base-url-here"
export GOTIFY_SERVER_TOKEN="paste-your-gotify-application-token-here"



kubectl apply -f secops-config.yaml

mkdir -p secops-build

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

curl -s "http://localhost:30080/index.html?file=../../../../etc/passwd" >/dev/null
curl -s "http://localhost:30080/login.php?query=UNION%20SELECT%20username,%20password%20FROM%20users" >/dev/null

AGENT_POD=$(kubectl get pods -l tier=security-ops -o jsonpath='{.items[0].metadata.name}')
kubectl logs "$AGENT_POD" --tail=40
curl -s -u 'admin:SecOpsAdmin2026!' http://localhost:8085/message | jq .

kubectl get deployment secops-intelligence-agent -o jsonpath='{.spec.template.spec.serviceAccountName}'
kubectl get role log-streamer-role -o jsonpath='{.rules[*].resources}'
kubectl get pods -l tier=security-ops
curl -s -u 'admin:SecOpsAdmin2026!' http://localhost:8085/message | jq '.messages | length'
