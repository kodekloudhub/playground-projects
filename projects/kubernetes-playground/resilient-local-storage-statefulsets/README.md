# Resilient Local Storage with StatefulSets

**Level:** intermediate  ·  **Playground:** Kubernetes Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-kubernetes-single-node-latest)** — open it, then copy the files below.

## Files in this project
- [`manifests.yaml`](./manifests.yaml)

> Copy these into your playground session (or `git clone` this repo and `cd` here).

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
It is 3:47 AM and a lightweight internal service has stopped responding after an unexpected Pod failure in a local Kubernetes environment. The application uses SQLite, so your team needs proof that the database file will survive Pod replacement instead of disappearing with the container.

## What you'll build
You will deploy a stateful SQLite workload using a headless Service, a StatefulSet, and dynamically provisioned local storage. After the workload is running, you will write validation data into the mounted volume, force-delete the database Pod, and confirm Kubernetes reattaches the same persistent volume when the Pod is recreated.

## Learning objectives
By the end you will be able to:
- Configure a dynamic local-path storage provisioner in a Kubernetes cluster.
- Author a headless Service and StatefulSet with `volumeClaimTemplates` for per-replica storage.
- Confirm stable Pod and PVC identities before writing application state.
- Prove storage resilience by forcing Pod failure and verifying the data survives.

## Prerequisites
- Playground: **kubernetes** (open it before starting)
- Basic kubectl CLI
- Understanding of Kubernetes Pods and Services
- Familiarity with persistent volumes and claims

## Architecture / overview
A **headless Service** (`sqlite-headless`, `clusterIP: None`) gives the StatefulSet Pod a stable identity. The **StatefulSet** (`local-db`) runs a single SQLite container whose `/data` directory is backed by a PVC created from `volumeClaimTemplates`, provisioned dynamically by the **local-path** StorageClass. The PVC outlives the Pod, which is what makes the data resilient.

## Steps

### Task 1 — Validate the Cluster and Configure Local Storage

Confirm the cluster is ready and install the local-path storage provisioner.

1. Confirm the cluster is reachable and has at least one Ready node:
```bash
kubectl cluster-info
kubectl get nodes
```

2. Install the local-path provisioner:
```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.36/deploy/local-path-storage.yaml

kubectl wait -n local-path-storage \
  --for=condition=available deployment/local-path-provisioner \
  --timeout=180s
```

3. Verify the `local-path` StorageClass:
```bash
kubectl get storageclass local-path
kubectl describe storageclass local-path
```

> **Why:** A StatefulSet needs a dynamic provisioner to create PersistentVolumes on demand; the `local-path` StorageClass supplies them from node-local disk.

### Task 2 — Deploy the Headless Service and StatefulSet

Create the resources that give SQLite stable network identity and persistent storage.

1. Create `manifests.yaml`:
```bash
cat << 'EOF' > manifests.yaml
apiVersion: v1
kind: Service
metadata:
  name: sqlite-headless
  labels:
    app: sqlite-db
spec:
  ports:
  - port: 80
    name: dummy
  clusterIP: None
  selector:
    app: sqlite-db
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: local-db
spec:
  serviceName: sqlite-headless
  replicas: 1
  selector:
    matchLabels:
      app: sqlite-db
  template:
    metadata:
      labels:
        app: sqlite-db
    spec:
      containers:
      - name: sqlite
        image: alpine:latest
        command: ["/bin/sh", "-c"]
        args:
          - apk add --no-cache sqlite;
            mkdir -p /data;
            tail -f /dev/null
        volumeMounts:
        - name: sqlite-storage
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: sqlite-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: local-path
      resources:
        requests:
          storage: 1Gi
EOF
```

2. Apply the manifest and wait for the StatefulSet:
```bash
kubectl apply -f manifests.yaml
kubectl rollout status statefulset/local-db --timeout=180s
kubectl get svc,statefulset,pods,pvc
```

> **Why:** The headless Service provides stable addressing, and `volumeClaimTemplates` creates a dedicated PVC that persists across Pod replacement.

### Task 3 — Confirm the Service, Pod, and PVC Initialize Correctly

Verify the runtime objects exist and the PVC is bound before writing data.

1. Check the headless Service, Pod, and PVC:
```bash
kubectl get svc sqlite-headless
kubectl get pods -l app=sqlite-db
kubectl get pvc
```

2. Confirm the Pod name is `local-db-0` with status `Running`.
3. Confirm the PVC name is `sqlite-storage-local-db-0` with status `Bound`.

> **Why:** A StatefulSet with one replica produces the predictable Pod `local-db-0` and a bound PVC; both must be ready before the database file lands on persistent storage.

### Task 4 — Insert Validation Data into SQLite

Write durable application data into the mounted volume before testing recovery.

1. Create the table, insert the validation row, and query it:
```bash
kubectl exec local-db-0 -- sqlite3 /data/test.db "
CREATE TABLE resilience_test (
  id INTEGER PRIMARY KEY,
  status TEXT NOT NULL
);
INSERT INTO resilience_test (id, status) VALUES (1, 'Data is Safe!');
SELECT id || '|' || status FROM resilience_test;
"
```

2. Query again to confirm the saved value:
```bash
kubectl exec local-db-0 -- sqlite3 /data/test.db "SELECT id || '|' || status FROM resilience_test WHERE id=1;"
```

The output must be:
```text
1|Data is Safe!
```

> **Why:** A running Pod alone does not prove persistence — the database file must be created under `/data`, which is backed by the StatefulSet PVC.

### Task 5 — Delete the Pod and Prove the Data Survives

Force the StatefulSet Pod to be replaced and prove Kubernetes reattaches the same volume.

1. Record the current Pod and PVC details:
```bash
kubectl get pod local-db-0
kubectl get pvc sqlite-storage-local-db-0
```

2. Force-delete the Pod:
```bash
kubectl delete pod local-db-0 --force --grace-period=0
```

3. Wait for the replacement Pod:
```bash
kubectl wait --for=condition=Ready pod/local-db-0 --timeout=180s
kubectl get pod local-db-0
kubectl get pvc sqlite-storage-local-db-0
```

4. Query the database from the recreated Pod:
```bash
kubectl exec local-db-0 -- sqlite3 /data/test.db "SELECT id || '|' || status FROM resilience_test WHERE id=1;"
```

The output must still be `1|Data is Safe!`.

> **Why:** Deleting `local-db-0` simulates an abrupt failure; the controller recreates it with the same stable name while retaining the original PVC, proving the data survives.

## Validation

1. Verify the cluster and StorageClass are ready:
```bash
kubectl get nodes
kubectl get storageclass local-path -o jsonpath='{.provisioner}'
```

2. Verify the headless Service and StatefulSet were authored correctly:
```bash
kubectl get svc sqlite-headless -o jsonpath='{.spec.clusterIP}'
kubectl get statefulset local-db -o jsonpath='{.spec.serviceName}{"\n"}{.spec.volumeClaimTemplates[0].spec.resources.requests.storage}'
```

3. Verify the Pod is Running and the PVC is Bound:
```bash
kubectl get pod local-db-0 -o jsonpath='{.status.phase}'
kubectl get pvc sqlite-storage-local-db-0 -o jsonpath='{.status.phase}'
```

4. Verify the data survives Pod recreation:
```bash
kubectl exec local-db-0 -- sqlite3 /data/test.db "SELECT id || '|' || status FROM resilience_test WHERE id=1;"
```

Expected result:
- [ ] The `local-path` StorageClass uses provisioner `rancher.io/local-path`.
- [ ] `sqlite-headless` exists with `clusterIP: None`, and `local-db` requests a `1Gi` volume from `local-path`.
- [ ] Pod `local-db-0` is `Running` and PVC `sqlite-storage-local-db-0` is `Bound`.
- [ ] The SQLite query returns `1|Data is Safe!` before the chaos test.
- [ ] After force-deleting the Pod, the recreated `local-db-0` still returns `1|Data is Safe!`.

## References & further learning
- StatefulSets: https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
- Services and headless Services: https://kubernetes.io/docs/concepts/services-networking/service/
- Dynamic volume provisioning: https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/
- Local Path Provisioner: https://github.com/rancher/local-path-provisioner
- KodeKloud course: Kubernetes for the Absolute Beginners - Hands-on Tutorial: https://kodekloud.com/courses/kubernetes-for-the-absolute-beginners-hands-on-tutorial/
