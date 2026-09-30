import requests, logging, sys
from flask import Flask, request

app = Flask(__name__)
logging.basicConfig(stream=sys.stdout, level=logging.INFO, format='%(message)s')

@app.route('/add')
def add_to_cart():
    tx_id = request.headers.get('X-Transaction-ID', 'unknown')
    logging.info(f'{{"service": "cart", "transaction_id": "{tx_id}", "event": "items_compiled"}}')

    headers = {'X-Transaction-ID': tx_id}
    res = requests.get('http://payment-service:8080/charge', headers=headers)
    return "Cart updated.\n", res.status_code

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
