#!/usr/bin/env bash
set -euo pipefail

Create the dependencies file:

Create the application file containing the logistics logic:

### Task 3 — Containerize the Application
Create a Dockerfile that packages the application securely. This file uses a slim image and implements a non-root user to adhere to security best practices.

### Task 4 — Define the Kubernetes Infrastructure
Create a `manifests.yaml` file. This includes the exact Base64-encoded Docker registry credentials provided in the playground, ensuring the cluster has permission to pull your custom image.

### Task 5 — Author the Jenkins Pipeline
Create the `Jenkinsfile`. This declarative script instructs Jenkins to pull your code, build the container, push it to your private registry, and deploy it. It also features a forced rollout restart to guarantee the latest code is served immediately.

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

> **Note:** When prompted in the terminal, enter the Gitea credentials (`max` / `Max_pass123`). Characters will be hidden as you type. Once the push completes, switch to your Jenkins UI. You should see the `weather-advisory-pipeline` automatically spin up and sequentially execute your stages.

## Validation
Verify the microservice is running successfully on the Kubernetes cluster and test your automation loop.

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
