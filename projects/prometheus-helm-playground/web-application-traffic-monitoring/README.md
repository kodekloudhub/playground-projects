# Web Application Traffic Monitoring

**Level:** intermediate  ·  **Playground:** Prometheus Helm Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-prometheus-with-helm)** — open it, then copy the files below.

## Files in this project
- [`app.py`](./app.py)
- [`requirements.txt`](./requirements.txt)
- [`retail-frontend/Chart.yaml`](./retail-frontend/Chart.yaml)
- [`retail-frontend/templates/deployment.yaml`](./retail-frontend/templates/deployment.yaml)
- [`retail-frontend/templates/ingress.yaml`](./retail-frontend/templates/ingress.yaml)
- [`retail-frontend/templates/service.yaml`](./retail-frontend/templates/service.yaml)
- [`retail-frontend/templates/servicemonitor.yaml`](./retail-frontend/templates/servicemonitor.yaml)
- [`retail-frontend/values.yaml`](./retail-frontend/values.yaml)
- [`templates/cart.html`](./templates/cart.html)
- [`templates/collections.html`](./templates/collections.html)
- [`templates/index.html`](./templates/index.html)
- [`templates/shop.html`](./templates/shop.html)

> Copy these into your playground session (or `git clone` this repo and `cd` here).

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
A digital retail company recently migrated their primary customer-facing application to Kubernetes. Currently, the operations team has a major observability blind spot: when developers release a new version of the storefront, the team relies on basic infrastructure metrics or delayed support tickets to understand user behavior. They lack real-time visibility into how traffic flows through different parts of the application, making it difficult to assess the immediate impact of marketing surges or UI changes.

The Site Reliability Engineering team is transitioning to a proactive, automated observability model. You have been tasked with building a dynamic monitoring workflow. The goal is to ensure that whenever the application is deployed, it automatically registers itself with the cluster's monitoring system. You must deploy a custom retail web application, configure an Ingress route to accept external traffic, expose its labeled telemetry data, and prove that traffic spikes and page-specific user journeys are immediately visualized in a centralized Grafana dashboard without manually editing configuration files.

## What you'll build
Starting from a baseline Kubernetes environment, you will establish an end-to-end deployment and monitoring workflow. You will use Helm to deploy the NGINX Ingress Controller and the retail web application. You will configure the Helm deployment to automatically generate a ServiceMonitor and an Ingress resource, route external HTTP traffic to the application, and use Prometheus and Grafana to track user traffic across distinct application routes in real-time.

## Learning objectives
By the end you will be able to:
- Deploy the NGINX Ingress Controller using Helm to manage external traffic routing.
- Scaffold and deploy a custom Helm chart containing dynamic `values.yaml` overrides.
- Automatically generate Kubernetes `ServiceMonitor` resources to expose metrics to Prometheus.
- Execute PromQL queries to aggregate and visualize HTTP request telemetry.
- Build live, multi-panel Grafana dashboards to track customer traffic distributions.

## Prerequisites
- Playground: **Prometheus with Helm** (open it before starting)

---

## Steps

### Task 1 — Verify the Monitoring Stack
Ensure the playground's Prometheus stack has fully initialized before proceeding.

```bash
while [[ $(helm status prometheus-stack | egrep -w STATUS | awk -F: '{print $2}' | tr -d ' ') != "deployed" ]]; 
do
  echo "Waiting for the kube-prometheus-stack to come up...";
  sleep 5; 
done
```

Explicitly verify this by checking for the `deployed` status in your release list:
```bash
helm list
```

### Task 2 — Create the Functional Application Code
This Python code includes routes for `/`, `/shop`, `/collections`, and `/cart`, with a labeled Prometheus metric (`['page']`) tracking traffic across all four pages.

```bash
cat << 'EOF' > app.py
from flask import Flask, render_template, Response
from prometheus_client import Counter, generate_latest

app = Flask(__name__)

REQUESTS = Counter('http_requests_total', 'Total HTTP requests from customers', ['page'])

@app.route('/')
def index():
    REQUESTS.labels(page='home').inc()
    return render_template('index.html')

@app.route('/shop')
def shop():
    REQUESTS.labels(page='shop').inc()
    return render_template('shop.html')

@app.route('/collections')
def collections():
    REQUESTS.labels(page='collections').inc()
    return render_template('collections.html')

@app.route('/cart')
def cart():
    REQUESTS.labels(page='cart').inc()
    return render_template('cart.html')

@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype="text/plain")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF
```

```bash
cat << 'EOF' > requirements.txt
Flask==3.0.0
prometheus_client==0.17.1
EOF
```

### Task 3 — Create the Interactive Web Interface
Generate the templates for all four unique pages.

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
    <title>Kode Retail Storefront</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-50 font-sans text-gray-800">
    <nav class="bg-white shadow-sm p-5 flex justify-between items-center border-b border-gray-200">
        <div class="text-3xl font-extrabold text-indigo-600 tracking-tight">Kode Retail</div>
        <ul class="flex space-x-8 text-sm font-semibold text-gray-500 uppercase tracking-wide">
            <li><a href="/shop" class="hover:text-indigo-600 transition">Shop</a></li>
            <li><a href="/collections" class="hover:text-indigo-600 transition">Collections</a></li>
            <li><a href="/cart" class="text-indigo-600 border border-indigo-600 px-4 py-2 rounded-full hover:bg-indigo-50 transition">Cart (0)</a></li>
        </ul>
    </nav>
    <main class="container mx-auto mt-16 px-6 text-center">
        <h1 class="text-6xl font-black text-gray-900 mb-6 tracking-tight">The Future of Shopping.</h1>
        <p class="text-xl text-gray-500 mb-10 max-w-2xl mx-auto">Experience seamless, lightning-fast checkout powered by Kubernetes.</p>
        <a href="/shop" class="inline-block bg-indigo-600 text-white px-8 py-4 rounded-full font-bold text-lg shadow-lg hover:bg-indigo-700 hover:shadow-xl transition transform hover:-translate-y-1">Shop the Collection</a>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-10 mt-20 text-left">
            <a href="/shop" class="block bg-white p-6 rounded-2xl shadow-sm border border-gray-100 hover:shadow-xl transition duration-300">
                <div class="bg-gray-100 h-64 rounded-xl mb-6 flex items-center justify-center text-gray-400 font-medium">Image Placeholder</div>
                <h3 class="text-2xl font-bold mb-2">Cloud Native Sneakers</h3>
                <p class="text-indigo-600 font-extrabold text-xl">$120.00</p>
            </a>
            <a href="/shop" class="block bg-white p-6 rounded-2xl shadow-sm border border-gray-100 hover:shadow-xl transition duration-300">
                <div class="bg-gray-100 h-64 rounded-xl mb-6 flex items-center justify-center text-gray-400 font-medium">Image Placeholder</div>
                <h3 class="text-2xl font-bold mb-2">Observability Hoodie</h3>
                <p class="text-indigo-600 font-extrabold text-xl">$65.00</p>
            </a>
            <a href="/shop" class="block bg-white p-6 rounded-2xl shadow-sm border border-gray-100 hover:shadow-xl transition duration-300">
                <div class="bg-gray-100 h-64 rounded-xl mb-6 flex items-center justify-center text-gray-400 font-medium">Image Placeholder</div>
                <h3 class="text-2xl font-bold mb-2">Telemetry Smartwatch</h3>
                <p class="text-indigo-600 font-extrabold text-xl">$199.00</p>
            </a>
        </div>
    </main>
</body>
</html>
EOF
```

```bash
cat << 'EOF' > templates/shop.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Shop - Kode Retail</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-50 font-sans text-gray-800">
    <nav class="bg-white shadow-sm p-5 flex justify-between items-center border-b border-gray-200">
        <div class="text-3xl font-extrabold text-indigo-600 tracking-tight"><a href="/">Kode Retail</a></div>
        <ul class="flex space-x-8 text-sm font-semibold text-gray-500 uppercase tracking-wide">
            <li><a href="/shop" class="text-indigo-600 border-b-2 border-indigo-600 pb-1">Shop</a></li>
            <li><a href="/collections" class="hover:text-indigo-600 transition">Collections</a></li>
            <li><a href="/" class="hover:text-indigo-600 transition">Home</a></li>
            <li><a href="/cart" class="border border-indigo-600 px-4 py-2 rounded-full hover:bg-indigo-50 transition">Cart (0)</a></li>
        </ul>
    </nav>
    <main class="container mx-auto mt-16 px-6">
        <h1 class="text-4xl font-black text-gray-900 mb-2">The Collection</h1>
        <p class="text-lg text-gray-500 mb-10">Select an item below. Every click generates telemetry.</p>
        <div class="grid grid-cols-1 md:grid-cols-4 gap-8">
            <div class="bg-white p-4 rounded-xl shadow-sm border border-gray-100 hover:shadow-lg transition">
                <div class="bg-blue-100 h-48 rounded-lg mb-4 flex items-center justify-center text-blue-500 font-bold text-xl">Kube-Tee</div>
                <h3 class="font-bold text-lg">Kubernetes T-Shirt</h3>
                <p class="text-gray-500 mb-4">$25.00</p>
                <a href="/cart" class="block text-center w-full bg-indigo-50 text-indigo-700 font-bold py-2 rounded hover:bg-indigo-100 transition">Add to Cart</a>
            </div>
            <div class="bg-white p-4 rounded-xl shadow-sm border border-gray-100 hover:shadow-lg transition">
                <div class="bg-green-100 h-48 rounded-lg mb-4 flex items-center justify-center text-green-500 font-bold text-xl">Helm Hat</div>
                <h3 class="font-bold text-lg">Helm Logo Cap</h3>
                <p class="text-gray-500 mb-4">$18.00</p>
                <a href="/cart" class="block text-center w-full bg-indigo-50 text-indigo-700 font-bold py-2 rounded hover:bg-indigo-100 transition">Add to Cart</a>
            </div>
            <div class="bg-white p-4 rounded-xl shadow-sm border border-gray-100 hover:shadow-lg transition">
                <div class="bg-purple-100 h-48 rounded-lg mb-4 flex items-center justify-center text-purple-500 font-bold text-xl">Prometheus Mug</div>
                <h3 class="font-bold text-lg">Metrics Coffee Mug</h3>
                <p class="text-gray-500 mb-4">$15.00</p>
                <a href="/cart" class="block text-center w-full bg-indigo-50 text-indigo-700 font-bold py-2 rounded hover:bg-indigo-100 transition">Add to Cart</a>
            </div>
            <div class="bg-white p-4 rounded-xl shadow-sm border border-gray-100 hover:shadow-lg transition">
                <div class="bg-yellow-100 h-48 rounded-lg mb-4 flex items-center justify-center text-yellow-600 font-bold text-xl">Grafana Socks</div>
                <h3 class="font-bold text-lg">Dashboard Socks</h3>
                <p class="text-gray-500 mb-4">$12.00</p>
                <a href="/cart" class="block text-center w-full bg-indigo-50 text-indigo-700 font-bold py-2 rounded hover:bg-indigo-100 transition">Add to Cart</a>
            </div>
        </div>
    </main>
</body>
</html>
EOF
```

```bash
cat << 'EOF' > templates/collections.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Collections - Kode Retail</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-50 font-sans text-gray-800">
    <nav class="bg-white shadow-sm p-5 flex justify-between items-center border-b border-gray-200">
        <div class="text-3xl font-extrabold text-indigo-600 tracking-tight"><a href="/">Kode Retail</a></div>
        <ul class="flex space-x-8 text-sm font-semibold text-gray-500 uppercase tracking-wide">
            <li><a href="/shop" class="hover:text-indigo-600 transition">Shop</a></li>
            <li><a href="/collections" class="text-indigo-600 border-b-2 border-indigo-600 pb-1">Collections</a></li>
            <li><a href="/" class="hover:text-indigo-600 transition">Home</a></li>
            <li><a href="/cart" class="border border-indigo-600 px-4 py-2 rounded-full hover:bg-indigo-50 transition">Cart (0)</a></li>
        </ul>
    </nav>
    <main class="container mx-auto mt-16 px-6">
        <h1 class="text-4xl font-black text-gray-900 mb-2">Featured Collections</h1>
        <p class="text-lg text-gray-500 mb-10">Curated cloud-native bundles.</p>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-8 max-w-4xl mx-auto">
            <div class="bg-white p-4 rounded-xl shadow-sm border border-gray-100 hover:shadow-lg transition">
                <div class="bg-indigo-100 h-64 rounded-lg mb-4 flex items-center justify-center text-indigo-500 font-bold text-2xl">Observability Winter Line</div>
                <h3 class="font-bold text-xl">Bundle: Hoodie & Socks</h3>
                <p class="text-gray-500 mb-4">$70.00</p>
                <a href="/cart" class="block text-center w-full bg-indigo-50 text-indigo-700 font-bold py-3 rounded hover:bg-indigo-100 transition">Add Bundle to Cart</a>
            </div>
            <div class="bg-white p-4 rounded-xl shadow-sm border border-gray-100 hover:shadow-lg transition">
                <div class="bg-teal-100 h-64 rounded-lg mb-4 flex items-center justify-center text-teal-500 font-bold text-2xl">Container Summer Line</div>
                <h3 class="font-bold text-xl">Bundle: T-Shirt & Cap</h3>
                <p class="text-gray-500 mb-4">$40.00</p>
                <a href="/cart" class="block text-center w-full bg-indigo-50 text-indigo-700 font-bold py-3 rounded hover:bg-indigo-100 transition">Add Bundle to Cart</a>
            </div>
        </div>
    </main>
</body>
</html>
EOF
```

```bash
cat << 'EOF' > templates/cart.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cart - Kode Retail</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-50 font-sans text-gray-800">
    <nav class="bg-white shadow-sm p-5 flex justify-between items-center border-b border-gray-200">
        <div class="text-3xl font-extrabold text-indigo-600 tracking-tight"><a href="/">Kode Retail</a></div>
        <ul class="flex space-x-8 text-sm font-semibold text-gray-500 uppercase tracking-wide">
            <li><a href="/shop" class="hover:text-indigo-600 transition">Shop</a></li>
            <li><a href="/collections" class="hover:text-indigo-600 transition">Collections</a></li>
            <li><a href="/" class="hover:text-indigo-600 transition">Home</a></li>
            <li><a href="/cart" class="text-indigo-600 border border-indigo-600 px-4 py-2 rounded-full bg-indigo-50 transition">Cart (1)</a></li>
        </ul>
    </nav>
    <main class="container mx-auto mt-16 px-6 text-center">
        <h1 class="text-4xl font-black text-gray-900 mb-6">Your Cart</h1>
        <div class="bg-white p-8 rounded-2xl shadow-sm border border-gray-100 max-w-2xl mx-auto">
            <div class="flex justify-between items-center border-b border-gray-100 pb-4 mb-4">
                <span class="text-xl font-bold">Awesome Cloud Item</span>
                <span class="text-xl text-indigo-600 font-extrabold">$25.00</span>
            </div>
            <div class="flex justify-between items-center text-lg font-bold mb-8">
                <span>Total</span>
                <span>$25.00</span>
            </div>
            <a href="/" class="block w-full bg-indigo-600 text-white px-8 py-4 rounded-full font-bold text-lg shadow-lg hover:bg-indigo-700 transition">Secure Checkout</a>
        </div>
    </main>
</body>
</html>
EOF
```

### Task 4 — Load the Code into Kubernetes ConfigMaps

```bash
kubectl create configmap retail-code --from-file=app.py --from-file=requirements.txt
```

```bash
kubectl create configmap retail-templates \
  --from-file=templates/index.html \
  --from-file=templates/shop.html \
  --from-file=templates/collections.html \
  --from-file=templates/cart.html
```

### Task 5 — Scaffold the Helm Chart
Build out the basic Helm structure and define the necessary Kubernetes manifests.

```bash
mkdir -p retail-frontend/templates
```

```bash
cat << 'EOF' > retail-frontend/Chart.yaml
apiVersion: v2
name: retail-frontend
description: A custom retail web application with Prometheus observability
version: 0.1.0
appVersion: "1.0"
EOF
```

```bash
cat << 'EOF' > retail-frontend/values.yaml
replicaCount: 1

image:
  repository: python
  pullPolicy: IfNotPresent
  tag: "3.11-slim"

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  className: ""
  hosts:
    - host: retail-frontend.local
      paths:
        - path: /

metrics:
  enabled: false
  serviceMonitor:
    enabled: false
    interval: 10s
EOF
```

```bash
cat << 'EOF' > retail-frontend/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
  labels:
    app: retail-frontend
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: retail-frontend
  template:
    metadata:
      labels:
        app: retail-frontend
    spec:
      containers:
        - name: application
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          workingDir: /app
          command: ["/bin/sh", "-c"]
          args: ["pip install --no-cache-dir -r requirements.txt && python app.py"]
          ports:
            - name: http
              containerPort: 8080
          volumeMounts:
            - name: code
              mountPath: /app/app.py
              subPath: app.py
            - name: code
              mountPath: /app/requirements.txt
              subPath: requirements.txt
            - name: templates
              mountPath: /app/templates
      volumes:
        - name: code
          configMap:
            name: retail-code
        - name: templates
          configMap:
            name: retail-templates
EOF
```

```bash
cat << 'EOF' > retail-frontend/templates/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}
  labels:
    app: retail-frontend
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
      name: http
  selector:
    app: retail-frontend
EOF
```

```bash
cat << 'EOF' > retail-frontend/templates/ingress.yaml
{{- if .Values.ingress.enabled -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .Release.Name }}
spec:
  {{- if .Values.ingress.className }}
  ingressClassName: {{ .Values.ingress.className }}
  {{- end }}
  rules:
    {{- range .Values.ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: Prefix
            backend:
              service:
                name: {{ $.Release.Name }}
                port:
                  number: {{ $.Values.service.port }}
          {{- end }}
    {{- end }}
{{- end }}
EOF
```

```bash
cat << 'EOF' > retail-frontend/templates/servicemonitor.yaml
{{- if and .Values.metrics.enabled .Values.metrics.serviceMonitor.enabled -}}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ .Release.Name }}
  labels:
    app: retail-frontend
    release: prometheus-stack
spec:
  selector:
    matchLabels:
      app: retail-frontend
  endpoints:
    - port: http
      path: /metrics
      interval: {{ .Values.metrics.serviceMonitor.interval }}
{{- end }}
EOF
```

### Task 6 — Deploy the Infrastructure

First, deploy the NGINX Ingress Controller.
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx
```

Wait for the ingress controller webhook to initialize fully:
```bash
kubectl wait --namespace default --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
```

Deploy the Retail Application, applying overrides to enable Ingress and the ServiceMonitor:
```bash
helm install retail-frontend ./retail-frontend \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host=retail-frontend.local \
  --set ingress.hosts[0].paths[0].path=/ \
  --set metrics.enabled=true \
  --set metrics.serviceMonitor.enabled=true
```

Verify your workload is running:
```bash
kubectl get pods
```

### Task 7 — View the UI and Generate Traffic
Expose the application directly so you can view the storefront in your browser.

```bash
kubectl port-forward --address 0.0.0.0 svc/retail-frontend 18081:80 &
```
1. Click the ellipses button in the top right of your playground environment > **View Port**.
2. Enter port `18081` > **Open Port**.
3. Click through the full UI! Go to "Shop", "Collections", click "Add to Cart", and view your Cart. Every unique page load generates a distinctly labeled metric.

*(Optional)* To simulate an automated background surge on the main endpoint, run this block in your terminal:
```bash
echo "127.0.0.1 retail-frontend.local" | sudo tee -a /etc/hosts
kubectl port-forward --address 0.0.0.0 svc/ingress-nginx-controller 18080:80 &
while true; do curl -s -o /dev/null -w "Status: %{http_code}\n" -H "Host: retail-frontend.local" http://localhost:18080; sleep 0.5; done
```

### Task 8 — Visualize the Telemetry in Prometheus
1. Click the **Prometheus** button in the top right corner of your terminal.
2. Go to **Status > Targets** and verify `retail-frontend` is `UP`.
3. Return to the home screen, query `http_requests_total`, click **Execute**, and select the **Graph** tab. Ensure you click the pages in your UI unevenly so the traffic lines fan out instead of overlapping perfectly.

### Task 9 — Create the Grafana Dashboard
1. Click the **Grafana** tab located in the top-right corner of your terminal.
2. Log in with:
   - **Username:** `admin`
   - **Password:** `Admin@123`
3. In the left navigation menu, hover over the **Dashboards** icon (the four squares) and click **+ New dashboard** from the flyout menu.

**Create Panel 1: Total Requests by Page**
1. Select **Add a new panel**.
2. In the bottom query section (Row A), click the **Code** button to switch to the text editor.
3. Paste the query: `sum by (page) (http_requests_total)`
4. On the right-hand sidebar under *Panel options*, set the Title to **Total Requests by Page**.
5. Leave the visualization type as *Time series*.
6. Click the blue **Apply** button in the top right.

**Create Panel 2: Total Storefront Visits**
1. Click the **Add panel** icon (+) at the top right, and select **Add a new panel**.
2. Click **Code** and enter query: `sum(http_requests_total)`
3. Under *Panel options*, set Title to **Total Customer Visits**.
4. Go to the top right corner of the screen (right beneath the Apply button). Click the dropdown menu that currently says *Time series* and change it to **Stat**.
5. Click **Apply**.

**Create Panel 3: Page Popularity Breakdown**
1. Click the **Add panel** icon > **Add a new panel**.
2. Click **Code** and enter query: `sum by (page) (http_requests_total)`
3. Under *Panel options*, set Title to **Traffic Distribution**.
4. Click the *Time series* dropdown at the top right again, and change it to **Pie chart**.
5. Click **Apply**.

Finally, set the auto-refresh dropdown in the top right to **5s**. Click the **Save dashboard** icon (the floppy disk next to the Add panel button), name it `Kode Retail Overview`, and watch your graphs react in real-time as you run through the shopping flow in your UI tab.

---

## Validation
Verify your application resources are running and test the external ingress routing.

```bash
# 1. Check the status of your retail application resources and ServiceMonitor
kubectl get all,servicemonitor -l app=retail-frontend
```

```bash
# 2. Test the application routing via the NGINX Ingress Controller
curl -s -H "Host: retail-frontend.local" http://localhost:18080/shop | grep "<title>"
```

Expected result:
- [ ] Is the Prometheus monitoring stack actively running in your Kubernetes cluster?
- [ ] Is the NGINX Ingress Controller actively running and listening for external traffic?
- [ ] Did the application Helm installation successfully create the Pods, Services, Ingress resource, and the required `ServiceMonitor` Custom Resource?
- [ ] Can you successfully reach the application via its configured Ingress routing and navigate through the different pages of the storefront?
- [ ] Is the application successfully discovered and listed in an `UP` state on the Prometheus **Status > Targets** page?
- [ ] Does your PromQL query successfully parse the raw metrics and return a valid graph of HTTP traffic split by the page labels?
- [ ] Is your Grafana dashboard successfully displaying live data across all three required UI panels?
- [ ] **The Final E2E Test:** If you send a rapid burst of HTTP requests through the NGINX Ingress Controller using an automated background loop (or by rapidly navigating the UI), do your Grafana and Prometheus graphs immediately display a corresponding, real-time spike in the `http_requests_total` metric without any manual intervention?

## References & further learning
- Prometheus Querying Basics: https://prometheus.io/docs/prometheus/latest/querying/basics/
- Grafana Dashboards Documentation: https://grafana.com/docs/grafana/latest/dashboards/
- Helm Charts Guide: https://helm.sh/docs/topics/charts/
- KodeKloud course: Kubernetes for the Absolute Beginners - Hands-on Tutorial: https://kodekloud.com/courses/kubernetes-for-the-absolute-beginners-hands-on-tutorial/
- KodeKloud course: Helm for Beginners: https://kodekloud.com/courses/helm-for-beginners/
- KodeKloud course: Prep Course - Prometheus Certified Associate (PCA) Certification: https://kodekloud.com/courses/prometheus-certified-associate-pca/
