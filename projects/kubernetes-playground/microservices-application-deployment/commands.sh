#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f legal-tech-secret.yaml

kubectl apply -f legal-tech-stack.yaml

kubectl get deployment python-doc-worker -o jsonpath='{.spec.template.spec.containers[0].resources}'

kubectl get svc redis-master

kubectl describe deployment node-frontend-api | grep -A 3 REDIS_PASSWORD

kubectl port-forward deployment/node-frontend-api 8082:3000 --address 0.0.0.0 &

curl http://localhost:8082

kubectl get pods -l app=doc-worker

kubectl logs -f <pod-name>

curl http://localhost:8082

kubectl get deployment python-doc-worker -o jsonpath='{.spec.template.spec.containers[0].resources}'

kubectl get svc redis-master
