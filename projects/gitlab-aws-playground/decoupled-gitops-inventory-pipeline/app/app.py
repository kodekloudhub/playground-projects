import os
import socket
import urllib.request
import boto3
from flask import Flask, render_template, request, redirect, url_for
import psutil

app = Flask(__name__)

TABLE_NAME = os.environ.get("DYNAMODB_TABLE", "InventoryItems")
REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")

dynamodb = boto3.resource("dynamodb", region_name=REGION)
table = dynamodb.Table(TABLE_NAME)

def get_aws_metadata():
    meta = {"id": "Local-Node", "az": "Unknown-AZ", "ip": socket.gethostbyname(socket.gethostname())}
    try:
        token_req = urllib.request.Request("http://169.254.169.254/latest/api/token", method="PUT")
        token_req.add_header("X-aws-ec2-metadata-token-ttl-seconds", "21600")
        token = urllib.request.urlopen(token_req, timeout=1).read().decode()
        headers = {"X-aws-ec2-metadata-token": token}

        meta["id"] = urllib.request.urlopen(urllib.request.Request("http://169.254.169.254/latest/meta-data/instance-id", headers=headers), timeout=1).read().decode()
        meta["az"] = urllib.request.urlopen(urllib.request.Request("http://169.254.169.254/latest/meta-data/placement/availability-zone", headers=headers), timeout=1).read().decode()
        meta["ip"] = urllib.request.urlopen(urllib.request.Request("http://169.254.169.254/latest/meta-data/local-ipv4", headers=headers), timeout=1).read().decode()
    except Exception:
        pass
    return meta

def seed_default_records():
    try:
        response = table.scan(Limit=1)
        if response.get("Count", 0) == 0:
            defaults = [
                {"item_id": "MOD-101", "name": "Core Compute Node", "category": "Compute", "stock": 25},
                {"item_id": "MOD-102", "name": "Edge Cache Appliance", "category": "Storage", "stock": 8},
                {"item_id": "MOD-103", "name": "Gigabit Fiber Switch", "category": "Networking", "stock": 14}
            ]
            with table.batch_writer() as batch:
                for item in defaults:
                    batch.put_item(Item=item)
    except Exception as err:
        print(f"DynamoDB initialization warning: {err}")

@app.route("/")
def index():
    seed_default_records()
    items = []
    try:
        resp = table.scan()
        items = resp.get("Items", [])
        items.sort(key=lambda x: x.get("item_id", ""))
    except Exception as err:
        print(f"Fetch failed: {err}")

    metadata = get_aws_metadata()
    stats = {
        "cpu": psutil.cpu_percent(),
        "mem": psutil.virtual_memory().percent
    }
    return render_template("index.html", meta=metadata, stats=stats, items=items)

@app.route("/items", methods=["POST"])
def create_item():
    item_id = request.form.get("item_id", "").strip()
    name = request.form.get("name", "").strip()
    category = request.form.get("category", "").strip()
    stock = int(request.form.get("stock", 0))

    if item_id and name:
        table.put_item(Item={
            "item_id": item_id,
            "name": name,
            "category": category,
            "stock": stock
        })
    return redirect(url_for("index"))

@app.route("/items/update", methods=["POST"])
def update_item():
    item_id = request.form.get("item_id")
    stock = int(request.form.get("stock", 0))
    if item_id:
        table.update_item(
            Key={"item_id": item_id},
            UpdateExpression="SET stock = :val",
            ExpressionAttributeValues={":val": stock}
        )
    return redirect(url_for("index"))

@app.route("/items/delete/<item_id>", methods=["POST"])
def delete_item(item_id):
    if item_id:
        table.delete_item(Key={"item_id": item_id})
    return redirect(url_for("index"))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
