from flask import Flask, request, jsonify
import uuid, datetime

app = Flask(__name__)

INVENTORY = {
    "item_1": {"name": "Kubernetes CKA Voucher", "price": 395.00},
    "item_2": {"name": "Mechanical Keyboard", "price": 129.99},
    "item_3": {"name": "Cloud Architecture Poster", "price": 24.50}
}

@app.route('/api/process-order', methods=['POST'])
def process_order():
    data = request.json
    item_id = data.get('item_id')

    if item_id not in INVENTORY:
        return jsonify({"error": "Item not found in inventory"}), 404

    item = INVENTORY[item_id]

    return jsonify({
        "status": "APPROVED",
        "receipt_id": f"ORD-{uuid.uuid4().hex[:8].upper()}",
        "item_purchased": item["name"],
        "amount_charged": f"${item['price']:.2f}",
        "timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC"),
        "processor_node": "payment-api-v3"
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
