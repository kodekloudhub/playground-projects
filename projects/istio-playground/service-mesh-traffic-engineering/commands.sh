#!/usr/bin/env bash
set -euo pipefail

kubectl label namespace default istio-injection=enabled
kubectl get namespace default --show-labels

cd /home/admin

kubectl apply -f canary-workloads.yaml
kubectl rollout status deployment/payment-engine-v1
kubectl rollout status deployment/payment-engine-v2
kubectl get pods -l app=payment-processor -o wide

cd /home/admin

kubectl apply -f mesh-routing.yaml
kubectl get destinationrule payment-destinations
kubectl get virtualservice payment-traffic-splitter

cd /home/admin

kubectl apply -f enforce-security.yaml
kubectl get peerauthentication strict-mtls-mandate

kubectl run client-test --image=alpine --restart=Never -- sleep 3600
kubectl wait --for=condition=Ready pod/client-test --timeout=120s
kubectl get pods --show-labels
kubectl get pod client-test -o jsonpath='{.status.containerStatuses[*].name}{"\n"}'

kubectl exec client-test -c client-test -- sh -c 'apk add --no-cache curl >/dev/null 2>&1; for i in $(seq 1 50); do curl -s http://payment-service; echo; done' > /home/admin/canary-results.txt
sort /home/admin/canary-results.txt | uniq -c

POD_IP=$(kubectl get pod -l app=payment-processor,version=v1 -o jsonpath='{.items[0].status.podIP}')
echo "Targeting production pod IP: $POD_IP"

if kubectl exec client-test -c client-test -- curl -sS --connect-timeout 3 "http://$POD_IP" > /home/admin/plaintext-attempt.txt 2>&1; then
  echo "Unexpected HTTP response:"
  cat /home/admin/plaintext-attempt.txt
else
  echo "Plaintext request rejected as expected"
fi
cat /home/admin/plaintext-attempt.txt

kubectl get namespace default -o jsonpath='{.metadata.labels.istio-injection}'
kubectl get deployment payment-engine-v1 -o jsonpath='{.status.readyReplicas}'
kubectl get deployment payment-engine-v2 -o jsonpath='{.status.readyReplicas}'

kubectl get virtualservice payment-traffic-splitter -o yaml | grep 'weight:'
kubectl get peerauthentication strict-mtls-mandate -o jsonpath='{.spec.mtls.mode}'

kubectl get pod client-test -o jsonpath='{.spec.containers[*].name}'
grep -c 'PAYMENT GATEWAY V1.0' /home/admin/canary-results.txt
grep -c 'PAYMENT GATEWAY V2.0' /home/admin/canary-results.txt
