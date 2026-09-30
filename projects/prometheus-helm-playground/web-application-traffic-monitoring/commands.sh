#!/usr/bin/env bash
set -euo pipefail

while [[ $(helm status prometheus-stack | egrep -w STATUS | awk -F: '{print $2}' | tr -d ' ') != "deployed" ]]; 
do
  echo "Waiting for the kube-prometheus-stack to come up...";
  sleep 5; 
done

helm list

mkdir -p templates

kubectl create configmap retail-code --from-file=app.py --from-file=requirements.txt

kubectl create configmap retail-templates \
  --from-file=templates/index.html \
  --from-file=templates/shop.html \
  --from-file=templates/collections.html \
  --from-file=templates/cart.html

mkdir -p retail-frontend/templates

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx

kubectl wait --namespace default --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s

helm install retail-frontend ./retail-frontend \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host=retail-frontend.local \
  --set ingress.hosts[0].paths[0].path=/ \
  --set metrics.enabled=true \
  --set metrics.serviceMonitor.enabled=true

kubectl get pods

kubectl port-forward --address 0.0.0.0 svc/retail-frontend 18081:80 &

echo "127.0.0.1 retail-frontend.local" | sudo tee -a /etc/hosts
kubectl port-forward --address 0.0.0.0 svc/ingress-nginx-controller 18080:80 &
while true; do curl -s -o /dev/null -w "Status: %{http_code}\n" -H "Host: retail-frontend.local" http://localhost:18080; sleep 0.5; done

# 1. Check the status of your retail application resources and ServiceMonitor
kubectl get all,servicemonitor -l app=retail-frontend

# 2. Test the application routing via the NGINX Ingress Controller
curl -s -H "Host: retail-frontend.local" http://localhost:18080/shop | grep "<title>"
