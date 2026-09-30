#!/usr/bin/env bash
set -euo pipefail

mkdir -p ~/ecommerce-src
cd ~/ecommerce-src

# Create the Backend Order API


# Create the Frontend Store UI

kubectl create configmap app-source-codes --from-file=backend_api.py --from-file=storefront.py

cd ~


# Apply the infrastructure
kubectl apply -f ecommerce-infra.yaml
kubectl get pods -w

kubectl exec rogue-attacker -- curl -s -X POST -H "Content-Type: application/json" -d '{"item_id":"item_1"}' http://payment-svc:5000/api/process-order

kubectl apply -f default-deny.yaml

kubectl apply -f allow-external-frontend.yaml

kubectl apply -f allow-frontend.yaml

kubectl exec rogue-attacker -- curl -m 3 -s -X POST -H "Content-Type: application/json" -d '{"item_id":"item_1"}' http://payment-svc:5000/api/process-order

# 1. Review all active network policies in the namespace
kubectl get networkpolicies

# 2. Inspect the specific rules protecting the payment processor
kubectl describe networkpolicy allow-frontend-to-payment
