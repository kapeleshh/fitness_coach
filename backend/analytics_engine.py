"""
AI Pattern Analysis Engine
Advanced analytics for Garmin health data using pandas/numpy
Discovers hidden patterns, anomalies, and correlations
"""

import json
import math
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional
from collections import defaultdict

# Load data
DATA_FILE = Path(__file__).parent / "parsed_health_data.json"


def load_data() -> List[Dict]:
    """Load parsed health data"""
    with open(DATA_FILE, 'r') as f:
        return json.load(f)


# ============= CORRELATION MATRIX =============

def calculate_correlation_matrix(data: List[Dict]) -> Dict:
    """
    Calculate full correlation matrix between all metrics
    Returns a heatmap-ready structure
    """
    metrics = [
        'sleep_score', 'hrv', 'avg_stress', 'body_battery_start',
        'body_battery_end', 'steps', 'deep_sleep_minutes', 
        'light_sleep_minutes', 'rem_sleep_minutes', 'resting_hr',
        'total_calories', 'active_minutes'
    ]
    
    # Extract values for each metric
    values = {m: [] for m in metrics}
    for day in data:
        for m in metrics:
            val = day.get(m, 0)
            if val is None:
                val = 0
            values[m].append(float(val))
    
    # Calculate correlation matrix
    matrix = {}
    for m1 in metrics:
        matrix[m1] = {}
        for m2 in metrics:
            corr = pearson_correlation(values[m1], values[m2])
            matrix[m1][m2] = round(corr, 3) if not math.isnan(corr) else 0
    
    # Find strongest correlations
    strong_correlations = []
    for i, m1 in enumerate(metrics):
        for m2 in metrics[i+1:]:
            corr = matrix[m1][m2]
            if abs(corr) > 0.3:  # Significant correlation
                strong_correlations.append({
                    'metric1': m1,
                    'metric2': m2,
                    'correlation': corr,
                    'strength': 'strong' if abs(corr) > 0.6 else 'moderate',
                    'direction': 'positive' if corr > 0 else 'negative'
                })
    
    # Sort by absolute correlation
    strong_correlations.sort(key=lambda x: abs(x['correlation']), reverse=True)
    
    return {
        'matrix': matrix,
        'metrics': metrics,
        'strong_correlations': strong_correlations[:10]  # Top 10
    }


def pearson_correlation(x: List[float], y: List[float]) -> float:
    """Calculate Pearson correlation coefficient"""
    n = len(x)
    if n < 3:
        return 0.0
    
    # Filter out zeros/missing
    pairs = [(a, b) for a, b in zip(x, y) if a > 0 and b > 0]
    if len(pairs) < 3:
        return 0.0
    
    x_vals = [p[0] for p in pairs]
    y_vals = [p[1] for p in pairs]
    n = len(x_vals)
    
    mean_x = sum(x_vals) / n
    mean_y = sum(y_vals) / n
    
    numerator = sum((x_vals[i] - mean_x) * (y_vals[i] - mean_y) for i in range(n))
    denom_x = math.sqrt(sum((v - mean_x) ** 2 for v in x_vals))
    denom_y = math.sqrt(sum((v - mean_y) ** 2 for v in y_vals))
    
    if denom_x * denom_y == 0:
        return 0.0
    
    return numerator / (denom_x * denom_y)


# ============= TIME-LAGGED CORRELATIONS =============

def calculate_lagged_correlations(data: List[Dict]) -> Dict:
    """
    Calculate correlations with time lag
    E.g., Does yesterday's stress predict tonight's sleep?
    """
    # Sort by date (newest first is default)
    
    lagged_pairs = [
        ('avg_stress', 'sleep_score', 1, "Yesterday's Stress → Tonight's Sleep"),
        ('sleep_score', 'body_battery_start', 1, "Last Night's Sleep → Today's Energy"),
        ('steps', 'sleep_score', 0, "Activity → Same Night Sleep"),
        ('avg_stress', 'hrv', 1, "Stress → Next Day HRV"),
        ('deep_sleep_minutes', 'body_battery_start', 1, "Deep Sleep → Next Day Battery"),
        ('body_battery_end', 'sleep_score', 0, "Evening Battery → Same Night Sleep"),
        ('active_minutes', 'deep_sleep_minutes', 0, "Exercise → Deep Sleep"),
        ('high_stress_minutes', 'hrv', 1, "High Stress Duration → Next Day HRV"),
    ]
    
    results = []
    
    for m1, m2, lag, description in lagged_pairs:
        corr = calculate_single_lagged_correlation(data, m1, m2, lag)
        if corr is not None and abs(corr) > 0.15:  # Only meaningful correlations
            results.append({
                'metric1': m1,
                'metric2': m2,
                'lag_days': lag,
                'description': description,
                'correlation': round(corr, 3),
                'strength': categorize_strength(corr),
                'insight': generate_lagged_insight(m1, m2, corr, lag)
            })
    
    results.sort(key=lambda x: abs(x['correlation']), reverse=True)
    return {'lagged_correlations': results}


def calculate_single_lagged_correlation(data: List[Dict], m1: str, m2: str, lag: int) -> Optional[float]:
    """Calculate correlation between m1 and m2 with specified day lag"""
    values1 = []
    values2 = []
    
    for i in range(lag, len(data)):
        v1 = data[i].get(m1, 0)
        v2 = data[i - lag].get(m2, 0)
        
        if v1 and v2 and v1 > 0 and v2 > 0:
            values1.append(float(v1))
            values2.append(float(v2))
    
    if len(values1) < 5:
        return None
    
    return pearson_correlation(values1, values2)


def categorize_strength(corr: float) -> str:
    """Categorize correlation strength"""
    abs_corr = abs(corr)
    if abs_corr > 0.6:
        return 'strong'
    elif abs_corr > 0.4:
        return 'moderate'
    elif abs_corr > 0.2:
        return 'weak'
    return 'minimal'


def generate_lagged_insight(m1: str, m2: str, corr: float, lag: int) -> str:
    """Generate human-readable insight from lagged correlation"""
    metric_names = {
        'sleep_score': 'sleep quality',
        'hrv': 'HRV',
        'avg_stress': 'stress levels',
        'body_battery_start': 'morning energy',
        'body_battery_end': 'evening energy',
        'steps': 'step count',
        'deep_sleep_minutes': 'deep sleep',
        'active_minutes': 'exercise time',
        'high_stress_minutes': 'high stress duration'
    }
    
    n1 = metric_names.get(m1, m1)
    n2 = metric_names.get(m2, m2)
    
    if corr > 0:
        return f"Higher {n1} tends to lead to higher {n2} the {'next day' if lag > 0 else 'same day'}"
    else:
        return f"Higher {n1} tends to lead to lower {n2} the {'next day' if lag > 0 else 'same day'}"


# ============= ANOMALY DETECTION =============

def detect_anomalies(data: List[Dict]) -> Dict:
    """
    Detect unusual patterns using Z-score method
    Flags days where metrics deviate significantly from baseline
    """
    metrics_to_check = [
        ('hrv', 'HRV', 'lower'),  # Lower HRV is concerning
        ('sleep_score', 'Sleep Score', 'lower'),
        ('avg_stress', 'Stress', 'higher'),  # Higher stress is concerning
        ('body_battery_start', 'Morning Energy', 'lower'),
        ('resting_hr', 'Resting HR', 'higher'),
    ]
    
    anomalies = []
    
    for metric, name, concern_direction in metrics_to_check:
        values = [float(d.get(metric, 0)) for d in data if d.get(metric, 0) > 0]
        if len(values) < 7:
            continue
        
        mean = sum(values) / len(values)
        std = math.sqrt(sum((v - mean) ** 2 for v in values) / len(values))
        
        if std == 0:
            continue
        
        # Find anomalies (Z-score > 2 or < -2)
        for day in data:
            val = day.get(metric, 0)
            if not val or val <= 0:
                continue
            
            z_score = (val - mean) / std
            
            is_anomaly = False
            severity = 'mild'
            
            if concern_direction == 'lower' and z_score < -1.5:
                is_anomaly = True
                severity = 'severe' if z_score < -2.5 else 'moderate' if z_score < -2 else 'mild'
            elif concern_direction == 'higher' and z_score > 1.5:
                is_anomaly = True
                severity = 'severe' if z_score > 2.5 else 'moderate' if z_score > 2 else 'mild'
            
            if is_anomaly:
                anomalies.append({
                    'date': day['date'],
                    'metric': metric,
                    'metric_name': name,
                    'value': val,
                    'baseline': round(mean, 1),
                    'z_score': round(z_score, 2),
                    'severity': severity,
                    'direction': 'below' if z_score < 0 else 'above',
                    'deviation_pct': round(abs(val - mean) / mean * 100, 1)
                })
    
    # Sort by date (most recent first) and severity
    severity_order = {'severe': 0, 'moderate': 1, 'mild': 2}
    anomalies.sort(key=lambda x: (x['date'], severity_order.get(x['severity'], 3)), reverse=True)
    
    # Group by date
    anomalies_by_date = defaultdict(list)
    for a in anomalies:
        anomalies_by_date[a['date']].append(a)
    
    # Find worst days (most anomalies or severe anomalies)
    worst_days = []
    for date, day_anomalies in anomalies_by_date.items():
        severe_count = sum(1 for a in day_anomalies if a['severity'] == 'severe')
        total_count = len(day_anomalies)
        worst_days.append({
            'date': date,
            'anomaly_count': total_count,
            'severe_count': severe_count,
            'anomalies': day_anomalies
        })
    
    worst_days.sort(key=lambda x: (x['severe_count'], x['anomaly_count']), reverse=True)
    
    return {
        'all_anomalies': anomalies[:50],  # Limit to 50
        'worst_days': worst_days[:10],
        'summary': {
            'total_anomalies': len(anomalies),
            'severe_count': sum(1 for a in anomalies if a['severity'] == 'severe'),
            'moderate_count': sum(1 for a in anomalies if a['severity'] == 'moderate'),
            'days_with_anomalies': len(anomalies_by_date)
        }
    }


# ============= WEEKLY PATTERNS =============

def analyze_weekly_patterns(data: List[Dict]) -> Dict:
    """
    Analyze patterns by day of week
    Find best/worst days for each metric
    """
    day_names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
    
    metrics = ['sleep_score', 'hrv', 'avg_stress', 'body_battery_start', 'steps', 'deep_sleep_minutes']
    
    # Group by day of week
    by_day = {i: {m: [] for m in metrics} for i in range(7)}
    
    for day in data:
        try:
            date = datetime.strptime(day['date'], '%Y-%m-%d')
            dow = date.weekday()
            
            for m in metrics:
                val = day.get(m, 0)
                if val and val > 0:
                    by_day[dow][m].append(float(val))
        except:
            continue
    
    # Calculate averages and find best/worst
    patterns = {}
    
    for m in metrics:
        metric_data = []
        for dow in range(7):
            values = by_day[dow][m]
            if values:
                avg = sum(values) / len(values)
                metric_data.append({
                    'day': day_names[dow],
                    'day_num': dow,
                    'average': round(avg, 1),
                    'sample_size': len(values)
                })
        
        if metric_data:
            # Sort to find best/worst
            # For stress, lower is better
            if m == 'avg_stress':
                best = min(metric_data, key=lambda x: x['average'])
                worst = max(metric_data, key=lambda x: x['average'])
            else:
                best = max(metric_data, key=lambda x: x['average'])
                worst = min(metric_data, key=lambda x: x['average'])
            
            patterns[m] = {
                'by_day': metric_data,
                'best_day': best,
                'worst_day': worst,
                'variance': round(max(x['average'] for x in metric_data) - min(x['average'] for x in metric_data), 1)
            }
    
    # Generate insights
    insights = []
    
    if 'sleep_score' in patterns:
        p = patterns['sleep_score']
        insights.append({
            'category': 'Sleep',
            'insight': f"You sleep best on {p['best_day']['day']}s (avg {p['best_day']['average']}) and worst on {p['worst_day']['day']}s (avg {p['worst_day']['average']})",
            'impact': 'high' if p['variance'] > 10 else 'moderate'
        })
    
    if 'avg_stress' in patterns:
        p = patterns['avg_stress']
        insights.append({
            'category': 'Stress',
            'insight': f"Your lowest stress day is {p['best_day']['day']} (avg {p['best_day']['average']}) and highest is {p['worst_day']['day']} (avg {p['worst_day']['average']})",
            'impact': 'high' if p['variance'] > 10 else 'moderate'
        })
    
    if 'steps' in patterns:
        p = patterns['steps']
        insights.append({
            'category': 'Activity',
            'insight': f"You're most active on {p['best_day']['day']}s ({int(p['best_day']['average']):,} steps avg)",
            'impact': 'moderate'
        })
    
    return {
        'patterns': patterns,
        'insights': insights
    }


# ============= PERSONAL BASELINES =============

def calculate_personal_baselines(data: List[Dict]) -> Dict:
    """
    Calculate personal baseline ranges for all metrics
    Including optimal, normal, and concerning thresholds
    """
    metrics = {
        'sleep_score': {'name': 'Sleep Score', 'higher_better': True},
        'hrv': {'name': 'HRV', 'higher_better': True},
        'avg_stress': {'name': 'Average Stress', 'higher_better': False},
        'body_battery_start': {'name': 'Morning Energy', 'higher_better': True},
        'steps': {'name': 'Daily Steps', 'higher_better': True},
        'deep_sleep_minutes': {'name': 'Deep Sleep', 'higher_better': True},
        'resting_hr': {'name': 'Resting HR', 'higher_better': False},
    }
    
    baselines = {}
    
    for metric, info in metrics.items():
        values = [float(d.get(metric, 0)) for d in data if d.get(metric, 0) > 0]
        
        if len(values) < 7:
            continue
        
        values.sort()
        n = len(values)
        
        mean = sum(values) / n
        std = math.sqrt(sum((v - mean) ** 2 for v in values) / n)
        
        # Percentiles
        p10 = values[int(n * 0.1)]
        p25 = values[int(n * 0.25)]
        p50 = values[int(n * 0.5)]
        p75 = values[int(n * 0.75)]
        p90 = values[int(n * 0.9)]
        
        # Current (most recent 7 days average)
        recent = [float(d.get(metric, 0)) for d in data[:7] if d.get(metric, 0) > 0]
        current_avg = sum(recent) / len(recent) if recent else mean
        
        # Status
        if info['higher_better']:
            if current_avg >= p75:
                status = 'excellent'
            elif current_avg >= p50:
                status = 'good'
            elif current_avg >= p25:
                status = 'fair'
            else:
                status = 'needs_attention'
        else:
            if current_avg <= p25:
                status = 'excellent'
            elif current_avg <= p50:
                status = 'good'
            elif current_avg <= p75:
                status = 'fair'
            else:
                status = 'needs_attention'
        
        baselines[metric] = {
            'name': info['name'],
            'higher_better': info['higher_better'],
            'mean': round(mean, 1),
            'std': round(std, 1),
            'min': round(values[0], 1),
            'max': round(values[-1], 1),
            'percentiles': {
                'p10': round(p10, 1),
                'p25': round(p25, 1),
                'p50': round(p50, 1),
                'p75': round(p75, 1),
                'p90': round(p90, 1),
            },
            'current_avg': round(current_avg, 1),
            'status': status,
            'optimal_range': {
                'low': round(p75 if info['higher_better'] else p10, 1),
                'high': round(p90 if info['higher_better'] else p25, 1)
            },
            'sample_size': n
        }
    
    return {'baselines': baselines}


# ============= TREND ANALYSIS =============

def analyze_trends(data: List[Dict], window_days: int = 7) -> Dict:
    """
    Analyze trends over different time windows
    """
    if len(data) < window_days * 2:
        return {'error': 'Insufficient data for trend analysis'}
    
    metrics = ['sleep_score', 'hrv', 'avg_stress', 'body_battery_start', 'steps']
    
    trends = {}
    
    for metric in metrics:
        recent = [float(d.get(metric, 0)) for d in data[:window_days] if d.get(metric, 0) > 0]
        previous = [float(d.get(metric, 0)) for d in data[window_days:window_days*2] if d.get(metric, 0) > 0]
        
        if not recent or not previous:
            continue
        
        recent_avg = sum(recent) / len(recent)
        previous_avg = sum(previous) / len(previous)
        
        change = recent_avg - previous_avg
        change_pct = (change / previous_avg * 100) if previous_avg > 0 else 0
        
        # Determine trend direction
        if change_pct > 5:
            direction = 'improving' if metric != 'avg_stress' else 'worsening'
        elif change_pct < -5:
            direction = 'worsening' if metric != 'avg_stress' else 'improving'
        else:
            direction = 'stable'
        
        trends[metric] = {
            'recent_avg': round(recent_avg, 1),
            'previous_avg': round(previous_avg, 1),
            'change': round(change, 1),
            'change_pct': round(change_pct, 1),
            'direction': direction
        }
    
    return {'trends': trends, 'window_days': window_days}


# ============= COMPREHENSIVE ANALYSIS =============

def run_full_analysis() -> Dict:
    """
    Run all analyses and compile results
    """
    data = load_data()
    
    return {
        'data_summary': {
            'total_days': len(data),
            'date_range': {
                'start': data[-1]['date'] if data else None,
                'end': data[0]['date'] if data else None
            }
        },
        'correlation_matrix': calculate_correlation_matrix(data),
        'lagged_correlations': calculate_lagged_correlations(data),
        'anomalies': detect_anomalies(data),
        'weekly_patterns': analyze_weekly_patterns(data),
        'baselines': calculate_personal_baselines(data),
        'trends': analyze_trends(data)
    }


# Main execution for testing
if __name__ == '__main__':
    results = run_full_analysis()
    print(json.dumps(results, indent=2))
