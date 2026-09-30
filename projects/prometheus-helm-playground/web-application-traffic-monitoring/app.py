from flask import Flask, render_template, Response
from prometheus_client import Counter, generate_latest

app = Flask(__name__)

REQUESTS = Counter('http_requests_total', 'Total HTTP requests from customers', ['page'])

@app.route('/')
def index():
    REQUESTS.labels(page='home').inc()
    return render_template('index.html')

@app.route('/shop')
def shop():
    REQUESTS.labels(page='shop').inc()
    return render_template('shop.html')

@app.route('/collections')
def collections():
    REQUESTS.labels(page='collections').inc()
    return render_template('collections.html')

@app.route('/cart')
def cart():
    REQUESTS.labels(page='cart').inc()
    return render_template('cart.html')

@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype="text/plain")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
