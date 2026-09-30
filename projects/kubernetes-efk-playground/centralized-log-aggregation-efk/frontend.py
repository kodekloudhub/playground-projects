import uuid, requests, logging, sys
from flask import Flask, render_template

app = Flask(__name__)
logging.basicConfig(stream=sys.stdout, level=logging.INFO, format='%(message)s')

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/checkout')
def checkout():
    tx_id = str(uuid.uuid4())
    logging.info(f'{{"service": "frontend", "transaction_id": "{tx_id}", "event": "checkout_started"}}')

    headers = {'X-Transaction-ID': tx_id}
    try:
        res = requests.get('http://cart-service:8080/add', headers=headers, timeout=5)
        status = "Success" if res.status_code == 200 else "Failed"
        return render_template('checkout.html', tx_id=tx_id, status=status)
    except Exception as e:
        logging.error(f'{{"service": "frontend", "transaction_id": "{tx_id}", "error": "{str(e)}"}}')
        return render_template('checkout.html', tx_id=tx_id, status="Error")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
