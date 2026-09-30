import hashlib
import json
import os
import re
import sys
import time
import urllib.request
from threading import Lock, Thread

from kubernetes import client, config
from smolagents import OpenAIServerModel, ToolCallingAgent

try:
    config.load_incluster_config()
except Exception as exc:
    print(f"Failed to load cluster credentials: {exc}", flush=True)
    sys.exit(1)

v1 = client.CoreV1Api()
NAMESPACE = os.getenv("TARGET_NAMESPACE", "default")
SELECTOR = os.getenv("LABEL_SELECTOR", "app=web-gateway")
NOTIFIER_URL = os.getenv("NOTIFIER_URL")
GOTIFY_TOKEN = os.getenv("GOTIFY_TOKEN")
AI_API_KEY = os.getenv("AI_API_KEY")
AI_BASE_URL = os.getenv("AI_BASE_URL")
AI_MODEL_NAME = os.getenv("AI_MODEL_NAME", "gpt-6-luna")
DEDUPE_SECONDS = 300
_dedupe_lock = Lock()
_last_alert = {}
_claimed_incidents = set()

ATTACK_SIGNATURES = [
    re.compile(r"\.\./", re.I),
    re.compile(r"%2f", re.I),
    re.compile(r"UNION\s+SELECT", re.I),
    re.compile(r"SELECT.*FROM", re.I),
]

def classify_incident(line):
    """Return a deterministic incident class before any AI call is made."""
    if re.search(r"UNION\s+SELECT|SELECT.*FROM", line, re.I):
        return "sql-injection"
    if re.search(r"\.\./|%2f", line, re.I):
        return "path-traversal"
    if re.search(r"(?:403|404|499)", line, re.I):
        return "reconnaissance"
    return None

def claim_incident(incident_class):
    """Allow one AI investigation per incident class in this run."""
    with _dedupe_lock:
        if incident_class in _claimed_incidents:
            return False
        _claimed_incidents.add(incident_class)
        return True

def alert_key(title, message, incident_class):
    normalized = re.sub(r"\s+", " ", message).lower()
    return hashlib.sha256(f"{title.lower()}|{incident_class}|{normalized[:200]}".encode()).hexdigest()

def send_gotify(title, message, incident_class):
    if not NOTIFIER_URL or not GOTIFY_TOKEN:
        return "Notifier configuration is incomplete."
    key = alert_key(title, message, incident_class)
    with _dedupe_lock:
        if time.time() - _last_alert.get(key, 0) < DEDUPE_SECONDS:
            return "Duplicate alert suppressed during cooldown."
        _last_alert[key] = time.time()
    payload = json.dumps({"title": title, "message": message, "priority": 7}).encode()
    request = urllib.request.Request(
        f"{NOTIFIER_URL}?token={GOTIFY_TOKEN}",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            if response.status == 200:
                return "Alert delivered to Gotify."
            with _dedupe_lock:
                _last_alert.pop(key, None)
            return f"Gotify returned HTTP {response.status}."
    except Exception as exc:
        with _dedupe_lock:
            _last_alert.pop(key, None)
        return f"Gotify delivery failed: {exc}"

def investigate(raw_line, pod_name, incident_class):
    model = OpenAIServerModel(model_id=AI_MODEL_NAME, api_base=AI_BASE_URL, api_key=AI_API_KEY)

    agent = ToolCallingAgent(tools=[], model=model)
    prompt = (
        f"Analyze this suspicious log line from pod {pod_name}: {raw_line}. "
        "Describe the attack and mitigation. Use the exact title 'SecOps Web Log Anomaly'. "
        "The notification is dispatched by the host process exactly once."
    )
    report = agent.run(prompt)
    print(send_gotify("SecOps Web Log Anomaly", str(report), incident_class), flush=True)

def monitor(pod_name):
    stream = v1.read_namespaced_pod_log(
        name=pod_name,
        namespace=NAMESPACE,
        follow=True,
        tail_lines=0,
        _preload_content=False,
    )
    for raw_line in iter(stream.readline, b""):
        line = raw_line.decode("utf-8", errors="replace").strip()
        incident_class = classify_incident(line)
        if incident_class and claim_incident(incident_class):
            Thread(
                target=investigate,
                args=(line, pod_name, incident_class),
                daemon=True,
            ).start()

def main():
    pods = v1.list_namespaced_pod(namespace=NAMESPACE, label_selector=SELECTOR)
    if not pods.items:
        print("No matching target pods found.", flush=True)
        return
    threads = [Thread(target=monitor, args=(pod.metadata.name,), daemon=True) for pod in pods.items]
    for thread in threads:
        thread.start()
    while True:
        time.sleep(1)

if __name__ == "__main__":
    main()
