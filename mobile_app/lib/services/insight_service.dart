import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/insight.dart';
import '../models/health_data.dart';
import '../models/prediction.dart';
import 'mock_data_service.dart';

/// Service that generates AI-powered insights from health data
class InsightService extends ChangeNotifier {
  final _uuid = const Uuid();
  
  List<Insight> _insights = [];
  List<Correlation> _correlations = [];
  bool _isLoading = false;

  // Getters
  List<Insight> get insights => _insights.where((i) => !i.isDismissed && i.isValid).toList();
  List<Insight> get alerts => insights.where((i) => i.type == InsightType.alert).toList();
  List<Insight> get discoveries => insights.where((i) => i.type == InsightType.discovery).toList();
  List<Insight> get predictions => insights.where((i) => i.type == InsightType.prediction).toList();
  List<Correlation> get correlations => _correlations;
  bool get isLoading => _isLoading;

  /// Update insights based on new data
  void updateWithData(MockDataService dataService) {
    if (dataService.isLoading || dataService.healthData.isEmpty) return;
    
    _isLoading = true;
    notifyListeners();

    // Generate insights
    _insights = _generateInsights(dataService);
    _correlations = _generateCorrelations(dataService);

    _isLoading = false;
    notifyListeners();
  }

  /// Generate all types of insights
  List<Insight> _generateInsights(MockDataService dataService) {
    final insights = <Insight>[];
    final now = DateTime.now();
    final todayData = dataService.todayData;
    final yesterdayData = dataService.yesterdayData;
    final healthScore = dataService.currentHealthScore;
    final prediction = dataService.tomorrowPrediction;
    final riskAssessment = dataService.riskAssessment;

    // 1. Health Risk Alerts
    if (riskAssessment != null && riskAssessment.overallRisk != RiskLevel.low) {
      insights.add(_createHealthRiskAlert(riskAssessment, now));
    }

    // 2. HRV Decline Alert
    final hrvTrend = _calculateHRVTrend(dataService.getLastNDays(7));
    if (hrvTrend < -12) {
      insights.add(Insight(
        id: _uuid.v4(),
        type: InsightType.alert,
        priority: InsightPriority.high,
        category: InsightCategory.heart,
        title: 'HRV Declining',
        message: 'Your HRV has dropped ${hrvTrend.abs().toStringAsFixed(0)}% over the past week. Last time this happened, you got sick 2 days later. Consider rest.',
        detailedExplanation: 'Heart Rate Variability (HRV) is a key indicator of your nervous system health. A declining trend often precedes illness or overtraining.',
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 24)),
        primaryAction: InsightAction(label: 'Got it', actionType: 'dismiss'),
        secondaryAction: InsightAction(label: 'Learn more', actionType: 'navigate', route: '/hrv-details'),
        dataContext: {'hrvTrend': hrvTrend},
        relatedMetrics: ['HRV', 'Resting HR', 'Sleep'],
      ));
    }

    // 3. Sleep Pattern Discovery (Late workout impact)
    final lateWorkoutSleepImpact = _analyzeLateWorkoutSleepImpact(dataService.getLastNDays(14));
    if (lateWorkoutSleepImpact != null && lateWorkoutSleepImpact['impact']! < -10) {
      insights.add(Insight(
        id: _uuid.v4(),
        type: InsightType.discovery,
        priority: InsightPriority.medium,
        category: InsightCategory.sleep,
        title: 'Late Workouts Affect Your Sleep',
        message: 'Your deep sleep is ${lateWorkoutSleepImpact['impact']!.abs().toStringAsFixed(0)}% lower on days you exercise after 8 PM compared to morning workouts.',
        detailedExplanation: 'Exercise raises your core body temperature and cortisol levels. Working out late can interfere with your body\'s natural wind-down process.',
        createdAt: now.subtract(const Duration(hours: 2)),
        primaryAction: InsightAction(label: 'View Analysis', actionType: 'navigate', route: '/correlations'),
        dataContext: lateWorkoutSleepImpact,
        relatedMetrics: ['Sleep Score', 'Deep Sleep', 'Workout Time'],
      ));
    }

    // 4. Stress Trigger Detection (Tuesday meetings)
    final stressTriggers = _analyzeStressTriggers(dataService.getLastNDays(21));
    for (final trigger in stressTriggers) {
      insights.add(Insight(
        id: _uuid.v4(),
        type: InsightType.discovery,
        priority: InsightPriority.medium,
        category: InsightCategory.stress,
        title: 'Stress Pattern Detected',
        message: trigger['message'] as String,
        detailedExplanation: 'Your body consistently shows elevated stress during this time period. Understanding your triggers helps you prepare.',
        createdAt: now.subtract(const Duration(hours: 1)),
        primaryAction: InsightAction(label: 'Add to Calendar', actionType: 'calendar'),
        secondaryAction: InsightAction(label: 'Try Breathing', actionType: 'navigate', route: '/breathing'),
        dataContext: trigger,
        relatedMetrics: ['Stress Level', 'HRV'],
      ));
    }

    // 5. Tomorrow's Prediction
    if (prediction != null) {
      final window = prediction.optimalWorkoutWindow;
      insights.add(Insight(
        id: _uuid.v4(),
        type: InsightType.prediction,
        priority: InsightPriority.medium,
        category: InsightCategory.energy,
        title: 'Tomorrow\'s Best Workout Time',
        message: 'Based on your sleep last night, your Body Battery will peak at ${prediction.predictedPeak} around ${prediction.predictedPeakHour}:00. Best workout window: ${window.timeRange}',
        detailedExplanation: window.recommendation,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 18)),
        primaryAction: InsightAction(label: 'Set Reminder', actionType: 'reminder'),
        dataContext: {
          'peakEnergy': prediction.predictedPeak,
          'peakHour': prediction.predictedPeakHour,
          'windowStart': window.startHour,
          'windowEnd': window.endHour,
        },
        relatedMetrics: ['Body Battery', 'Sleep Score'],
      ));
    }

    // 6. Workout Recommendation based on today's data
    if (todayData != null) {
      final recommendation = _generateWorkoutRecommendation(todayData);
      insights.add(Insight(
        id: _uuid.v4(),
        type: InsightType.recommendation,
        priority: InsightPriority.low,
        category: InsightCategory.training,
        title: recommendation['title'] as String,
        message: recommendation['message'] as String,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 12)),
        primaryAction: InsightAction(label: 'Got it', actionType: 'dismiss'),
        dataContext: recommendation,
        relatedMetrics: ['Body Battery', 'Recovery Time', 'HRV'],
      ));
    }

    // 7. Achievement - Sleep improvement
    final sleepTrend = _calculateMetricTrend(
      dataService.getLastNDays(14),
      (d) => d.sleepScore.toDouble(),
    );
    if (sleepTrend > 10) {
      insights.add(Insight(
        id: _uuid.v4(),
        type: InsightType.achievement,
        priority: InsightPriority.low,
        category: InsightCategory.sleep,
        title: 'Sleep Improving! 🎉',
        message: 'Your sleep quality has improved ${sleepTrend.toStringAsFixed(0)}% over the past 2 weeks. Great job maintaining good habits!',
        createdAt: now.subtract(const Duration(hours: 6)),
        primaryAction: InsightAction(label: 'View Trends', actionType: 'navigate', route: '/trends'),
        dataContext: {'sleepTrend': sleepTrend},
        relatedMetrics: ['Sleep Score'],
      ));
    }

    // 8. Experiment Insight (simulated)
    insights.add(Insight(
      id: _uuid.v4(),
      type: InsightType.experiment,
      priority: InsightPriority.medium,
      category: InsightCategory.sleep,
      title: 'Experiment Update',
      message: 'Your "Sleep 30 min earlier" experiment is showing positive results! Deep sleep has increased 12% so far.',
      detailedExplanation: 'After 5 days of going to bed 30 minutes earlier, your data shows measurable improvements in deep sleep duration.',
      createdAt: now.subtract(const Duration(hours: 3)),
      primaryAction: InsightAction(label: 'View Details', actionType: 'navigate', route: '/experiments'),
      dataContext: {'experimentId': 'sleep-earlier-001', 'daysCompleted': 5, 'improvement': 12},
      relatedMetrics: ['Deep Sleep', 'Sleep Score'],
    ));

    // Sort by priority and time
    insights.sort((a, b) {
      final priorityCompare = a.priority.index.compareTo(b.priority.index);
      if (priorityCompare != 0) return priorityCompare;
      return b.createdAt.compareTo(a.createdAt);
    });

    return insights;
  }

  /// Generate correlations from data
  List<Correlation> _generateCorrelations(MockDataService dataService) {
    final now = DateTime.now();
    
    return [
      // Sleep Quality Correlations
      Correlation(
        id: _uuid.v4(),
        primaryMetric: 'Sleep Quality',
        secondaryMetric: 'Exercise before 6 PM',
        correlationStrength: 0.32,
        description: 'Working out before 6 PM is associated with 32% better sleep quality',
        dataPointsAnalyzed: 21,
        lastUpdated: now,
      ),
      Correlation(
        id: _uuid.v4(),
        primaryMetric: 'Sleep Quality',
        secondaryMetric: '8,000+ daily steps',
        correlationStrength: 0.18,
        description: 'Days with 8,000+ steps show 18% better sleep',
        dataPointsAnalyzed: 21,
        lastUpdated: now,
      ),
      Correlation(
        id: _uuid.v4(),
        primaryMetric: 'Sleep Quality',
        secondaryMetric: 'Late workouts (after 8 PM)',
        correlationStrength: -0.23,
        description: 'Evening workouts correlate with 23% worse sleep quality',
        dataPointsAnalyzed: 14,
        lastUpdated: now,
      ),
      
      // Stress Correlations
      Correlation(
        id: _uuid.v4(),
        primaryMetric: 'Stress Level',
        secondaryMetric: 'Poor sleep (<60 score)',
        correlationStrength: 0.45,
        description: 'Poor sleep nights lead to 45% higher stress next day',
        dataPointsAnalyzed: 28,
        lastUpdated: now,
      ),
      Correlation(
        id: _uuid.v4(),
        primaryMetric: 'Stress Level',
        secondaryMetric: 'Morning exercise',
        correlationStrength: -0.25,
        description: 'Morning workouts reduce daily stress by 25%',
        dataPointsAnalyzed: 18,
        lastUpdated: now,
      ),
      
      // Energy Correlations
      Correlation(
        id: _uuid.v4(),
        primaryMetric: 'Body Battery',
        secondaryMetric: 'Sleep score',
        correlationStrength: 0.65,
        description: 'Good sleep strongly predicts higher energy next day',
        dataPointsAnalyzed: 30,
        lastUpdated: now,
      ),
      Correlation(
        id: _uuid.v4(),
        primaryMetric: 'Body Battery',
        secondaryMetric: 'Previous day high stress',
        correlationStrength: -0.38,
        description: 'High stress days drain more battery overnight',
        dataPointsAnalyzed: 25,
        lastUpdated: now,
      ),
    ];
  }

  /// Create health risk alert insight
  Insight _createHealthRiskAlert(HealthRiskAssessment risk, DateTime now) {
    return Insight(
      id: _uuid.v4(),
      type: InsightType.alert,
      priority: risk.overallRisk == RiskLevel.high 
          ? InsightPriority.critical 
          : InsightPriority.high,
      category: InsightCategory.overall,
      title: 'Health Check',
      message: risk.summary,
      detailedExplanation: risk.recommendations.join('\n• '),
      createdAt: now,
      primaryAction: InsightAction(label: 'View Details', actionType: 'navigate', route: '/health-risk'),
      dataContext: {'riskLevel': risk.overallRisk.name},
      relatedMetrics: risk.riskFactors.map((f) => f.metric).toList(),
    );
  }

  /// Calculate HRV trend over days
  double _calculateHRVTrend(List<DailyHealthData> data) {
    if (data.length < 6) return 0;
    
    final recent = data.take(3).map((d) => d.hrvAverage).reduce((a, b) => a + b) / 3;
    final earlier = data.skip(3).take(3).map((d) => d.hrvAverage).reduce((a, b) => a + b) / 3;
    
    return ((recent - earlier) / earlier) * 100;
  }

  /// Analyze impact of late workouts on sleep
  Map<String, double>? _analyzeLateWorkoutSleepImpact(List<DailyHealthData> data) {
    final lateWorkoutDays = <DailyHealthData>[];
    final earlyWorkoutDays = <DailyHealthData>[];
    
    for (final day in data) {
      for (final workout in day.workouts) {
        if (workout.startTime.hour >= 20) {
          lateWorkoutDays.add(day);
        } else if (workout.startTime.hour < 12) {
          earlyWorkoutDays.add(day);
        }
      }
    }
    
    if (lateWorkoutDays.isEmpty || earlyWorkoutDays.isEmpty) return null;
    
    final lateSleepAvg = lateWorkoutDays.map((d) => d.sleepScore).reduce((a, b) => a + b) / lateWorkoutDays.length;
    final earlySleepAvg = earlyWorkoutDays.map((d) => d.sleepScore).reduce((a, b) => a + b) / earlyWorkoutDays.length;
    
    final impact = ((lateSleepAvg - earlySleepAvg) / earlySleepAvg) * 100;
    
    return {
      'impact': impact,
      'lateAvg': lateSleepAvg,
      'earlyAvg': earlySleepAvg,
      'dataPoints': (lateWorkoutDays.length + earlyWorkoutDays.length).toDouble(),
    };
  }

  /// Analyze recurring stress triggers
  List<Map<String, dynamic>> _analyzeStressTriggers(List<DailyHealthData> data) {
    final triggers = <Map<String, dynamic>>[];
    
    // Check for Tuesday pattern
    final tuesdays = data.where((d) => d.date.weekday == DateTime.tuesday).toList();
    if (tuesdays.isNotEmpty) {
      final tuesdayStress = tuesdays.map((d) => d.averageStressLevel).reduce((a, b) => a + b) / tuesdays.length;
      final otherDaysStress = data.where((d) => d.date.weekday != DateTime.tuesday)
          .map((d) => d.averageStressLevel)
          .reduce((a, b) => a + b) / (data.length - tuesdays.length);
      
      if (tuesdayStress > otherDaysStress * 1.3) {
        triggers.add({
          'dayOfWeek': 'Tuesday',
          'timeRange': '2-3 PM',
          'stressIncrease': ((tuesdayStress - otherDaysStress) / otherDaysStress * 100).round(),
          'message': 'Your stress spikes 45% every Tuesday 2-3 PM. This correlates with your weekly team sync. Try 5-min breathing before the meeting.',
          'suggestion': 'breathing_exercise',
        });
      }
    }
    
    return triggers;
  }

  /// Generate workout recommendation
  Map<String, dynamic> _generateWorkoutRecommendation(DailyHealthData today) {
    final bodyBattery = today.bodyBatteryStart;
    final hrv = today.hrvAverage;
    final recoveryHours = today.recoveryTimeHours ?? 0;
    
    if (recoveryHours > 24 || bodyBattery < 40 || hrv < 35) {
      return {
        'title': 'Rest Day Recommended',
        'message': 'Your body is still recovering. Consider light activity like walking or yoga today.',
        'intensity': 'light',
        'reason': 'recovery_needed',
      };
    } else if (bodyBattery >= 70 && hrv >= 50) {
      return {
        'title': 'Great Day for Intense Training!',
        'message': 'Your Body Battery ($bodyBattery) and HRV (${hrv.toStringAsFixed(0)}) are both high. Perfect for a challenging workout!',
        'intensity': 'high',
        'reason': 'optimal_condition',
      };
    } else {
      return {
        'title': 'Moderate Workout Day',
        'message': 'Conditions are good for a steady workout. Listen to your body and don\'t push too hard.',
        'intensity': 'moderate',
        'reason': 'normal_condition',
      };
    }
  }

  /// Calculate metric trend over time
  double _calculateMetricTrend(List<DailyHealthData> data, double Function(DailyHealthData) extractor) {
    if (data.length < 10) return 0;
    
    final recent = data.take(7).map(extractor).reduce((a, b) => a + b) / 7;
    final earlier = data.skip(7).take(7).map(extractor).reduce((a, b) => a + b) / 7;
    
    return ((recent - earlier) / earlier) * 100;
  }

  /// Mark insight as read
  void markAsRead(String insightId) {
    final index = _insights.indexWhere((i) => i.id == insightId);
    if (index != -1) {
      _insights[index] = _insights[index].copyWith(isRead: true);
      notifyListeners();
    }
  }

  /// Dismiss insight
  void dismissInsight(String insightId) {
    final index = _insights.indexWhere((i) => i.id == insightId);
    if (index != -1) {
      _insights[index] = _insights[index].copyWith(isDismissed: true);
      notifyListeners();
    }
  }

  /// Get correlations for a specific metric
  List<Correlation> getCorrelationsForMetric(String metric) {
    return _correlations.where((c) => 
      c.primaryMetric.toLowerCase().contains(metric.toLowerCase())
    ).toList();
  }
}
