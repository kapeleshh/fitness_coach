import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/health_data.dart';
import '../models/prediction.dart';
import 'mock_data_service.dart';

/// Service to fetch real Garmin data from the API
class RealDataService extends ChangeNotifier {
  static const String _baseUrl = 'http://localhost:8081';
  
  List<DailyHealthData> _healthData = [];
  Map<String, dynamic>? _summary;
  bool _isLoading = false;
  String? _error;
  
  // Getters
  List<DailyHealthData> get healthData => _healthData;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get summary => _summary;
  
  DailyHealthData? get todayData => _healthData.isNotEmpty ? _healthData.first : null;
  DailyHealthData? get yesterdayData => _healthData.length > 1 ? _healthData[1] : null;
  
  HealthScore? get currentHealthScore {
    if (todayData == null) return null;
    return _calculateHealthScore(todayData!);
  }
  
  WorkoutPrediction? get tomorrowPrediction {
    if (_healthData.length < 3) return null;
    return _generatePrediction();
  }
  
  /// Initialize by loading data from API
  Future<void> initialize() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      // Fetch summary first
      await fetchSummary();
      
      // Then fetch all health data
      await fetchAllHealthData();
      
      _isLoading = false;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
    }
    notifyListeners();
  }
  
  /// Fetch summary statistics
  Future<void> fetchSummary() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/summary'));
      if (response.statusCode == 200) {
        _summary = json.decode(response.body);
      }
    } catch (e) {
      debugPrint('Error fetching summary: $e');
    }
  }
  
  /// Fetch all health data from API
  Future<void> fetchAllHealthData() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/health-data'));
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        _healthData = jsonList.map((json) => _parseHealthData(json)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching health data: $e');
      rethrow;
    }
  }
  
  /// Parse JSON to DailyHealthData
  DailyHealthData _parseHealthData(Map<String, dynamic> json) {
    return DailyHealthData(
      date: DateTime.parse(json['date']),
      sleepScore: json['sleep_score'] ?? 0,
      sleepDurationMinutes: (json['deep_sleep_minutes'] ?? 0) + 
                           (json['light_sleep_minutes'] ?? 0) + 
                           (json['rem_sleep_minutes'] ?? 0),
      deepSleepMinutes: json['deep_sleep_minutes'] ?? 0,
      lightSleepMinutes: json['light_sleep_minutes'] ?? 0,
      remSleepMinutes: json['rem_sleep_minutes'] ?? 0,
      awakeDurationMinutes: json['awake_minutes'] ?? 0,
      restingHeartRate: json['resting_hr'] ?? 0,
      averageHeartRate: json['resting_hr'] ?? 0,
      maxHeartRate: json['max_hr'] ?? 0,
      minHeartRate: json['min_hr'] ?? 0,
      hrvAverage: (json['hrv'] ?? 0).toDouble(),
      hrvRmssd: (json['hrv'] ?? 0).toDouble(),
      hrvStatus: _parseHrvStatus(json['hrv_status']),
      bodyBatteryStart: json['body_battery_start'] ?? 0,
      bodyBatteryEnd: json['body_battery_end'] ?? 0,
      bodyBatteryMax: json['body_battery_high'] ?? 0,
      bodyBatteryMin: json['body_battery_low'] ?? 0,
      hourlyBodyBattery: [],
      averageStressLevel: json['avg_stress'] ?? 0,
      maxStressLevel: json['max_stress'] ?? 0,
      lowStressMinutes: json['stress_low_minutes'] ?? 0,
      mediumStressMinutes: json['stress_medium_minutes'] ?? 0,
      highStressMinutes: json['stress_high_minutes'] ?? 0,
      restMinutes: json['stress_rest_minutes'] ?? 0,
      stressEvents: [],
      steps: json['steps'] ?? 0,
      floorsClimbed: json['floors_climbed'] ?? 0,
      activeMinutes: json['active_minutes'] ?? 0,
      activeCalories: json['active_calories'] ?? 0,
      totalCalories: json['total_calories'] ?? 0,
      distanceMeters: (json['distance_meters'] ?? 0).toDouble(),
      averageRespirationRate: (json['avg_respiration'] ?? 0).toDouble(),
      sleepRespirationRate: (json['avg_respiration'] ?? 0).toDouble(),
      workouts: [],
    );
  }
  
  HRVStatus _parseHrvStatus(String? status) {
    switch (status) {
      case 'IN_RANGE': return HRVStatus.good;
      case 'ABOVE': return HRVStatus.excellent;
      case 'BELOW': return HRVStatus.poor;
      default: return HRVStatus.fair;
    }
  }
  
  /// Calculate health score from today's data
  HealthScore _calculateHealthScore(DailyHealthData data) {
    // Weight factors
    double sleepWeight = 0.25;
    double hrvWeight = 0.20;
    double bodyBatteryWeight = 0.20;
    double stressWeight = 0.20;
    double activityWeight = 0.15;
    
    // Normalize scores (0-100)
    double sleepScore = data.sleepScore.toDouble();
    double hrvScore = (data.hrvAverage / 100 * 100).clamp(0, 100);
    double bodyBatteryScore = data.bodyBatteryStart.toDouble();
    double stressScore = (100 - data.averageStressLevel).toDouble();
    double activityScore = (data.steps / 10000 * 100).clamp(0, 100);
    
    int overall = ((sleepScore * sleepWeight) +
                   (hrvScore * hrvWeight) +
                   (bodyBatteryScore * bodyBatteryWeight) +
                   (stressScore * stressWeight) +
                   (activityScore * activityWeight)).round();
    
    return HealthScore(
      overallScore: overall.clamp(0, 100),
      sleepScore: sleepScore.round(),
      stressScore: stressScore.round(),
      recoveryScore: bodyBatteryScore.round(),
      activityScore: activityScore.round(),
      trend: _calculateTrend(),
      insights: _generateInsights(data),
    );
  }
  
  ScoreTrend _calculateTrend() {
    if (_healthData.length < 7) return ScoreTrend.stable;
    
    // Compare last 7 days to previous 7 days
    var recent = _healthData.take(7).map((d) => d.sleepScore).reduce((a, b) => a + b) / 7;
    var previous = _healthData.skip(7).take(7).map((d) => d.sleepScore).reduce((a, b) => a + b) / 7;
    
    if (recent > previous + 5) return ScoreTrend.improving;
    if (recent < previous - 5) return ScoreTrend.declining;
    return ScoreTrend.stable;
  }
  
  List<String> _generateInsights(DailyHealthData data) {
    List<String> insights = [];
    
    if (data.sleepScore < 60) {
      insights.add('Sleep quality was below average');
    }
    if (data.hrvAverage < 50) {
      insights.add('HRV indicates recovery needed');
    }
    if (data.averageStressLevel > 50) {
      insights.add('Higher than usual stress levels');
    }
    if (data.bodyBatteryStart < 30) {
      insights.add('Low energy reserves - consider rest');
    }
    if (data.steps > 10000) {
      insights.add('Great activity level!');
    }
    
    return insights;
  }
  
  WorkoutPrediction _generatePrediction() {
    // Simple prediction based on recent trends
    var recentBattery = _healthData.take(3).map((d) => d.bodyBatteryStart).reduce((a, b) => a + b) / 3;
    var recentHrv = _healthData.take(3).map((d) => d.hrvAverage).reduce((a, b) => a + b) / 3;
    var recentStress = _healthData.take(3).map((d) => d.averageStressLevel).reduce((a, b) => a + b) / 3;
    
    // Calculate optimal workout intensity
    double readinessScore = (recentBattery / 100 * 0.4) + 
                            (recentHrv / 100 * 0.3) + 
                            ((100 - recentStress) / 100 * 0.3);
    
    WorkoutIntensity intensity;
    String recommendation;
    
    if (readinessScore > 0.7) {
      intensity = WorkoutIntensity.high;
      recommendation = 'Your body is well-recovered. Great day for high intensity!';
    } else if (readinessScore > 0.5) {
      intensity = WorkoutIntensity.moderate;
      recommendation = 'Moderate intensity recommended based on your recovery status.';
    } else {
      intensity = WorkoutIntensity.low;
      recommendation = 'Consider light activity or rest. Body Battery and HRV suggest recovery needed.';
    }
    
    return WorkoutPrediction(
      date: DateTime.now().add(const Duration(days: 1)),
      recommendedIntensity: intensity,
      confidence: (readinessScore * 100).round().clamp(50, 95),
      optimalTimeWindow: const TimeOfDay(hour: 7, minute: 0),
      recommendation: recommendation,
      factors: [
        PredictionFactor(
          name: 'Body Battery',
          impact: recentBattery > 50 ? FactorImpact.positive : FactorImpact.negative,
          description: 'Average ${recentBattery.round()}% over last 3 days',
        ),
        PredictionFactor(
          name: 'HRV',
          impact: recentHrv > 50 ? FactorImpact.positive : FactorImpact.negative,
          description: 'Average ${recentHrv.round()}ms',
        ),
        PredictionFactor(
          name: 'Stress',
          impact: recentStress < 40 ? FactorImpact.positive : FactorImpact.negative,
          description: 'Average ${recentStress.round()}',
        ),
      ],
    );
  }
  
  /// Get weekly averages
  Map<String, double> getWeeklyAverages() {
    if (_healthData.isEmpty) return {};
    
    var week = _healthData.take(7).toList();
    return {
      'sleep': week.map((d) => d.sleepScore).reduce((a, b) => a + b) / week.length,
      'hrv': week.map((d) => d.hrvAverage).reduce((a, b) => a + b) / week.length,
      'stress': week.map((d) => d.averageStressLevel).reduce((a, b) => a + b) / week.length,
      'steps': week.map((d) => d.steps).reduce((a, b) => a + b) / week.length,
      'bodyBattery': week.map((d) => d.bodyBatteryStart).reduce((a, b) => a + b) / week.length,
    };
  }
}
