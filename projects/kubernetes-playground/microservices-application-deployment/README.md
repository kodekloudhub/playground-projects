# Microservices Application Deployment

**Level:** intermediate  ·  **Playground:** Kubernetes Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-kubernetes-single-node-latest)** — open it, then copy the files below.

## Files in this project
- [`legal-tech-secret.yaml`](./legal-tech-secret.yaml)
- [`legal-tech-stack.yaml`](./legal-tech-stack.yaml)

> Copy these into your playground session (or `git clone` this repo and `cd` here).

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
A legal tech startup's monolithic web application for analyzing 100-page PDF contracts is failing catastrophically under load. When users upload large files, browsers time out, and the single server suffers from frequent Out-Of-Memory (OOM) crashes. To resolve this, the engineering team has refactored the application into an asynchronous microservices architecture using a Node.js Frontend API, a Redis Message Broker, and a fleet of Python Background Workers.

## What you'll build
You will author and apply a cohesive directory of Kubernetes YAML manifests (Deployments, Services, and Secrets) to deploy this decoupled stack. You will configure the system so the Node API is accessible via the internet, the Redis instance is locked down to internal cluster traffic, and the Python Workers have strict resource constraints to protect the cluster's compute capacity. 

## Learning objectives
By the end you will be able to:
- Securely manage and inject application credentials using Kubernetes Secrets.
- Deploy decoupled microservices that can scale independently based on demand.
- Establish compute boundaries with resource requests and limits to prevent node starvation.
- Configure internal cluster networking and expose frontend services appropriately.

## Prerequisites
- Playground: **Kubernetes single-node (latest)** (open it before starting)
- Basic kubectl CLI
- Understanding of Kubernetes Deployments and Services

## Steps

### Task 1 — Initialize System Passwords (Kubernetes Secrets)

1. Create the secret configuration file:
```bash
cat << 'EOF' > legal-tech-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: redis-credentials
type: Opaque
data:
  # The value below is 'LegalTechSecure2026' encoded in base64
  redis-password: TGVnYWxUZWNoU2VjdXJlMjAyNg==
EOF
```

2. Apply the secret to your cluster:
```bash
kubectl apply -f legal-tech-secret.yaml
```
> **Why:** To prevent security leaks, all microservices must retrieve their Redis authentication credentials securely from a Kubernetes Secret instead of reading hardcoded values.

### Task 2 — Review and Apply the Asynchronous Infrastructure Stack

1. Create the stack manifest file:
```bash
cat << 'EOF' > legal-tech-stack.yaml
# ==========================================
# 1. SECURE REDIS JOB QUEUE BROKER
# ==========================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-broker
  labels:
    app: redis-queue
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-queue
  template:
    metadata:
      labels:
        app: redis-queue
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        command: ["redis-server", "--requirepass", "$(REDIS_PASSWORD)"]
        ports:
        - containerPort: 6379
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: redis-credentials
              key: redis-password
---
apiVersion: v1
kind: Service
metadata:
  name: redis-master # Accessible via redis-master.default.svc.cluster.local
spec:
  type: ClusterIP   # Completely isolated from public internet traffic
  ports:
  - port: 6379
    targetPort: 6379
  selector:
    app: redis-queue
---
# ==========================================
# 2. PYTHON WORKER TIERS (Heavy Computations)
# ==========================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: python-doc-worker
  labels:
    tier: background-worker
spec:
  replicas: 2 # Scale up to process jobs in parallel
  selector:
    matchLabels:
      app: doc-worker
  template:
    metadata:
      labels:
        app: doc-worker
    spec:
      containers:
      - name: worker
        image: kodekloud/python-worker:v1
        imagePullPolicy: IfNotPresent
        resources:
          requests:
            memory: "128Mi"
            cpu: "250m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        env:
        - name: REDIS_HOST
          value: "redis-master"
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: redis-credentials
              key: redis-password
---
# ==========================================
# 3. NODE.JS WEB FRONTEND API
# ==========================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: node-frontend-api
  labels:
    tier: api-gateway
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend-api
  template:
    metadata:
      labels:
        app: frontend-api
    spec:
      containers:
      - name: node-api
        image: kodekloud/node-frontend-api:v1
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 3000
        env:
        - name: REDIS_HOST
          value: "redis-master"
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: redis-credentials
              key: redis-password
        - name: REDIS_URL
          value: "redis://:$(REDIS_PASSWORD)@redis-master:6379"

---
apiVersion: v1
kind: Service
metadata:
  name: frontend-api-service
spec:
  type: NodePort
  ports:
  - port: 3000
    targetPort: 3000
    nodePort: 30082 # Explicit port for verification
  selector:
    app: frontend-api
EOF
```

2. Submit the full stack manifest to the cluster:
```bash
kubectl apply -f legal-tech-stack.yaml
```
> **Why:** We declare independent deployment structures for each tier, ensuring that the Python Workers have strict resource limits applied so they cannot cannibalize node resources during document ingestion loops.

### Task 3 — Verify Resource Guardrails

Run the following command to check resource limits:
```bash
kubectl get deployment python-doc-worker -o jsonpath='{.spec.template.spec.containers[0].resources}'
```
> **Why:** To verify that the worker deployments are constrained correctly so that a massive 100-page document cannot degrade performance for other cluster applications.

### Task 4 — Verify Network Isolation & Secret Injection

1. Verify Redis is purely an internal network resource:
```bash
kubectl get svc redis-master
```

2. Check that the Node API container successfully references the secret values:
```bash
kubectl describe deployment node-frontend-api | grep -A 3 REDIS_PASSWORD
```
> **Why:** Ensures that internal brokers are blocked from external reach and are successfully decrypting database secrets at runtime.

### Task 5 — Execute Async Validation & Verify Worker Logs

1. Expose the API (Run in the background):
```bash
kubectl port-forward deployment/node-frontend-api 8082:3000 --address 0.0.0.0 &
```

2. Trigger a background job:
```bash
curl http://localhost:8082
```

3. Identify your worker pods:
```bash
kubectl get pods -l app=doc-worker
```

4. View the worker pod logs (replace `<pod-name>` with one from the output above):
```bash
kubectl logs -f <pod-name>
```
> **Why:** To expose the Node.js API, verify it accepts requests instantly, and confirm via worker logs that the background processing was successful.

## Validation

1. Verify the API responds with a successful job creation:
```bash
curl http://localhost:8082
```

2. Verify Python worker resources are constrained:
```bash
kubectl get deployment python-doc-worker -o jsonpath='{.spec.template.spec.containers[0].resources}'
```

3. Verify Redis Service is isolated internally:
```bash
kubectl get svc redis-master
```

Expected result:
- [ ] A curl to the Node API returns `{"status":"Job Accepted","queue":"redis-master:6379"}`.
- [ ] The resource JSON string outputs exactly `{"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"250m","memory":"128Mi"}}`.
- [ ] The `redis-master` service displays a type of `ClusterIP` with no External-IP.
- [ ] `node-frontend-api`, `python-doc-worker`, and `redis-broker` have dedicated Deployment definitions allowing independent scaling.
- [ ] Checking a worker's logs via `kubectl logs` displays `Picked up job for document: <random-id>` and `Job completed successfully.`

## References & further learning
- Kubernetes Secrets Documentation: https://kubernetes.io/docs/concepts/configuration/secret/
- Managing Resources for Containers: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
- KodeKloud course: Kubernetes for the Absolute Beginners - Hands-on Tutorial: https://kodekloud.com/courses/kubernetes-for-the-absolute-beginners-hands-on-tutorial/
