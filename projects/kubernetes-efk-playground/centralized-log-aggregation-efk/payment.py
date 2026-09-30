import logging, sys, random
from flask import Flask, request

app = Flask(__name__)
logging.basicConfig(stream=sys.stdout, level=logging.INFO, format='%(message)s')

@app.route('/charge')
def charge():
    tx_id = request.headers.get('X-Transaction-ID', 'unknown')

    if random.choice([True, False]):
        logging.error(f'{{"service": "payment", "transaction_id": "{tx_id}", "event": "charge_failed", "error": "insufficient_funds"}}')
        return "Payment failed.\n", 500
    else:
        logging.info(f'{{"service": "payment", "transaction_id": "{tx_id}", "event": "charge_successful"}}')
        return "Payment processed.\n", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
