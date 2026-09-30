# Automated Dependency Guardrail

**Level:** intermediate  ·  **Playground:** Docker Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-docker)** — open it, then copy the files below.

## Files in this project
- [`/tmp/guardrail-runner-config.yaml`](.//tmp/guardrail-runner-config.yaml)

> Copy these into your playground session (or `git clone` this repo and `cd` here).

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
A software development firm was hit by a supply-chain incident after a vulnerable open-source dependency reached production. Users were exposed while the vulnerable package sat unnoticed in the build. The security team now wants a dependency guardrail that runs on every push and automatically blocks any HIGH or CRITICAL findings before code merges.

## What you'll build
You will stand up a complete self-hosted CI environment with Docker: a Gitea server and a Gitea Actions runner. Inside it you will create a repository, commit a Trivy dependency-scanning workflow that triggers on every push, and then prove both pipeline paths — a vulnerable dependency that fails the gate and a remediated dependency that clears it.

## Learning objectives
By the end you will be able to:
- Run a self-hosted Gitea server and Actions runner with Docker networking and volumes.
- Author a Gitea Actions workflow that scans dependencies on every push.
- Use Trivy as a policy gate that blocks HIGH and CRITICAL vulnerabilities via a non-zero exit code.
- Demonstrate both the failing and remediated pipeline paths end to end.

## Prerequisites
- Playground: **Docker** (open it before starting)
- Basic Docker CLI
- Understanding of CI/CD pipelines
- Familiarity with Git and repository workflows

## Architecture / overview
The stack runs three cooperating pieces on a shared Docker network (`guardrail-net`): the **Gitea** server on port `3000`, a **Gitea Actions runner** that executes jobs in ephemeral containers, and the **Trivy** scanner that runs inside each job to inspect committed dependencies.

## Steps

### Task 1 — Start Gitea and the Actions Runner with Docker

Start the complete self-hosted CI environment. Gitea will be available on port `3000`, and the runner will register automatically.

1. Confirm Docker is available:
```bash
docker version
```

2. Create the shared network and persistent volumes:
```bash
docker network create guardrail-net
docker volume create gitea-data
docker volume create gitea-runner-data
```

3. Pull the required images:
```bash
docker pull docker.gitea.com/gitea:1.22.6
docker pull docker.io/gitea/act_runner:0.2.11
```

4. Start Gitea:
```bash
docker run -d \
  --name gitea \
  --restart unless-stopped \
  --network guardrail-net \
  -p 3000:3000 \
  -v gitea-data:/data \
  -e GITEA__database__DB_TYPE=sqlite3 \
  -e GITEA__repository__DEFAULT_BRANCH=main \
  -e GITEA__service__DISABLE_REGISTRATION=true \
  -e GITEA__security__INSTALL_LOCK=true \
  -e GITEA__actions__ENABLED=true \
  -e GITEA__server__ROOT_URL=http://localhost:3000/ \
  docker.gitea.com/gitea:1.22.6
```

5. Wait for Gitea, then create the administrator:
```bash
until curl -fsS http://localhost:3000/user/login >/dev/null; do
  sleep 2
done

docker exec --user git gitea gitea admin user create \
  --username security-admin \
  --password gitea2026 \
  --email admin@xfusioncorp.internal \
  --admin \
  --must-change-password=false \
  --config /data/gitea/conf/app.ini
```

6. Create the runner configuration and start the runner. Run this entire block before opening Gitea. The job image supplies Node.js and Docker tooling, while `container.network` lets job containers resolve the `gitea` hostname:
```bash
cat <<'EOF' > /tmp/guardrail-runner-config.yaml
log:
  level: info

runner:
  file: .runner
  capacity: 1
  timeout: 3h

container:
  network: guardrail-net
  privileged: false
  valid_volumes:
    - '**'
EOF

RUNNER_TOKEN=$(docker exec --user git gitea gitea actions generate-runner-token \
  --config /data/gitea/conf/app.ini | tr -d '[:space:]')

docker run -d \
  --name gitea-runner \
  --restart unless-stopped \
  --network guardrail-net \
  -v gitea-runner-data:/data \
  -v /tmp/guardrail-runner-config.yaml:/config.yaml:ro \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e CONFIG_FILE=/config.yaml \
  -e GITEA_INSTANCE_URL=http://gitea:3000 \
  -e GITEA_RUNNER_REGISTRATION_TOKEN="$RUNNER_TOKEN" \
  -e GITEA_RUNNER_NAME=guardrail-runner \
  -e GITEA_RUNNER_LABELS="ubuntu-latest:docker://catthehacker/ubuntu:act-latest" \
  docker.io/gitea/act_runner:0.2.11
```

7. Verify Gitea, the runner, the mounted configuration, and the registered job image:
```bash
docker ps --filter name=gitea
curl -I http://localhost:3000/user/login
docker exec gitea-runner grep -A5 '^container:' /config.yaml
docker exec gitea-runner grep -o \
  'ubuntu-latest:docker://catthehacker/ubuntu:act-latest' \
  /data/.runner
docker logs gitea-runner --tail 30
```

8. Open the **Gitea** port button and sign in with `security-admin` / `gitea2026`.

> **Why:** Brings up a fully self-hosted CI environment where the runner is registered on a shared network so job containers can reach Gitea by hostname.

### Task 2 — Create the Repository in the Gitea UI

Create and initialize the repository entirely in the Gitea web interface.

1. Open Gitea with the port button and sign in as `security-admin`.
2. Select the **+** menu, then **New Repository**.
3. Enter `dependency-guardrail` as the repository name.
4. Enter `Trivy dependency security gate` as the description.
5. Keep the repository public.
6. Select **Initialize Repository** and choose **README**.
7. Confirm the default branch is `main`, then select **Create Repository**.
8. Open **Settings > Units** and ensure **Actions** is enabled. Save if needed.

> **Why:** Establishes the repository on `main` with the Actions unit turned on so the workflow can run.

### Task 3 — Add the Trivy Workflow in Gitea

Gitea reads workflows from `.gitea/workflows/`. Create the workflow that scans every push and blocks HIGH or CRITICAL vulnerabilities.

1. Open the `dependency-guardrail` repository in Gitea.
2. Select **Add File**, then **New File**.
3. Enter the file name:
```text
.gitea/workflows/main.yaml
```

4. Paste the following workflow:
```yaml
name: Automated Dependency Guardrail

on: [push]

jobs:
  security-gate:
    name: Dependency Scan
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code Artifacts
        uses: actions/checkout@v3

      - name: Execute Resilient Containerized Scan
        run: |
          cleanup() {
            docker rm -f t-scanner > /dev/null 2>&1 || true
          }
          trap cleanup EXIT

          docker create --name t-scanner \
            --entrypoint /bin/sh \
            ghcr.io/aquasecurity/trivy:latest \
            -c "tail -f /dev/null"
          docker start t-scanner
          docker cp . t-scanner:/src

          docker exec t-scanner trivy fs /src \
            --format cyclonedx \
            --output /src/sbom.json
          docker cp t-scanner:/src/sbom.json .

          docker exec t-scanner trivy fs /src \
            --severity HIGH,CRITICAL \
            --exit-code 1 \
            --format table
```

5. Enter `Add dependency guardrail workflow` as the commit message and select **Commit Changes**.
6. Open the **Actions** tab and wait for the first workflow run.

> **Why:** `--exit-code 1` turns the Trivy scan into a blocking gate that fails the pipeline on HIGH or CRITICAL findings.

### Task 4 — Add a Vulnerable Dependency and Verify Failure

Prove the guardrail blocks a vulnerable dependency. The payload `Django==1.11` has known HIGH/CRITICAL vulnerabilities.

1. Open the repository's **Code** page.
2. Select **Add File**, then **New File**.
3. Enter `requirements.txt` as the file name.
4. Paste:
```text
Django==1.11
```

5. Enter `Test vulnerable dependency guardrail` as the commit message and select **Commit Changes**.
6. Open the latest Actions run, refresh until it finishes, and inspect the Trivy step.

> **Why:** Confirms the failure path — a known-vulnerable dependency is rejected by the gate.

### Task 5 — Update the Dependency and Verify Success

Replace the vulnerable dependency and prove the same workflow now passes.

1. Open `requirements.txt` from the **Code** page and select **Edit File**.
2. Replace the content with:
```text
Django==6.0.6
```

3. Enter `Remediate dependency vulnerability` as the commit message and select **Commit Changes**.
4. Open the latest Actions run and wait for it to complete successfully.

> **Why:** Confirms the remediation path — the unchanged workflow clears once the dependency is fixed, proving the gate is accurate, not just strict.

## Validation

1. Verify both containers are running and Gitea is reachable:
```bash
docker ps --filter name=gitea
curl -I http://localhost:3000/user/login
```

2. Verify the repository exists and is initialized on `main`:
```bash
curl -fsS -u security-admin:gitea2026 \
  http://localhost:3000/api/v1/repos/security-admin/dependency-guardrail
```

3. Verify the workflow enforces a blocking HIGH/CRITICAL gate:
```bash
git clone http://security-admin:gitea2026@localhost:3000/security-admin/dependency-guardrail.git /tmp/dg
grep -- '--severity HIGH,CRITICAL' /tmp/dg/.gitea/workflows/main.yaml
grep -- '--exit-code 1' /tmp/dg/.gitea/workflows/main.yaml
```

4. Verify the failing and remediated runs via the Actions API:
```bash
curl -fsS -u security-admin:gitea2026 \
  "http://localhost:3000/api/v1/repos/security-admin/dependency-guardrail/actions/runs?branch=main"
```

Expected result:
- [ ] The `gitea` and `gitea-runner` containers are running, and Gitea is reachable on port `3000`.
- [ ] `dependency-guardrail` exists under `security-admin`, initialized on `main` with the Actions tab available.
- [ ] `.gitea/workflows/main.yaml` runs `trivy fs` with `--severity HIGH,CRITICAL` and `--exit-code 1`.
- [ ] The commit adding `Django==1.11` produces a **failing** workflow run.
- [ ] The commit updating to `Django==6.0.6` produces a **successful** workflow run.

## References & further learning
- Gitea Actions Quick Start: https://docs.gitea.com/usage/actions/quickstart
- Gitea act_runner: https://docs.gitea.com/usage/actions/act-runner
- Trivy filesystem scans: https://trivy.dev/docs/latest/references/configuration/cli/trivy_filesystem/
- Trivy exit code behavior: https://trivy.dev/docs/latest/configuration/others/
