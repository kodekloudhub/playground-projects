#!/usr/bin/env bash
set -euo pipefail

kubectl cluster-info
kubectl get nodes

kubectl apply -f seatsync-stack.yaml
kubectl wait --for=condition=available deployment --all --timeout=180s
kubectl get deploy,svc,pods

kubectl get deploy,svc,pods

kubectl get pods -l app=seatsync-cache
kubectl get pods -l app=seatsync-backend
kubectl get pods -l app=seatsync-frontend

kubectl get deployment seatsync-backend-deploy -o jsonpath='{.spec.template.spec.containers[0].env}'
kubectl get deployment seatsync-frontend-deploy -o jsonpath='{.spec.template.spec.containers[0].env}'

kubectl get svc redis-cache backend-service frontend-service

kubectl port-forward deployment/seatsync-frontend-deploy 3000:3000 --address 0.0.0.0

kubectl get svc redis-cache backend-service frontend-service

REDIS_POD=$(kubectl get pods -l app=seatsync-cache -o jsonpath='{.items[0].metadata.name}')
BACKEND_POD=$(kubectl get pods -l app=seatsync-backend -o jsonpath='{.items[0].metadata.name}')

kubectl exec "$REDIS_POD" -- redis-cli ping

kubectl logs "$BACKEND_POD"

kubectl scale deployment seatsync-frontend-deploy --replicas=3

kubectl get pods

kubectl get deployment seatsync-frontend-deploy

kubectl get deployment seatsync-redis-deploy -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get deployment seatsync-backend-deploy -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get deployment seatsync-frontend-deploy -o jsonpath='{.spec.template.spec.containers[0].image}'

kubectl get deployment seatsync-backend-deploy -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="REDIS_HOST")].value}'
kubectl get deployment seatsync-frontend-deploy -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="BACKEND_URL")].value}'
kubectl get svc redis-cache backend-service frontend-service -o jsonpath='{.items[*].spec.type}'

kubectl exec "$(kubectl get pods -l app=seatsync-cache -o jsonpath='{.items[0].metadata.name}')" -- redis-cli ping

kubectl get deployment seatsync-frontend-deploy -o jsonpath='{.status.readyReplicas}'
kubectl get endpoints frontend-service -o jsonpath='{.subsets[0].addresses[*].ip}'
