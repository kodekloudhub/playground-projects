# Monolith to Microservices

**Level:** intermediate  ·  **Playground:** Kubernetes Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-kubernetes-single-node-latest)** — open it, then copy the files below.

## Files in this project
- [`seatsync-stack.yaml`](./seatsync-stack.yaml)

> Copy these into your playground session (or `git clone` this repo and `cd` here).

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
SeatSync is being modernized from a legacy monolithic cinema reservation application into a Kubernetes-based microservices architecture. The new platform separates the dashboard, reservation logic, and shared seat state so the frontend can scale independently while all replicas stay synchronized.

## What you'll build
You will deploy SeatSync as three independent services on Kubernetes — a Next.js frontend for the seating dashboard, a FastAPI backend for reservation logic, and a Redis cache for centralized seat state. You will verify the internal wiring, validate the dashboard end to end, confirm the backend and Redis stay internal-only, and scale the frontend horizontally without breaking synchronized behavior.

## Learning objectives
By the end you will be able to:
- Deploy a three-tier microservices stack from a single Kubernetes manifest.
- Wire services together using internal DNS names and ClusterIP networking.
- Verify network isolation and shared Redis-backed state from the terminal.
- Scale a stateless frontend horizontally and confirm continued synchronization.

## Prerequisites
- Playground: **Kubernetes single-node (latest)** (open it before starting)
- Basic kubectl CLI
- Understanding of Kubernetes Deployments and Services
- Familiarity with environment-based service configuration

## Architecture / overview
Three tiers run behind internal **ClusterIP** Services: the **frontend** (`seatsync-frontend-deploy`, port 3000) talks to the **backend** via `http://backend-service:8000`; the **backend** (`seatsync-backend-deploy`, port 8000) talks to **Redis** via `redis-cache:6379`; and **Redis** (`seatsync-redis-deploy`, port 6379) holds centralized seat state. Only the frontend is opened for inspection.

## Steps

### Task 1 — Validate the Cluster and Deploy SeatSync

Confirm the cluster is ready and deploy the complete SeatSync stack.

1. Confirm the cluster is reachable and has at least one Ready node:
```bash
kubectl cluster-info
kubectl get nodes
```

2. Create `seatsync-stack.yaml`:
```bash
cat << 'EOF' > seatsync-stack.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: seatsync-redis-deploy
  labels:
    tier: cache
spec:
  replicas: 1
  selector:
    matchLabels:
      app: seatsync-cache
  template:
    metadata:
      labels:
        app: seatsync-cache
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 6379
---
apiVersion: v1
kind: Service
metadata:
  name: redis-cache
  labels:
    tier: cache
spec:
  type: ClusterIP
  selector:
    app: seatsync-cache
  ports:
    - port: 6379
      targetPort: 6379
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: seatsync-backend-deploy
  labels:
    tier: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: seatsync-backend
  template:
    metadata:
      labels:
        app: seatsync-backend
    spec:
      containers:
        - name: api
          image: kodekloud/seatsync-api:latest
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8000
          env:
            - name: REDIS_HOST
              value: redis-cache
            - name: REDIS_PORT
              value: "6379"
---
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  labels:
    tier: backend
spec:
  type: ClusterIP
  selector:
    app: seatsync-backend
  ports:
    - port: 8000
      targetPort: 8000
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: seatsync-frontend-deploy
  labels:
    tier: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: seatsync-frontend
  template:
    metadata:
      labels:
        app: seatsync-frontend
    spec:
      containers:
        - name: web
          image: kodekloud/seatsync-web:latest
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 3000
          env:
            - name: BACKEND_URL
              value: http://backend-service:8000
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  type: ClusterIP
  selector:
    app: seatsync-frontend
  ports:
    - port: 3000
      targetPort: 3000
EOF
```

3. Apply the stack and wait for all Deployments:
```bash
kubectl apply -f seatsync-stack.yaml
kubectl wait --for=condition=available deployment --all --timeout=180s
kubectl get deploy,svc,pods
```

> **Why:** Deploying all six resources from one manifest stands up the decoupled Redis, backend, and frontend tiers with the correct images and internal Services.

### Task 2 — Inspect Deployments, Services, and Internal Wiring

Confirm from the terminal that every workload is running and service discovery is wired correctly.

1. List the workloads and Services:
```bash
kubectl get deploy,svc,pods
```

2. Confirm all three Pods are running:
```bash
kubectl get pods -l app=seatsync-cache
kubectl get pods -l app=seatsync-backend
kubectl get pods -l app=seatsync-frontend
```

3. Inspect the internal connection settings:
```bash
kubectl get deployment seatsync-backend-deploy -o jsonpath='{.spec.template.spec.containers[0].env}'
kubectl get deployment seatsync-frontend-deploy -o jsonpath='{.spec.template.spec.containers[0].env}'
```

4. Confirm the Services are internal-only and expose the expected ports:
```bash
kubectl get svc redis-cache backend-service frontend-service
```

> **Why:** A migration can look complete while hiding broken selectors or env config; inspecting live resources confirms the backend points to `redis-cache:6379` and the frontend to `http://backend-service:8000`.

### Task 3 — Validate Dashboard Access and Live Application Behavior

Prove the frontend dashboard is reachable and reflects a working backend connection.

1. Port-forward the frontend Deployment:
```bash
kubectl port-forward deployment/seatsync-frontend-deploy 3000:3000 --address 0.0.0.0
```

2. To open the forwarded dashboard, click the ellipsis in the top-right corner and select **View Port**. Enter `3000`, click **Open Port**, and you will be redirected to the SeatSync dashboard.
3. Verify the page renders the SeatSync dashboard content.
4. Confirm the page shows reservation statistics and backend connection status.
5. Watch briefly for live seat updates.

> **Why:** Even though the tiers are separate services, the dashboard should render seating data, reservation statistics, and connection status as one coherent application.

### Task 4 — Verify Internal Network Isolation and Shared State

Prove with terminal checks that the backend and Redis stay internal-only while the app uses Redis as shared state.

1. Check the Service types and external IPs:
```bash
kubectl get svc redis-cache backend-service frontend-service
```

2. Find the Redis and backend Pods:
```bash
REDIS_POD=$(kubectl get pods -l app=seatsync-cache -o jsonpath='{.items[0].metadata.name}')
BACKEND_POD=$(kubectl get pods -l app=seatsync-backend -o jsonpath='{.items[0].metadata.name}')
```

3. Confirm Redis responds from inside the cluster:
```bash
kubectl exec "$REDIS_POD" -- redis-cli ping
```

4. Inspect backend startup logs:
```bash
kubectl logs "$BACKEND_POD"
```

> **Why:** Only the frontend should be exposed; the backend and Redis communicate through Kubernetes DNS with no external endpoints, and Redis should answer `PONG` from inside the cluster.

### Task 5 — Scale the Frontend Horizontally and Verify Synchronized Behavior

Prove the stateless frontend can scale horizontally without losing synchronized behavior.

1. Scale the frontend Deployment from 1 to 3 replicas:
```bash
kubectl scale deployment seatsync-frontend-deploy --replicas=3
```

2. Confirm Kubernetes created three frontend Pods:
```bash
kubectl get pods
```

3. Ensure the Deployment reports 3 desired and 3 ready replicas:
```bash
kubectl get deployment seatsync-frontend-deploy
```

4. In the dashboard, refresh several times, create or remove reservations, and verify data stays synchronized across refreshes.

> **Why:** Multiple frontend replicas keep serving the same experience because they all share centralized state through the backend and Redis — the payoff of breaking the frontend out of the monolith.

## Validation

1. Verify the stack deployed with the correct images:
```bash
kubectl get deployment seatsync-redis-deploy -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get deployment seatsync-backend-deploy -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get deployment seatsync-frontend-deploy -o jsonpath='{.spec.template.spec.containers[0].image}'
```

2. Verify internal wiring and ClusterIP-only Services:
```bash
kubectl get deployment seatsync-backend-deploy -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="REDIS_HOST")].value}'
kubectl get deployment seatsync-frontend-deploy -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="BACKEND_URL")].value}'
kubectl get svc redis-cache backend-service frontend-service -o jsonpath='{.items[*].spec.type}'
```

3. Verify Redis shared state responds from inside the cluster:
```bash
kubectl exec "$(kubectl get pods -l app=seatsync-cache -o jsonpath='{.items[0].metadata.name}')" -- redis-cli ping
```

4. Verify the frontend scaled to three ready replicas:
```bash
kubectl get deployment seatsync-frontend-deploy -o jsonpath='{.status.readyReplicas}'
kubectl get endpoints frontend-service -o jsonpath='{.subsets[0].addresses[*].ip}'
```

Expected result:
- [ ] Redis, backend, and frontend Deployments run `redis:7-alpine`, `kodekloud/seatsync-api:latest`, and `kodekloud/seatsync-web:latest`.
- [ ] The backend `REDIS_HOST` is `redis-cache` and the frontend `BACKEND_URL` is `http://backend-service:8000`; all three Services are `ClusterIP`.
- [ ] Redis responds `PONG` and the backend logs show normal startup.
- [ ] The frontend Deployment reports `3/3` ready replicas with three endpoints registered.
- [ ] The dashboard renders reservation statistics and stays synchronized after scaling.

## References & further learning
- Kubernetes Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- Kubernetes Services: https://kubernetes.io/docs/concepts/services-networking/service/
- kubectl cluster access: https://kubernetes.io/docs/tasks/access-application-cluster/access-cluster/
- Scale a Deployment: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#scaling-a-deployment
- KodeKloud course: Kubernetes for the Absolute Beginners - Hands-on Tutorial: https://kodekloud.com/courses/kubernetes-for-the-absolute-beginners-hands-on-tutorial/
