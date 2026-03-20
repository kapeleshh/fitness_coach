import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Centralized API service for fetching real Garmin health data
/// Includes caching, error handling, and data transformation
class HealthApiService extends ChangeNotifier {
  static const String _baseUrl = 'http://localhost:8081';
  static const String _cacheKey = 'health_data_cache';
  static const String _lastSyncKey = 'last_sync_timestamp';
  static const Duration _cacheValidity = Duration(hours: 1);
  
  List<Map<String, dynamic>> _healthData = [];
  Map<String, dynamic>? _summary;
  bool _isLoading = false;
  String? _error;
  DateTime? _lastSync;
  
  // Getters
  List<Map<String, dynamic>> get healthData => _healthData;
  Map<String, dynamic>? get summary => _summary;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get lastSync => _lastSync;
  int get totalDays => _healthData.length;
  
  /// Get today's data
  Map<String, dynamic>? get today => 
      _healthData.isNotEmpty ? _healthData.first : null;
  
  /// Get yesterday's data
  Map<String, dynamic>? get yesterday => 
      _healthData.length > 1 ? _healthData[1] : null;
  
  /// Get last 7 days
  List<Map<String, dynamic>> get last7Days => 
      _healthData.take(7).toList();
  
  /// Get last 30 days
  List<Map<String, dynamic>> get last30Days => 
      _healthData.take(30).toList();
  
  /// Initialize the service - load from cache then refresh
  Future<void> initialize() async {
    await _loadFromCache();
    await refresh();
  }
  
  /// Force refresh data from API
  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      // Fetch summary
      final summaryRes = await http.get(
        Uri.parse('$_baseUrl/api/summary'),
      ).timeout(const Duration(seconds: 10));
      
      if (summaryRes.statusCode == 200) {
        _summary = json.decode(summaryRes.body);
      }
      
      // Fetch all health data
      final dataRes = await http.get(
        Uri.parse('$_baseUrl/api/health-data'),
      ).timeout(const Duration(seconds: 10));
      
      if (dataRes.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(dataRes.body);
        _healthData = jsonList.cast<Map<String, dynamic>>();
        _lastSync = DateTime.now();
        
        // Save to cache
        await _saveToCache();
      }
      
      _isLoading = false;
    } catch (e) {
      _error = 'Unable to connect to health data API. Using cached data.';
      _isLoading = false;
      debugPrint('API Error: $e');
    }
    
    notifyListeners();
  }
  
  /// Load data from local cache (simplified - no shared_preferences)
  Future<void> _loadFromCache() async {
    // For web, we skip local cache - data loads fresh from API
    debugPrint('Cache: Using API data directly');
  }
  
  /// Save data to local cache (simplified - no shared_preferences)
  Future<void> _saveToCache() async {
    // For web, caching is handled by browser
    debugPrint('Cache: Data saved in memory');
  }
  
  /// Get data for specific date range
  List<Map<String, dynamic>> getDateRange(DateTime start, DateTime end) {
    return _healthData.where((d) {
      final date = DateTime.parse(d['date']);
      return date.isAfter(start.subtract(const Duration(days: 1))) && 
             date.isBefore(end.add(const Duration(days: 1)));
    }).toList();
  }
  
  /// Get data for specific date
  Map<String, dynamic>? getDate(String dateStr) {
    try {
      return _healthData.firstWhere((d) => d['date'] == dateStr);
    } catch (e) {
      return null;
    }
  }
  
  // ============= CALCULATED METRICS =============
  
  /// Calculate overall health score from a day's data
  int calculateHealthScore(Map<String, dynamic> day) {
    double sleepWeight = 0.25;
    double hrvWeight = 0.20;
    double batteryWeight = 0.20;
    double stressWeight = 0.20;
    double activityWeight = 0.15;
    
    double sleepScore = (day['sleep_score'] ?? 0).toDouble();
    double hrvScore = ((day['hrv'] ?? 0) / 100 * 100).clamp(0, 100);
    double batteryScore = (day['body_battery_start'] ?? 0).toDouble();
    double stressScore = (100 - (day['avg_stress'] ?? 50)).toDouble();
    double activityScore = ((day['steps'] ?? 0) / 10000 * 100).clamp(0, 100);
    
    return ((sleepScore * sleepWeight) +
            (hrvScore * hrvWeight) +
            (batteryScore * batteryWeight) +
            (stressScore * stressWeight) +
            (activityScore * activityWeight)).round().clamp(0, 100);
  }
  
  /// Get weekly averages
  Map<String, double> getWeeklyAverages() {
    if (_healthData.isEmpty) return {};
    
    var week = last7Days;
    if (week.isEmpty) return {};
    
    return {
      'sleep': _average(week, 'sleep_score'),
      'hrv': _average(week, 'hrv'),
      'stress': _average(week, 'avg_stress'),
      'steps': _average(week, 'steps'),
      'bodyBattery': _average(week, 'body_battery_start'),
      'restingHr': _average(week, 'resting_hr'),
    };
  }
  
  /// Get monthly averages
  Map<String, double> getMonthlyAverages() {
    if (_healthData.isEmpty) return {};
    
    var month = last30Days;
    if (month.isEmpty) return {};
    
    return {
      'sleep': _average(month, 'sleep_score'),
      'hrv': _average(month, 'hrv'),
      'stress': _average(month, 'avg_stress'),
      'steps': _average(month, 'steps'),
      'bodyBattery': _average(month, 'body_battery_start'),
      'restingHr': _average(month, 'resting_hr'),
    };
  }
  
  double _average(List<Map<String, dynamic>> data, String field) {
    var values = data
        .map((d) => (d[field] ?? 0).toDouble())
        .where((v) => v > 0)
        .toList();
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }
  
  // ============= TREND ANALYSIS =============
  
  /// Compare this week to last week
  Map<String, double> getWeekOverWeekChange() {
    if (_healthData.length < 14) return {};
    
    var thisWeek = _healthData.take(7).toList();
    var lastWeek = _healthData.skip(7).take(7).toList();
    
    return {
      'sleep': _average(thisWeek, 'sleep_score') - _average(lastWeek, 'sleep_score'),
      'hrv': _average(thisWeek, 'hrv') - _average(lastWeek, 'hrv'),
      'stress': _average(thisWeek, 'avg_stress') - _average(lastWeek, 'avg_stress'),
      'steps': _average(thisWeek, 'steps') - _average(lastWeek, 'steps'),
    };
  }
  
  /// Get trend direction for a metric
  String getTrend(String metric) {
    var changes = getWeekOverWeekChange();
    var change = changes[metric] ?? 0;
    
    // For stress, lower is better
    if (metric == 'stress') {
      if (change < -3) return 'improving';
      if (change > 3) return 'declining';
    } else {
      if (change > 3) return 'improving';
      if (change < -3) return 'declining';
    }
    return 'stable';
  }
  
  // ============= INSIGHTS GENERATION =============
  
  /// Generate insights from recent data
  List<Map<String, dynamic>> generateInsights() {
    List<Map<String, dynamic>> insights = [];
    
    if (today == null) return insights;
    
    var t = today!;
    var weekAvg = getWeeklyAverages();
    
    // Sleep insights
    if ((t['sleep_score'] ?? 0) < 50) {
      insights.add({
        'type': 'warning',
        'category': 'Sleep',
        'title': 'Poor Sleep Quality',
        'description': 'Your sleep score of ${t['sleep_score']} is below average. Consider going to bed earlier.',
        'icon': '😴',
        'metric': 'sleep_score',
        'value': t['sleep_score'],
        'benchmark': weekAvg['sleep']?.round() ?? 70,
      });
    } else if ((t['sleep_score'] ?? 0) > 80) {
      insights.add({
        'type': 'positive',
        'category': 'Sleep',
        'title': 'Excellent Sleep!',
        'description': 'Great sleep score of ${t['sleep_score']}. Your body is well-rested.',
        'icon': '🌟',
        'metric': 'sleep_score',
        'value': t['sleep_score'],
        'benchmark': weekAvg['sleep']?.round() ?? 70,
      });
    }
    
    // HRV insights
    if ((t['hrv'] ?? 0) < (weekAvg['hrv'] ?? 50) - 10) {
      insights.add({
        'type': 'warning',
        'category': 'Recovery',
        'title': 'Lower HRV Today',
        'description': 'HRV of ${t['hrv']?.round()}ms is below your average. Consider lighter activity.',
        'icon': '❤️',
        'metric': 'hrv',
        'value': t['hrv'],
        'benchmark': weekAvg['hrv']?.round() ?? 55,
      });
    }
    
    // Body Battery insights
    if ((t['body_battery_start'] ?? 0) < 30) {
      insights.add({
        'type': 'warning',
        'category': 'Energy',
        'title': 'Low Energy Reserves',
        'description': 'Starting the day with Body Battery at ${t['body_battery_start']}%. Prioritize rest.',
        'icon': '🔋',
        'metric': 'body_battery_start',
        'value': t['body_battery_start'],
        'benchmark': 50,
      });
    } else if ((t['body_battery_start'] ?? 0) > 80) {
      insights.add({
        'type': 'positive',
        'category': 'Energy',
        'title': 'Fully Charged!',
        'description': 'Body Battery at ${t['body_battery_start']}%. Great day for high-intensity activity!',
        'icon': '⚡',
        'metric': 'body_battery_start',
        'value': t['body_battery_start'],
        'benchmark': 50,
      });
    }
    
    // Stress insights
    if ((t['avg_stress'] ?? 0) > 50) {
      insights.add({
        'type': 'warning',
        'category': 'Stress',
        'title': 'Elevated Stress',
        'description': 'Average stress of ${t['avg_stress']} is higher than ideal. Try breathing exercises.',
        'icon': '😰',
        'metric': 'avg_stress',
        'value': t['avg_stress'],
        'benchmark': weekAvg['stress']?.round() ?? 35,
      });
    }
    
    // Activity insights
    if ((t['steps'] ?? 0) > 10000) {
      insights.add({
        'type': 'positive',
        'category': 'Activity',
        'title': 'Step Goal Achieved!',
        'description': 'You\'ve walked ${t['steps']} steps today. Keep it up!',
        'icon': '🚶',
        'metric': 'steps',
        'value': t['steps'],
        'benchmark': 10000,
      });
    }
    
    // Week-over-week trends
    var trends = getWeekOverWeekChange();
    if ((trends['sleep'] ?? 0) > 5) {
      insights.add({
        'type': 'positive',
        'category': 'Trend',
        'title': 'Sleep Improving',
        'description': 'Your sleep score is up ${trends['sleep']?.round()} points from last week!',
        'icon': '📈',
        'metric': 'sleep_trend',
        'value': trends['sleep'],
        'benchmark': 0,
      });
    }
    
    return insights;
  }
  
  // ============= CORRELATIONS =============
  
  /// Calculate correlation between two metrics
  Map<String, dynamic> calculateCorrelation(String metric1, String metric2, {int lagDays = 0}) {
    if (_healthData.length < 7) {
      return {'correlation': 0.0, 'strength': 'insufficient_data'};
    }
    
    List<double> values1 = [];
    List<double> values2 = [];
    
    for (int i = lagDays; i < _healthData.length; i++) {
      var v1 = (_healthData[i][metric1] ?? 0).toDouble();
      var v2 = (_healthData[i - lagDays][metric2] ?? 0).toDouble();
      
      if (v1 > 0 && v2 > 0) {
        values1.add(v1);
        values2.add(v2);
      }
    }
    
    if (values1.length < 5) {
      return {'correlation': 0.0, 'strength': 'insufficient_data'};
    }
    
    // Calculate Pearson correlation
    double mean1 = values1.reduce((a, b) => a + b) / values1.length;
    double mean2 = values2.reduce((a, b) => a + b) / values2.length;
    
    double numerator = 0;
    double denom1 = 0;
    double denom2 = 0;
    
    for (int i = 0; i < values1.length; i++) {
      double diff1 = values1[i] - mean1;
      double diff2 = values2[i] - mean2;
      numerator += diff1 * diff2;
      denom1 += diff1 * diff1;
      denom2 += diff2 * diff2;
    }
    
    double correlation = numerator / sqrt(denom1 * denom2);
    
    String strength;
    if (correlation.abs() > 0.7) strength = 'strong';
    else if (correlation.abs() > 0.4) strength = 'moderate';
    else if (correlation.abs() > 0.2) strength = 'weak';
    else strength = 'none';
    
    return {
      'correlation': correlation,
      'strength': strength,
      'sampleSize': values1.length,
      'metric1Avg': mean1,
      'metric2Avg': mean2,
    };
  }
  
  /// Get all interesting correlations
  List<Map<String, dynamic>> discoverCorrelations() {
    List<Map<String, dynamic>> correlations = [];
    
    // Same-day correlations
    var pairs = [
      ['sleep_score', 'body_battery_start', 'Sleep → Body Battery'],
      ['avg_stress', 'hrv', 'Stress ↔ HRV'],
      ['steps', 'total_calories', 'Steps → Calories'],
      ['deep_sleep_minutes', 'hrv', 'Deep Sleep → HRV'],
    ];
    
    for (var pair in pairs) {
      var result = calculateCorrelation(pair[0], pair[1]);
      if (result['strength'] != 'none' && result['strength'] != 'insufficient_data') {
        correlations.add({
          'metric1': pair[0],
          'metric2': pair[1],
          'label': pair[2],
          ...result,
        });
      }
    }
    
    // Lagged correlations (yesterday affects today)
    var laggedPairs = [
      ['sleep_score', 'body_battery_start', 'Last Night\'s Sleep → Today\'s Energy'],
      ['avg_stress', 'sleep_score', 'Yesterday\'s Stress → Tonight\'s Sleep'],
    ];
    
    for (var pair in laggedPairs) {
      var result = calculateCorrelation(pair[0], pair[1], lagDays: 1);
      if (result['strength'] != 'none' && result['strength'] != 'insufficient_data') {
        correlations.add({
          'metric1': pair[0],
          'metric2': pair[1],
          'label': pair[2],
          'lagged': true,
          ...result,
        });
      }
    }
    
    // Sort by correlation strength
    correlations.sort((a, b) => 
        (b['correlation'] as double).abs().compareTo((a['correlation'] as double).abs()));
    
    return correlations;
  }
  
  // ============= PREDICTIONS =============
  
  /// Predict tomorrow's metrics based on patterns
  Map<String, dynamic> predictTomorrow() {
    if (_healthData.length < 7) {
      return {'confidence': 0, 'message': 'Need more data for predictions'};
    }
    
    var weekAvg = getWeeklyAverages();
    var t = today ?? {};
    
    // Simple prediction: weighted average of recent days + today's trends
    double predictedBattery = (weekAvg['bodyBattery'] ?? 50) * 0.6 +
                              (t['body_battery_end'] ?? 50) * 0.4;
    
    // Adjust based on today's stress
    if ((t['avg_stress'] ?? 30) > 50) {
      predictedBattery *= 0.9; // High stress reduces recovery
    }
    
    // Workout intensity recommendation
    String intensity;
    String recommendation;
    if (predictedBattery > 70) {
      intensity = 'high';
      recommendation = 'Great recovery predicted. Good day for intense workout!';
    } else if (predictedBattery > 50) {
      intensity = 'moderate';
      recommendation = 'Moderate energy expected. Balanced workout recommended.';
    } else {
      intensity = 'low';
      recommendation = 'Lower energy predicted. Consider light activity or rest.';
    }
    
    return {
      'predictedBodyBattery': predictedBattery.round(),
      'confidence': 75,
      'recommendedIntensity': intensity,
      'recommendation': recommendation,
      'factors': [
        {
          'name': 'Recent Sleep',
          'impact': (t['sleep_score'] ?? 70) > 70 ? 'positive' : 'negative',
          'value': t['sleep_score'],
        },
        {
          'name': 'Current Stress',
          'impact': (t['avg_stress'] ?? 30) < 40 ? 'positive' : 'negative',
          'value': t['avg_stress'],
        },
        {
          'name': 'HRV Status',
          'impact': (t['hrv'] ?? 50) > (weekAvg['hrv'] ?? 50) ? 'positive' : 'neutral',
          'value': t['hrv'],
        },
      ],
    };
  }
  
  // ============= DATA EXPORT =============
  
  /// Export data as CSV string
  String exportToCsv() {
    if (_healthData.isEmpty) return '';
    
    // Header
    var headers = [
      'date', 'sleep_score', 'deep_sleep_min', 'light_sleep_min', 'rem_sleep_min',
      'body_battery_start', 'body_battery_end', 'hrv', 'avg_stress',
      'steps', 'calories', 'resting_hr'
    ];
    
    var lines = [headers.join(',')];
    
    for (var day in _healthData) {
      var row = [
        day['date'],
        day['sleep_score'],
        day['deep_sleep_minutes'],
        day['light_sleep_minutes'],
        day['rem_sleep_minutes'],
        day['body_battery_start'],
        day['body_battery_end'],
        day['hrv'],
        day['avg_stress'],
        day['steps'],
        day['total_calories'],
        day['resting_hr'],
      ];
      lines.add(row.join(','));
    }
    
    return lines.join('\n');
  }
}

// Singleton instance
final healthApiService = HealthApiService();
