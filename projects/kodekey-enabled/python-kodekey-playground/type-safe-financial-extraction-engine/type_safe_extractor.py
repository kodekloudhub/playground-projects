import os
import sys
from datetime import datetime
from typing import List
from pydantic import BaseModel, Field, field_validator
from pydantic_core import ValidationError
from pydantic_ai import Agent

# Import the specific ChatModel and Provider for OpenAI-compatible endpoints
from pydantic_ai.models.openai import OpenAIChatModel
from pydantic_ai.providers.openai import OpenAIProvider

# =====================================================================
# 1. Schema Definitions (Type-Safe Layer)
# =====================================================================

class InvoiceItem(BaseModel):
    description: str = Field(..., description="Clear description of the line item service or product")
    quantity: int = Field(..., ge=1, description="Quantity of items processed; must be 1 or greater")
    unit_price: float = Field(..., ge=0.0, description="Cost per individual unit")
    total_price: float = Field(..., ge=0.0, description="Total cost calculated for this specific line item")

    @field_validator('total_price')
    @classmethod
    def verify_line_item_math(cls, v: float, info) -> float:
        """Validates that line item math matches quantity * unit price."""
        values = info.data
        if 'quantity' in values and 'unit_price' in values:
            expected = round(values['quantity'] * values['unit_price'], 2)
            if abs(v - expected) > 0.01:
                raise ValueError(f"Line item math mismatch: {values['quantity']} * {values['unit_price']} != {v}")
        return v

class ValidatedInvoiceOutput(BaseModel):
    invoice_id: str = Field(..., description="The unique, clean alphanumeric string tracking the invoice identification")
    timestamp: datetime = Field(..., description="The exact ISO parsed timestamp when the document was issued")
    vendor_name: str = Field(..., description="The official legal name of the selling vendor entity")
    currency: str = Field(..., min_length=3, max_length=3, description="Strict 3-letter ISO code denoting currency representation")
    items: List[InvoiceItem] = Field(..., description="Full array of line items extracted from the statement source")
    subtotal: float = Field(..., ge=0.0, description="Summation total of all individual line items before taxes")
    tax_amount: float = Field(..., ge=0.0, description="Total tax applied to the transaction pool")
    total_amount_due: float = Field(..., ge=0.0, description="The terminal financial balance required for payment resolution")

    @field_validator('total_amount_due')
    @classmethod
    def verify_global_totals(cls, v: float, info) -> float:
        """Enforces write-time strict mathematical checking on the invoice sum totals."""
        values = info.data
        if 'subtotal' in values and 'tax_amount' in values:
            expected_total = round(values['subtotal'] + values['tax_amount'], 2)
            if abs(v - expected_total) > 0.01:
                raise ValueError(f"Global total tracking mismatch: Subtotal ({values['subtotal']}) + Tax ({values['tax_amount']}) does not equal Total Due ({v})")
        return v

# =====================================================================
# 2. Agent Initialization & Engine Setup (KodeKloud Config)
# =====================================================================

def initialize_extraction_agent() -> Agent:
    """Configures the pydantic-ai client natively using the KodeKloud endpoint."""

    # Pull KodeKloud credentials from the environment
    api_key = os.getenv("KODEKLOUD_API_KEY")
    base_url = os.getenv("KODEKLOUD_BASE_URL")
    model_name = os.getenv("KODEKLOUD_MODEL_NAME")

    if not all([api_key, base_url, model_name]):
        print("[CRITICAL SETUP ERROR] Missing required KodeKloud credentials.")
        print("Please run the following commands in your terminal before executing:")
        print('  export KODEKLOUD_API_KEY="your-api-key-here"')
        print('  export KODEKLOUD_BASE_URL="[https://api.ai.kodekloud.com/v1](https://api.ai.kodekloud.com/v1)"')
        print('  export KODEKLOUD_MODEL_NAME="claude-haiku-4-5"')
        sys.exit(1)

    # Initialize the OpenAIChatModel natively pointing to the KodeKloud proxy
    kodekloud_model = OpenAIChatModel(
        model_name,
        provider=OpenAIProvider(
            base_url=base_url,
            api_key=api_key
        )
    )

    # Initialize the specific Agent bind configuration
    agent = Agent(
        model=kodekloud_model,
        output_type=ValidatedInvoiceOutput,
        retries=3,
        system_prompt=(
            "You are a strict, production-tier financial data extraction engine. "
            "Your objective is to read raw, unstructured invoices and format the data "
            "directly into the required structured type schema. "
            "Do not truncate item values, do not invent fields, and preserve numeric fidelity."
        )
    )

    return agent

# =====================================================================
# 3. Pipeline Runtime Execution Loop
# =====================================================================

def execute_extraction_pipeline(
    file_path: str = "invoice_raw.txt",
    output_path: str = "output.json"
):
    """Reads target files, executes agent execution context, saves JSON output, and isolates structural faults."""

    print(f"[*] Starting extraction process for targeted file asset: {file_path}")

    if not os.path.exists(file_path):
        print(f"[ERROR] Target input source data document path '{file_path}' does not exist.")
        sys.exit(1)

    with open(file_path, "r", encoding="utf-8") as file_source:
        raw_document_content = file_source.read()

    extraction_agent = initialize_extraction_agent()

    try:
        print(f"[*] Dispatching transactional parsing load to KodeKloud structural agent...")

        execution_context = extraction_agent.run_sync(user_prompt=raw_document_content)

        validated_invoice_output: ValidatedInvoiceOutput = execution_context.output

        print("\n[SUCCESS] Document parsed and written without schema infractions.")
        print("=====================================================================")
        print(f"Invoice ID Reference: {validated_invoice_output.invoice_id}")
        print(f"Timestamp Record:     {validated_invoice_output.timestamp}")
        print(f"Identified Vendor:    {validated_invoice_output.vendor_name}")
        print(f"Currency Target:      {validated_invoice_output.currency}")
        print(f"Line Item Unit Count: {len(validated_invoice_output.items)}")
        print(f"Subtotal Calculated:  {validated_invoice_output.subtotal}")
        print(f"Tax Record Value:     {validated_invoice_output.tax_amount}")
        print(f"Total Amount Due:     {validated_invoice_output.total_amount_due}")
        print("=====================================================================")

        # Save structured output to JSON file
        with open(output_path, "w", encoding="utf-8") as json_output:
            json_output.write(
                validated_invoice_output.model_dump_json(indent=2)
            )

        print(f"[SUCCESS] JSON output written to: {output_path}")

        return validated_invoice_output

    except ValidationError as schema_fault:
        print("\n[CRITICAL RUNTIME EXCEPTION] Write-Time Pydantic validation failed.")
        print("The LLM returned structured records violating runtime validation schemas:")
        print(schema_fault)
        sys.exit(2)

    except Exception as runtime_fault:
        print(f"\n[CRITICAL AGENT ERROR] Pipeline terminated unexpectedly: {runtime_fault}")
        sys.exit(3)

if __name__ == "__main__":
    execute_extraction_pipeline()
