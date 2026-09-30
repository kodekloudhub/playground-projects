# End-to-End CICD Microservice Pipeline

**Level:** advanced  ·  **Playground:** Full CI/CD Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-ci-cd)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

```plain
---
# ─── Metadata (read by the playground for listing & filtering) ───
id: end-to-end-cicd-microservice-pipeline      
title: End-to-End CICD Microservice Pipeline      
playground: CI/CD
playground_link: https://kodekloud.com/playgrounds/playground-ci-cd
difficulty: advanced
estimated_minutes: 60                      
tags:                                      
  - cicd
  - jenkins
  - kubernetes
  - docker
  - python
  - gitea
skills:                                    
  - writing jenkins pipelines
  - configuring webhooks
  - containerizing python apps
  - kubernetes deployments
prerequisites:                             
  - Basic Git command line
  - Understanding of Jenkins and Kubernetes
---

# End-to-End CICD Microservice Pipeline

## Scenario
A global shipping logistics company relies on a custom "Weather Advisory API" to determine if cargo flights and container ships should be delayed at major global ports. This Python microservice dynamically fetches real-time meteorological data from a 3rd-party weather service to calculate operational status. Currently, the deployment process is entirely manual: engineers manually build container images on their local machines and execute deployment commands directly against the production cluster. This manual handoff creates a high risk of version mismatches, configuration drift, and deployment downtime. 

The Platform Engineering team has mandated a shift to a fully automated Continuous Integration and Continuous Deployment (CI/CD) model. You have been tasked with engineering a zero-touch pipeline. The goal is to ensure that every time a developer commits an update to the application code, the CI/CD system automatically builds the container, securely publishes it to a private registry, and seamlessly deploys the updated state to the Kubernetes cluster without human intervention.

## What you'll build
You will establish a complete, zero-touch CI/CD workflow from scratch. You will define the environment by authoring a Dockerfile, configure its target state by writing Kubernetes manifests (including deployment, service, and registry secrets), and bridge the gap by configuring a declarative Jenkins Pipeline. Finally, you will tie the version control system (Gitea) directly to Jenkins via Webhooks to automate the entire process upon a code push.

## Learning objectives
By the end you will be able to:
- Package Python applications using Docker best practices (non-root users).
- Author declarative Kubernetes manifests containing private registry authentication secrets.
- Write multi-stage Jenkins Pipelines (`Jenkinsfile`) to automate building, publishing, and deploying code.
- Configure secure Webhooks to trigger automated pipelines directly from Git push events.

## Prerequisites
- Playground: **CI/CD** (open it before starting)

## Steps

### Task 1 — Create the Gitea Repository
First, we need a centralized Git repository to store our application code and configurations.

1. Open the Gitea UI in your browser and log in with the credentials `max` / `Max_pass123`.
2. Click the **+** icon in the top right corner and select **New Repository**.
3. Name the repository `weather-advisory`.
4. Leave the "Initialize Repository" checkbox unchecked (we will push our own files).
5. Click **Create Repository**.

### Task 2 — Initialize the Local Workspace
Return to your terminal to set up your local development environment. Clone the empty repository and configure your Git identity:

```bash
git clone http://git-server:3000/max/weather-advisory.git
cd weather-advisory

git config --global user.name "max"
git config --global user.email "max@example.com"
```

Create the dependencies file:
```bash
cat << 'EOF' > requirements.txt
Flask==3.0.0
Werkzeug==3.0.1
EOF
```

Create the application file containing the logistics logic:
```bash
cat << 'EOF' > app.py
from flask import Flask, jsonify
import urllib.request
import json

app = Flask(__name__)
HUBS = {
    "seattle": {"lat": 47.60, "lon": -122.33},
    "miami": {"lat": 25.76, "lon": -80.19},
    "tokyo": {"lat": 35.68, "lon": 139.69},
    "manila": {"lat": 14.60, "lon": 120.98},
    "mumbai": {"lat": 19.07, "lon": 72.88}
}

@app.route('/weather/<hub>', methods=['GET'])
def get_weather(hub):
    hub_lower = hub.lower()
    if hub_lower not in HUBS:
        return jsonify({"error": "Hub not found."}), 404

    coords = HUBS[hub_lower]
    url = f"https://api.open-meteo.com/v1/forecast?latitude={coords['lat']}&longitude={coords['lon']}&current_weather=true"

    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            current = data.get("current_weather", {})

            temp = current.get("temperature")
            wind = current.get("windspeed")

            status = "CLEAR_FOR_TRANSIT"
            if wind > 30:
                status = "DELAYED_HIGH_WINDS"

            return jsonify({
                "hub": hub_lower,
                "temperature_c": temp,
                "wind_speed_kmh": wind,
                "logistics_status": status
            })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF
```

### Task 3 — Containerize the Application
Create a Dockerfile that packages the application securely. This file uses a slim image and implements a non-root user to adhere to security best practices.

```bash
cat << 'EOF' > Dockerfile
FROM python:3.10-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
EXPOSE 5000

RUN useradd -m appuser && chown -R appuser /app
USER appuser

ENTRYPOINT ["python", "app.py"]
EOF
```

### Task 4 — Define the Kubernetes Infrastructure
Create a `manifests.yaml` file. This includes the exact Base64-encoded Docker registry credentials provided in the playground, ensuring the cluster has permission to pull your custom image.

```bash
cat << 'EOF' > manifests.yaml
apiVersion: v1
data:
  .dockerconfigjson: eyJhdXRocyI6eyJkb2NrZXItaG9zdDo1MDAwIjp7InVzZXJuYW1lIjoiZG9ja191c2VyIiwicGFzc3dvcmQiOiJkb2NrX3Bhc3N3b3JkIiwiZW1haWwiOiJkb2NrX3VzZXJAZG9ja2VyLWhvc3QiLCJhdXRoIjoiWkc5amExOTFjMlZ5T21SdlkydGZjR0Z6YzNkdmNtUT0ifX19
kind: Secret
metadata:
  name: private-reg-cred
type: kubernetes.io/dockerconfigjson
---
apiVersion: apps/v1
kind: Deployment 
metadata:
  name: weather-advisory
spec:
  selector:
    matchLabels:
      app: weather-advisory
  replicas: 2
  template:
    metadata:
      labels:
        app: weather-advisory
    spec:
      imagePullSecrets: 
      - name: private-reg-cred
      containers:
        - name: weather-api
          image: docker-host:5000/weather-api:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 5000 
---
apiVersion: v1
kind: Service 
metadata: 
  name: weather-advisory-svc
spec:
  type: NodePort
  selector:
    app: weather-advisory
  ports:
    - port: 5000 
      targetPort: 5000
      nodePort: 30050
EOF
```

### Task 5 — Author the Jenkins Pipeline
Create the `Jenkinsfile`. This declarative script instructs Jenkins to pull your code, build the container, push it to your private registry, and deploy it. It also features a forced rollout restart to guarantee the latest code is served immediately.

```bash
cat << 'EOF' > Jenkinsfile
pipeline {
    agent {
        label "docker"
    }
    stages {
        stage('Checkout code') {
            steps {
                checkout([$class: 'GitSCM', branches: [[name: '*/master']], extensions: [], userRemoteConfigs: [[url: 'http://git-server:3000/max/weather-advisory.git']]])
            }
        }
        stage('Build Image') {
            steps {
                sh 'docker build -t docker-host:5000/weather-api:latest .'
            }
        }
        stage('Publish to Registry') {
            steps {
                sh 'docker login -u dock_user -p dock_password docker-host:5000'
                sh 'docker push docker-host:5000/weather-api:latest'
            }
        }
        stage('Deploy to Kubernetes') {
            steps {
                withKubeConfig(caCertificate: "${KUBE_CERT}", clusterName: 'kubernetes', contextName: 'kubernetes-admin@kubernetes', credentialsId: 'my-kube-config-credentials', namespace: 'default', restrictKubeConfigAccess: false, serverUrl: 'https://jump-host:6443') 
                {
                    sh 'kubectl apply -f manifests.yaml'
                    sh 'kubectl rollout restart deployment/weather-advisory'
                    sh 'kubectl rollout status deployment/weather-advisory'
                }
            }
        }  
    }
}
EOF
```

### Task 6 — Configure the Jenkins Pipeline
Instruct Jenkins to monitor your repository and listen for build triggers.

1. Open the Jenkins UI in your browser and log in with `admin` / `Adm!n321`.
2. Click **New Item** on the left menu.
3. Enter the item name as `weather-advisory-pipeline`, select **Pipeline**, and click **OK**.
4. Scroll down to the **Build Triggers** section.
5. Check the box for **Trigger builds remotely (e.g., from scripts)**.
6. In the Authentication Token field, type `weather-token`.
7. Scroll down to the **Pipeline** section.
8. Change the Definition dropdown to **Pipeline script from SCM**.
9. Change SCM to **Git**.
10. In the Repository URL, enter `http://git-server:3000/max/weather-advisory.git`.
11. Change the Branch Specifier to `*/master`.
12. Click **Save**.

### Task 7 — Generate a Jenkins API Token
Jenkins requires an API token to securely authenticate incoming webhooks without blocking them.

1. In the Jenkins UI, click on your username (`admin`) in the top right corner.
2. Select **Security** (or Configure) from the dropdown menu.
3. Scroll down to the **API Token** section.
4. Click the **Add new Token** button.
5. Name the token `gitea-webhook` and click **Generate**.
6. Copy the generated token immediately (you will not be able to see it again).

### Task 8 — Configure the Gitea Webhook
Connect Gitea to Jenkins so that code pushes automatically trigger the pipeline.

1. Go back to your `weather-advisory` repository in the Gitea UI.
2. Click on **Settings** (top right corner of the repo page) and select the **Webhooks** tab.
3. Click **Add Webhook** and select **Gitea**.
4. In the Target URL field, enter the exact trigger URL, replacing `<YOUR_NEW_API_TOKEN>` with the token you just copied:
   `http://admin:<YOUR_NEW_API_TOKEN>@jump-host:8085/job/weather-advisory-pipeline/build?token=weather-token`
5. Leave "Trigger On" set to **Push Events**.
6. Click **Add Webhook**.

### Task 9 — Push Code & Trigger the Pipeline
Commit your code. This single action will kick off the entire automated workflow.

```bash
git add .
git commit -m "Initial microservice deployment"
git push origin master
```
> **Note:** When prompted in the terminal, enter the Gitea credentials (`max` / `Max_pass123`). Characters will be hidden as you type. Once the push completes, switch to your Jenkins UI. You should see the `weather-advisory-pipeline` automatically spin up and sequentially execute your stages.

## Validation
Verify the microservice is running successfully on the Kubernetes cluster and test your automation loop.

```bash
# 1. Check the status of your pods and services
kubectl get all
```

```bash
# 2. Test the API by requesting weather data for a logistics hub
curl http://jump-host:30050/weather/tokyo
```

Expected result:
- [ ] You generated the `private-reg-cred` Kubernetes Secret in your manifest to allow the cluster to authenticate with the Docker host.
- [ ] When viewing your Gitea repository settings, the Webhook shows a successful delivery payload (HTTP 200) after your last git push.
- [ ] Your Jenkins UI shows a successfully completed pipeline triggered directly by the Gitea webhook (Push event) rather than a manual trigger.
- [ ] Running `kubectl get all` shows your application replicas in a `Running` state.
- [ ] The `curl` command against your NodePort service receives a JSON response populated with live weather data.
- [ ] **The Final E2E Test:** If you edit `app.py` to add a new logistics hub, commit the change, and run `git push`, the live URL for the new hub becomes available within a few minutes without you running any manual Jenkins or Kubernetes commands.

## References & further learning
- Jenkins Pipeline Documentation: https://www.jenkins.io/doc/book/pipeline/
- Kubernetes Image Pull Secrets: https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/
- Docker Security Best Practices: https://docs.docker.com/develop/security-best-practices/
- KodeKloud course: Git for Beginners: https://kodekloud.com/courses/git-for-beginners/
- KodeKloud course: Docker Training Course for the Absolute Beginner: https://kodekloud.com/courses/docker-training-course-for-the-absolute-beginner/
- KodeKloud course: Kubernetes for the Absolute Beginners - Hands-on Tutorial: https://kodekloud.com/courses/kubernetes-for-the-absolute-beginners-hands-on-tutorial/
- KodeKloud course: Jenkins: https://kodekloud.com/courses/jenkins/
```
