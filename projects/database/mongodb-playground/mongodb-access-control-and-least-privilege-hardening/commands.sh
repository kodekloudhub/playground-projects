#!/usr/bin/env bash
set -euo pipefail

# 1. Access the MongoDB Shell
mongosh --authenticationDatabase "admin" -u "myUserAdmin" -p

# (When prompted for the password, type: Admin#123)

# 1. Authenticate as the Application User
mongosh --authenticationDatabase "movies" -u "app_reader" -p

# (When prompted, type: AppPassword123!)
