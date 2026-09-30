#!/usr/bin/env bash
set -euo pipefail

mkdir -p templates

kubectl create configmap frontend-code --from-file=app.py=frontend.py --from-file=requirements.txt
kubectl create configmap frontend-templates --from-file=templates/index.html --from-file=templates/checkout.html
kubectl create configmap cart-code --from-file=app.py=cart.py --from-file=requirements.txt
kubectl create configmap payment-code --from-file=app.py=payment.py --from-file=requirements.txt

kubectl apply -f retail-apps.yaml

kubectl delete -f elastic-search/ --ignore-not-found=true
kubectl delete namespace elastic-stack --ignore-not-found=true
kubectl create namespace observability

kubectl apply -f efk-stack.yaml

kubectl get pods -n observability -w

until $(curl --output /dev/null --silent --head --fail http://0.0.0.0:30601); do
    echo 'Waiting for Kibana UI...'
    sleep 5
done
echo "Kibana is UP!"

kubectl port-forward --address 0.0.0.0 svc/frontend-service 18080:8080 &

# 1. Check the status of the retail application microservices
kubectl get all -l 'app in (frontend, cart, payment)'

# 2. Check the status of the EFK Stack components
kubectl get all -n observability
