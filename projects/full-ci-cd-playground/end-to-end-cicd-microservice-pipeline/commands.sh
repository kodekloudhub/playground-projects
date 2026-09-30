#!/usr/bin/env bash
set -euo pipefail

git clone http://git-server:3000/max/weather-advisory.git
cd weather-advisory

git config --global user.name "max"
git config --global user.email "max@example.com"

git add .
git commit -m "Initial microservice deployment"
git push origin master

# 1. Check the status of your pods and services
kubectl get all

# 2. Test the API by requesting weather data for a logistics hub
curl http://jump-host:30050/weather/tokyo
