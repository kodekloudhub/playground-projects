#!/usr/bin/env bash
set -euo pipefail

ssh azureuser@<YOUR-VM-PUBLIC-IP>

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

./config.sh

sudo ./svc.sh install
sudo ./svc.sh start
