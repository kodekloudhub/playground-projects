from flask import Flask, jsonify
import urllib.request
import json

app = Flask(__name__)
HUBS = {
    "seattle": {"lat": 47.60, "lon": -122.33},
    "miami": {"lat": 25.76, "lon": -80.19},
    "tokyo": {"lat": 35.68, "lon": 139.69},
    "manila": {"lat": 14.60, "lon": 120.98},
    "mumbai": {"lat": 19.07, "lon": 72.88}
}

@app.route('/weather/<hub>', methods=['GET'])
def get_weather(hub):
    hub_lower = hub.lower()
    if hub_lower not in HUBS:
        return jsonify({"error": "Hub not found."}), 404

    coords = HUBS[hub_lower]
    url = f"https://api.open-meteo.com/v1/forecast?latitude={coords['lat']}&longitude={coords['lon']}&current_weather=true"

    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            current = data.get("current_weather", {})

            temp = current.get("temperature")
            wind = current.get("windspeed")

            status = "CLEAR_FOR_TRANSIT"
            if wind > 30:
                status = "DELAYED_HIGH_WINDS"

            return jsonify({
                "hub": hub_lower,
                "temperature_c": temp,
                "wind_speed_kmh": wind,
                "logistics_status": status
            })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
