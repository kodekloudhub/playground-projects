#!/usr/bin/env bash
set -euo pipefail

ssh azureuser@<YOUR-VM-PUBLIC-IP>

./config.sh

sudo ./svc.sh install
sudo ./svc.sh start
