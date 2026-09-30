# Cloud-Native E-Commerce WASM Storefront with AWS Serverless Backend

> ⚠️ **DRAFT** — this project is still being finalized.

**Level:** advanced  ·  **Playground:** WASM | AWS Playground

▶ **[Launch the playground](['https://kodekloud.com/cloud-playgrounds/aws', 'https://kodekloud.com/playgrounds/playground-wasm'])** — open it, then copy the files below.

```perl
---
# ─── Metadata (read by the playground for listing & filtering) ───
id: cloud-native-ecommerce-wasm-microservice-engine
title: Cloud-Native E-Commerce WASM Storefront with AWS Serverless Backend
playground: AWS Cloud Sandbox and WASM Playground
playground_link:
  - https://kodekloud.com/cloud-playgrounds/aws
  - https://kodekloud.com/playgrounds/playground-wasm
difficulty: advanced
estimated_minutes: 150
tags:
  - rust
  - webassembly
  - wasm
  - aws
  - s3
  - api-gateway
  - lambda
  - dynamodb
  - serverless
skills:
  - compiling browser-compatible Rust WebAssembly
  - separating client computation from trusted backend operations
  - deploying versioned static assets to Amazon S3
  - configuring Amazon S3 static website hosting
  - building a Go Lambda function with the AWS SDK
  - using DynamoDB transactions and idempotency
  - applying least-privilege IAM permissions
---

# Cloud-Native E-Commerce WASM Storefront with AWS Serverless Backend

## Scenario

An online store wants a fast storefront that can validate cart input in the browser. The storefront must be served as static content, but inventory and order state must remain authoritative on AWS.

You will compile a Rust WebAssembly module for the browser, publish it as part of a static site, and connect the site to a serverless AWS backend. The browser performs fast, non-authoritative checks. API Gateway, Go Lambda, and DynamoDB perform the trusted inventory reservation and order write.

## What you'll build

You will build and deploy an end-to-end WASM e-commerce storefront:

- A browser-compatible Rust WASM module for client-side order validation.
- A static storefront deployed to an Amazon S3 website endpoint.
- An API Gateway HTTP API connected to a Go Lambda function.
- DynamoDB inventory and orders tables.
- An atomic inventory reservation and order write using TransactWriteItems.
- Idempotent order requests using a client-supplied idempotency key.

The WASM bundle never contains AWS credentials and never writes directly to DynamoDB.

## Learning objectives

By the end you will be able to:

- Compile Rust code to browser-compatible WebAssembly.
- Call WASM from a browser-based JavaScript storefront.
- Separate untrusted client-side validation from trusted server-side decisions.
- Deploy versioned static WASM assets to S3.
- Configure S3 static website hosting and public object delivery.
- Build and deploy a Go Lambda function using the AWS SDK for Go.
- Use DynamoDB transactions for inventory and order consistency.
- Verify idempotency, insufficient inventory, CORS, and site release behavior.

## Prerequisites

- AWS Cloud Sandbox: [open the AWS Playground](https://kodekloud.com/cloud-playgrounds/aws)
- WASM Playground: [open the WASM Playground](https://kodekloud.com/playgrounds/playground-wasm)
- Basic Rust and Cargo knowledge
- Basic Go, HTTP, JSON, and JavaScript knowledge
- Basic AWS console and CLI knowledge

Keep both playgrounds open. Use the WASM Playground for source code, compilation, and local checks. Use the AWS Playground for DynamoDB, IAM, Lambda, API Gateway, and S3.

## Architecture / overview

~~~text
Browser
  |
  | HTTP S3 website endpoint
  v
Public S3 static website bucket
  |
  +-- index.html
  +-- JavaScript
  +-- wasm/wasm_ecommerce_frontend_bg.wasm

Browser JavaScript
  |
  | HTTPS JSON request
  v
API Gateway HTTP API
  |
  v
Go Lambda
  |
  | TransactWriteItems
  v
DynamoDB
  +-- ECommerceInventory
  +-- ECommerceOrders
~~~

The browser WASM module validates item identifiers and quantities. The Go Lambda repeats all validation and owns the business decision. Browser code, including WASM, is observable and modifiable by the user.

S3 static website hosting is intentionally used for this lab. The website endpoint is HTTP-only and requires public read access. Do not place secrets or private data in the bucket.

## Important shell-paste rule

Several tasks use cat > file <<'EOF' blocks. Paste the complete block, including the final EOF. The closing EOF must be on its own line with no spaces. If the terminal shows a > continuation prompt, paste the closing EOF line and press Enter.

## Steps

### Task 1 — Open both playgrounds and verify AWS access

Open the [AWS Cloud Sandbox](https://kodekloud.com/cloud-playgrounds/aws) and the [WASM Playground](https://kodekloud.com/playgrounds/playground-wasm).

In the AWS Cloud Sandbox terminal:

~~~bash
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_PAGER=""
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

aws sts get-caller-identity
printf 'Region: %s\nAccount: %s\n' "$AWS_REGION" "$AWS_ACCOUNT_ID"
~~~

`AWS_PAGER=""` keeps AWS CLI output in the terminal instead of opening an interactive pager. If you start a new AWS terminal, run the exports again. Run each command block below separately and check its result before moving on; commands that depend on an ID from a failed call will not work.

The WASM Playground does not need AWS CLI or AWS credentials. Build there, then upload artifacts through short-lived presigned S3 URLs generated in the AWS Playground. Never copy AWS credentials into the Rust, JavaScript, or WASM files.

### Task 2 — Install the WASM and Go toolchains

In the WASM Playground terminal:

~~~bash
rustc --version
cargo --version
rustup --version
wasm-bindgen --version
go version
rustup target add wasm32-unknown-unknown
~~~

Use the CLI version that matches the Rust dependency in Task 3. If `wasm-bindgen --version` is not `0.2.95`, install that version:

~~~bash
cargo install wasm-bindgen-cli --version 0.2.95 --locked --force
wasm-bindgen --version
~~~

If Go is missing:

~~~bash
GO_VERSION="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1)"
mkdir -p "$HOME/.local"
curl -fsSL "https://go.dev/dl/$GO_VERSION.linux-amd64.tar.gz" -o /tmp/go.tar.gz
rm -rf "$HOME/.local/go"
tar -xzf /tmp/go.tar.gz -C "$HOME/.local"
export PATH="$HOME/.local/go/bin:$PATH"
go version
~~~

Create the workspaces:

~~~bash
mkdir -p "$HOME/wasm-ecommerce-store/src" "$HOME/wasm-ecommerce-store/web/wasm"
mkdir -p "$HOME/wasm-ecommerce-api"
if ! command -v zip >/dev/null 2>&1; then
  apt-get update
  apt-get install -y zip
fi
~~~

This project uses the browser target wasm32-unknown-unknown. It does not use the Spin WASI target because the final WASM module is loaded by a browser from S3.

### Task 3 — Build the browser WASM module

~~~bash
cd "$HOME/wasm-ecommerce-store"
cat > Cargo.toml <<'EOF'
[package]
name = "wasm_ecommerce_frontend"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
wasm-bindgen = "=0.2.95"
EOF

cat > src/lib.rs <<'EOF'
use serde::Serialize;
use wasm_bindgen::prelude::*;

#[derive(Serialize)]
struct ValidationResult {
    valid: bool,
    message: String,
}

#[wasm_bindgen]
pub fn validate_order(item_id: &str, quantity: u32) -> String {
    let item_id = item_id.trim();

    let result = if item_id.is_empty() {
        ValidationResult {
            valid: false,
            message: "Item ID is required".to_string(),
        }
    } else if item_id.len() > 64 {
        ValidationResult {
            valid: false,
            message: "Item ID must be 64 characters or fewer".to_string(),
        }
    } else if quantity == 0 {
        ValidationResult {
            valid: false,
            message: "Quantity must be greater than zero".to_string(),
        }
    } else if quantity > 100 {
        ValidationResult {
            valid: false,
            message: "Quantity must not exceed 100".to_string(),
        }
    } else {
        ValidationResult {
            valid: true,
            message: "Order request is valid for submission".to_string(),
        }
    };

    serde_json::to_string(&result).expect("validation result must serialize")
}
EOF

~~~

The leading `=` pins the Rust crate to exactly `0.2.95`; without it, Cargo may select a newer `0.2.x` release that the CLI cannot process. Refresh the lockfile and rebuild before running the CLI:

~~~bash
cargo update -p wasm-bindgen --precise 0.2.95
cargo build --target wasm32-unknown-unknown --release
~~~

Generate the browser binding:

~~~bash
wasm-bindgen \
  target/wasm32-unknown-unknown/release/wasm_ecommerce_frontend.wasm \
  --out-dir web/wasm \
  --target web
~~~

Verify that both outputs exist before packaging the storefront:

~~~bash
test -s web/wasm/wasm_ecommerce_frontend_bg.wasm &&
test -s web/wasm/wasm_ecommerce_frontend.js &&
ls -lh web/wasm/wasm_ecommerce_frontend*
~~~

### Task 4 — Create the browser storefront

The API placeholder is replaced after API Gateway is deployed.

~~~bash
cd "$HOME/wasm-ecommerce-store"
cat > web/index.html <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="theme-color" content="#101827">
  <meta name="description" content="A WebAssembly powered storefront with AWS order processing.">
  <title>Northstar Supply | WASM Storefront</title>
  <style>
    :root {
      color-scheme: light;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: #172033;
      background: #f4f6f8;
      font-synthesis: none;
      text-rendering: optimizeLegibility;
    }
    * { box-sizing: border-box; }
    body { margin: 0; min-width: 320px; }
    button, input { font: inherit; }
    .topbar { background: #101827; color: #f8fafc; }
    .topbar-inner, main, footer { width: min(1100px, calc(100% - 40px)); margin: 0 auto; }
    .topbar-inner { min-height: 72px; display: flex; align-items: center; justify-content: space-between; gap: 20px; }
    .brand { display: flex; align-items: center; gap: 11px; font-size: 0.94rem; font-weight: 750; letter-spacing: 0.04em; }
    .brand-mark { display: grid; place-items: center; width: 34px; height: 34px; border-radius: 11px; background: #f3a847; color: #101827; font-weight: 900; }
    .top-note { color: #aeb9c9; font-size: 0.82rem; }
    main { padding: 58px 0 76px; }
    .eyebrow { color: #a65b14; font-size: 0.76rem; font-weight: 800; letter-spacing: 0.14em; text-transform: uppercase; }
    .intro { max-width: 700px; margin-bottom: 34px; }
    h1 { margin: 10px 0 13px; color: #101827; font-size: clamp(2.35rem, 5vw, 4rem); line-height: 1.02; letter-spacing: -0.055em; }
    .intro p { max-width: 620px; margin: 0; color: #566175; font-size: 1.08rem; line-height: 1.7; }
    .layout { display: grid; grid-template-columns: minmax(0, 1.05fr) minmax(320px, 0.8fr); gap: 22px; align-items: start; }
    .card { overflow: hidden; border: 1px solid #e2e7ee; border-radius: 20px; background: #fff; box-shadow: 0 16px 45px rgb(16 24 39 / 7%); }
    .product-art { position: relative; display: grid; min-height: 230px; place-items: center; overflow: hidden; background: radial-gradient(circle at 50% 38%, #394962 0, #202d42 42%, #151f30 100%); }
    .product-art::before, .product-art::after { position: absolute; width: 210px; height: 210px; border: 1px solid rgb(255 255 255 / 12%); border-radius: 50%; content: ""; }
    .product-art::after { width: 280px; height: 280px; }
    .pack { position: relative; z-index: 1; display: grid; width: 124px; height: 142px; place-items: center; border: 1px solid rgb(255 255 255 / 26%); border-radius: 36px 36px 26px 26px; background: linear-gradient(145deg, #e9a253, #b96a31); box-shadow: 0 20px 35px rgb(0 0 0 / 28%); color: #392417; font-size: 2.8rem; }
    .product-body { padding: 25px 27px 27px; }
    .product-kicker { color: #a65b14; font-size: 0.76rem; font-weight: 800; letter-spacing: 0.12em; text-transform: uppercase; }
    h2 { margin: 8px 0 10px; color: #101827; font-size: 1.55rem; letter-spacing: -0.03em; }
    .product-copy { margin: 0; color: #667085; font-size: 0.95rem; line-height: 1.65; }
    .specs { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 20px; }
    .spec { padding: 7px 10px; border: 1px solid #e7ebf0; border-radius: 999px; color: #465267; font-size: 0.76rem; font-weight: 650; }
    .order-card { padding: 27px; }
    .order-card h2 { margin-top: 0; }
    .order-card > p { margin: -3px 0 23px; color: #667085; font-size: 0.9rem; line-height: 1.55; }
    form { display: grid; gap: 16px; }
    label { display: grid; gap: 7px; color: #344054; font-size: 0.82rem; font-weight: 700; }
    input { width: 100%; min-height: 47px; padding: 0 13px; border: 1px solid #d7dde6; border-radius: 10px; outline: none; background: #fff; color: #172033; transition: border-color 120ms ease, box-shadow 120ms ease; }
    input:focus { border-color: #c57a31; box-shadow: 0 0 0 3px rgb(197 122 49 / 16%); }
    .submit { min-height: 49px; margin-top: 2px; border: 0; border-radius: 10px; background: #b96a31; color: #fff; cursor: pointer; font-weight: 800; transition: background 120ms ease, transform 120ms ease; }
    .submit:hover:not(:disabled) { transform: translateY(-1px); background: #9f5624; }
    .submit:disabled { cursor: wait; opacity: 0.65; }
    .result { min-height: 62px; margin-top: 17px; padding: 13px 14px; border: 1px solid #e2e7ee; border-radius: 11px; background: #f8fafc; color: #475467; font-size: 0.85rem; line-height: 1.5; overflow-wrap: anywhere; }
    .result[data-state="success"] { border-color: #b7e4c7; background: #f0fbf4; color: #17643a; }
    .result[data-state="error"] { border-color: #f4c7c3; background: #fff5f4; color: #a2342a; }
    .result[data-state="loading"] { border-color: #f2d3a8; background: #fff9ef; color: #88500f; }
    .learning { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin-top: 22px; }
    .learning-item { padding: 15px; border: 1px solid #e2e7ee; border-radius: 13px; background: rgb(255 255 255 / 72%); }
    .learning-item strong { display: block; margin-bottom: 5px; color: #263248; font-size: 0.8rem; }
    .learning-item span { color: #687386; font-size: 0.76rem; line-height: 1.45; }
    footer { display: flex; justify-content: space-between; gap: 16px; padding: 0 0 25px; color: #778195; font-size: 0.76rem; }
    @media (max-width: 760px) {
      .topbar-inner, main, footer { width: min(100% - 28px, 560px); }
      main { padding: 39px 0 52px; }
      .layout { grid-template-columns: 1fr; }
      .product-art { min-height: 190px; }
      .learning { grid-template-columns: 1fr; }
      .top-note { display: none; }
      footer { flex-direction: column; }
    }
  </style>
</head>
<body>
  <header class="topbar">
    <div class="topbar-inner">
      <div class="brand"><span class="brand-mark" aria-hidden="true">N</span> NORTHSTAR SUPPLY</div>
      <div class="top-note">Small essentials. Thoughtfully made.</div>
    </div>
  </header>

  <main>
    <section class="intro" aria-labelledby="page-title">
      <div class="eyebrow">Everyday collection</div>
      <h1 id="page-title">Carry less.<br>Go further.</h1>
      <p>A simple storefront backed by fast browser-side checks and a reliable cloud order flow.</p>
    </section>

    <section class="layout" aria-label="Featured item and order form">
      <article class="card">
        <div class="product-art" role="img" aria-label="Illustration of a rust-colored everyday carry pack">
          <div class="pack" aria-hidden="true">N</div>
        </div>
        <div class="product-body">
          <div class="product-kicker">Featured item · ITEM-9942</div>
          <h2>Everyday Carry Pack</h2>
          <p class="product-copy">A dependable companion for daily essentials, designed for commutes, short trips, and everything between.</p>
          <div class="specs" aria-label="Product details">
            <span class="spec">Weather-ready</span>
            <span class="spec">Lightweight</span>
            <span class="spec">Daily use</span>
          </div>
        </div>
      </article>

      <section class="card order-card" aria-labelledby="order-title">
        <div class="eyebrow">Quick checkout</div>
        <h2 id="order-title">Place an order</h2>
        <p>Enter your details. The browser validates the request with WebAssembly before AWS processes it.</p>
        <form id="order-form">
          <label for="item-id">Item ID
            <input id="item-id" name="item_id" value="ITEM-9942" maxlength="64" autocomplete="off" required>
          </label>
          <label for="quantity">Quantity
            <input id="quantity" name="quantity" type="number" min="1" max="100" value="2" inputmode="numeric" required>
          </label>
          <label for="customer-id">Customer ID
            <input id="customer-id" name="customer_id" value="CUST-104" maxlength="64" autocomplete="off" required>
          </label>
          <button class="submit" id="submit-order" type="submit" disabled>Loading secure checkout...</button>
        </form>
        <div class="result" id="result" role="status" aria-live="polite" data-state="loading">Loading the Rust WebAssembly validation module...</div>
      </section>
    </section>

    <section class="learning" aria-label="How the order flow works">
      <div class="learning-item"><strong>01 · Validate</strong><span>Rust compiled to WebAssembly checks the item and quantity in your browser.</span></div>
      <div class="learning-item"><strong>02 · Process</strong><span>API Gateway sends valid requests to the Go order function.</span></div>
      <div class="learning-item"><strong>03 · Protect stock</strong><span>DynamoDB commits inventory and order changes in one transaction.</span></div>
    </section>
  </main>

  <footer><span>Northstar Supply demonstration storefront</span><span>WebAssembly · AWS · DynamoDB</span></footer>

  <script type="module">
    import init, { validate_order } from "./wasm/wasm_ecommerce_frontend.js";

    const API_BASE_URL = "__API_BASE_URL__";
    const form = document.querySelector("#order-form");
    const result = document.querySelector("#result");
    const submitButton = document.querySelector("#submit-order");

    function showResult(message, state) {
      result.textContent = message;
      result.dataset.state = state;
    }

    try {
      await init();
      submitButton.disabled = false;
      submitButton.textContent = "Place order";
      showResult("Checkout is ready. Your order will be confirmed by AWS.", "success");
    } catch (error) {
      submitButton.textContent = "Checkout unavailable";
      showResult("Could not load the WebAssembly validator. Refresh the page or check that the WASM files were uploaded.", "error");
      console.error("WASM initialization failed:", error);
    }

    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      if (submitButton.disabled) return;
      const itemId = document.querySelector("#item-id").value.trim();
      const quantity = Number(document.querySelector("#quantity").value);
      const customerId = document.querySelector("#customer-id").value.trim();
      const validation = JSON.parse(validate_order(itemId, quantity));

      if (!validation.valid) {
        showResult(validation.message, "error");
        return;
      }

      submitButton.disabled = true;
      submitButton.textContent = "Submitting order...";
      showResult("Sending the validated order to AWS...", "loading");
      try {
        const response = await fetch(API_BASE_URL + "/orders", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            item_id: itemId,
            quantity: quantity,
            customer_id: customerId,
            idempotency_key: "order-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 12)
          })
        });
        const data = await response.json();
        showResult(data.message + " (" + data.status + ", HTTP " + response.status + ")", response.ok ? "success" : "error");
      } catch (error) {
        showResult("The request could not reach the order API. Check the connection and try again.", "error");
        console.error("Order request failed:", error);
      } finally {
        submitButton.disabled = false;
        submitButton.textContent = "Place order";
      }
    });
  </script>
</body>
</html>
EOF
~~~

### Task 5 — Create and seed DynamoDB

In the AWS Cloud Sandbox terminal:

~~~bash
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_PAGER=""
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export INVENTORY_TABLE_NAME="ECommerceInventory"
export ORDERS_TABLE_NAME="ECommerceOrders"
~~~

Create the inventory table:

~~~bash
aws dynamodb create-table \
  --table-name "$INVENTORY_TABLE_NAME" \
  --attribute-definitions AttributeName=item_id,AttributeType=S \
  --key-schema AttributeName=item_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION"
~~~

Create the orders table:

~~~bash
aws dynamodb create-table \
  --table-name "$ORDERS_TABLE_NAME" \
  --attribute-definitions AttributeName=order_id,AttributeType=S \
  --key-schema AttributeName=order_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION"
~~~

Wait for both tables before inserting data:

~~~bash
aws dynamodb wait table-exists --table-name "$INVENTORY_TABLE_NAME" --region "$AWS_REGION"
aws dynamodb wait table-exists --table-name "$ORDERS_TABLE_NAME" --region "$AWS_REGION"
~~~

Seed one inventory item:

~~~bash
aws dynamodb put-item \
  --table-name "$INVENTORY_TABLE_NAME" \
  --item '{"item_id":{"S":"ITEM-9942"},"quantity":{"N":"10"}}' \
  --condition-expression 'attribute_not_exists(item_id)' \
  --region "$AWS_REGION" || true
~~~

Enable point-in-time recovery on each table:

~~~bash
aws dynamodb update-continuous-backups \
  --table-name "$INVENTORY_TABLE_NAME" \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
  --region "$AWS_REGION"
~~~

~~~bash
aws dynamodb update-continuous-backups \
  --table-name "$ORDERS_TABLE_NAME" \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
  --region "$AWS_REGION"
~~~

### Task 6 — Create the Lambda execution role

Use a role name with the AWS Playground naming convention:

~~~bash
export LAMBDA_ROLE_NAME="iam_role_wasm_ecommerce_lambda"

cat > /tmp/lambda-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
~~~

Create the IAM role:

~~~bash
aws iam create-role \
  --role-name "$LAMBDA_ROLE_NAME" \
  --assume-role-policy-document file:///tmp/lambda-trust-policy.json
~~~

Attach the basic Lambda execution policy:

~~~bash
aws iam attach-role-policy \
  --role-name "$LAMBDA_ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
~~~

Attach the DynamoDB policy:

~~~bash
aws iam attach-role-policy \
  --role-name "$LAMBDA_ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess_v2
~~~

Check both attachments before continuing:

~~~bash
aws iam list-attached-role-policies \
  --role-name "$LAMBDA_ROLE_NAME" \
  --query 'AttachedPolicies[].PolicyName' \
  --output table
~~~

~~~bash
LAMBDA_ROLE_ARN="$(aws iam get-role \
  --role-name "$LAMBDA_ROLE_NAME" \
  --query 'Role.Arn' \
  --output text)"
echo "$LAMBDA_ROLE_ARN"
~~~

If the role already exists, skip `create-role` and run the attachment and verification commands above. The output must include both `AWSLambdaBasicExecutionRole` and `AmazonDynamoDBFullAccess_v2` before you deploy Lambda. If role creation is denied, create the same role in the AWS console with the exact name `iam_role_wasm_ecommerce_lambda`, then attach those two AWS-managed policies. If attaching a policy is denied, stop and check the playground's IAM permissions; having a role ARN alone does not give Lambda DynamoDB access. `AmazonDynamoDBFullAccess_v2` is broader than this project's two tables, so replace it with a table-scoped policy in an unrestricted AWS account.

### Task 7 — Build the Go Lambda backend

In the WASM Playground terminal:

~~~bash
cd "$HOME/wasm-ecommerce-api"
cat > go.mod <<'EOF'
module wasm-ecommerce-api

go 1.22
EOF

cat > main.go <<'EOF'
package main

import (
    "context"
    "encoding/json"
    "errors"
    "fmt"
    "os"
    "strconv"
    "strings"
    "time"

    "github.com/aws/aws-lambda-go/events"
    "github.com/aws/aws-lambda-go/lambda"
    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/config"
    "github.com/aws/aws-sdk-go-v2/service/dynamodb"
    "github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

type orderRequest struct {
    Item_id        string
    Quantity       int64
    Customer_id    string
    Idempotency_key string
}

var (
    db             *dynamodb.Client
    inventoryTable string
    ordersTable    string
    allowedOrigin  string
)

func init() {
    cfg, err := config.LoadDefaultConfig(context.Background())
    if err != nil {
        panic(err)
    }
    db = dynamodb.NewFromConfig(cfg)
    inventoryTable = os.Getenv("INVENTORY_TABLE_NAME")
    ordersTable = os.Getenv("ORDERS_TABLE_NAME")
    allowedOrigin = os.Getenv("ALLOWED_ORIGIN")
    if allowedOrigin == "" {
        allowedOrigin = "*"
    }
    if inventoryTable == "" || ordersTable == "" {
        panic("INVENTORY_TABLE_NAME and ORDERS_TABLE_NAME are required")
    }
}

func jsonResponse(status int, value any) (events.APIGatewayV2HTTPResponse, error) {
    body, err := json.Marshal(value)
    if err != nil {
        return events.APIGatewayV2HTTPResponse{}, err
    }
    return events.APIGatewayV2HTTPResponse{
        StatusCode: status,
        Headers: map[string]string{
            "content-type":                "application/json",
            "access-control-allow-origin": allowedOrigin,
        },
        Body: string(body),
    }, nil
}

func validate(order orderRequest) error {
    if strings.TrimSpace(order.Item_id) == "" || len(order.Item_id) > 64 {
        return errors.New("item_id must contain 1 to 64 characters")
    }
    if order.Quantity < 1 || order.Quantity > 100 {
        return errors.New("quantity must be between 1 and 100")
    }
    if strings.TrimSpace(order.Customer_id) == "" || len(order.Customer_id) > 64 {
        return errors.New("customer_id must contain 1 to 64 characters")
    }
    if len(order.Idempotency_key) < 1 || len(order.Idempotency_key) > 36 {
        return errors.New("idempotency_key must contain 1 to 36 characters")
    }
    return nil
}

func handler(ctx context.Context, request events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
    if request.RequestContext.HTTP.Method != "POST" {
        return jsonResponse(405, map[string]string{"message": "method not allowed"})
    }

    var order orderRequest
    if err := json.Unmarshal([]byte(request.Body), &order); err != nil {
        return jsonResponse(400, map[string]string{"message": "request body must be valid JSON"})
    }
    if err := validate(order); err != nil {
        return jsonResponse(400, map[string]string{"message": err.Error()})
    }

    now := time.Now().UTC().Format(time.RFC3339)
    _, err := db.TransactWriteItems(ctx, &dynamodb.TransactWriteItemsInput{
        TransactItems: []types.TransactWriteItem{
            {
                Update: &types.Update{
                    TableName:           aws.String(inventoryTable),
                    Key:                 map[string]types.AttributeValue{"item_id": &types.AttributeValueMemberS{Value: order.Item_id}},
                    UpdateExpression:    aws.String("SET quantity = quantity - :quantity"),
                    ConditionExpression: aws.String("attribute_exists(item_id) AND quantity >= :quantity"),
                    ExpressionAttributeValues: map[string]types.AttributeValue{
                        ":quantity": &types.AttributeValueMemberN{Value: strconv.FormatInt(order.Quantity, 10)},
                    },
                },
            },
            {
                Put: &types.Put{
                    TableName: aws.String(ordersTable),
                    Item: map[string]types.AttributeValue{
                        "order_id":    &types.AttributeValueMemberS{Value: order.Idempotency_key},
                        "item_id":     &types.AttributeValueMemberS{Value: order.Item_id},
                        "quantity":    &types.AttributeValueMemberN{Value: strconv.FormatInt(order.Quantity, 10)},
                        "customer_id": &types.AttributeValueMemberS{Value: order.Customer_id},
                        "status":      &types.AttributeValueMemberS{Value: "CONFIRMED"},
                        "created_at":  &types.AttributeValueMemberS{Value: now},
                    },
                    ConditionExpression: aws.String("attribute_not_exists(order_id)"),
                },
            },
        },
    })
    if err != nil {
        fmt.Printf("DynamoDB transaction rejected: %v\n", err)
        return jsonResponse(409, map[string]string{
            "status":   "REJECTED",
            "order_id": order.Idempotency_key,
            "message":  "inventory was unavailable or the order already exists",
        })
    }

    return jsonResponse(201, map[string]string{
        "status":   "CONFIRMED",
        "order_id": order.Idempotency_key,
        "message":  "order created",
    })
}

func main() {
    lambda.Start(handler)
}
EOF
~~~

Run `gofmt` before fetching dependencies. If it reports `missing import path`, inspect `main.go`: the import lines must contain only quoted package paths, not pasted prompt text such as `go.mod`. Fix the file before continuing. This heredoc uses spaces for indentation to avoid tab-paste problems in the playground terminal.

~~~bash
gofmt -w main.go
~~~

Then download dependencies and build. Packaging runs only if the build succeeds:

~~~bash
go get github.com/aws/aws-lambda-go/events
go get github.com/aws/aws-lambda-go/lambda
go get github.com/aws/aws-sdk-go-v2/config
go get github.com/aws/aws-sdk-go-v2/service/dynamodb
go mod tidy

GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
  go build -tags lambda.norpc -trimpath -ldflags="-s -w" -o bootstrap . &&
  zip -j function.zip bootstrap &&
  test -s function.zip
~~~

### Task 8 — Deploy Lambda and create the API

Use a private S3 bucket to transfer the build artifacts. In the AWS Playground terminal, create a fresh staging bucket with public access blocked:

~~~bash
export ARTIFACT_BUCKET="wasm-ecommerce-artifacts-$AWS_ACCOUNT_ID-$(date +%s)"

if [ "$AWS_REGION" = "us-east-1" ]; then
  aws s3api create-bucket --bucket "$ARTIFACT_BUCKET" --region "$AWS_REGION"
else
  aws s3api create-bucket \
    --bucket "$ARTIFACT_BUCKET" \
    --create-bucket-configuration "LocationConstraint=$AWS_REGION" \
    --region "$AWS_REGION"
fi

aws s3api put-public-access-block \
  --bucket "$ARTIFACT_BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
  --region "$AWS_REGION"
~~~

Still in the AWS Playground, create a short-lived upload URL. The AWS terminal must have Python 3 and Boto3; if `python3 -c 'import boto3'` fails, install Boto3 there with `python3 -m pip install --user boto3`.

~~~bash
cat > /tmp/presign-artifact.py <<'PY'
import os
import sys

import boto3
from botocore.config import Config

bucket, key = sys.argv[1:3]
client = boto3.client(
    "s3",
    region_name=os.environ["AWS_REGION"],
    config=Config(signature_version="s3v4"),
)
print(client.generate_presigned_url(
    "put_object",
    Params={"Bucket": bucket, "Key": key},
    ExpiresIn=900,
    HttpMethod="PUT",
))
PY

python3 /tmp/presign-artifact.py "$ARTIFACT_BUCKET" function.zip
~~~

Copy the complete URL from that output. It grants temporary upload access to one private object, so do not share it publicly. In the WASM Playground terminal, paste the URL when prompted. The URL is visible while pasting so you can spot an empty or incomplete paste; do not include it in screenshots or shared terminal output.

~~~bash
cd "$HOME/wasm-ecommerce-api"
test -s function.zip
read -r -p 'Paste function.zip upload URL, then press Enter: ' FUNCTION_PUT_URL
printf 'Length: %s\nFirst bytes: ' "${#FUNCTION_PUT_URL}"
printf '%s' "$FUNCTION_PUT_URL" | head -c 8 | od -An -tx1
if [[ "$FUNCTION_PUT_URL" == https://* ]]; then
  curl -fS --retry 2 -T function.zip "$FUNCTION_PUT_URL"
else
  echo 'URL is empty or does not begin with https://; generate a new URL and paste again.'
fi
unset FUNCTION_PUT_URL
sha256sum function.zip
~~~

The first bytes of a valid `https://` URL are `68 74 74 70 73 3a 2f 2f`. If they differ, do not upload. The upload URL is a temporary credential; regenerate it if it appears in a screenshot or shared log.

Back in the AWS Playground terminal, download the private object and compare its SHA-256 checksum with the WASM Playground output:

~~~bash
mkdir -p "$HOME/wasm-ecommerce-api"
aws s3 cp "s3://$ARTIFACT_BUCKET/function.zip" \
  "$HOME/wasm-ecommerce-api/function.zip" \
  --region "$AWS_REGION"
sha256sum "$HOME/wasm-ecommerce-api/function.zip"
test -s "$HOME/wasm-ecommerce-api/function.zip"
~~~

If the upload URL expires, generate a new one in the AWS Playground and repeat the `curl` upload. No AWS CLI or AWS credentials are needed in the WASM Playground.

Now deploy the Lambda function in the AWS Playground. First, retrieve its execution role and prepare its environment:

~~~bash
export LAMBDA_FUNCTION_NAME="wasm-ecommerce-order-api"
LAMBDA_ROLE_ARN="$(aws iam get-role \
  --role-name "$LAMBDA_ROLE_NAME" \
  --query 'Role.Arn' \
  --output text)"
printf 'Role ARN: %s\n' "$LAMBDA_ROLE_ARN"
~~~

Stop if the role ARN is empty or `None`. Then prepare the environment file:

~~~bash
cat > /tmp/lambda-environment.json <<EOF
{
  "Variables": {
    "INVENTORY_TABLE_NAME": "$INVENTORY_TABLE_NAME",
    "ORDERS_TABLE_NAME": "$ORDERS_TABLE_NAME",
    "ALLOWED_ORIGIN": "*"
  }
}
EOF
~~~

Create the function and confirm it is active before creating the API:

~~~bash
aws lambda create-function \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --runtime provided.al2023 \
  --handler bootstrap \
  --architectures x86_64 \
  --role "$LAMBDA_ROLE_ARN" \
  --zip-file "fileb://$HOME/wasm-ecommerce-api/function.zip" \
  --timeout 10 \
  --memory-size 256 \
  --environment file:///tmp/lambda-environment.json \
  --region "$AWS_REGION"
~~~

~~~bash
aws lambda wait function-active-v2 \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --region "$AWS_REGION"

LAMBDA_ARN="$(aws lambda get-function \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --query 'Configuration.FunctionArn' \
  --output text \
  --region "$AWS_REGION")"
printf 'Lambda ARN: %s\n' "$LAMBDA_ARN"
~~~

The Lambda ARN must start with `arn:aws:lambda:` and end with `:function:wasm-ecommerce-order-api`. An empty or malformed ARN produces `Invalid integration URI` in the next step. Do not create an integration until the ARN is correct.

Prepare API CORS in the AWS Playground:

~~~bash
cat > /tmp/api-cors.json <<'EOF'
{
  "AllowOrigins": ["*"],
  "AllowMethods": ["POST", "OPTIONS"],
  "AllowHeaders": ["content-type"]
}
EOF
~~~

Create the HTTP API and check its ID:

~~~bash
API_ID="$(aws apigatewayv2 create-api \
  --name "wasm-ecommerce-api" \
  --protocol-type HTTP \
  --cors-configuration file:///tmp/api-cors.json \
  --query ApiId \
  --output text \
  --region "$AWS_REGION")"
printf 'API ID: %s\n' "$API_ID"
~~~

Stop if the API ID is empty or `None`. Then create the Lambda integration:

~~~bash
INTEGRATION_ID="$(aws apigatewayv2 create-integration \
  --api-id "$API_ID" \
  --integration-type AWS_PROXY \
  --integration-uri "$LAMBDA_ARN" \
  --payload-format-version 2.0 \
  --query IntegrationId \
  --output text \
  --region "$AWS_REGION")"
printf 'Integration ID: %s\n' "$INTEGRATION_ID"
~~~

Stop if the integration ID is empty or `None`. Only then create the route:

~~~bash
aws apigatewayv2 create-route \
  --api-id "$API_ID" \
  --route-key 'POST /orders' \
  --target "integrations/$INTEGRATION_ID" \
  --region "$AWS_REGION"
~~~

Create an auto-deploying default stage:

~~~bash
aws apigatewayv2 create-stage \
  --api-id "$API_ID" \
  --stage-name '$default' \
  --auto-deploy \
  --region "$AWS_REGION"
~~~

Allow this API to invoke the Lambda function:

~~~bash
aws lambda add-permission \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --statement-id allow-http-api \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$AWS_REGION:$AWS_ACCOUNT_ID:$API_ID/*/*/*" \
  --region "$AWS_REGION"
~~~

Finally, retrieve the API endpoint:

~~~bash
API_BASE_URL="$(aws apigatewayv2 get-api \
  --api-id "$API_ID" \
  --query ApiEndpoint \
  --output text \
  --region "$AWS_REGION")"
echo "$API_BASE_URL"
~~~

If an earlier integration or route failed but the API and `$default` stage already exist, reuse them. Re-run the Lambda ARN lookup, then create only the missing integration and route. Do not create a second API or repeat `add-permission` if that statement already exists.

Verify that `POST /orders` points to an integration:

~~~bash
aws apigatewayv2 get-routes \
  --api-id "$API_ID" \
  --query 'Items[].{Route:RouteKey,Target:Target}' \
  --output table \
  --region "$AWS_REGION"
~~~

Test the backend:

~~~bash
export TEST_ORDER_ID="order-test-$(date +%s)"
curl -i -X POST "$API_BASE_URL/orders" \
  -H 'content-type: application/json' \
  -d "{\"item_id\":\"ITEM-9942\",\"quantity\":2,\"customer_id\":\"CUST-104\",\"idempotency_key\":\"$TEST_ORDER_ID\"}"
~~~

Check the stored order separately:

~~~bash
aws dynamodb get-item \
  --table-name "$ORDERS_TABLE_NAME" \
  --key "{\"order_id\":{\"S\":\"$TEST_ORDER_ID\"}}" \
  --region "$AWS_REGION"
~~~

Expected result: HTTP 201, a CONFIRMED order, and inventory reduced by 2. Repeating the exact request must return HTTP 409 without reducing inventory again.

### Task 9 — Create the S3 static website

~~~bash
export SITE_BUCKET="wasm-ecommerce-site-$AWS_ACCOUNT_ID-$AWS_REGION-$(date +%s)"

if [ "$AWS_REGION" = "us-east-1" ]; then
  aws s3api create-bucket --bucket "$SITE_BUCKET" --region "$AWS_REGION"
else
  aws s3api create-bucket \
    --bucket "$SITE_BUCKET" \
    --region "$AWS_REGION" \
    --create-bucket-configuration LocationConstraint="$AWS_REGION"
fi

aws s3api put-public-access-block \
  --bucket "$SITE_BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false \
  --region "$AWS_REGION"
~~~

Enable versioning and default encryption:

~~~bash
aws s3api put-bucket-versioning \
  --bucket "$SITE_BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$SITE_BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'
~~~

Configure website hosting:

~~~bash
aws s3api put-bucket-website \
  --bucket "$SITE_BUCKET" \
  --website-configuration '{
    "IndexDocument": {"Suffix": "index.html"},
    "ErrorDocument": {"Key": "index.html"}
  }' \
  --region "$AWS_REGION"
~~~

Prepare the public-read policy for the website files only:

~~~bash
cat > /tmp/site-public-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadForStaticWebsite",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$SITE_BUCKET/*"
    }
  ]
}
EOF
~~~

Apply the policy:

~~~bash
aws s3api put-bucket-policy \
  --bucket "$SITE_BUCKET" \
  --policy file:///tmp/site-public-policy.json \
  --region "$AWS_REGION"
~~~

Set the website origin for the next steps:

~~~bash
export SITE_ORIGIN="http://$SITE_BUCKET.s3-website-$AWS_REGION.amazonaws.com"
echo "$SITE_ORIGIN"
~~~

S3 website hosting requires public read access to the site files. If account-level S3 Block Public Access prevents the policy, this account cannot serve the site directly until its owner changes that setting. Keep credentials and private data out of this bucket.

Transfer the storefront through the same private staging bucket. In the WASM Playground, bundle the `web` directory:

~~~bash
cd "$HOME/wasm-ecommerce-store"
test -s web/index.html &&
test -s web/wasm/wasm_ecommerce_frontend_bg.wasm &&
test -s web/wasm/wasm_ecommerce_frontend.js &&
tar -czf web.tar.gz web &&
test -s web.tar.gz &&
tar -tzf web.tar.gz | grep 'web/wasm/wasm_ecommerce_frontend' &&
sha256sum web.tar.gz
~~~

In the AWS Playground, generate a new presigned upload URL for this archive:

~~~bash
python3 /tmp/presign-artifact.py "$ARTIFACT_BUCKET" web.tar.gz
~~~

Copy that URL into the WASM Playground prompt and upload the archive. Use the same first-byte check before the upload:

~~~bash
cd "$HOME/wasm-ecommerce-store"
read -r -p 'Paste web.tar.gz upload URL, then press Enter: ' WEB_PUT_URL
printf 'Length: %s\nFirst bytes: ' "${#WEB_PUT_URL}"
printf '%s' "$WEB_PUT_URL" | head -c 8 | od -An -tx1
if [[ "$WEB_PUT_URL" == https://* ]]; then
  curl -fS --retry 2 -T web.tar.gz "$WEB_PUT_URL"
else
  echo 'URL is empty or does not begin with https://; generate a new URL and paste again.'
fi
unset WEB_PUT_URL
~~~

Back in the AWS Playground, retrieve and extract it. Check that its SHA-256 checksum matches the WASM Playground output:

~~~bash
mkdir -p "$HOME/wasm-ecommerce-store"
aws s3 cp "s3://$ARTIFACT_BUCKET/web.tar.gz" \
  "$HOME/wasm-ecommerce-store/web.tar.gz" \
  --region "$AWS_REGION"
sha256sum "$HOME/wasm-ecommerce-store/web.tar.gz"
tar -xzf "$HOME/wasm-ecommerce-store/web.tar.gz" \
  -C "$HOME/wasm-ecommerce-store"
test -s "$HOME/wasm-ecommerce-store/web/wasm/wasm_ecommerce_frontend_bg.wasm"
~~~

Insert the API URL in the AWS Playground and publish the website files:

~~~bash
cd "$HOME/wasm-ecommerce-store"
sed "s|__API_BASE_URL__|$API_BASE_URL|g" web/index.html > /tmp/index.html
cp /tmp/index.html web/index.html
~~~

Upload the HTML, then the generated JavaScript and WASM files:

~~~bash
aws s3 cp web/index.html "s3://$SITE_BUCKET/index.html" \
  --cache-control 'no-cache,no-store,must-revalidate' \
  --content-type 'text/html' \
  --region "$AWS_REGION"
~~~

~~~bash
aws s3 sync web/wasm "s3://$SITE_BUCKET/wasm" \
  --cache-control 'no-cache,max-age=0,must-revalidate' \
  --region "$AWS_REGION"
~~~

Set the correct content type on the WASM object and check both URLs:

~~~bash
aws s3 cp web/wasm/wasm_ecommerce_frontend_bg.wasm "s3://$SITE_BUCKET/wasm/wasm_ecommerce_frontend_bg.wasm" \
  --cache-control 'no-cache,max-age=0,must-revalidate' \
  --content-type 'application/wasm' \
  --region "$AWS_REGION"
~~~

~~~bash
curl -fsSI "$SITE_ORIGIN/"
curl -fsSI "$SITE_ORIGIN/wasm/wasm_ecommerce_frontend_bg.wasm"
~~~

### Task 10 — Lock API CORS to the S3 website and test orders

Replace the temporary wildcard with the S3 website origin:

~~~bash
cat > /tmp/api-cors-exact.json <<EOF
{
  "AllowOrigins": ["$SITE_ORIGIN"],
  "AllowMethods": ["POST", "OPTIONS"],
  "AllowHeaders": ["content-type"]
}
EOF
~~~

~~~bash
aws apigatewayv2 update-api \
  --api-id "$API_ID" \
  --cors-configuration file:///tmp/api-cors-exact.json \
  --region "$AWS_REGION"
~~~

Prepare the Lambda environment with the same website origin:

~~~bash
cat > /tmp/lambda-environment-exact.json <<EOF
{
  "Variables": {
    "INVENTORY_TABLE_NAME": "$INVENTORY_TABLE_NAME",
    "ORDERS_TABLE_NAME": "$ORDERS_TABLE_NAME",
    "ALLOWED_ORIGIN": "$SITE_ORIGIN"
  }
}
EOF
~~~

~~~bash
aws lambda update-function-configuration \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --environment file:///tmp/lambda-environment-exact.json \
  --region "$AWS_REGION"
~~~

~~~bash
aws lambda wait function-updated-v2 \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --region "$AWS_REGION"
~~~

Open SITE_ORIGIN in a browser and verify:

- The page loads from the S3 website endpoint.
- The status changes from Loading validation module... to Ready.
- Invalid quantities are rejected before an API request is sent.
- A valid order returns CONFIRMED.
- Replaying the same idempotency key does not decrement inventory twice.
- An unknown item or excessive quantity returns HTTP 409.

### Task 11 — Verify website configuration and release updates

~~~bash
aws dynamodb describe-table \
  --table-name "$INVENTORY_TABLE_NAME" \
  --query 'Table.{Name:TableName,Status:TableStatus}' \
  --output table \
  --region "$AWS_REGION"
~~~

~~~bash
aws lambda get-function-configuration \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --query '{Runtime:Runtime,State:State,Role:Role,Memory:MemorySize}' \
  --output table \
  --region "$AWS_REGION"
~~~

~~~bash
aws s3api get-bucket-website \
  --bucket "$SITE_BUCKET" \
  --region "$AWS_REGION"
~~~

~~~bash
aws s3api get-public-access-block \
  --bucket "$SITE_BUCKET" \
  --region "$AWS_REGION"
~~~

~~~bash
aws s3api get-bucket-policy \
  --bucket "$SITE_BUCKET" \
  --region "$AWS_REGION"
~~~

~~~bash
aws s3api get-bucket-policy-status \
  --bucket "$SITE_BUCKET" \
  --region "$AWS_REGION"
~~~

For future releases, rebuild the WASM module and upload the updated files. The website uses the same object names, so the browser should revalidate them:

~~~bash
aws s3 cp web/index.html "s3://$SITE_BUCKET/index.html" \
  --cache-control 'no-cache,no-store,must-revalidate' \
  --content-type 'text/html' \
  --region "$AWS_REGION"

aws s3 sync web/wasm "s3://$SITE_BUCKET/wasm" \
  --cache-control 'no-cache,max-age=0,must-revalidate' \
  --region "$AWS_REGION"

aws s3 cp web/wasm/wasm_ecommerce_frontend_bg.wasm "s3://$SITE_BUCKET/wasm/wasm_ecommerce_frontend_bg.wasm" \
  --cache-control 'no-cache,max-age=0,must-revalidate' \
  --content-type 'application/wasm' \
  --region "$AWS_REGION"
~~~

## Validation

The deployment is complete when all checks pass:

- [ ] wasm32-unknown-unknown is installed in the WASM Playground.
- [ ] The browser WASM binary and JavaScript binding are generated.
- [ ] The Lambda ZIP and storefront bundle transfer through private, short-lived S3 upload URLs with matching checksums.
- [ ] The storefront loads through the S3 website endpoint.
- [ ] DynamoDB tables are Active and point-in-time recovery is enabled.
- [ ] The Lambda role is named iam_role_wasm_ecommerce_lambda.
- [ ] Lambda uses provided.al2023 and reaches DynamoDB through its IAM role.
- [ ] API Gateway exposes POST /orders.
- [ ] A valid request creates an order and decrements inventory.
- [ ] Replaying an idempotency key does not double-decrement inventory.
- [ ] Invalid inventory requests return HTTP 409.
- [ ] S3 website hosting serves index.html and the WASM file with the correct content type.
- [ ] The S3 bucket policy grants public read access only to this website bucket's objects.
- [ ] API CORS allows the S3 website origin rather than a permanent wildcard.
- [ ] No AWS access key, secret key, or session token exists in the WASM or JavaScript files.

## What you learned

- Browser WASM is compiled for wasm32-unknown-unknown, not the WASI target used by Spin.
- WASM is useful for portable client-side computation, but it cannot be trusted with secrets or authoritative business state.
- S3 website hosting serves the static WASM assets from a public bucket over HTTP.
- API Gateway and Lambda provide the trusted request boundary.
- DynamoDB transactions protect inventory and order consistency.
- Idempotency prevents retries from creating duplicate orders.
- Presigned S3 URLs move build artifacts between playgrounds without putting AWS credentials in the build environment.
- S3 website hosting requires public object reads and supports HTTP endpoints only.

## References & further learning

- [AWS: Configuring a static website on Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/HostingWebsiteOnS3Setup.html)
- [AWS: Uploading objects with presigned URLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/PresignedUrlUploadObject.html)
- [AWS: API Gateway and Lambda RESTful microservices](https://docs.aws.amazon.com/wellarchitected/latest/serverless-applications-lens/restful-microservices.html)
- [AWS: DynamoDB TransactWriteItems](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_TransactWriteItems.html)
- [AWS SDK for Go v2 Developer Guide](https://docs.aws.amazon.com/sdk-for-go/v2/developer-guide/)
- [Rust and WebAssembly Book](https://rustwasm.github.io/docs/book/)
- [wasm-bindgen guide](https://rustwasm.github.io/wasm-bindgen/)
```
