# In-Memory Caching for Latency Reduction and API Rate Limiting

**Level:** intermediate  ·  **Playground:** Redis Playground

## Files in this project
- [`app.py`](./app.py)

> Copy these into your playground session (or `git clone` this repo and `cd` here).

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
Your team maintains a "Developer Pulse" dashboard that tracks highly active, open-source Python repositories globally. To populate this dashboard, the backend queries the live GitHub Search API for projects actively receiving code updates this exact minute. However, GitHub strictly limits unauthenticated search requests to just 10 requests per minute. If multiple engineers open the dashboard simultaneously, your application will hit the rate limit, receive an HTTP 403 Forbidden error, and crash. 

You have been tasked with integrating a Redis caching tier. Your goal is to cache the API response for 60 seconds, allowing the dashboard to serve the data instantly to thousands of concurrent visitors while drastically reducing page load latency and safely bypassing the rate limit constraints.

## What you'll build
You will provision a Python Flask web server. The backend code will query the live GitHub Search API for trending repositories, intercept that request using a Redis caching layer, and render the resulting data into a dark-mode engineering dashboard. You will validate the architecture by opening the portal in your browser, comparing the load time of the initial network request against the sub-millisecond load time of the subsequent Redis memory retrieval.

## Learning objectives
By the end you will be able to:
- Integrate a Redis caching layer into a Python Flask web application.
- Mitigate third-party API rate limits by storing and serving temporary in-memory payloads.
- Authenticate and navigate the `redis-cli` to directly inspect memory stores.
- Monitor cache volatility and enforce expiration policies using Time-To-Live (TTL) commands.

## Prerequisites
- Playground: **Redis** (open it before starting)

---

## Steps

### Task 1 — Application Setup
Install the required system dependencies and provision the Python web application containing the frontend dashboard and backend caching logic.

1. **Install Dependencies:** Install Flask, the Redis driver, and the Requests library via the system package manager.
```bash
apt-get update && apt-get install -y python3-flask python3-redis python3-requests
```

2. **Provision the Web Application:** Run this command to generate the `app.py` file, which contains both the styled frontend template and the backend Redis caching logic.
```bash
cat << 'EOF' > app.py
from flask import Flask, render_template_string
import redis, requests, time, json

app = Flask(__name__)
cache = redis.Redis(host='localhost', port=6379, decode_responses=True)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Developer Pulse</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; background: #0d1117; color: #c9d1d9; padding: 30px; margin: 0; }
        .container { max-width: 900px; margin: 0 auto; }
        .metrics { background: #161b22; border: 1px solid #30363d; border-left: 5px solid #238636; padding: 15px; margin-bottom: 25px; border-radius: 6px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(400px, 1fr)); gap: 15px; }
        .card { background: #161b22; border: 1px solid #30363d; padding: 20px; border-radius: 6px; }
        h1 { color: #c9d1d9; font-size: 24px; border-bottom: 1px solid #21262d; padding-bottom: 10px; }
        h3 { margin-top: 0; }
        a { color: #58a6ff; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .highlight { font-weight: bold; color: #ff7b72; }
        .desc { font-size: 14px; color: #8b949e; min-height: 40px; }
        .badges { margin-top: 15px; font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: 12px; }
        .badge { display: inline-block; padding: 4px 8px; border-radius: 2em; color: #fff; margin-right: 5px; font-weight: 600; }
        .stars { background: #d4a72c; color: #000; }
        .forks { background: #1f6feb; }
        .issues { background: #da3633; }
    </style>
</head>
<body>
    <div class="container">
        <h1>⚡ Developer Pulse: Live Python Activity</h1>

        <div class="metrics">
            <p><strong>Infrastructure Routing:</strong> <span class="highlight">{{ data_source }}</span></p>
            <p><strong>Latency:</strong> {{ load_time }} seconds</p>
        </div>

        <div class="grid">
            {% for repo in repos %}
            <div class="card">
                <h3><a href="{{ repo.html_url }}" target="_blank">{{ repo.name }}</a></h3>
                <p class="desc">{{ repo.description or 'No description provided.' }}</p>
                <div class="badges">
                    <span class="badge stars">⭐ {{ repo.stargazers_count }}</span>
                    <span class="badge forks">🔄 {{ repo.forks_count }}</span>
                    <span class="badge issues">⚠️ {{ repo.open_issues_count }} Issues</span>
                </div>
            </div>
            {% endfor %}
        </div>
    </div>
</body>
</html>
"""

@app.route('/')
def dashboard():
    start_time = time.time()

    # STEP 1: Check Redis Cache First
    cached_payload = cache.get('trending_repos')

    if cached_payload:
        # Data found in memory! Load it instantly.
        repos = json.loads(cached_payload)
        data_source = "REDIS CACHE (Memory Hit)"
    else:
        # STEP 2: Cache miss. Reach out to the internet (Real Network Latency).
        # We query the Search API for highly starred Python repos updated right NOW. Limit: 10 req/minute.
        headers = {'User-Agent': 'Python-Flask-App'}
        response = requests.get('https://api.github.com/search/repositories?q=language:python+stars:>500&sort=updated&order=desc&per_page=6', headers=headers)
        data = response.json()
        repos = data.get('items', [])

        # STEP 3: Store the extracted list in Redis for 60 seconds
        cache.setex('trending_repos', 60, json.dumps(repos))
        data_source = "GITHUB SEARCH API (Network Trip)"

    duration = time.time() - start_time
    return render_template_string(HTML_TEMPLATE, repos=repos, data_source=data_source, load_time=round(duration, 4))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
EOF
```

3. **Launch the Application:** Start the web server in the background so you can retain access to your terminal for database validation.
```bash
python3 app.py &
```

### Task 2 — Performance Testing
Simulate users accessing the dashboard to observe the difference between an external network call and an in-memory cache hit.

1. **Baseline the Network Latency:** Simulate an engineer loading the dashboard for the first time.
   - Click the ellipses (**...**) on the top right of your lab interface.
   - Select **View Port**, enter `8000`, and click **Open Port**.
   - Review the styled dashboard. Notice the *Infrastructure Routing* says `GITHUB SEARCH API` and the *Latency* shows the actual time it took to cross the internet to fetch the repositories.

2. **Test the Redis Cache:** Simulate a second engineer loading the dashboard simultaneously.
   - Refresh your newly opened browser tab.
   - Notice the *Infrastructure Routing* instantly flips to `REDIS CACHE`. 
   - Look at the *Latency*, it should now be drastically lower because the network trip was completely bypassed, saving your API rate limit.

### Task 3 — Infrastructure Verification
Access the Redis engine directly from the command line to verify the stored cache payload and monitor its automated expiration (TTL).

1. **Access the Redis CLI:** Enter the interactive Redis shell by explicitly connecting to your local host.
```bash
redis-cli -h localhost -p 6379
```

2. **Inspect the Raw Payload:** Retrieve the cached JSON string directly from memory.
```text
GET trending_repos
```
> **Note:** Because the cache is set to expire after 60 seconds, this command might return `(nil)`. If that happens, simply switch to your web browser, refresh the dashboard to trigger a fresh cache write, and run the command again.

3. **Monitor Volatility:** Check exactly how many seconds remain before Redis automatically purges the memory. When this timer hits `-2`, the key has expired.
```text
TTL trending_repos
```

4. **Exit the Database:** Return to your standard Linux terminal.
```text
exit
```

---

## Validation
Verify your application is running and the cache is correctly interfacing with Redis.

```bash
# 1. Verify the Python web server is listening on port 8000
netstat -tlnp | grep 8000
```

```bash
# 2. Check if the Redis server is actively accepting connections
redis-cli ping
```

Expected result:
- [ ] Did the web server launch successfully and bind to port 8000?
- [ ] When opening the View Port, did the frontend render the dark-mode Developer Pulse dashboard?
- [ ] Did the initial load indicate the data source was the "GITHUB SEARCH API" with a measurable delay?
- [ ] Upon refreshing, did the dashboard indicate the data source was the "REDIS CACHE" and load significantly faster?
- [ ] Were you able to authenticate into the database using the `redis-cli` and successfully view the cached JSON payload before it expired?

## References & further learning
- Redis GET Command: https://redis.io/commands/get/
- Redis TTL Command: https://redis.io/commands/ttl/
- Python Redis Client (redis-py): https://redis.readthedocs.io/en/stable/
- KodeKloud course: Database Fundamentals: https://kodekloud.com/courses/database-fundamentals/
