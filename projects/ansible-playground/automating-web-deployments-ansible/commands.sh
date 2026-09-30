#!/usr/bin/env bash
set -euo pipefail

cd /root/playbooks
mkdir -p group_vars templates

# 1. Verify connectivity using an ad-hoc ping
ansible webservers -m ping

# 2. Deploy the infrastructure
ansible-playbook deploy.yml

ansible-playbook deploy.yml

# 1. Verify the Web Application Delivery (Checking for v2.0 update)
curl http://web1
curl http://web2

# 2. Verify Absolute Idempotency (Run playbook a third time)
ansible-playbook deploy.yml

# 3. Verify the Baseline User Account Creation
ansible webservers -a "id deployer"
