# Zero-Trust Micro-Segmentation with Calico

**Level:** advanced  ·  **Playground:** Kubernetes With Calico Playground

## Files in this project
- [`allow-external-frontend.yaml`](./allow-external-frontend.yaml)
- [`allow-frontend.yaml`](./allow-frontend.yaml)
- [`backend_api.py`](./backend_api.py)
- [`default-deny.yaml`](./default-deny.yaml)
- [`ecommerce-infra.yaml`](./ecommerce-infra.yaml)
- [`storefront.py`](./storefront.py)

> Copy these into your playground session (or `git clone` this repo and `cd` here).

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
Your organization is migrating a legacy e-commerce application to Kubernetes. The application consists of a public-facing web frontend and a highly sensitive backend payment processor. By default, Kubernetes operates on a "flat" network where all pods can freely communicate with one another. Because standard Kubernetes lacks built-in firewall enforcement, a compromised web frontend would allow an attacker to freely pivot to the payment processor. 

To achieve PCI-DSS compliance, your infrastructure team has integrated Calico, a high-performance Container Network Interface (CNI) plugin that enforces strict, kernel-level security rules. You have been tasked with leveraging Calico to design a zero-trust network architecture that prevents unauthorized lateral movement between microservices.

## What you'll build
You will deploy two target pods representing the frontend and backend services into a Kubernetes environment. You will leverage Calico's network routing engine to implement a "default deny" security posture, effectively isolating all workloads. You will then write and apply a declarative Calico Network Policy to surgically allow traffic only on specific, approved TCP ports. Finally, you will validate the architecture by simulating an internal network breach, proving that Calico successfully drops unauthorized connections.

## Learning objectives
By the end you will be able to:
- Inject application source code dynamically into Kubernetes workloads using ConfigMaps.
- Deploy multi-tier applications with associated Services and NodePorts.
- Implement a "Default Deny" network policy to establish a zero-trust baseline.
- Author targeted Calico allow-list policies using pod selectors and specific ingress rules.
- Validate network boundaries by simulating unauthorized lateral movement from rogue containers.

## Prerequisites
- Playground: **Kubernetes With Calico** (open it before starting)

---

## Steps

### Task 1 — Provision the E-Commerce Applications
We will first create our application codebase on the local filesystem, inject it into the cluster dynamically, and then deploy the clean infrastructure manifests.

1. **Create the Application Codebase:** Create a directory for your source code and generate the backend API and the frontend storefront applications.

```bash
mkdir -p ~/ecommerce-src
cd ~/ecommerce-src

# Create the Backend Order API
cat << 'EOF' > backend_api.py
from flask import Flask, request, jsonify
import uuid, datetime

app = Flask(__name__)

INVENTORY = {
    "item_1": {"name": "Kubernetes CKA Voucher", "price": 395.00},
    "item_2": {"name": "Mechanical Keyboard", "price": 129.99},
    "item_3": {"name": "Cloud Architecture Poster", "price": 24.50}
}

@app.route('/api/process-order', methods=['POST'])
def process_order():
    data = request.json
    item_id = data.get('item_id')

    if item_id not in INVENTORY:
        return jsonify({"error": "Item not found in inventory"}), 404

    item = INVENTORY[item_id]

    return jsonify({
        "status": "APPROVED",
        "receipt_id": f"ORD-{uuid.uuid4().hex[:8].upper()}",
        "item_purchased": item["name"],
        "amount_charged": f"${item['price']:.2f}",
        "timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC"),
        "processor_node": "payment-api-v3"
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

# Create the Frontend Store UI
cat << 'EOF' > storefront.py
from flask import Flask, render_template_string
import requests

app = Flask(__name__)

STORE_HTML = """
<!DOCTYPE html>
<html>
<head>
    <title>CloudNative Store</title>
    <style>
        :root { --bg: #0b0f19; --card: #111827; --primary: #3b82f6; --text: #f3f4f6; --accent: #10b981; }
        body { background: var(--bg); color: var(--text); font-family: 'Segoe UI', system-ui, sans-serif; margin: 0; padding: 40px; }
        .nav { display: flex; justify-content: space-between; align-items: center; max-width: 1000px; margin: 0 auto 40px; padding-bottom: 20px; border-bottom: 1px solid #1f2937; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 30px; max-width: 1000px; margin: 0 auto; }
        .card { background: var(--card); border: 1px solid #1f2937; border-radius: 12px; padding: 25px; transition: transform 0.2s, box-shadow 0.2s; position: relative; overflow: hidden; }
        .card:hover { transform: translateY(-5px); box-shadow: 0 10px 25px rgba(0,0,0,0.5); border-color: #374151; }
        .card::before { content: ''; position: absolute; top: 0; left: 0; width: 100%; height: 4px; background: linear-gradient(90deg, var(--primary), var(--accent)); }
        .price { font-size: 28px; font-weight: bold; color: var(--text); margin: 15px 0; display: block; }
        .btn { background: var(--primary); color: white; display: block; text-align: center; padding: 12px; border-radius: 8px; font-size: 16px; font-weight: 600; text-decoration: none; transition: background 0.2s; box-sizing: border-box; }
        .btn:hover { background: #2563eb; }
    </style>
</head>
<body>
    <div class="nav">
        <h1 style="margin:0; font-size:24px;">☁️ CloudNative Store</h1>
        <span style="background:#1f2937; padding:6px 12px; border-radius:20px; font-size:14px; border: 1px solid #374151;">Secure Checkout v2.0</span>
    </div>
    <div class="grid">
        <div class="card">
            <h3 style="margin-top:0; color:#9ca3af; font-size:14px; text-transform:uppercase;">Certification</h3>
            <span style="font-size:20px; font-weight:600;">Kubernetes CKA Voucher</span>
            <span class="price">$395.00</span>
            <a href="/buy/item_1" class="btn">Buy Now</a>
        </div>
        <div class="card">
            <h3 style="margin-top:0; color:#9ca3af; font-size:14px; text-transform:uppercase;">Hardware</h3>
            <span style="font-size:20px; font-weight:600;">Mechanical Keyboard</span>
            <span class="price">$129.99</span>
            <a href="/buy/item_2" class="btn">Buy Now</a>
        </div>
        <div class="card">
            <h3 style="margin-top:0; color:#9ca3af; font-size:14px; text-transform:uppercase;">Merch</h3>
            <span style="font-size:20px; font-weight:600;">Architecture Poster</span>
            <span class="price">$24.50</span>
            <a href="/buy/item_3" class="btn">Buy Now</a>
        </div>
    </div>
</body>
</html>
"""

RECEIPT_HTML = """
<!DOCTYPE html>
<html>
<head>
    <title>Transaction Result</title>
    <style>
        body { background: #0b0f19; color: #f3f4f6; font-family: 'Segoe UI', system-ui, sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; }
        .receipt-card { background: #111827; border: 1px solid #1f2937; border-radius: 16px; padding: 40px; width: 100%; max-width: 450px; text-align: center; box-shadow: 0 20px 25px -5px rgba(0,0,0,0.3); }
        .icon-circle { width: 72px; height: 72px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 36px; margin: 0 auto 20px; }
        .success-icon { background: rgba(16, 185, 129, 0.1); color: #10b981; border: 2px solid rgba(16, 185, 129, 0.2); }
        .error-icon { background: rgba(239, 68, 68, 0.1); color: #ef4444; border: 2px solid rgba(239, 68, 68, 0.2); }
        .details { text-align: left; background: #1f2937; padding: 20px; border-radius: 8px; margin: 25px 0; }
        .row { display: flex; justify-content: space-between; margin-bottom: 12px; font-size: 14px; }
        .row:last-child { margin-bottom: 0; }
        .label { color: #9ca3af; }
        .val { font-weight: 600; }
        .back-btn { background: transparent; color: #3b82f6; border: 1px solid #3b82f6; padding: 10px 20px; border-radius: 8px; font-weight: 600; cursor: pointer; text-decoration: none; display: inline-block; transition: all 0.2s; }
        .back-btn:hover { background: #3b82f6; color: white; }
    </style>
</head>
<body>
    <div class="receipt-card">
        {% if error %}
            <div class="icon-circle error-icon">❌</div>
            <h2 style="margin: 0 0 10px; color: #ef4444;">Checkout Failed</h2>
            <p style="color: #9ca3af; font-size: 14px; margin: 0;">The network request to the backend payment processor was dropped by the firewall.</p>
            <div class="details" style="font-family: monospace; color: #ef4444; font-size: 12px; word-break: break-all;">
                {{ error_details }}
            </div>
        {% else %}
            <div class="icon-circle success-icon">✓</div>
            <h2 style="margin: 0 0 10px; color: #10b981;">Payment Approved</h2>
            <p style="color: #9ca3af; font-size: 14px; margin: 0;">Secure transaction completed.</p>
            <div class="details">
                <div class="row"><span class="label">Item</span> <span class="val">{{ data.item_purchased }}</span></div>
                <div class="row"><span class="label">Total</span> <span class="val" style="color: #10b981;">{{ data.amount_charged }}</span></div>
                <div class="row"><span class="label">Order ID</span> <span class="val" style="font-family: monospace;">{{ data.receipt_id }}</span></div>
                <div class="row"><span class="label">Node</span> <span class="val" style="color: #9ca3af;">{{ data.processor_node }}</span></div>
            </div>
        {% endif %}
        <a href="/" class="back-btn">← Return to Store</a>
    </div>
</body>
</html>
"""

@app.route('/')
def store():
    return render_template_string(STORE_HTML)

@app.route('/buy/<item_id>')
def checkout(item_id):
    try:
        # The frontend makes a strict POST request with a 3-second hard timeout
        response = requests.post("http://payment-svc:5000/api/process-order", json={"item_id": item_id}, timeout=3)
        response.raise_for_status()
        data = response.json()
        return render_template_string(RECEIPT_HTML, data=data, error=False)
    except Exception as e:
        # Safely catches the Calico Network Policy timeout or dropped packets
        return render_template_string(RECEIPT_HTML, error=True, error_details=str(e))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF
```

2. **Inject the Codebase into Kubernetes:** Use the native Kubernetes API to securely package the files from your local disk into a cluster resource.

```bash
kubectl create configmap app-source-codes --from-file=backend_api.py --from-file=storefront.py
```

3. **Deploy the Infrastructure Architecture:** Return to your home directory and create the infrastructure manifest containing the deployments, services, and a rogue pod.

```bash
cd ~
cat << 'EOF' > ecommerce-infra.yaml
---
# BACKEND WORKLOAD (Payment Processor)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-processor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payment-processor
  template:
    metadata:
      labels:
        app: payment-processor
    spec:
      containers:
      - name: api
        image: python:3.10-slim
        command: ["/bin/sh", "-c", "pip install flask requests && python /app/backend_api.py"]
        ports:
        - containerPort: 5000
        volumeMounts:
        - name: code-volume
          mountPath: /app
      volumes:
      - name: code-volume
        configMap:
          name: app-source-codes
---
apiVersion: v1
kind: Service
metadata:
  name: payment-svc
spec:
  selector:
    app: payment-processor
  ports:
  - port: 5000
    targetPort: 5000

---
# FRONTEND WORKLOAD (Store UI)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web-frontend
  template:
    metadata:
      labels:
        app: web-frontend
    spec:
      containers:
      - name: ui
        image: python:3.10-slim
        command: ["/bin/sh", "-c", "pip install flask requests && python /app/storefront.py"]
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: code-volume
          mountPath: /app
      volumes:
      - name: code-volume
        configMap:
          name: app-source-codes
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
spec:
  type: NodePort
  selector:
    app: web-frontend
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30080

---
# ROGUE ATTACKER POD
apiVersion: v1
kind: Pod
metadata:
  name: rogue-attacker
  labels:
    app: rogue
spec:
  containers:
  - name: attacker
    image: alpine/curl
    command: ["sleep", "3600"]
EOF

# Apply the infrastructure
kubectl apply -f ecommerce-infra.yaml
kubectl get pods -w
```
> **Note:** Press `Ctrl+C` once all pods show a `Running` status to exit the watch command.

### Task 2 — Baseline the Vulnerable Network
Before applying security, we must prove the cluster is inherently vulnerable. In standard Kubernetes, any pod can talk to any other pod.

1. **Verify Legitimate Frontend Traffic:** 
- Open the **View Port** in your lab interface and navigate to **Port 30080**. 
- You will see the CloudNative Store. Click on "Buy Now" for any item. 
- You will receive a successful receipt, proving the frontend can process orders against the backend database.

2. **Execute the Simulated Attack:** Return to your terminal. Execute a `curl` POST request from inside the `rogue-attacker` pod, targeting the internal `payment-svc` on port 5000.

```bash
kubectl exec rogue-attacker -- curl -s -X POST -H "Content-Type: application/json" -d '{"item_id":"item_1"}' http://payment-svc:5000/api/process-order
```
> **Why:** You will immediately receive the JSON payload containing an approved transaction ID. This is a critical security failure: an unauthorized container has successfully bypassed the frontend and forced a transaction directly in the sensitive payment processor.

### Task 3 — Enforce the Zero-Trust Boundary
We will now use Calico to lock down the network at the kernel level.

1. **Apply the Default Deny Policy:** The foundation of zero-trust is dropping everything by default. Create and apply a policy that blocks all incoming traffic to all pods in the default namespace.

```bash
cat << 'EOF' > default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF
kubectl apply -f default-deny.yaml
```

2. **Allow External UI Access & Verify Isolation:** Because the previous step dropped all traffic, we must punch a surgical hole to allow external users to hit the frontend UI.

```bash
cat << 'EOF' > allow-external-frontend.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-to-frontend
spec:
  podSelector:
    matchLabels:
      app: web-frontend
  policyTypes:
  - Ingress
  ingress:
  - ports:
    - protocol: TCP
      port: 8080
EOF
kubectl apply -f allow-external-frontend.yaml
```
- Return to your browser and attempt to make another purchase in the View Port (Port 30080). 
- After 3 seconds, the page will render a red error message: **"Checkout Failed"**. The Calico firewall has severed the internal connection. The frontend is fully isolated from the backend.

### Task 4 — Implement the Calico Allow-List
Now that the environment is secure, we must explicitly punch a surgical hole in the firewall to restore application functionality, without letting the attacker back in.

1. **Apply the Targeted Allow Policy:** Create a policy that applies only to the payment processor, and permits ingress traffic only if it originates from a pod labeled `app: web-frontend` on port 5000.

```bash
cat << 'EOF' > allow-frontend.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-payment
spec:
  podSelector:
    matchLabels:
      app: payment-processor
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web-frontend
    ports:
    - protocol: TCP
      port: 5000
EOF
kubectl apply -f allow-frontend.yaml
```

2. **Validate Frontend Restoration:** 
- Return to your View Port browser tab (Port 30080) and attempt to purchase an item again. 
- The green Payment Approved receipt is back. The authorized frontend can once again speak to the backend.

3. **Validate the Micro-Segmentation:** Return to your terminal and attempt the exact same attack you ran earlier. We are adding `-m 3` to force the command to timeout after 3 seconds.

```bash
kubectl exec rogue-attacker -- curl -m 3 -s -X POST -H "Content-Type: application/json" -d '{"item_id":"item_1"}' http://payment-svc:5000/api/process-order
```
> **Why:** The command will hang and ultimately return `command terminated with exit code 28` (Timeout). The Calico CNI has successfully recognized that the rogue pod lacks the correct labels and dropped the packets before they ever reached the payment processor.

---

## Validation
Verify your Kubernetes network policies are correctly enforced across your environment.

```bash
# 1. Review all active network policies in the namespace
kubectl get networkpolicies
```

```bash
# 2. Inspect the specific rules protecting the payment processor
kubectl describe networkpolicy allow-frontend-to-payment
```

Expected result:
- [ ] Were the frontend and backend pods successfully scheduled and assigned IP addresses by the Calico CNI?
- [ ] Did the default deny policy successfully block generic ping requests across the cluster?
- [ ] After applying the allow-list policy, could the frontend successfully communicate with the backend on the approved port?
- [ ] Was lateral traffic from rogue or unauthorized pods completely dropped by the Calico firewall rules?

## References & further learning
- Kubernetes Network Policies Documentation: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- Calico Documentation: Getting Started with Network Policy: https://docs.tigera.io/calico/latest/network-policy/
- KodeKloud course: Certified Kubernetes Security Specialist (CKS): https://kodekloud.com/courses/certified-kubernetes-security-specialist-cks
