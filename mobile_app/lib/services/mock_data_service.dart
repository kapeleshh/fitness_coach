import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/health_data.dart';
import '../models/prediction.dart';
import '../models/insight.dart';

/// Service that generates realistic mock data simulating Garmin Forerunner 965
class MockDataService extends ChangeNotifier {
  final _uuid = const Uuid();
  final _random = Random(42); // Fixed seed for consistent data
  
  List<DailyHealthData> _healthData = [];
  HealthScore? _currentHealthScore;
  BodyBatteryPrediction? _tomorrowPrediction;
  HealthRiskAssessment? _riskAssessment;
  bool _isLoading = false;

  // Getters
  List<DailyHealthData> get healthData => _healthData;
  DailyHealthData? get todayData => _healthData.isNotEmpty ? _healthData.first : null;
  DailyHealthData? get yesterdayData => _healthData.length > 1 ? _healthData[1] : null;
  HealthScore? get currentHealthScore => _currentHealthScore;
  BodyBatteryPrediction? get tomorrowPrediction => _tomorrowPrediction;
  HealthRiskAssessment? get riskAssessment => _riskAssessment;
  bool get isLoading => _isLoading;

  /// Initialize with 30 days of mock data
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    // Simulate loading delay
    await Future.delayed(const Duration(milliseconds: 500));

    _healthData = _generate30DaysData();
    _currentHealthScore = _calculateHealthScore();
    _tomorrowPrediction = _generateTomorrowPrediction();
    _riskAssessment = _generateRiskAssessment();

    _isLoading = false;
    notifyListeners();
  }

  /// Generate 30 days of realistic health data with embedded patterns
  List<DailyHealthData> _generate30DaysData() {
    final data = <DailyHealthData>[];
    final now = DateTime.now();

    for (int i = 0; i < 30; i++) {
      final date = now.subtract(Duration(days: i));
      data.add(_generateDayData(date, i));
    }

    return data;
  }

  /// Generate data for a single day with realistic patterns
  DailyHealthData _generateDayData(DateTime date, int daysAgo) {
    final dayOfWeek = date.weekday;
    final isWeekend = dayOfWeek == DateTime.saturday || dayOfWeek == DateTime.sunday;
    
    // Pattern: Tuesdays have higher stress (simulating team meeting)
    final isTuesday = dayOfWeek == DateTime.tuesday;
    
    // Pattern: Weekend days have better sleep
    // Pattern: Days with late workouts have worse sleep
    final hasLateWorkout = daysAgo % 4 == 0 && !isWeekend;
    
    // Base values with daily variation
    final baseSleepScore = isWeekend ? 78 : 72;
    final sleepPenalty = hasLateWorkout ? -15 : 0;
    final sleepScore = (baseSleepScore + sleepPenalty + _randomVariation(10)).clamp(30, 100);
    
    // Sleep duration
    final baseSleepDuration = isWeekend ? 480 : 420; // 8h vs 7h
    final sleepDurationMinutes = baseSleepDuration + _randomVariation(45);
    
    // Sleep stages (should sum to ~sleepDurationMinutes - awake time)
    final awakeDuration = 15 + _randomVariation(15);
    final actualSleepTime = sleepDurationMinutes - awakeDuration;
    final deepSleep = (actualSleepTime * 0.20 + _randomVariation(15)).toInt();
    final remSleep = (actualSleepTime * 0.22 + _randomVariation(15)).toInt();
    final lightSleep = actualSleepTime - deepSleep - remSleep;

    // Heart rate - affected by sleep quality
    final restingHR = 52 + (sleepScore < 60 ? 5 : 0) + _randomVariation(4);
    
    // HRV - inversely correlated with stress, positively with sleep
    final baseHRV = 55.0 + (sleepScore - 70) * 0.3;
    final hrvAverage = (baseHRV + _randomVariation(8).toDouble()).clamp(25.0, 85.0);
    
    // Body Battery
    final bodyBatteryStart = (80 + _randomVariation(15)).clamp(40, 100);
    final bodyBatteryEnd = (35 + _randomVariation(20)).clamp(15, 70);
    
    // Stress - higher on Tuesdays, lower on weekends
    final baseStress = isWeekend ? 25 : (isTuesday ? 48 : 35);
    final averageStress = (baseStress + _randomVariation(12)).clamp(15, 75);
    
    // Steps - more on workout days
    final hadWorkoutToday = daysAgo % 2 == 0;
    final baseSteps = hadWorkoutToday ? 12000 : 7500;
    final steps = baseSteps + _randomVariation(3000);

    // Generate workouts
    final workouts = <Workout>[];
    if (hadWorkoutToday) {
      final workoutHour = hasLateWorkout ? 21 : 7; // Late workout vs morning
      workouts.add(_generateWorkout(date, workoutHour));
    }

    // Generate stress events (Tuesday afternoon spike)
    final stressEvents = <StressEvent>[];
    if (isTuesday) {
      stressEvents.add(StressEvent(
        startTime: DateTime(date.year, date.month, date.day, 14, 0),
        endTime: DateTime(date.year, date.month, date.day, 15, 30),
        averageLevel: 65,
        peakLevel: 78,
        possibleTrigger: 'Weekly team sync',
      ));
    }

    // Generate hourly body battery
    final hourlyBB = _generateHourlyBodyBattery(date, bodyBatteryStart, bodyBatteryEnd);

    return DailyHealthData(
      date: date,
      sleepScore: sleepScore,
      sleepDurationMinutes: sleepDurationMinutes,
      deepSleepMinutes: deepSleep,
      lightSleepMinutes: lightSleep,
      remSleepMinutes: remSleep,
      awakeDurationMinutes: awakeDuration,
      bedTime: DateTime(date.year, date.month, date.day - 1, 22, 30 + _randomVariation(45)),
      wakeTime: DateTime(date.year, date.month, date.day, 6, 30 + _randomVariation(30)),
      restingHeartRate: restingHR,
      averageHeartRate: restingHR + 15 + _randomVariation(8),
      maxHeartRate: 150 + _randomVariation(30),
      minHeartRate: restingHR - 5,
      hrvAverage: hrvAverage,
      hrvRmssd: hrvAverage * 1.2,
      hrvStatus: hrvAverage > 50 ? HRVStatus.good : HRVStatus.fair,
      bodyBatteryStart: bodyBatteryStart,
      bodyBatteryEnd: bodyBatteryEnd,
      bodyBatteryMax: (bodyBatteryStart + 5).clamp(0, 100),
      bodyBatteryMin: bodyBatteryEnd - 10,
      hourlyBodyBattery: hourlyBB,
      averageStressLevel: averageStress,
      maxStressLevel: (averageStress + 25).clamp(0, 100),
      lowStressMinutes: (1440 * (1 - averageStress / 100) * 0.4).toInt(),
      mediumStressMinutes: (1440 * 0.3).toInt(),
      highStressMinutes: (1440 * averageStress / 100 * 0.3).toInt(),
      restMinutes: 480 + _randomVariation(60),
      stressEvents: stressEvents,
      steps: steps,
      floorsClimbed: 8 + _randomVariation(6),
      activeMinutes: hadWorkoutToday ? 60 + _randomVariation(30) : 25 + _randomVariation(15),
      activeCalories: hadWorkoutToday ? 450 + _randomVariation(150) : 200 + _randomVariation(100),
      totalCalories: 2200 + _randomVariation(400),
      distanceMeters: (steps * 0.75).toDouble(),
      averageSpO2: 96.0 + _randomVariation(2).toDouble(),
      minSpO2: 93.0 + _randomVariation(2).toDouble(),
      averageRespirationRate: 14.0 + _randomVariation(2).toDouble(),
      sleepRespirationRate: 12.0 + _randomVariation(2).toDouble(),
      trainingStatus: hadWorkoutToday ? TrainingStatus.productive : TrainingStatus.recovery,
      recoveryTimeHours: hadWorkoutToday ? 24 + _randomVariation(12) : 0,
      trainingLoad: hadWorkoutToday ? 75.0 + _randomVariation(25).toDouble() : null,
      vo2Max: 52.0 + _randomVariation(3).toDouble(),
      workouts: workouts,
    );
  }

  /// Generate a workout
  Workout _generateWorkout(DateTime date, int hour) {
    final types = [WorkoutType.running, WorkoutType.cycling, WorkoutType.strength];
    final type = types[_random.nextInt(types.length)];
    final duration = 30 + _randomVariation(30);
    
    return Workout(
      id: _uuid.v4(),
      type: type,
      startTime: DateTime(date.year, date.month, date.day, hour, 0),
      endTime: DateTime(date.year, date.month, date.day, hour, duration),
      durationMinutes: duration,
      calories: 300 + _randomVariation(200),
      distanceMeters: type == WorkoutType.running ? (5000 + _randomVariation(3000)).toDouble() : null,
      averageHeartRate: 140 + _randomVariation(15),
      maxHeartRate: 165 + _randomVariation(15),
      averagePace: type == WorkoutType.running ? 5.5 + _randomVariation(1).toDouble() : null,
      trainingEffect: 3 + _random.nextInt(2),
      recoveryTime: 24 + _randomVariation(12),
    );
  }

  /// Generate hourly body battery values
  List<HourlyBodyBattery> _generateHourlyBodyBattery(DateTime date, int start, int end) {
    final hourly = <HourlyBodyBattery>[];
    final decline = (start - end) / 16; // Decline over 16 waking hours
    
    for (int h = 6; h < 23; h++) {
      final hoursAwake = h - 6;
      int value;
      
      if (h < 10) {
        // Morning: slight recovery after waking
        value = start + 5 - (hoursAwake * 2);
      } else if (h < 14) {
        // Late morning: gradual decline
        value = start - (hoursAwake * decline).toInt();
      } else if (h < 16) {
        // Afternoon dip
        value = start - (hoursAwake * decline * 1.2).toInt();
      } else {
        // Evening: continued decline
        value = start - (hoursAwake * decline).toInt();
      }
      
      hourly.add(HourlyBodyBattery(
        time: DateTime(date.year, date.month, date.day, h),
        value: value.clamp(15, 100),
      ));
    }
    
    return hourly;
  }

  /// Calculate overall health score
  HealthScore _calculateHealthScore() {
    if (_healthData.isEmpty) {
      return HealthScore(
        overallScore: 0,
        sleepScore: 0,
        stressScore: 0,
        energyScore: 0,
        activityScore: 0,
        recoveryScore: 0,
        calculatedAt: DateTime.now(),
        summary: 'No data available',
        topFactors: [],
        improvementAreas: [],
      );
    }

    // Calculate 7-day averages
    final last7Days = _healthData.take(7).toList();
    
    final avgSleepScore = last7Days.map((d) => d.sleepScore).reduce((a, b) => a + b) ~/ 7;
    final avgStress = last7Days.map((d) => d.averageStressLevel).reduce((a, b) => a + b) ~/ 7;
    final stressScore = 100 - avgStress; // Invert stress
    final avgBodyBattery = last7Days.map((d) => (d.bodyBatteryStart + d.bodyBatteryEnd) ~/ 2).reduce((a, b) => a + b) ~/ 7;
    final avgSteps = last7Days.map((d) => d.steps).reduce((a, b) => a + b) ~/ 7;
    final activityScore = (avgSteps / 100).clamp(0, 100).toInt();
    
    // Recovery score based on HRV trend
    final hrvTrend = last7Days.map((d) => d.hrvAverage).reduce((a, b) => a + b) / 7;
    final recoveryScore = (hrvTrend * 1.5).clamp(0, 100).toInt();
    
    // Weighted overall score
    final overallScore = (
      avgSleepScore * 0.25 +
      stressScore * 0.20 +
      avgBodyBattery * 0.20 +
      activityScore * 0.15 +
      recoveryScore * 0.20
    ).toInt();

    // Determine factors
    final topFactors = <String>[];
    final improvementAreas = <String>[];

    if (avgSleepScore >= 75) {
      topFactors.add('Good sleep quality');
    } else {
      improvementAreas.add('Sleep quality needs improvement');
    }

    if (stressScore >= 70) {
      topFactors.add('Well-managed stress');
    } else {
      improvementAreas.add('High stress levels detected');
    }

    if (avgBodyBattery >= 60) {
      topFactors.add('Strong energy levels');
    } else {
      improvementAreas.add('Low energy - consider more rest');
    }

    if (activityScore >= 70) {
      topFactors.add('Active lifestyle');
    } else {
      improvementAreas.add('Increase daily activity');
    }

    String summary;
    if (overallScore >= 80) {
      summary = "You're in excellent shape! Keep up the great work.";
    } else if (overallScore >= 65) {
      summary = "You're doing well. Small improvements can boost your score.";
    } else if (overallScore >= 50) {
      summary = "There's room for improvement. Focus on the suggested areas.";
    } else {
      summary = "Your body needs attention. Consider rest and recovery.";
    }

    return HealthScore(
      overallScore: overallScore,
      sleepScore: avgSleepScore,
      stressScore: stressScore,
      energyScore: avgBodyBattery,
      activityScore: activityScore,
      recoveryScore: recoveryScore,
      calculatedAt: DateTime.now(),
      summary: summary,
      topFactors: topFactors,
      improvementAreas: improvementAreas,
    );
  }

  /// Generate tomorrow's body battery prediction
  BodyBatteryPrediction _generateTomorrowPrediction() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final today = _healthData.isNotEmpty ? _healthData.first : null;
    
    // Base prediction on today's data
    final basePeak = today != null ? today.bodyBatteryMax : 75;
    final predictedPeak = (basePeak + _randomVariation(5)).clamp(50, 95);
    
    final hourlyPredictions = <HourlyPrediction>[];
    
    // Generate hourly predictions
    for (int h = 6; h <= 22; h++) {
      int predicted;
      if (h <= 10) {
        predicted = predictedPeak - ((h - 6) * 2);
      } else if (h <= 14) {
        predicted = predictedPeak - 8 - ((h - 10) * 4);
      } else {
        predicted = predictedPeak - 24 - ((h - 14) * 3);
      }
      
      hourlyPredictions.add(HourlyPrediction(
        hour: h,
        predictedValue: predicted.clamp(25, 95),
        confidence: 0.75 + _random.nextDouble() * 0.15,
      ));
    }

    final peakHour = 9 + _random.nextInt(3); // Between 9-11 AM
    
    return BodyBatteryPrediction(
      date: tomorrow,
      hourlyPredictions: hourlyPredictions,
      predictedPeak: predictedPeak,
      predictedPeakHour: peakHour,
      predictedLow: 35 + _randomVariation(10),
      predictedLowHour: 18,
      confidence: 0.82,
    );
  }

  /// Generate health risk assessment
  HealthRiskAssessment _generateRiskAssessment() {
    // Analyze HRV trend (looking for drops that might indicate illness)
    final last7Days = _healthData.take(7).toList();
    final hrvValues = last7Days.map((d) => d.hrvAverage).toList();
    
    // Calculate trend
    double hrvTrend = 0;
    if (hrvValues.length >= 3) {
      final recent = hrvValues.take(3).reduce((a, b) => a + b) / 3;
      final earlier = hrvValues.skip(3).take(3).reduce((a, b) => a + b) / 3;
      hrvTrend = ((recent - earlier) / earlier) * 100;
    }

    final riskFactors = <RiskFactor>[];
    var overallRisk = RiskLevel.low;

    // HRV Risk Factor
    if (hrvTrend < -10) {
      riskFactors.add(RiskFactor(
        name: 'HRV Decline',
        metric: 'Heart Rate Variability',
        level: hrvTrend < -15 ? RiskLevel.elevated : RiskLevel.moderate,
        description: 'Your HRV has dropped ${hrvTrend.abs().toStringAsFixed(0)}% over the past week.',
        trendPercentage: hrvTrend,
        daysTracked: 7,
      ));
      overallRisk = RiskLevel.moderate;
    } else {
      riskFactors.add(RiskFactor(
        name: 'HRV Stable',
        metric: 'Heart Rate Variability',
        level: RiskLevel.low,
        description: 'Your HRV is stable and within normal range.',
        trendPercentage: hrvTrend,
        daysTracked: 7,
      ));
    }

    // Sleep Risk Factor
    final avgSleep = last7Days.map((d) => d.sleepScore).reduce((a, b) => a + b) / 7;
    if (avgSleep < 60) {
      riskFactors.add(RiskFactor(
        name: 'Sleep Quality',
        metric: 'Sleep Score',
        level: RiskLevel.moderate,
        description: 'Your average sleep score is below optimal.',
        trendPercentage: -5,
        daysTracked: 7,
      ));
      if (overallRisk == RiskLevel.low) overallRisk = RiskLevel.moderate;
    }

    // Resting HR Risk Factor
    final avgRestingHR = last7Days.map((d) => d.restingHeartRate).reduce((a, b) => a + b) / 7;
    riskFactors.add(RiskFactor(
      name: 'Resting Heart Rate',
      metric: 'Resting HR',
      level: avgRestingHR > 65 ? RiskLevel.moderate : RiskLevel.low,
      description: avgRestingHR > 65 
          ? 'Slightly elevated resting heart rate detected.'
          : 'Resting heart rate is in healthy range.',
      trendPercentage: 0,
      daysTracked: 7,
    ));

    final recommendations = <String>[];
    if (overallRisk != RiskLevel.low) {
      recommendations.add('Prioritize rest and recovery');
      recommendations.add('Ensure 7-8 hours of quality sleep');
      recommendations.add('Consider reducing training intensity');
    }

    return HealthRiskAssessment(
      assessedAt: DateTime.now(),
      overallRisk: overallRisk,
      riskFactors: riskFactors,
      summary: overallRisk == RiskLevel.low
          ? 'All health indicators are within normal ranges.'
          : 'Some indicators suggest your body may need extra attention.',
      recommendations: recommendations,
    );
  }

  /// Get data for last N days
  List<DailyHealthData> getLastNDays(int n) {
    return _healthData.take(n).toList();
  }

  /// Get average value for a metric over N days
  double getAverageForMetric(String metric, int days) {
    final data = getLastNDays(days);
    if (data.isEmpty) return 0;

    switch (metric) {
      case 'sleepScore':
        return data.map((d) => d.sleepScore).reduce((a, b) => a + b) / data.length;
      case 'stress':
        return data.map((d) => d.averageStressLevel).reduce((a, b) => a + b) / data.length;
      case 'bodyBattery':
        return data.map((d) => (d.bodyBatteryStart + d.bodyBatteryEnd) / 2).reduce((a, b) => a + b) / data.length;
      case 'steps':
        return data.map((d) => d.steps).reduce((a, b) => a + b) / data.length;
      case 'hrv':
        return data.map((d) => d.hrvAverage).reduce((a, b) => a + b) / data.length;
      default:
        return 0;
    }
  }

  int _randomVariation(int range) {
    return _random.nextInt(range * 2) - range;
  }
}
