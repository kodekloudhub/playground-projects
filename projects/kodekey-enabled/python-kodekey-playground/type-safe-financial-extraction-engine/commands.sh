#!/usr/bin/env bash
set -euo pipefail

pydantic-ai
pydantic

python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

ACME INVOICE CORP
--- RECEIPT OF TRANSACTION ---
Invoice ID: INV-2026-89421
Date Issued: June 24, 2026, 14:32:00 UTC
Vendor: Delta Global Logistics Ltd.
Billed To: Fintech Credit Metrics Platform

We have processed your logistics routing dispatch. Please see the breakdown of fees below:
- LINE ITEM 1: Heavy cargo container handling fees. Qty: 3 units. Unit Price: $450.00. Totaling $1350.00.
- LINE ITEM 2: Cross-dock facility customs processing clearance surcharge. Qty: 1 unit. Unit Price: $125.50. Totaling $125.50.

Summary Figures:
Subtotal: USD 1475.50
Tax Allocation (10% standard rate): USD 147.55
Grand Total Due Upon Receipt: USD 1623.05

Payment Currency: USD
Please remit all wire transfers within 30 calendar days to avoid automated penalty assessment.

export KODEKLOUD_API_KEY="your-copied-api-key-here"
export KODEKLOUD_BASE_URL="your-copied-base-url-here"
export KODEKLOUD_MODEL_NAME="claude-haiku-4-5"

python type_safe_extractor.py

cat output.json
