# AI Financial Data Extractor

## Project info

- **ID:** type-safe-financial-extraction-engine
- **Title:** Type-Safe Financial Extraction Engine
- **Playground:** Python
- **Playground link:** [https://kodekloud.com/playgrounds/playground-python](https://kodekloud.com/playgrounds/playground-python)
- **Difficulty:** advanced
- **Estimated minutes:** 45
- **Tags:**
  - python
  - ai
  - llm
  - pydantic
  - data-engineering
- **Skills:**
  - schema validation
  - data extraction
  - pydantic-ai
  - api integration
- **Prerequisites:**
  - Basic Python knowledge
  - Understanding of LLMs and API keys

## Scenario
A fintech platform processes thousands of unstructured bank statements and invoice receipts to determine real-time credit metrics. However, raw conversational LLMs frequently produce unstable, fluctuating JSON structures or drop critical fields entirely, throwing application runtime exceptions and breaking database schemas. To eliminate this runtime instability, the Tech Lead has mandated a shift toward type-safe agent development. As the engineer assigned to this initiative, you must provision your own testing environment - including establishing a sample unstructured document (`invoice_raw.txt`) and securing access keys to a compatible LLM provider - to build and validate the new architecture.

## What you'll build
You will construct a highly structured data extraction agent utilizing the `pydantic-ai` framework. You will define a strict schema using a Pydantic BaseModel containing mandatory type annotations (such as currency values, timestamps, and string rules). The agent will route data through an LLM API, guaranteeing that the response perfectly conforms to your schema rules at runtime, effectively blocking any malformed formats from escaping into your database.

## Learning objectives
By the end you will be able to:
- Initialize and configure an LLM extraction agent using the `pydantic-ai` framework.
- Explicitly declare targeted dataset structures using type-safe Pydantic BaseModel layouts.
- Handle and validate complex data types and strict mathematical rules directly within the data extraction pipeline.
- Securely execute extraction scripts that reject corrupted or mismatched data properties at runtime.

## Prerequisites
- Playground: **Python** (open it before starting)
- Basic Python execution and environment variable management

## Steps

### Task 1 - Create Dependencies & Setup Environment

1. Create a file named `requirements.txt` and add the following:
```bash
pydantic-ai
pydantic
```

2. Create a virtual environment, activate it, and install the dependencies:
```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```
> **Why:** The `pydantic-ai` framework bridges the gap between unstructured LLM outputs and strict, validated Python objects, ensuring application stability.

### Task 2 - Create the Source File

Create a file named `invoice_raw.txt` and add the following:
```bash
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
```
> **Why:** This simulates the messy, unstructured textual data (like PDFs or OCR text) that financial systems must ingest and map into rigid database schemas.

### Task 3 - Create the Main Script

Create a file named `type_safe_extractor.py` and add the python script that defines the strict schema and executes the extraction agent:
> 📄 **[`type_safe_extractor.py`](./type_safe_extractor.py)**
> **Why:** This script builds the Pydantic BaseModels (complete with logic validators) and configures the AI agent. The validators guarantee that no mismatched math or corrupted data structures pass through the pipeline.

### Task 4 - Retrieve Credentials & Execute Script

1. **Obtain your credentials:** Go to https://kodekloud.com/ai-playgrounds/kodekey and click **Launch now** > **Start Playground**. Copy the Base URL and API Key.
2. Set the environment variables in your terminal (replace `"your-copied-api-key-here"` and `"your-copied-base-url-here"` with your actual key and url):
```bash
export KODEKLOUD_API_KEY="your-copied-api-key-here"
export KODEKLOUD_BASE_URL="your-copied-base-url-here"
export KODEKLOUD_MODEL_NAME="claude-haiku-4-5"
```

3. Execute the type-safe extraction pipeline:
```bash
python type_safe_extractor.py
```
> **Why:** The script needs authorized access to an LLM provider to process the raw invoice text. Upon execution, the LLM parses the data and forces it into your strictly defined JSON schema object.

## Validation

Run the following command to review the extracted JSON output and confirm your pipeline successfully maintained structural integrity.

```bash
cat output.json
```

Expected result:
- [ ] The command successfully outputs a final payload object matching the original document metrics.
- [ ] Inspecting the JSON output confirms that all data types match the targeted `ValidatedInvoiceOutput` schema (e.g., `"currency": "USD"`, and the float math aligns perfectly).

## References & further learning
- Pydantic AI Documentation: https://ai.pydantic.dev/
- Pydantic Models & Field Validation: https://docs.pydantic.dev/latest/concepts/models/
- KodeKloud course: Python Basics: https://kodekloud.com/courses/python-basics/
- KodeKloud course: AI Agents Fundamentals: https://kodekloud.com/courses/ai-agents-fundamentals
```

```

---

## Files in this folder

The steps above reference these ready-to-use files (copy them onto the playground):

- [`type_safe_extractor.py`](./type_safe_extractor.py)
