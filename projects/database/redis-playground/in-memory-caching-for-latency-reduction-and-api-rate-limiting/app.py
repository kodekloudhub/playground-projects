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
