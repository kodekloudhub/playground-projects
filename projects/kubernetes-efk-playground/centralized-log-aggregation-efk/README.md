# Centralized Log Aggregation and Analysis with EFK

**Level:** advanced  ·  **Playground:** Kubernetes EFK Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-k8s-with-efk)** — open it, then copy the files below.

## Files in this project
- [`cart.py`](./cart.py)
- [`efk-stack.yaml`](./efk-stack.yaml)
- [`frontend.py`](./frontend.py)
- [`payment.py`](./payment.py)
- [`requirements.txt`](./requirements.txt)
- [`retail-apps.yaml`](./retail-apps.yaml)
- [`templates/checkout.html`](./templates/checkout.html)
- [`templates/index.html`](./templates/index.html)

> Copy these into your playground session (or `git clone` this repo and `cd` here).

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
A rapidly growing e-commerce company recently refactored their monolithic platform into a distributed microservice architecture. Their primary retail application is now split across three distinct Kubernetes deployments: a Frontend Storefront, a Cart API, and a Payment Processor. 

This shift has created a massive troubleshooting bottleneck. When a customer reports a failed checkout, the engineering team has to manually run `kubectl logs` across dozens of individual microservice pods spread across multiple nodes just to piece together the transaction history. Worse, if a pod crashes and restarts during a traffic spike, the volatile logs are lost forever, leaving the team completely blind to the root cause. The Site Reliability Engineering team has mandated the implementation of a centralized logging system to decouple log storage from the application lifecycle.

## What you'll build
You will build an EFK (Elasticsearch, Fluentd, Kibana) stack from scratch. You will deploy the multi-tier application, build the backend Elasticsearch storage, configure Fluentd as a DaemonSet to securely scrape logs from all cluster nodes, and expose the Kibana UI. Finally, you will prove the pipeline works by reproducing a checkout error through the storefront UI and using a unique `transaction_id` to visually trace the failure across all three microservices from a single dashboard.

## Learning objectives
By the end you will be able to:
- Deploy a multi-tier microservice architecture that generates correlatable log data.
- Provision an Elasticsearch instance in Kubernetes for centralized log storage.
- Configure and deploy Fluentd as a DaemonSet with appropriate RBAC permissions to collect container logs node-wide.
- Create Index Patterns and execute cross-service search queries in Kibana.
- Build custom visualizations in Kibana based on Kubernetes metadata (e.g., pod labels).

## Prerequisites
- Playground: **K8s with EFK** (open it before starting)

---

## Steps

### Task 1 — Create the Microservice Application Code
These scripts contain the logic for the Frontend, Cart, and Payment services. The Payment service is programmed to randomly fail 50% of the time to generate a trace.

```bash
cat << 'EOF' > frontend.py
import uuid, requests, logging, sys
from flask import Flask, render_template

app = Flask(__name__)
logging.basicConfig(stream=sys.stdout, level=logging.INFO, format='%(message)s')

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/checkout')
def checkout():
    tx_id = str(uuid.uuid4())
    logging.info(f'{{"service": "frontend", "transaction_id": "{tx_id}", "event": "checkout_started"}}')

    headers = {'X-Transaction-ID': tx_id}
    try:
        res = requests.get('http://cart-service:8080/add', headers=headers, timeout=5)
        status = "Success" if res.status_code == 200 else "Failed"
        return render_template('checkout.html', tx_id=tx_id, status=status)
    except Exception as e:
        logging.error(f'{{"service": "frontend", "transaction_id": "{tx_id}", "error": "{str(e)}"}}')
        return render_template('checkout.html', tx_id=tx_id, status="Error")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF
```

```bash
cat << 'EOF' > cart.py
import requests, logging, sys
from flask import Flask, request

app = Flask(__name__)
logging.basicConfig(stream=sys.stdout, level=logging.INFO, format='%(message)s')

@app.route('/add')
def add_to_cart():
    tx_id = request.headers.get('X-Transaction-ID', 'unknown')
    logging.info(f'{{"service": "cart", "transaction_id": "{tx_id}", "event": "items_compiled"}}')

    headers = {'X-Transaction-ID': tx_id}
    res = requests.get('http://payment-service:8080/charge', headers=headers)
    return "Cart updated.\n", res.status_code

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF
```

```bash
cat << 'EOF' > payment.py
import logging, sys, random
from flask import Flask, request

app = Flask(__name__)
logging.basicConfig(stream=sys.stdout, level=logging.INFO, format='%(message)s')

@app.route('/charge')
def charge():
    tx_id = request.headers.get('X-Transaction-ID', 'unknown')

    if random.choice([True, False]):
        logging.error(f'{{"service": "payment", "transaction_id": "{tx_id}", "event": "charge_failed", "error": "insufficient_funds"}}')
        return "Payment failed.\n", 500
    else:
        logging.info(f'{{"service": "payment", "transaction_id": "{tx_id}", "event": "charge_successful"}}')
        return "Payment processed.\n", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF
```

```bash
cat << 'EOF' > requirements.txt
Flask==3.0.0
requests==2.31.0
EOF
```
> **Why:** The microservices pass a unified `X-Transaction-ID` header between them and log it to standard output. This creates a distributed trace that our logging architecture will soon aggregate.

### Task 2 — Create the Interactive Web Interface
Generate the HTML templates for the Frontend Storefront UI.

```bash
mkdir -p templates
```

```bash
cat << 'EOF' > templates/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Kode E-Commerce</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-50 font-sans text-gray-800 flex items-center justify-center h-screen">
    <div class="bg-white p-10 rounded-2xl shadow-lg border border-gray-100 max-w-md text-center">
        <h1 class="text-3xl font-black text-gray-900 mb-2">Kode E-Commerce</h1>
        <p class="text-gray-500 mb-8">Distributed Microservices Demo</p>
        <div class="bg-gray-100 h-48 rounded-xl mb-6 flex items-center justify-center">
            <span class="text-gray-400 font-bold text-xl">Premium Cloud Item</span>
        </div>
        <div class="flex justify-between items-center mb-8">
            <span class="text-xl font-bold">Total Price</span>
            <span class="text-2xl text-indigo-600 font-extrabold">$250.00</span>
        </div>
        <a href="/checkout" class="block w-full bg-indigo-600 text-white px-8 py-4 rounded-full font-bold text-lg shadow-lg hover:bg-indigo-700 transition">Complete Checkout</a>
    </div>
</body>
</html>
EOF
```

```bash
cat << 'EOF' > templates/checkout.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Checkout Status</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-50 font-sans text-gray-800 flex items-center justify-center h-screen">
    <div class="bg-white p-10 rounded-2xl shadow-lg border border-gray-100 max-w-lg text-center">
        {% if status == 'Success' %}
            <div class="text-green-500 text-6xl mb-4">✓</div>
            <h1 class="text-3xl font-black text-gray-900 mb-2">Order Confirmed</h1>
            <p class="text-gray-500 mb-6">Your payment was successfully processed.</p>
        {% else %}
            <div class="text-red-500 text-6xl mb-4">✗</div>
            <h1 class="text-3xl font-black text-gray-900 mb-2">Checkout Failed</h1>
            <p class="text-gray-500 mb-6">Payment processor declined the transaction. Check Kibana logs.</p>
        {% endif %}
        <div class="bg-gray-100 p-4 rounded-lg text-left mb-8 break-all">
            <span class="text-xs text-gray-400 uppercase font-bold">Transaction ID (Trace ID)</span><br>
            <span class="font-mono text-gray-700 font-bold">{{ tx_id }}</span>
        </div>
        <a href="/" class="block w-full bg-gray-200 text-gray-700 px-8 py-4 rounded-full font-bold text-lg hover:bg-gray-300 transition">Return to Storefront</a>
    </div>
</body>
</html>
EOF
```

### Task 3 — Deploy the Microservices
Load your code and templates into Kubernetes ConfigMaps, then deploy the frontend, cart, and payment deployments and services.

```bash
kubectl create configmap frontend-code --from-file=app.py=frontend.py --from-file=requirements.txt
kubectl create configmap frontend-templates --from-file=templates/index.html --from-file=templates/checkout.html
kubectl create configmap cart-code --from-file=app.py=cart.py --from-file=requirements.txt
kubectl create configmap payment-code --from-file=app.py=payment.py --from-file=requirements.txt
```

```bash
cat << 'EOF' > retail-apps.yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  selector:
    app: frontend
  ports:
    - port: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: app
          image: python:3.11-slim
          command: ["/bin/sh", "-c", "pip install --no-cache-dir -r /app/requirements.txt && python /app/app.py"]
          volumeMounts:
            - name: code
              mountPath: /app
            - name: templates
              mountPath: /app/templates
      volumes:
        - name: code
          configMap:
            name: frontend-code
        - name: templates
          configMap:
            name: frontend-templates
---
apiVersion: v1
kind: Service
metadata:
  name: cart-service
spec:
  selector:
    app: cart
  ports:
    - port: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cart
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cart
  template:
    metadata:
      labels:
        app: cart
    spec:
      containers:
        - name: app
          image: python:3.11-slim
          command: ["/bin/sh", "-c", "pip install --no-cache-dir -r /app/requirements.txt && python /app/app.py"]
          volumeMounts:
            - name: code
              mountPath: /app
      volumes:
        - name: code
          configMap:
            name: cart-code
---
apiVersion: v1
kind: Service
metadata:
  name: payment-service
spec:
  selector:
    app: payment
  ports:
    - port: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payment
  template:
    metadata:
      labels:
        app: payment
    spec:
      containers:
        - name: app
          image: python:3.11-slim
          command: ["/bin/sh", "-c", "pip install --no-cache-dir -r /app/requirements.txt && python /app/app.py"]
          volumeMounts:
            - name: code
              mountPath: /app
      volumes:
        - name: code
          configMap:
            name: payment-code
EOF
```

```bash
kubectl apply -f retail-apps.yaml
```

### Task 4 — Prepare the Namespace & Deploy the EFK Stack
Clear out any conflicting pre-configured lab environments, prepare a clean `observability` namespace, and deploy Elasticsearch, Fluentd, and Kibana.

```bash
kubectl delete -f elastic-search/ --ignore-not-found=true
kubectl delete namespace elastic-stack --ignore-not-found=true
kubectl create namespace observability
```

```bash
cat << 'EOF' > efk-stack.yaml
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  namespace: observability
spec:
  selector:
    app: elasticsearch
  ports:
    - port: 9200
      targetPort: 9200
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: elasticsearch
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: elasticsearch
  template:
    metadata:
      labels:
        app: elasticsearch
    spec:
      containers:
      - name: elasticsearch
        image: docker.elastic.co/elasticsearch/elasticsearch:7.17.9
        env:
        - name: discovery.type
          value: single-node
        - name: ES_JAVA_OPTS
          value: "-Xms512m -Xmx512m"
        resources:
          limits:
            memory: 1Gi
          requests:
            memory: 512Mi
        ports:
        - containerPort: 9200
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fluentd
  namespace: observability
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: fluentd
rules:
- apiGroups: [""]
  resources: ["pods", "namespaces"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: fluentd
roleRef:
  kind: ClusterRole
  name: fluentd
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: fluentd
  namespace: observability
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
  namespace: observability
spec:
  selector:
    matchLabels:
      app: fluentd
  template:
    metadata:
      labels:
        app: fluentd
    spec:
      serviceAccountName: fluentd
      containers:
      - name: fluentd
        image: fluent/fluentd-kubernetes-daemonset:v1.15-debian-elasticsearch7-1
        env:
          - name: FLUENT_ELASTICSEARCH_HOST
            value: "elasticsearch"
          - name: FLUENT_ELASTICSEARCH_PORT
            value: "9200"
          - name: FLUENT_ELASTICSEARCH_SCHEME
            value: "http"
          - name: FLUENT_CONTAINER_TAIL_PARSER_TYPE
            value: "cri"
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
---
apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: observability
spec:
  type: NodePort
  ports:
    - port: 5601
      nodePort: 30601
  selector:
    app: kibana
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kibana
  template:
    metadata:
      labels:
        app: kibana
    spec:
      containers:
      - name: kibana
        image: docker.elastic.co/kibana/kibana:7.17.9
        env:
        - name: ELASTICSEARCH_HOSTS
          value: "http://elasticsearch.observability.svc.cluster.local:9200"
        resources:
          limits:
            memory: 1Gi
          requests:
            memory: 512Mi
        ports:
        - containerPort: 5601
EOF
```

```bash
kubectl apply -f efk-stack.yaml
```
> **Why:** The fluentd DaemonSet uses the generated `ServiceAccount` and `ClusterRoleBinding` to gain permission to read pod metadata, allowing it to enrich the raw logs it scrapes from the node's `/var/log` mounts before shipping them to Elasticsearch.

### Task 5 — Initialization & Traffic Generation
Watch the EFK pods spin up. Do not proceed until all pods show a `Running` status.

```bash
kubectl get pods -n observability -w
```
*(Press **Ctrl+C** to exit the watch screen once they are ready).*

Wait for Kibana to become responsive on the exposed NodePort:
```bash
until $(curl --output /dev/null --silent --head --fail http://0.0.0.0:30601); do
    echo 'Waiting for Kibana UI...'
    sleep 5
done
echo "Kibana is UP!"
```

Expose the Frontend application so you can trigger the web interface:
```bash
kubectl port-forward --address 0.0.0.0 svc/frontend-service 18080:8080 &
```
1. Click the ellipses button in the top right of your playground environment > **View Port**.
2. Enter port `18080` > **Open Port**.
3. Click **Complete Checkout**. Keep attempting checkouts until you receive a *Checkout Failed* screen. Note down the specific Transaction ID displayed.

### Task 6 — Monitoring & Tracing in Kibana
1. Click the **Kibana Dashboard** button in your lab UI.
2. Click **Explore on my own**.
3. Navigate to the left hamburger menu > **Stack Management > Index Patterns**.
4. Click **Create index pattern**.
5. Type `logstash-*`, select `@timestamp`, and click **Create index pattern**.
6. Open the left menu again and click **Discover**. Ensure the time filter (top right) is set to **Today**.
7. Paste your copied Transaction ID into the main Kibana search bar (e.g., `123e4567-e89b-12d3-a456-426614174000`) and hit enter. Observe the chronological lifecycle of the checkout flow passing from the Frontend pod to the Cart pod, and ultimately failing at the Payment pod.
8. On the left menu click **Visualize Library > Create new visualization**. Choose **Lens**.
9. Drag the `kubernetes.labels.app.keyword` field into the visualization pane to immediately see a breakdown of log volume distributed across your three microservices.
10. Click **Save** in the top right corner. Enter a Title (e.g., "Microservice Log Distribution"), select the **None** radio button under *Add to dashboard*, and click **Save**.

---

## Validation
Verify your application and observability components are running before checking your Kibana logs.

```bash
# 1. Check the status of the retail application microservices
kubectl get all -l 'app in (frontend, cart, payment)'
```

```bash
# 2. Check the status of the EFK Stack components
kubectl get all -n observability
```

Expected result:
- [ ] Are the Frontend, Cart, and Payment microservices actively running?
- [ ] Are the Elasticsearch, Fluentd, and Kibana pods successfully deployed and displaying a `Ready` status?
- [ ] Does the Fluentd DaemonSet have the correct RBAC permissions (ClusterRole/Binding) to access namespace and pod metadata?
- [ ] Were you able to successfully reach the Kibana UI via its configured Service port in your browser?
- [ ] Did you successfully configure an Index Pattern (e.g., `logstash-*` or `fluentd-*`) using the `@timestamp` field?
- [ ] Did you successfully reproduce a checkout failure in the Frontend UI and retrieve the associated Transaction ID?
- [ ] Can you search Kibana for that specific `transaction_id` and see the sequential log entries pinpointing exactly where the payment failed?
- [ ] Did you successfully render and save a visual graph summarizing the log data distribution across the microservices?

## References & further learning
- Elasticsearch Documentation: https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html
- Fluentd Kubernetes DaemonSet Repository & Guide: https://github.com/fluent/fluentd-kubernetes-daemonset
- Kibana Discover & Visualization: https://www.elastic.co/guide/en/kibana/current/discover.html
- KodeKloud course: Kubernetes for the Absolute Beginners - Hands-on Tutorial: https://kodekloud.com/courses/kubernetes-for-the-absolute-beginners-hands-on-tutorial/
- KodeKloud course: EFK Stack: Enterprise-Grade Logging and Monitoring: https://kodekloud.com/courses/efk-stack-enterprise-grade-logging-and-monitoring
- KodeKloud course: Learn By Doing: Deploying and Managing the EFK Stack on Kubernetes: https://kodekloud.com/courses/learn-by-doing-deploying-and-managing-the-efk-stack-on-kubernetes
