/// Represents a single day's health data from Garmin Forerunner 965
class DailyHealthData {
  final DateTime date;
  
  // Sleep Metrics
  final int sleepScore;                    // 0-100
  final int sleepDurationMinutes;          // Total sleep time
  final int deepSleepMinutes;
  final int lightSleepMinutes;
  final int remSleepMinutes;
  final int awakeDurationMinutes;
  final DateTime? bedTime;
  final DateTime? wakeTime;
  
  // Heart Rate Metrics
  final int restingHeartRate;              // BPM
  final int averageHeartRate;
  final int maxHeartRate;
  final int minHeartRate;
  
  // HRV (Heart Rate Variability)
  final double hrvAverage;                 // ms
  final double hrvRmssd;                   // Root mean square of successive differences
  final HRVStatus hrvStatus;
  
  // Body Battery
  final int bodyBatteryStart;              // 0-100 at start of day
  final int bodyBatteryEnd;                // 0-100 at end of day
  final int bodyBatteryMax;
  final int bodyBatteryMin;
  final List<HourlyBodyBattery> hourlyBodyBattery;
  
  // Stress
  final int averageStressLevel;            // 0-100
  final int maxStressLevel;
  final int lowStressMinutes;
  final int mediumStressMinutes;
  final int highStressMinutes;
  final int restMinutes;
  final List<StressEvent> stressEvents;
  
  // Activity
  final int steps;
  final int floorsClimbed;
  final int activeMinutes;
  final int activeCalories;
  final int totalCalories;
  final double distanceMeters;
  
  // SpO2
  final double? averageSpO2;               // Percentage
  final double? minSpO2;
  
  // Respiration
  final double averageRespirationRate;     // Breaths per minute
  final double sleepRespirationRate;
  
  // Training
  final TrainingStatus? trainingStatus;
  final int? recoveryTimeHours;
  final double? trainingLoad;
  final double? vo2Max;
  
  // Workouts
  final List<Workout> workouts;
  
  DailyHealthData({
    required this.date,
    required this.sleepScore,
    required this.sleepDurationMinutes,
    required this.deepSleepMinutes,
    required this.lightSleepMinutes,
    required this.remSleepMinutes,
    required this.awakeDurationMinutes,
    this.bedTime,
    this.wakeTime,
    required this.restingHeartRate,
    required this.averageHeartRate,
    required this.maxHeartRate,
    required this.minHeartRate,
    required this.hrvAverage,
    required this.hrvRmssd,
    required this.hrvStatus,
    required this.bodyBatteryStart,
    required this.bodyBatteryEnd,
    required this.bodyBatteryMax,
    required this.bodyBatteryMin,
    required this.hourlyBodyBattery,
    required this.averageStressLevel,
    required this.maxStressLevel,
    required this.lowStressMinutes,
    required this.mediumStressMinutes,
    required this.highStressMinutes,
    required this.restMinutes,
    required this.stressEvents,
    required this.steps,
    required this.floorsClimbed,
    required this.activeMinutes,
    required this.activeCalories,
    required this.totalCalories,
    required this.distanceMeters,
    this.averageSpO2,
    this.minSpO2,
    required this.averageRespirationRate,
    required this.sleepRespirationRate,
    this.trainingStatus,
    this.recoveryTimeHours,
    this.trainingLoad,
    this.vo2Max,
    required this.workouts,
  });

  /// Sleep quality category
  SleepQuality get sleepQuality {
    if (sleepScore >= 80) return SleepQuality.excellent;
    if (sleepScore >= 60) return SleepQuality.good;
    if (sleepScore >= 40) return SleepQuality.fair;
    return SleepQuality.poor;
  }

  /// Body Battery status
  EnergyStatus get energyStatus {
    final avg = (bodyBatteryStart + bodyBatteryEnd) ~/ 2;
    if (avg >= 70) return EnergyStatus.high;
    if (avg >= 40) return EnergyStatus.medium;
    return EnergyStatus.low;
  }

  /// Stress level category
  StressLevel get stressLevel {
    if (averageStressLevel <= 25) return StressLevel.relaxed;
    if (averageStressLevel <= 50) return StressLevel.low;
    if (averageStressLevel <= 75) return StressLevel.medium;
    return StressLevel.high;
  }

  /// Check if day had workout
  bool get hadWorkout => workouts.isNotEmpty;

  /// Get total workout duration
  int get totalWorkoutMinutes =>
      workouts.fold(0, (sum, w) => sum + w.durationMinutes);
}

/// Hourly body battery reading
class HourlyBodyBattery {
  final DateTime time;
  final int value;

  HourlyBodyBattery({required this.time, required this.value});
}

/// Stress event with time and intensity
class StressEvent {
  final DateTime startTime;
  final DateTime endTime;
  final int averageLevel;
  final int peakLevel;
  final String? possibleTrigger;

  StressEvent({
    required this.startTime,
    required this.endTime,
    required this.averageLevel,
    required this.peakLevel,
    this.possibleTrigger,
  });

  int get durationMinutes => endTime.difference(startTime).inMinutes;
}

/// Workout data
class Workout {
  final String id;
  final WorkoutType type;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final int calories;
  final double? distanceMeters;
  final int? averageHeartRate;
  final int? maxHeartRate;
  final double? averagePace;          // minutes per km
  final int? trainingEffect;          // 0-5 scale
  final int? recoveryTime;            // hours

  Workout({
    required this.id,
    required this.type,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.calories,
    this.distanceMeters,
    this.averageHeartRate,
    this.maxHeartRate,
    this.averagePace,
    this.trainingEffect,
    this.recoveryTime,
  });
}

// Enums
enum SleepQuality { excellent, good, fair, poor }
enum EnergyStatus { high, medium, low }
enum StressLevel { relaxed, low, medium, high }
enum HRVStatus { excellent, good, fair, poor, unbalanced }

enum TrainingStatus {
  productive,
  maintaining,
  recovery,
  unproductive,
  detraining,
  overreaching,
  peaking,
}

enum WorkoutType {
  running,
  cycling,
  swimming,
  walking,
  strength,
  hiit,
  yoga,
  other,
}

// Extension methods for display
extension SleepQualityExtension on SleepQuality {
  String get displayName {
    switch (this) {
      case SleepQuality.excellent: return 'Excellent';
      case SleepQuality.good: return 'Good';
      case SleepQuality.fair: return 'Fair';
      case SleepQuality.poor: return 'Poor';
    }
  }
}

extension StressLevelExtension on StressLevel {
  String get displayName {
    switch (this) {
      case StressLevel.relaxed: return 'Relaxed';
      case StressLevel.low: return 'Low';
      case StressLevel.medium: return 'Medium';
      case StressLevel.high: return 'High';
    }
  }
}

extension TrainingStatusExtension on TrainingStatus {
  String get displayName {
    switch (this) {
      case TrainingStatus.productive: return 'Productive';
      case TrainingStatus.maintaining: return 'Maintaining';
      case TrainingStatus.recovery: return 'Recovery';
      case TrainingStatus.unproductive: return 'Unproductive';
      case TrainingStatus.detraining: return 'Detraining';
      case TrainingStatus.overreaching: return 'Overreaching';
      case TrainingStatus.peaking: return 'Peaking';
    }
  }
}

extension WorkoutTypeExtension on WorkoutType {
  String get displayName {
    switch (this) {
      case WorkoutType.running: return 'Running';
      case WorkoutType.cycling: return 'Cycling';
      case WorkoutType.swimming: return 'Swimming';
      case WorkoutType.walking: return 'Walking';
      case WorkoutType.strength: return 'Strength';
      case WorkoutType.hiit: return 'HIIT';
      case WorkoutType.yoga: return 'Yoga';
      case WorkoutType.other: return 'Other';
    }
  }

  String get emoji {
    switch (this) {
      case WorkoutType.running: return '🏃';
      case WorkoutType.cycling: return '🚴';
      case WorkoutType.swimming: return '🏊';
      case WorkoutType.walking: return '🚶';
      case WorkoutType.strength: return '💪';
      case WorkoutType.hiit: return '🔥';
      case WorkoutType.yoga: return '🧘';
      case WorkoutType.other: return '🏋️';
    }
  }
}
