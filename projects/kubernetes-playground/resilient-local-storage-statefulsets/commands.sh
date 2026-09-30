#!/usr/bin/env bash
set -euo pipefail

kubectl cluster-info
kubectl get nodes

kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.36/deploy/local-path-storage.yaml

kubectl wait -n local-path-storage \
  --for=condition=available deployment/local-path-provisioner \
  --timeout=180s

kubectl get storageclass local-path
kubectl describe storageclass local-path

kubectl apply -f manifests.yaml
kubectl rollout status statefulset/local-db --timeout=180s
kubectl get svc,statefulset,pods,pvc

kubectl get svc sqlite-headless
kubectl get pods -l app=sqlite-db
kubectl get pvc

kubectl exec local-db-0 -- sqlite3 /data/test.db "
CREATE TABLE resilience_test (
  id INTEGER PRIMARY KEY,
  status TEXT NOT NULL
);
INSERT INTO resilience_test (id, status) VALUES (1, 'Data is Safe!');
SELECT id || '|' || status FROM resilience_test;
"

kubectl exec local-db-0 -- sqlite3 /data/test.db "SELECT id || '|' || status FROM resilience_test WHERE id=1;"

kubectl get pod local-db-0
kubectl get pvc sqlite-storage-local-db-0

kubectl delete pod local-db-0 --force --grace-period=0

kubectl wait --for=condition=Ready pod/local-db-0 --timeout=180s
kubectl get pod local-db-0
kubectl get pvc sqlite-storage-local-db-0

kubectl exec local-db-0 -- sqlite3 /data/test.db "SELECT id || '|' || status FROM resilience_test WHERE id=1;"

kubectl get nodes
kubectl get storageclass local-path -o jsonpath='{.provisioner}'

kubectl get svc sqlite-headless -o jsonpath='{.spec.clusterIP}'
kubectl get statefulset local-db -o jsonpath='{.spec.serviceName}{"\n"}{.spec.volumeClaimTemplates[0].spec.resources.requests.storage}'

kubectl get pod local-db-0 -o jsonpath='{.status.phase}'
kubectl get pvc sqlite-storage-local-db-0 -o jsonpath='{.status.phase}'

kubectl exec local-db-0 -- sqlite3 /data/test.db "SELECT id || '|' || status FROM resilience_test WHERE id=1;"
