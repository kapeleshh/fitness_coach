import 'package:flutter/material.dart';

/// Prediction for body battery throughout the day
class BodyBatteryPrediction {
  final DateTime date;
  final List<HourlyPrediction> hourlyPredictions;
  final int predictedPeak;
  final int predictedPeakHour;
  final int predictedLow;
  final int predictedLowHour;
  final double confidence;

  BodyBatteryPrediction({
    required this.date,
    required this.hourlyPredictions,
    required this.predictedPeak,
    required this.predictedPeakHour,
    required this.predictedLow,
    required this.predictedLowHour,
    required this.confidence,
  });

  /// Get optimal workout window
  WorkoutWindow get optimalWorkoutWindow {
    // Find the window with highest average body battery
    int bestStartHour = predictedPeakHour - 1;
    if (bestStartHour < 6) bestStartHour = 6;
    
    return WorkoutWindow(
      startHour: bestStartHour,
      endHour: (bestStartHour + 2).clamp(7, 20),
      predictedEnergyLevel: predictedPeak,
      recommendation: _getWorkoutRecommendation(),
    );
  }

  String _getWorkoutRecommendation() {
    if (predictedPeak >= 70) {
      return 'High energy expected - great for intense workouts!';
    } else if (predictedPeak >= 50) {
      return 'Moderate energy - suitable for a steady workout.';
    } else {
      return 'Lower energy predicted - consider light activity or rest.';
    }
  }
}

/// Single hour prediction
class HourlyPrediction {
  final int hour;
  final int predictedValue;
  final double confidence;

  HourlyPrediction({
    required this.hour,
    required this.predictedValue,
    required this.confidence,
  });
}

/// Recommended workout window
class WorkoutWindow {
  final int startHour;
  final int endHour;
  final int predictedEnergyLevel;
  final String recommendation;

  WorkoutWindow({
    required this.startHour,
    required this.endHour,
    required this.predictedEnergyLevel,
    required this.recommendation,
  });

  String get timeRange {
    final startStr = startHour > 12 
        ? '${startHour - 12}:00 PM' 
        : '$startHour:00 ${startHour < 12 ? "AM" : "PM"}';
    final endStr = endHour > 12 
        ? '${endHour - 12}:00 PM' 
        : '$endHour:00 ${endHour < 12 ? "AM" : "PM"}';
    return '$startStr - $endStr';
  }
}

/// Health risk assessment
class HealthRiskAssessment {
  final DateTime assessedAt;
  final RiskLevel overallRisk;
  final List<RiskFactor> riskFactors;
  final String summary;
  final List<String> recommendations;

  HealthRiskAssessment({
    required this.assessedAt,
    required this.overallRisk,
    required this.riskFactors,
    required this.summary,
    required this.recommendations,
  });
}

enum RiskLevel { low, moderate, elevated, high }

extension RiskLevelExtension on RiskLevel {
  String get displayName {
    switch (this) {
      case RiskLevel.low: return 'Low';
      case RiskLevel.moderate: return 'Moderate';
      case RiskLevel.elevated: return 'Elevated';
      case RiskLevel.high: return 'High';
    }
  }

  Color get color {
    switch (this) {
      case RiskLevel.low: return const Color(0xFF10B981);
      case RiskLevel.moderate: return const Color(0xFFF59E0B);
      case RiskLevel.elevated: return const Color(0xFFF97316);
      case RiskLevel.high: return const Color(0xFFEF4444);
    }
  }

  String get emoji {
    switch (this) {
      case RiskLevel.low: return '🟢';
      case RiskLevel.moderate: return '🟡';
      case RiskLevel.elevated: return '🟠';
      case RiskLevel.high: return '🔴';
    }
  }
}

/// Individual risk factor
class RiskFactor {
  final String name;
  final String metric;
  final RiskLevel level;
  final String description;
  final double trendPercentage;    // Positive = improving, Negative = worsening
  final int daysTracked;

  RiskFactor({
    required this.name,
    required this.metric,
    required this.level,
    required this.description,
    required this.trendPercentage,
    required this.daysTracked,
  });

  bool get isImproving => trendPercentage > 0;
}

/// Long-term trend analysis
class TrendAnalysis {
  final String metricName;
  final List<TrendDataPoint> dataPoints;
  final double overallTrend;       // Percentage change over period
  final TrendDirection direction;
  final String insight;
  final DateTime startDate;
  final DateTime endDate;

  TrendAnalysis({
    required this.metricName,
    required this.dataPoints,
    required this.overallTrend,
    required this.direction,
    required this.insight,
    required this.startDate,
    required this.endDate,
  });

  int get daysAnalyzed => endDate.difference(startDate).inDays;
}

class TrendDataPoint {
  final DateTime date;
  final double value;
  final double? movingAverage;

  TrendDataPoint({
    required this.date,
    required this.value,
    this.movingAverage,
  });
}

enum TrendDirection { improving, stable, declining }

extension TrendDirectionExtension on TrendDirection {
  String get displayName {
    switch (this) {
      case TrendDirection.improving: return 'Improving';
      case TrendDirection.stable: return 'Stable';
      case TrendDirection.declining: return 'Declining';
    }
  }

  Color get color {
    switch (this) {
      case TrendDirection.improving: return const Color(0xFF10B981);
      case TrendDirection.stable: return const Color(0xFF6366F1);
      case TrendDirection.declining: return const Color(0xFFEF4444);
    }
  }

  IconData get icon {
    switch (this) {
      case TrendDirection.improving: return Icons.trending_up_rounded;
      case TrendDirection.stable: return Icons.trending_flat_rounded;
      case TrendDirection.declining: return Icons.trending_down_rounded;
    }
  }
}

/// Sleep prediction for tonight
class SleepPrediction {
  final DateTime targetDate;
  final int predictedSleepScore;
  final int predictedDeepSleepMinutes;
  final int predictedTotalMinutes;
  final double confidence;
  final List<String> factors;
  final List<String> suggestions;

  SleepPrediction({
    required this.targetDate,
    required this.predictedSleepScore,
    required this.predictedDeepSleepMinutes,
    required this.predictedTotalMinutes,
    required this.confidence,
    required this.factors,
    required this.suggestions,
  });

  String get summary {
    if (predictedSleepScore >= 80) {
      return 'Great sleep predicted tonight!';
    } else if (predictedSleepScore >= 60) {
      return 'Decent sleep expected.';
    } else {
      return 'Sleep quality may be lower - follow the suggestions!';
    }
  }
}

/// Stress prediction
class StressPrediction {
  final DateTime targetDate;
  final List<HourlyStressPrediction> hourlyPredictions;
  final List<PredictedStressEvent> predictedEvents;
  final String summary;

  StressPrediction({
    required this.targetDate,
    required this.hourlyPredictions,
    required this.predictedEvents,
    required this.summary,
  });
}

class HourlyStressPrediction {
  final int hour;
  final int predictedLevel;
  final double confidence;

  HourlyStressPrediction({
    required this.hour,
    required this.predictedLevel,
    required this.confidence,
  });
}

class PredictedStressEvent {
  final int startHour;
  final int endHour;
  final int predictedLevel;
  final String? likelyTrigger;
  final String? suggestion;

  PredictedStressEvent({
    required this.startHour,
    required this.endHour,
    required this.predictedLevel,
    this.likelyTrigger,
    this.suggestion,
  });
}
