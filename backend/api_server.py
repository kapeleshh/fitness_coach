"""
Simple API Server to serve parsed Garmin health data
Serves the parsed_health_data.json with CORS enabled for Flutter web app
Also serves AI Pattern Analysis from analytics_engine.py
"""

from http.server import HTTPServer, SimpleHTTPRequestHandler
import json
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

# Get the parsed data path
DATA_FILE = Path(__file__).parent / "parsed_health_data.json"

class CORSRequestHandler(SimpleHTTPRequestHandler):
    """HTTP handler with CORS support for serving health data API"""
    
    def end_headers(self):
        # Add CORS headers
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        super().end_headers()
    
    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()
    
    def do_GET(self):
        if self.path == '/api/health-data' or self.path == '/api/health-data/':
            self.serve_health_data()
        elif self.path.startswith('/api/health-data/'):
            # Get specific date
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
        else:
            self.send_response(404)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            endpoints = [
                "/api/health-data",
                "/api/summary",
                "/api/analytics",
                "/api/analytics/correlations",
                "/api/analytics/lagged",
                "/api/analytics/anomalies",
                "/api/analytics/weekly",
                "/api/analytics/baselines",
                "/api/analytics/trends"
            ]
            self.wfile.write(json.dumps({"error": "Not found", "endpoints": endpoints}).encode())
    
    def serve_health_data(self, date=None):
        """Serve all health data or specific date"""
        try:
            with open(DATA_FILE, 'r') as f:
                data = json.load(f)
            
            if date:
                # Find specific date
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
            
            # Calculate summary stats
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
    
    def send_error_response(self, error_msg):
        """Send error response"""
        self.send_response(500)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"error": error_msg}).encode())


def run_server(port=8081):
    """Run the API server"""
    server_address = ('0.0.0.0', port)
    httpd = HTTPServer(server_address, CORSRequestHandler)
    print(f"🚀 Health Data API Server running at http://localhost:{port}")
    print(f"📊 Data Endpoints:")
    print(f"   GET /api/health-data     - All health data (86 days)")
    print(f"   GET /api/health-data/YYYY-MM-DD - Specific date")
    print(f"   GET /api/summary         - Summary statistics")
    print(f"\n🧠 Analytics Endpoints (Phase 4):")
    print(f"   GET /api/analytics       - Full AI analysis")
    print(f"   GET /api/analytics/correlations - Correlation matrix")
    print(f"   GET /api/analytics/lagged   - Time-lagged correlations")
    print(f"   GET /api/analytics/anomalies - Detected anomalies")
    print(f"   GET /api/analytics/weekly   - Weekly patterns")
    print(f"   GET /api/analytics/baselines - Personal baselines")
    print(f"   GET /api/analytics/trends   - Trend analysis")
    print(f"\n⏹️  Press Ctrl+C to stop")
    httpd.serve_forever()


if __name__ == "__main__":
    run_server()
