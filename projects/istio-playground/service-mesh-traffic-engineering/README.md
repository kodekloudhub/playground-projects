# Service Mesh Traffic Engineering

**Level:** advanced  ·  **Playground:** Istio Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-k8s-with-istio)** — open it, then copy the files below.

## Files in this project
- [`canary-workloads.yaml`](./canary-workloads.yaml)
- [`enforce-security.yaml`](./enforce-security.yaml)
- [`mesh-routing.yaml`](./mesh-routing.yaml)

> Copy these into your playground session (or `git clone` this repo and `cd` here).

A [`commands.sh`](./commands.sh) with the runnable steps is included.

 — Implementing Zero-Trust Mutual TLS (mTLS) & Canary Routing

## Scenario
A payment validation service is being introduced into an Istio service mesh. The platform team needs progressive delivery, automatic sidecar injection, strict workload encryption, and evidence that direct unencrypted access to a backend is rejected.

## What you'll build
You will deploy two payment-engine versions behind one Service, route traffic between them with a 90/10 canary policy using an Istio DestinationRule and VirtualService, enforce namespace-wide strict mTLS, launch an injected mesh client, measure the canary traffic distribution, and prove that a plaintext direct-access attempt against a backend pod is rejected.

## Learning objectives
By the end you will be able to:
- Enable automatic Istio sidecar injection with a namespace label.
- Route weighted canary traffic across versioned subsets.
- Enforce zero-trust encryption with a STRICT PeerAuthentication policy.
- Validate mesh behavior: injection, traffic split, and mTLS rejection of plaintext.

## Prerequisites
- Playground: **Istio** (open it before starting)
- Basic kubectl CLI
- Understanding of Kubernetes Deployments and Services
- Familiarity with service mesh concepts

## Architecture / overview
Two Deployments (`payment-engine-v1`, `payment-engine-v2`) share `app: payment-processor` behind `payment-service`. An Istio **DestinationRule** names `production-v1` and `canary-v2` subsets by version label; a **VirtualService** splits traffic 90/10 across them. A namespace-scoped **PeerAuthentication** in STRICT mode requires mTLS, and an injected `client-test` pod generates mesh traffic and probes direct-access protection.

## Steps

### Task 1 — Label the Namespace for Automatic Mesh Injection

Enable Istio's mutating webhook to inject Envoy sidecars into workloads created in the `default` namespace.

```bash
kubectl label namespace default istio-injection=enabled
kubectl get namespace default --show-labels
```

If the namespace already has the label, confirm the output and continue.

> **Why:** The label must exist before application pods are created; adding it later does not restart existing pods.

### Task 2 — Provision the Versioned Payment Workloads

Deploy two payment-engine versions behind one Service so the mesh can route between production and canary subsets.

```bash
cd /home/admin
cat <<'EOF' > canary-workloads.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-engine-v1
  labels:
    app: payment-processor
    version: v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: payment-processor
      version: v1
  template:
    metadata:
      labels:
        app: payment-processor
        version: v1
    spec:
      containers:
      - name: server
        image: nginx:alpine
        lifecycle:
          postStart:
            exec:
              command: ["/bin/sh", "-c", "echo '<h1>PAYMENT GATEWAY V1.0 (PROD)</h1>' > /usr/share/nginx/html/index.html"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-engine-v2
  labels:
    app: payment-processor
    version: v2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payment-processor
      version: v2
  template:
    metadata:
      labels:
        app: payment-processor
        version: v2
    spec:
      containers:
      - name: server
        image: nginx:alpine
        lifecycle:
          postStart:
            exec:
              command: ["/bin/sh", "-c", "echo '<h1>PAYMENT GATEWAY V2.0 (CANARY-RC)</h1>' > /usr/share/nginx/html/index.html"]
---
apiVersion: v1
kind: Service
metadata:
  name: payment-service
spec:
  ports:
  - port: 80
    targetPort: 80
    name: http
  selector:
    app: payment-processor
EOF
kubectl apply -f canary-workloads.yaml
kubectl rollout status deployment/payment-engine-v1
kubectl rollout status deployment/payment-engine-v2
kubectl get pods -l app=payment-processor -o wide
```

> **Why:** Both Deployments share the `app` label (selected by the Service) but carry distinct `version` labels that Istio subsets select later.

### Task 3 — Establish the 90/10 Istio Canary Routing Policy

Create Istio subsets for both versions and route 90 percent of traffic to production v1 and 10 percent to canary v2.

```bash
cd /home/admin
cat <<'EOF' > mesh-routing.yaml
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: payment-destinations
spec:
  host: payment-service
  subsets:
  - name: production-v1
    labels:
      version: v1
  - name: canary-v2
    labels:
      version: v2
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: payment-traffic-splitter
spec:
  hosts:
  - payment-service
  http:
  - route:
    - destination:
        host: payment-service
        subset: production-v1
      weight: 90
    - destination:
        host: payment-service
        subset: canary-v2
      weight: 10
EOF
kubectl apply -f mesh-routing.yaml
kubectl get destinationrule payment-destinations
kubectl get virtualservice payment-traffic-splitter
```

> **Why:** The DestinationRule names the version subsets and the VirtualService sends traffic to them by weight; the weights must add up to 100.

### Task 4 — Mandate Namespace-Wide Strict mTLS

Require encrypted, mutually authenticated traffic for workloads in the `default` namespace.

```bash
cd /home/admin
cat <<'EOF' > enforce-security.yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: strict-mtls-mandate
  namespace: default
spec:
  mtls:
    mode: STRICT
EOF
kubectl apply -f enforce-security.yaml
kubectl get peerauthentication strict-mtls-mandate
```

> **Why:** In permissive mode Istio accepts plaintext and mTLS; STRICT rejects plaintext access to injected workloads.

### Task 5 — Launch a Mesh Client and Verify Sidecar Injection

Create a client workload after namespace labeling and verify Istio injects an Envoy sidecar.

```bash
kubectl run client-test --image=alpine --restart=Never -- sleep 3600
kubectl wait --for=condition=Ready pod/client-test --timeout=120s
kubectl get pods --show-labels
kubectl get pod client-test -o jsonpath='{.status.containerStatuses[*].name}{"\n"}'
```

Confirm `client-test` reports `2/2` ready containers and includes an `istio-proxy` container.

> **Why:** An injected pod runs two containers — the application and the Envoy proxy — and must be injected to participate in mesh routing and security.

### Task 6 — Validate the 90/10 Canary Traffic Distribution

Generate mesh traffic from the injected client and measure that responses come from both versions with a bias toward v1.

```bash
kubectl exec client-test -c client-test -- sh -c 'apk add --no-cache curl >/dev/null 2>&1; for i in $(seq 1 50); do curl -s http://payment-service; echo; done' > /home/admin/canary-results.txt
sort /home/admin/canary-results.txt | uniq -c
```

The output should contain both the v1 and v2 payment markers, with v1 as the majority.

> **Why:** Istio distributes requests statistically — a 50-request sample won't be exactly 45/5, but it should show both versions with a clear majority on the 90 percent route.

### Task 7 — Execute the Plain-Text Direct-Access Security Test

Prove a direct unencrypted request to a production pod is rejected under strict mTLS.

1. Find a production pod IP:
```bash
POD_IP=$(kubectl get pod -l app=payment-processor,version=v1 -o jsonpath='{.items[0].status.podIP}')
echo "Targeting production pod IP: $POD_IP"
```

2. Attempt a plaintext request from the injected client — it should fail or return no payment response:
```bash
if kubectl exec client-test -c client-test -- curl -sS --connect-timeout 3 "http://$POD_IP" > /home/admin/plaintext-attempt.txt 2>&1; then
  echo "Unexpected HTTP response:"
  cat /home/admin/plaintext-attempt.txt
else
  echo "Plaintext request rejected as expected"
fi
cat /home/admin/plaintext-attempt.txt
```

> **Why:** Strict mTLS requires mesh-authenticated requests, so a plaintext request straight to a pod IP fails instead of returning the payment page — closing the routing-bypass attack path.

## Validation

1. Verify namespace injection and both versioned workloads:
```bash
kubectl get namespace default -o jsonpath='{.metadata.labels.istio-injection}'
kubectl get deployment payment-engine-v1 -o jsonpath='{.status.readyReplicas}'
kubectl get deployment payment-engine-v2 -o jsonpath='{.status.readyReplicas}'
```

2. Verify the canary routing weights and strict mTLS policy:
```bash
kubectl get virtualservice payment-traffic-splitter -o yaml | grep 'weight:'
kubectl get peerauthentication strict-mtls-mandate -o jsonpath='{.spec.mtls.mode}'
```

3. Verify the client sidecar and traffic split:
```bash
kubectl get pod client-test -o jsonpath='{.spec.containers[*].name}'
grep -c 'PAYMENT GATEWAY V1.0' /home/admin/canary-results.txt
grep -c 'PAYMENT GATEWAY V2.0' /home/admin/canary-results.txt
```

Expected result:
- [ ] The `default` namespace is labeled `istio-injection=enabled`; v1 has 2 ready replicas and v2 has 1.
- [ ] The VirtualService splits traffic 90/10 across `production-v1` and `canary-v2`.
- [ ] `strict-mtls-mandate` is STRICT in the `default` namespace.
- [ ] `client-test` is `2/2` with an `istio-proxy` sidecar, and traffic reaches both versions with v1 in the majority.
- [ ] A plaintext request to a v1 pod IP does not return the payment page.

## References & further learning
- Istio Sidecar Injection: https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/
- Istio Traffic Management: https://istio.io/latest/docs/concepts/traffic-management/
- Istio DestinationRule: https://istio.io/latest/docs/reference/config/networking/destination-rule/
- Istio PeerAuthentication: https://istio.io/latest/docs/reference/config/security/peer_authentication/
- KodeKloud course: Istio Service Mesh: https://kodekloud.com/courses/istio-service-mesh/
