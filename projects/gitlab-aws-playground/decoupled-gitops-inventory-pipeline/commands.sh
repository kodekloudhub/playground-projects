#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update -y
sudo apt-get install -y zip curl unzip
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
aws --version

# 1. Fetch token directly from the GitLab backend (this command takes ~15 seconds to load)
REGISTRATION_TOKEN=$(sudo gitlab-rails runner -e production "puts Gitlab::CurrentSettings.current_application_settings.runners_registration_token")

# 2. Register the runner
sudo gitlab-runner register \
  --non-interactive \
  --url "http://localhost/" \
  --registration-token "${REGISTRATION_TOKEN}" \
  --executor "shell" \
  --description "gitops-dynamo-runner"

sudo gitlab-runner start
sudo gitlab-runner verify

git config --global user.name "Cloud Engineer"
git config --global user.email "engineer@labs.local"
mkdir -p ~/cloud-inventory-portal/app/templates ~/cloud-inventory-portal/infrastructure
cd ~/cloud-inventory-portal
git init
git remote add origin http://localhost/root/cloud-inventory-portal.git

git add .
git commit -m "feat: deployment of clean 3-tier gitops pipeline"
git push origin master

grep -rl "Inventory Operations Center" . | xargs sed -i 's/Inventory Operations Center/Inventory Operations Center V2/g'

git add .
git commit -m "feat: upgrade UI to V2"
git push origin master

sudo gitlab-runner verify
