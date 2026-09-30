from flask import Flask, render_template_string
import requests

app = Flask(__name__)

STORE_HTML = """
<!DOCTYPE html>
<html>
<head>
    <title>CloudNative Store</title>
    <style>
        :root { --bg: #0b0f19; --card: #111827; --primary: #3b82f6; --text: #f3f4f6; --accent: #10b981; }
        body { background: var(--bg); color: var(--text); font-family: 'Segoe UI', system-ui, sans-serif; margin: 0; padding: 40px; }
        .nav { display: flex; justify-content: space-between; align-items: center; max-width: 1000px; margin: 0 auto 40px; padding-bottom: 20px; border-bottom: 1px solid #1f2937; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 30px; max-width: 1000px; margin: 0 auto; }
        .card { background: var(--card); border: 1px solid #1f2937; border-radius: 12px; padding: 25px; transition: transform 0.2s, box-shadow 0.2s; position: relative; overflow: hidden; }
        .card:hover { transform: translateY(-5px); box-shadow: 0 10px 25px rgba(0,0,0,0.5); border-color: #374151; }
        .card::before { content: ''; position: absolute; top: 0; left: 0; width: 100%; height: 4px; background: linear-gradient(90deg, var(--primary), var(--accent)); }
        .price { font-size: 28px; font-weight: bold; color: var(--text); margin: 15px 0; display: block; }
        .btn { background: var(--primary); color: white; display: block; text-align: center; padding: 12px; border-radius: 8px; font-size: 16px; font-weight: 600; text-decoration: none; transition: background 0.2s; box-sizing: border-box; }
        .btn:hover { background: #2563eb; }
    </style>
</head>
<body>
    <div class="nav">
        <h1 style="margin:0; font-size:24px;">☁️ CloudNative Store</h1>
        <span style="background:#1f2937; padding:6px 12px; border-radius:20px; font-size:14px; border: 1px solid #374151;">Secure Checkout v2.0</span>
    </div>
    <div class="grid">
        <div class="card">
            <h3 style="margin-top:0; color:#9ca3af; font-size:14px; text-transform:uppercase;">Certification</h3>
            <span style="font-size:20px; font-weight:600;">Kubernetes CKA Voucher</span>
            <span class="price">$395.00</span>
            <a href="/buy/item_1" class="btn">Buy Now</a>
        </div>
        <div class="card">
            <h3 style="margin-top:0; color:#9ca3af; font-size:14px; text-transform:uppercase;">Hardware</h3>
            <span style="font-size:20px; font-weight:600;">Mechanical Keyboard</span>
            <span class="price">$129.99</span>
            <a href="/buy/item_2" class="btn">Buy Now</a>
        </div>
        <div class="card">
            <h3 style="margin-top:0; color:#9ca3af; font-size:14px; text-transform:uppercase;">Merch</h3>
            <span style="font-size:20px; font-weight:600;">Architecture Poster</span>
            <span class="price">$24.50</span>
            <a href="/buy/item_3" class="btn">Buy Now</a>
        </div>
    </div>
</body>
</html>
"""

RECEIPT_HTML = """
<!DOCTYPE html>
<html>
<head>
    <title>Transaction Result</title>
    <style>
        body { background: #0b0f19; color: #f3f4f6; font-family: 'Segoe UI', system-ui, sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; }
        .receipt-card { background: #111827; border: 1px solid #1f2937; border-radius: 16px; padding: 40px; width: 100%; max-width: 450px; text-align: center; box-shadow: 0 20px 25px -5px rgba(0,0,0,0.3); }
        .icon-circle { width: 72px; height: 72px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 36px; margin: 0 auto 20px; }
        .success-icon { background: rgba(16, 185, 129, 0.1); color: #10b981; border: 2px solid rgba(16, 185, 129, 0.2); }
        .error-icon { background: rgba(239, 68, 68, 0.1); color: #ef4444; border: 2px solid rgba(239, 68, 68, 0.2); }
        .details { text-align: left; background: #1f2937; padding: 20px; border-radius: 8px; margin: 25px 0; }
        .row { display: flex; justify-content: space-between; margin-bottom: 12px; font-size: 14px; }
        .row:last-child { margin-bottom: 0; }
        .label { color: #9ca3af; }
        .val { font-weight: 600; }
        .back-btn { background: transparent; color: #3b82f6; border: 1px solid #3b82f6; padding: 10px 20px; border-radius: 8px; font-weight: 600; cursor: pointer; text-decoration: none; display: inline-block; transition: all 0.2s; }
        .back-btn:hover { background: #3b82f6; color: white; }
    </style>
</head>
<body>
    <div class="receipt-card">
        {% if error %}
            <div class="icon-circle error-icon">❌</div>
            <h2 style="margin: 0 0 10px; color: #ef4444;">Checkout Failed</h2>
            <p style="color: #9ca3af; font-size: 14px; margin: 0;">The network request to the backend payment processor was dropped by the firewall.</p>
            <div class="details" style="font-family: monospace; color: #ef4444; font-size: 12px; word-break: break-all;">
                {{ error_details }}
            </div>
        {% else %}
            <div class="icon-circle success-icon">✓</div>
            <h2 style="margin: 0 0 10px; color: #10b981;">Payment Approved</h2>
            <p style="color: #9ca3af; font-size: 14px; margin: 0;">Secure transaction completed.</p>
            <div class="details">
                <div class="row"><span class="label">Item</span> <span class="val">{{ data.item_purchased }}</span></div>
                <div class="row"><span class="label">Total</span> <span class="val" style="color: #10b981;">{{ data.amount_charged }}</span></div>
                <div class="row"><span class="label">Order ID</span> <span class="val" style="font-family: monospace;">{{ data.receipt_id }}</span></div>
                <div class="row"><span class="label">Node</span> <span class="val" style="color: #9ca3af;">{{ data.processor_node }}</span></div>
            </div>
        {% endif %}
        <a href="/" class="back-btn">← Return to Store</a>
    </div>
</body>
</html>
"""

@app.route('/')
def store():
    return render_template_string(STORE_HTML)

@app.route('/buy/<item_id>')
def checkout(item_id):
    try:
        # The frontend makes a strict POST request with a 3-second hard timeout
        response = requests.post("http://payment-svc:5000/api/process-order", json={"item_id": item_id}, timeout=3)
        response.raise_for_status()
        data = response.json()
        return render_template_string(RECEIPT_HTML, data=data, error=False)
    except Exception as e:
        # Safely catches the Calico Network Policy timeout or dropped packets
        return render_template_string(RECEIPT_HTML, error=True, error_details=str(e))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
