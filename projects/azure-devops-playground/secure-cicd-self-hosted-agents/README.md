# Secure CI/CD with Self-Hosted Agents

**Level:** intermediate  ·  **Playground:** Azure DevOps Playground

▶ **[Launch the playground](https://kodekloud.com/cloud-playgrounds/azure-devops)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
Your organization is migrating its web applications to Azure. To comply with strict data sovereignty mandates, the use of shared, Microsoft-hosted build agents is strictly prohibited; all pipelines must execute on isolated, self-hosted infrastructure. Furthermore, deployments must authenticate securely using a dedicated App Registration rather than personal user credentials. You have been tasked with bootstrapping this secure CI/CD environment and authoring a two-stage pipeline that builds an application artifact and simulates a secure deployment.

## What you'll build
You will log into the Azure DevOps project using your provided IAM credentials and access the Azure Portal. You will provision a dedicated self-hosted Agent Pool and register a Virtual Machine as your active build agent. You will then establish an Azure Resource Manager Service Connection utilizing the provided Application Client ID and Client Secret from your App Registration. Finally, you will write and execute a YAML pipeline containing a "Build" stage (CI) and a "Deploy" stage (CD) that runs exclusively on your self-hosted agent and authenticates via the App Registration.

## Learning objectives
By the end you will be able to:
- Provision Azure Virtual Machines and configure networking for remote SSH access.
- Create and manage self-hosted Agent Pools in Azure DevOps.
- Generate Personal Access Tokens (PATs) for secure agent registration.
- Establish Azure Resource Manager Service Connections using App Registration credentials.
- Author and execute multi-stage YAML pipelines (Build + Deploy) on self-hosted infrastructure.

## Prerequisites
- Playground: **Azure DevOps** - open before starting. The Azure Portal is accessible at `portal.azure.com` using the same session credentials.

---

## Steps

### Task 1 — Log into Azure DevOps
1. Open your playground and click the **Copy** button to copy the Azure DevOps URL.
2. Open a new **Incognito/Private** browser window and paste the URL.
3. Enter the **IAM username** and **Password** from your playground credentials when prompted.
4. If you see a "We need a few more details" profile page, leave the defaults and click **Continue**.
5. You will land on the organization home page. Click on the pre-existing project (e.g., `kk-devops-main-...`) to open it.

### Task 2 — Access the Azure Portal
1. Open a new browser tab and navigate to `portal.azure.com`.
   > Since you are already authenticated in the same browser session, the Azure Portal will log you in automatically.
2. You will see the Azure Portal home page with services like Virtual Machines, Storage accounts, and more.

### Task 3 — Retrieve the Subscription ID and Tenant ID
These values are required later to establish the Service Connection. Retrieve them now and keep them handy.

1. In the Azure Portal, click **Subscriptions** from the home page (under the "Navigate" section).
2. You will see your active subscription. **Copy the Subscription ID** and note the **Subscription Name**.
3. Return to the Azure Portal home page. In the top search bar, type `Microsoft Entra ID` and click on the result.
4. On the Overview page, **copy the Tenant ID**.

> Keep both the **Subscription ID**, **Subscription Name**, and **Tenant ID** saved somewhere accessible. You will need them in Task 8.

---

### Task 4 — Create the Agent Virtual Machine
Provision a Linux VM that will serve as your self-hosted pipeline agent.

1. In the Azure Portal, search for **Virtual machines**.
2. Click **+ Create** > **Azure virtual machine**.
3. Fill out the **Basics** tab:
   - **Resource group:** Select the existing resource group from the dropdown.
   - **Virtual machine name:** `devops-agent`
   - **Region:** `(US) East US` (or the default available region)
   - **Image:** `Ubuntu Server 24.04 LTS - x64 Gen2`
   - **Size:** `Standard_B1s` (click "See all sizes" if it is not visible)
   - **Authentication type:** Select **Password**
   - **Username:** `azureuser`
   - **Password:** `AgentP@ssw0rd1`
   - **Public inbound ports:** Select **Allow selected ports**
   - **Select inbound ports:** Check **SSH (22)**
   > **Note:** Exposing SSH to the entire internet is a security risk. In a real enterprise environment, you would use Azure Bastion, Just-in-Time (JIT) access, or IP-restricted Network Security Group rules. We are using this approach here strictly for the simplicity of this lab.
4. Click the **Disks** tab at the top. Change the **OS disk type** to `Standard SSD`.
5. Click **Review + create**, then click **Create**.
6. Wait for the deployment to complete (approximately 1-2 minutes). Click **Go to resource**.
7. On the VM overview page, **copy the Public IP address** from the right panel.

---

### Task 5 — Generate a Personal Access Token (PAT)
A PAT is required to securely authenticate the agent during registration.

1. Switch to your **Azure DevOps** browser tab.
2. In the top-right corner, click the **User settings** icon (the gear icon next to your avatar).
3. Select **Personal access tokens**.
4. Click **+ New Token**.
5. Fill out the form:
   - **Name:** `agent-registration`
   - **Organization:** Ensure your playground organization is selected.
   - **Expiration:** Leave the default.
   - **Scopes:** Click **Show all scopes** at the bottom. Scroll down and check **Agent Pools** > **Read & manage**.
6. Click **Create**.
7. **Immediately copy the generated token** and save it. It will not be shown again.

### Task 6 — Create a Self-Hosted Agent Pool
1. Click the **Azure DevOps** logo (top-left) to return to the organization home page, then click into your project.
2. Click **Project settings** (bottom-left corner of the page).
3. In the left sidebar under **Pipelines**, click **Agent pools**.
4. Click **Add pool** (top-right).
5. Fill out the form:
   - **Pool type:** Select **Self-hosted**.
   - **Name:** `self-hosted-pool`
   - **Grant access permission to all pipelines:** Check this box.
6. Click **Create**.
7. Click into your newly created **self-hosted-pool**.
8. Click the **New agent** button (top-right).
9. In the dialog that appears, select the **Linux** tab and **click the copy button** for the agent package (e.g., `https://download.agent.dev.azure.com/.../vsts-agent-linux-x64-...tar.gz`). Keep this dialog open for reference.

### Task 7 — Install and Register the Agent on the VM
Open a terminal on your local machine and SSH into the VM you created.

```bash
ssh azureuser@<YOUR-VM-PUBLIC-IP>
```
> Enter the password `AgentP@ssw0rd1` when prompted. Type `yes` if asked to confirm the host fingerprint.

Once connected, run the following commands to install the agent:

```bash
# 1. Install prerequisites
sudo apt-get update -y
sudo apt-get install -y curl git zip unzip

# 2. Install Azure CLI (required for the Deploy stage)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# 3. Create the agent directory
mkdir ~/myagent && cd ~/myagent

# 4. Download the agent package (paste the URL you copied from Task 6, Step 9)
wget <PASTE-AGENT-DOWNLOAD-URL-HERE>

# 5. Extract the agent
tar zxvf vsts-agent-linux-x64-*.tar.gz

# 6. Install .NET dependencies required by the agent
sudo ./bin/installdependencies.sh
```

Now configure and register the agent:

```bash
./config.sh
```

The script will prompt you for the following values:

| Prompt | Value |
|---|---|
| Server URL | `https://dev.azure.com/<YOUR-ORG-NAME>` (copy from the playground credentials page) |
| Authentication type | Press **Enter** (PAT is the default) |
| Personal access token | Paste the PAT you created in Task 5 |
| Agent pool | `self-hosted-pool` |
| Agent name | Press **Enter** (accepts the default hostname) |
| Work folder | Press **Enter** (accepts `_work`) |

Finally, install the agent as a persistent background service:

```bash
sudo ./svc.sh install
sudo ./svc.sh start
```

**Verify the agent is online:**
Return to your **Azure DevOps** browser tab. Navigate to **Project settings** > **Agent pools** > **self-hosted-pool** > **Agents** tab. Your VM agent should show a green **Online** status.

---

### Task 8 — Create an Azure Resource Manager Service Connection
This securely links your Azure DevOps pipeline to the Azure subscription using the App Registration credentials from your playground.

1. In Azure DevOps, navigate to your **project** (click the project name in the top breadcrumb).
2. Click **Project settings** (bottom-left corner).
3. In the left sidebar under **Pipelines**, click **Service connections**.
   > **Note:** You may see a pre-existing service connection (e.g., `kk-azure-main-...`). Ignore it, you will create your own for this lab.
4. Click **New service connection** (top-right).
5. Select **Azure Resource Manager** and click **Next**.
6. In the **Identity type** dropdown, select **App registration or managed identity (manual)**. In the **Credential** dropdown, select **Secret**.
7. Fill out the form using the values you collected earlier:

   | Field | Value |
   |---|---|
   | Environment | `Azure Cloud` |
   | Scope Level | `Subscription` |
   | Subscription Id | (The Subscription ID from Task 3) |
   | Subscription Name | (The Subscription Name from Task 3) |
   | Application (client) ID | (The **Application Client ID** from your playground credentials page) |
   | Directory (tenant) ID | (The **Tenant ID** from Task 3) |
   | Credential | Select **Service principal key** |
   | Client secret | (The **Client Secret** from your playground credentials page) |

8. Click **Verify** to test the connection. You should see a green checkmark confirming successful authentication.
9. Fill in the remaining fields:
   - **Service connection name:** `azure-arm-connection`
   - **Security:** Check **Grant access permission to all pipelines**.
10. Click **Verify and save**.

---

### Task 9 — Create the Application Code in the Repository
The application code must live in the repository. The pipeline will package and deploy it.

1. Return to your project's main dashboard (if you are still in Project settings, click your project name in the top breadcrumb). Then, click **Repos** > **Files** in the left sidebar.
2. Since the repo is empty, click **Initialize** (at the bottom) to create a default `README.md`.
3. Once initialized, click the **three dots** button in the top-right corner, then select **+ New** > **File**.
4. Name the file `index.html` and paste the following content:

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>KodeKloud Web App</title>
    <style>
        :root { --primary: #0078d4; --bg: #f3f2f1; --text: #323130; }
        body { margin: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: var(--bg); color: var(--text); }
        .navbar { background-color: white; padding: 16px 32px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); display: flex; align-items: center; justify-content: space-between; }
        .logo { font-size: 20px; font-weight: bold; color: var(--primary); }
        .hero { text-align: center; padding: 80px 20px; background: linear-gradient(135deg, #0078d4 0%, #004578 100%); color: white; }
        .hero h1 { margin: 0; font-size: 42px; font-weight: 600; }
        .hero p { font-size: 18px; opacity: 0.9; max-width: 600px; margin: 20px auto; line-height: 1.5; }
        .container { max-width: 900px; margin: -40px auto 40px; display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 24px; padding: 0 20px; }
        .card { background: white; border-radius: 8px; padding: 24px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); }
        .card h3 { color: var(--primary); margin-top: 0; font-size: 18px; }
        .card p { color: #605e5c; font-size: 14px; line-height: 1.6; margin-bottom: 0; }
        .tag { display: inline-block; background: #e1dfdd; padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: 600; margin-top: 16px; }
    </style>
</head>
<body>
    <div class="navbar">
        <div class="logo">☁️ KloudApp</div>
        <div style="font-size: 14px; font-weight: 600;">Secure Environment</div>
    </div>

    <div class="hero">
        <h1>Welcome to v1.0</h1>
        <p>This web application is hosted on Azure Storage and deployed securely through an isolated CI/CD pipeline.</p>
    </div>

    <div class="container">
        <div class="card">
            <h3>🔒 Zero-Trust Deployment</h3>
            <p>Deployed exclusively using a dedicated App Registration (Service Principal). No personal user credentials were used.</p>
            <div class="tag">Azure AD</div>
        </div>
        <div class="card">
            <h3>🏗️ Isolated Infrastructure</h3>
            <p>The CI/CD pipeline executed entirely on a self-hosted Azure VM, adhering to strict data sovereignty compliance.</p>
            <div class="tag">Self-Hosted Agent</div>
        </div>
        <div class="card">
            <h3>⚡ YAML Pipelines</h3>
            <p>Built and released using a multi-stage Azure DevOps YAML pipeline defining both Continuous Integration and Delivery.</p>
            <div class="tag">CI/CD</div>
        </div>
    </div>
</body>
</html>
```

5. Click **Commit** (top-right), leave the default commit message, and click **Commit** again.

### Task 10 — Create the Two-Stage YAML Pipeline
1. In the left sidebar, click **Pipelines**.
2. Click **Create Pipeline**.
3. Under "Where is your code?", select **Azure Repos Git**.
4. Select your repository.
5. Under "Configure your pipeline", select **Starter pipeline**.
6. The YAML editor will open with a basic template. **Select all** and **replace** the contents with the following pipeline:

```yaml
trigger:
  - main

stages:
  - stage: Build
    displayName: 'Build (CI)'
    pool:
      name: 'self-hosted-pool'
    jobs:
      - job: BuildJob
        displayName: 'Package Application'
        steps:
          - task: CopyFiles@2
            inputs:
              SourceFolder: '$(Build.SourcesDirectory)'
              Contents: 'index.html'
              TargetFolder: '$(Build.ArtifactStagingDirectory)/drop'
            displayName: 'Stage Application Files'

          - task: PublishBuildArtifacts@1
            inputs:
              PathtoPublish: '$(Build.ArtifactStagingDirectory)/drop'
              ArtifactName: 'app-artifact'
            displayName: 'Publish Build Artifact'

  - stage: Deploy
    displayName: 'Deploy (CD)'
    dependsOn: Build
    pool:
      name: 'self-hosted-pool'
    jobs:
      - job: DeployJob
        displayName: 'Deploy to Azure'
        steps:
          - task: DownloadBuildArtifacts@1
            inputs:
              buildType: 'current'
              downloadType: 'single'
              artifactName: 'app-artifact'
              downloadPath: '$(System.ArtifactsDirectory)'
            displayName: 'Download Build Artifact'

          - task: AzureCLI@2
            displayName: 'Deploy Static Website to Azure Storage'
            inputs:
              azureSubscription: 'azure-arm-connection'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                echo "========================================"
                echo "  Deploy Stage: Azure Static Website"
                echo "========================================"

                RG_NAME=$(az group list --query "[0].name" -o tsv)
                # Generate a deterministic, globally unique name using a hash of the resource group
                HASH=$(echo -n "$RG_NAME" | md5sum | head -c 16)
                STORAGE_NAME="cicdlab${HASH}"

                echo "Ensuring Storage Account exists: $STORAGE_NAME"
                az storage account create \
                  --name "$STORAGE_NAME" \
                  --resource-group "$RG_NAME" \
                  --sku Standard_LRS \
                  --kind StorageV2 \
                  --allow-blob-public-access true

                echo "Enabling static website hosting..."
                az storage blob service-properties update \
                  --account-name "$STORAGE_NAME" \
                  --static-website \
                  --index-document index.html

                echo "Uploading application files..."
                CONN_STRING=$(az storage account show-connection-string \
                  --name "$STORAGE_NAME" --resource-group "$RG_NAME" -o tsv)
                az storage blob upload-batch \
                  --connection-string "$CONN_STRING" \
                  --source "$(System.ArtifactsDirectory)/app-artifact" \
                  --destination '$web' \
                  --overwrite

                SITE_URL=$(az storage account show \
                  --name "$STORAGE_NAME" \
                  --query "primaryEndpoints.web" -o tsv)

                echo "========================================"
                echo "  DEPLOYMENT SUCCESSFUL!"
                echo "  Live URL: $SITE_URL"
                echo "========================================"
```

7. Click **Save and run** (top-right).
8. In the dialog, leave the default commit message and click **Save and run**.

### Task 11 — Monitor and Verify the Pipeline
1. You will be taken to the pipeline run page. Click on the **Build (CI)** stage to expand it and watch the live logs.
   - The job will stage the `index.html` from the repository and publish it as a build artifact.
2. Once the Build stage completes with a green checkmark, the **Deploy (CD)** stage will automatically begin.
   - Click the **Deploy (CD)** stage to expand it, then click the **Deploy to Azure** job.
   - Click on the **Deploy Static Website to Azure Storage** step to view its logs.
   - Wait for the step to finish. At the very bottom of these logs, you will see a **Live URL** printed.
3. **Copy the Live URL** and open it in a new browser tab.
   - You will see your KloudApp landing page, proving the entire CI/CD pipeline executed successfully!
4. Both stages should complete with green checkmarks.

---

## Validation
Verify your self-hosted agent and CI/CD operations.

1. **Verify your agent is online**
   Navigate to **Project settings** > **Agent pools** > **self-hosted-pool** > **Agents** tab. Confirm the agent shows a green **Online** status.

2. **Verify the Service Connection**
   Navigate to **Project settings** > **Service connections**. Confirm `azure-arm-connection` is listed with a successful verification status.

3. **Verify the pipeline executed on the self-hosted agent**
   Navigate to **Project settings** > **Agent pools** > **self-hosted-pool** > **Jobs** tab. Confirm that your pipeline jobs (`Job 1234`, etc.) are listed here with green checkmarks, proving the workload ran on your custom VM agent.

Expected result:
- [ ] You successfully authenticated to the Azure DevOps console using the provided IAM credentials.
- [ ] Is the custom Agent Pool created, and does the registered VM agent show an "Online" status?
- [ ] Was the Service Connection successfully established using the Application Client ID and Client Secret?
- [ ] Did the CI/CD pipeline successfully complete both the Build and Deploy stages on the self-hosted agent without execution errors?

## References & further learning
- Azure DevOps Self-Hosted Agents: https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/linux-agent
- Azure DevOps Service Connections: https://learn.microsoft.com/en-us/azure/devops/pipelines/library/service-endpoints
- Azure DevOps YAML Pipeline Reference: https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema
- KodeKloud course: AZ-400 Designing and Implementing Microsoft DevOps Solutions: https://learn.kodekloud.com/courses/az-400
