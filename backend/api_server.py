"""
Simple API Server to serve parsed Garmin health data
Serves the parsed_health_data.json with CORS enabled for Flutter web app
Also serves AI Pattern Analysis from analytics_engine.py
Also serves Garmin Connect live sync endpoints
"""

from http.server import HTTPServer, SimpleHTTPRequestHandler
import json
import threading
from pathlib import Path

# Import analytics engine
from analytics_engine import (
    run_full_analysis,
    calculate_correlation_matrix,
    calculate_lagged_correlations,
    detect_anomalies,
    analyze_weekly_patterns,
    calculate_personal_baselines,
    analyze_trends,
    load_data
)

# Import sync module (optional — only available if garminconnect is installed)
try:
    from garmin_sync import (
        get_garmin_client,
        sync_latest,
        sync_full,
        sync_date_range,
        get_sync_status,
    )
    from datetime import datetime
    SYNC_AVAILABLE = True
except ImportError:
    SYNC_AVAILABLE = False

# Get the parsed data path
DATA_FILE = Path(__file__).parent / "parsed_health_data.json"

# Track background sync state
_sync_state = {
    "running": False,
    "last_result": None,
    "last_error": None,
}


class CORSRequestHandler(SimpleHTTPRequestHandler):
    """HTTP handler with CORS support for serving health data API"""

    def end_headers(self):
        # Add CORS headers
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        if self.path == '/api/health-data' or self.path == '/api/health-data/':
            self.serve_health_data()
        elif self.path.startswith('/api/health-data/'):
            date = self.path.split('/')[-1]
            self.serve_health_data(date)
        elif self.path == '/api/summary':
            self.serve_summary()
        # ========== ANALYTICS ENDPOINTS ==========
        elif self.path == '/api/analytics' or self.path == '/api/analytics/':
            self.serve_full_analytics()
        elif self.path == '/api/analytics/correlations':
            self.serve_correlation_matrix()
        elif self.path == '/api/analytics/lagged':
            self.serve_lagged_correlations()
        elif self.path == '/api/analytics/anomalies':
            self.serve_anomalies()
        elif self.path == '/api/analytics/weekly':
            self.serve_weekly_patterns()
        elif self.path == '/api/analytics/baselines':
            self.serve_baselines()
        elif self.path == '/api/analytics/trends':
            self.serve_trends()
        # ========== SYNC ENDPOINTS ==========
        elif self.path == '/api/sync/status':
            self.serve_sync_status()
        else:
            self.send_response(404)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            endpoints = [
                "GET  /api/health-data",
                "GET  /api/health-data/YYYY-MM-DD",
                "GET  /api/summary",
                "GET  /api/analytics",
                "GET  /api/analytics/correlations",
                "GET  /api/analytics/lagged",
                "GET  /api/analytics/anomalies",
                "GET  /api/analytics/weekly",
                "GET  /api/analytics/baselines",
                "GET  /api/analytics/trends",
                "GET  /api/sync/status",
                "POST /api/sync/latest",
                "POST /api/sync/full",
                "POST /api/sync/range",
            ]
            self.wfile.write(json.dumps({"error": "Not found", "endpoints": endpoints}).encode())

    def do_POST(self):
        # ========== SYNC TRIGGER ENDPOINTS ==========
        if self.path == '/api/sync/latest':
            self.trigger_sync_latest()
        elif self.path == '/api/sync/full':
            self.trigger_sync_full()
        elif self.path == '/api/sync/range':
            self.trigger_sync_range()
        else:
            self.send_response(404)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Not found"}).encode())

    # ========== HEALTH DATA ENDPOINTS ==========

    def serve_health_data(self, date=None):
        """Serve all health data or specific date"""
        try:
            with open(DATA_FILE, 'r') as f:
                data = json.load(f)

            if date:
                day_data = next((d for d in data if d['date'] == date), None)
                if day_data:
                    response = day_data
                else:
                    self.send_response(404)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": f"No data for {date}"}).encode())
                    return
            else:
                response = data

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response, indent=2).encode())

        except FileNotFoundError:
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Data file not found"}).encode())

    def serve_summary(self):
        """Serve summary statistics"""
        try:
            with open(DATA_FILE, 'r') as f:
                data = json.load(f)

            if data:
                avg_sleep = sum(d['sleep_score'] for d in data if d['sleep_score'] > 0) / len([d for d in data if d['sleep_score'] > 0])
                avg_hrv = sum(d['hrv'] for d in data if d['hrv'] > 0) / len([d for d in data if d['hrv'] > 0])
                avg_stress = sum(d['avg_stress'] for d in data if d['avg_stress'] > 0) / len([d for d in data if d['avg_stress'] > 0])
                avg_steps = sum(d['steps'] for d in data) / len(data)

                summary = {
                    "total_days": len(data),
                    "date_range": {
                        "start": data[-1]['date'],
                        "end": data[0]['date']
                    },
                    "averages": {
                        "sleep_score": round(avg_sleep, 1),
                        "hrv": round(avg_hrv, 1),
                        "stress": round(avg_stress, 1),
                        "steps": round(avg_steps, 0)
                    },
                    "recent_day": data[0]
                }
            else:
                summary = {"error": "No data available"}

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(summary, indent=2).encode())

        except Exception as e:
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())

    # ========== ANALYTICS ENDPOINTS ==========

    def serve_full_analytics(self):
        """Serve complete AI pattern analysis"""
        try:
            results = run_full_analysis()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(results, indent=2).encode())
        except Exception as e:
            self.send_error_response(str(e))

    def serve_correlation_matrix(self):
        """Serve correlation matrix between all metrics"""
        try:
            data = load_data()
            results = calculate_correlation_matrix(data)
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(results, indent=2).encode())
        except Exception as e:
            self.send_error_response(str(e))

    def serve_lagged_correlations(self):
        """Serve time-lagged correlations"""
        try:
            data = load_data()
            results = calculate_lagged_correlations(data)
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(results, indent=2).encode())
        except Exception as e:
            self.send_error_response(str(e))

    def serve_anomalies(self):
        """Serve detected anomalies"""
        try:
            data = load_data()
            results = detect_anomalies(data)
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(results, indent=2).encode())
        except Exception as e:
            self.send_error_response(str(e))

    def serve_weekly_patterns(self):
        """Serve weekly patterns analysis"""
        try:
            data = load_data()
            results = analyze_weekly_patterns(data)
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(results, indent=2).encode())
        except Exception as e:
            self.send_error_response(str(e))

    def serve_baselines(self):
        """Serve personal baselines"""
        try:
            data = load_data()
            results = calculate_personal_baselines(data)
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(results, indent=2).encode())
        except Exception as e:
            self.send_error_response(str(e))

    def serve_trends(self):
        """Serve trend analysis"""
        try:
            data = load_data()
            results = analyze_trends(data)
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(results, indent=2).encode())
        except Exception as e:
            self.send_error_response(str(e))

    # ========== SYNC ENDPOINTS ==========

    def serve_sync_status(self):
        """GET /api/sync/status — current data freshness + sync availability"""
        status = get_sync_status() if SYNC_AVAILABLE else {"status": "unavailable", "message": "garminconnect not installed"}
        status["sync_available"] = SYNC_AVAILABLE
        status["sync_running"] = _sync_state["running"]
        status["last_sync_result"] = _sync_state["last_result"]
        status["last_sync_error"] = _sync_state["last_error"]
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(status, indent=2).encode())

    def trigger_sync_latest(self):
        """POST /api/sync/latest — sync last 7 days in background"""
        if not SYNC_AVAILABLE:
            self.send_error_response("garminconnect not installed. Run: uv sync in backend/")
            return

        # Read optional body: {"days": 7}
        body = self._read_body()
        days = body.get("days", 7) if body else 7

        if _sync_state["running"]:
            self.send_response(409)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Sync already running"}).encode())
            return

        # Run sync in background thread so API stays responsive
        def run():
            _sync_state["running"] = True
            _sync_state["last_error"] = None
            try:
                client = get_garmin_client()
                result = sync_latest(client, days=days)
                _sync_state["last_result"] = result
            except Exception as e:
                _sync_state["last_error"] = str(e)
            finally:
                _sync_state["running"] = False

        threading.Thread(target=run, daemon=True).start()

        self.send_response(202)  # Accepted
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({
            "message": f"Sync started for last {days} days",
            "status_url": "/api/sync/status"
        }).encode())

    def trigger_sync_full(self):
        """POST /api/sync/full — sync all historical data in background"""
        if not SYNC_AVAILABLE:
            self.send_error_response("garminconnect not installed. Run: uv sync in backend/")
            return

        if _sync_state["running"]:
            self.send_response(409)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Sync already running"}).encode())
            return

        def run():
            _sync_state["running"] = True
            _sync_state["last_error"] = None
            try:
                client = get_garmin_client()
                result = sync_full(client)
                _sync_state["last_result"] = result
            except Exception as e:
                _sync_state["last_error"] = str(e)
            finally:
                _sync_state["running"] = False

        threading.Thread(target=run, daemon=True).start()

        self.send_response(202)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({
            "message": "Full historical sync started",
            "status_url": "/api/sync/status"
        }).encode())

    def trigger_sync_range(self):
        """POST /api/sync/range — sync specific date range
        Body: {"start": "YYYY-MM-DD", "end": "YYYY-MM-DD", "overwrite": false}
        """
        if not SYNC_AVAILABLE:
            self.send_error_response("garminconnect not installed. Run: uv sync in backend/")
            return

        body = self._read_body()
        if not body or "start" not in body:
            self.send_response(400)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Body must include 'start' date (YYYY-MM-DD)"}).encode())
            return

        if _sync_state["running"]:
            self.send_response(409)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Sync already running"}).encode())
            return

        start_str = body["start"]
        end_str = body.get("end", datetime.today().strftime("%Y-%m-%d"))
        overwrite = body.get("overwrite", False)

        def run():
            _sync_state["running"] = True
            _sync_state["last_error"] = None
            try:
                client = get_garmin_client()
                start = datetime.strptime(start_str, "%Y-%m-%d").date()
                end = datetime.strptime(end_str, "%Y-%m-%d").date()
                result = sync_date_range(client, start, end, overwrite=overwrite)
                _sync_state["last_result"] = result
            except Exception as e:
                _sync_state["last_error"] = str(e)
            finally:
                _sync_state["running"] = False

        threading.Thread(target=run, daemon=True).start()

        self.send_response(202)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({
            "message": f"Range sync started: {start_str} → {end_str}",
            "status_url": "/api/sync/status"
        }).encode())

    def _read_body(self):
        """Read and parse JSON request body."""
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            if content_length > 0:
                body = self.rfile.read(content_length)
                return json.loads(body.decode('utf-8'))
        except Exception:
            pass
        return {}

    def send_error_response(self, error_msg):
        """Send 500 error response"""
        self.send_response(500)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"error": error_msg}).encode())

    def log_message(self, format, *args):
        """Suppress default request logging (cleaner output)."""
        pass


def run_server(port=8081):
    """Run the API server"""
    server_address = ('0.0.0.0', port)
    httpd = HTTPServer(server_address, CORSRequestHandler)
    print(f"🚀 Health Data API Server running at http://localhost:{port}")
    print(f"\n📊 Data Endpoints:")
    print(f"   GET  /api/health-data              - All health data")
    print(f"   GET  /api/health-data/YYYY-MM-DD   - Specific date")
    print(f"   GET  /api/summary                  - Summary statistics")
    print(f"\n🧠 Analytics Endpoints:")
    print(f"   GET  /api/analytics                - Full AI analysis")
    print(f"   GET  /api/analytics/correlations   - Correlation matrix")
    print(f"   GET  /api/analytics/lagged         - Time-lagged correlations")
    print(f"   GET  /api/analytics/anomalies      - Detected anomalies")
    print(f"   GET  /api/analytics/weekly         - Weekly patterns")
    print(f"   GET  /api/analytics/baselines      - Personal baselines")
    print(f"   GET  /api/analytics/trends         - Trend analysis")
    print(f"\n🔄 Sync Endpoints (requires garminconnect + backend/.env):")
    print(f"   GET  /api/sync/status              - Data freshness & sync state")
    print(f"   POST /api/sync/latest              - Sync last 7 days")
    print(f"   POST /api/sync/full                - Sync all historical data")
    print(f"   POST /api/sync/range               - Sync date range {{start, end}}")
    sync_status = "✅ available" if SYNC_AVAILABLE else "❌ unavailable (run: cd backend && uv sync)"
    print(f"\n   Garmin sync: {sync_status}")
    print(f"\n⏹️  Press Ctrl+C to stop")
    httpd.serve_forever()


if __name__ == "__main__":
    run_server()
