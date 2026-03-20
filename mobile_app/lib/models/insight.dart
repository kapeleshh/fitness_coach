import 'package:flutter/material.dart';

/// Types of AI-generated insights
enum InsightType {
  alert,          // Health warnings (e.g., "HRV dropping, you might be getting sick")
  discovery,      // Pattern discoveries (e.g., "Late workouts affect your sleep")
  prediction,     // Future predictions (e.g., "Best workout time tomorrow")
  recommendation, // Action suggestions (e.g., "Take a rest day")
  achievement,    // Positive milestones (e.g., "Sleep improved 15% this week")
  experiment,     // Experiment updates (e.g., "Your sleep experiment shows +12% improvement")
}

/// Priority/severity levels
enum InsightPriority {
  critical,   // Immediate attention needed
  high,       // Important insight
  medium,     // Regular insight
  low,        // Nice to know
}

/// Category of health metric the insight relates to
enum InsightCategory {
  sleep,
  stress,
  energy,
  activity,
  heart,
  training,
  overall,
}

/// Represents an AI-generated insight
class Insight {
  final String id;
  final InsightType type;
  final InsightPriority priority;
  final InsightCategory category;
  final String title;
  final String message;
  final String? detailedExplanation;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool isRead;
  final bool isDismissed;
  final InsightAction? primaryAction;
  final InsightAction? secondaryAction;
  final Map<String, dynamic>? dataContext;  // Supporting data for the insight
  final List<String>? relatedMetrics;

  Insight({
    required this.id,
    required this.type,
    required this.priority,
    required this.category,
    required this.title,
    required this.message,
    this.detailedExplanation,
    required this.createdAt,
    this.expiresAt,
    this.isRead = false,
    this.isDismissed = false,
    this.primaryAction,
    this.secondaryAction,
    this.dataContext,
    this.relatedMetrics,
  });

  /// Copy with modifications
  Insight copyWith({
    bool? isRead,
    bool? isDismissed,
  }) {
    return Insight(
      id: id,
      type: type,
      priority: priority,
      category: category,
      title: title,
      message: message,
      detailedExplanation: detailedExplanation,
      createdAt: createdAt,
      expiresAt: expiresAt,
      isRead: isRead ?? this.isRead,
      isDismissed: isDismissed ?? this.isDismissed,
      primaryAction: primaryAction,
      secondaryAction: secondaryAction,
      dataContext: dataContext,
      relatedMetrics: relatedMetrics,
    );
  }

  /// Get icon for insight type
  IconData get icon {
    switch (type) {
      case InsightType.alert:
        return Icons.warning_rounded;
      case InsightType.discovery:
        return Icons.lightbulb_rounded;
      case InsightType.prediction:
        return Icons.auto_awesome_rounded;
      case InsightType.recommendation:
        return Icons.tips_and_updates_rounded;
      case InsightType.achievement:
        return Icons.emoji_events_rounded;
      case InsightType.experiment:
        return Icons.science_rounded;
    }
  }

  /// Get color for insight type
  Color get color {
    switch (type) {
      case InsightType.alert:
        return const Color(0xFFEF4444);   // Red
      case InsightType.discovery:
        return const Color(0xFFF59E0B);   // Amber
      case InsightType.prediction:
        return const Color(0xFF6366F1);   // Indigo
      case InsightType.recommendation:
        return const Color(0xFF10B981);   // Green
      case InsightType.achievement:
        return const Color(0xFF8B5CF6);   // Purple
      case InsightType.experiment:
        return const Color(0xFF06B6D4);   // Cyan
    }
  }

  /// Get background color (lighter version)
  Color get backgroundColor {
    switch (type) {
      case InsightType.alert:
        return const Color(0xFFFEE2E2);
      case InsightType.discovery:
        return const Color(0xFFFEF3C7);
      case InsightType.prediction:
        return const Color(0xFFE0E7FF);
      case InsightType.recommendation:
        return const Color(0xFFD1FAE5);
      case InsightType.achievement:
        return const Color(0xFFEDE9FE);
      case InsightType.experiment:
        return const Color(0xFFCFFAFE);
    }
  }

  /// Get emoji for insight type
  String get emoji {
    switch (type) {
      case InsightType.alert:
        return '🚨';
      case InsightType.discovery:
        return '💡';
      case InsightType.prediction:
        return '🔮';
      case InsightType.recommendation:
        return '💪';
      case InsightType.achievement:
        return '🏆';
      case InsightType.experiment:
        return '🧪';
    }
  }

  /// Get label for insight type
  String get typeLabel {
    switch (type) {
      case InsightType.alert:
        return 'ALERT';
      case InsightType.discovery:
        return 'DISCOVERY';
      case InsightType.prediction:
        return 'PREDICTION';
      case InsightType.recommendation:
        return 'RECOMMENDATION';
      case InsightType.achievement:
        return 'ACHIEVEMENT';
      case InsightType.experiment:
        return 'EXPERIMENT';
    }
  }

  /// Check if insight is still valid
  bool get isValid {
    if (expiresAt == null) return true;
    return DateTime.now().isBefore(expiresAt!);
  }
}

/// Action that can be taken from an insight
class InsightAction {
  final String label;
  final String actionType;    // 'navigate', 'dismiss', 'snooze', 'external', etc.
  final String? route;        // For navigation
  final Map<String, dynamic>? params;

  InsightAction({
    required this.label,
    required this.actionType,
    this.route,
    this.params,
  });
}

/// Correlation between two metrics
class Correlation {
  final String id;
  final String primaryMetric;
  final String secondaryMetric;
  final double correlationStrength;   // -1 to 1
  final String description;
  final int dataPointsAnalyzed;
  final DateTime lastUpdated;
  final bool isPositive;

  Correlation({
    required this.id,
    required this.primaryMetric,
    required this.secondaryMetric,
    required this.correlationStrength,
    required this.description,
    required this.dataPointsAnalyzed,
    required this.lastUpdated,
  }) : isPositive = correlationStrength > 0;

  /// Get impact percentage (absolute value * 100)
  int get impactPercentage => (correlationStrength.abs() * 100).round();

  /// Get strength category
  String get strengthLabel {
    final abs = correlationStrength.abs();
    if (abs >= 0.7) return 'Strong';
    if (abs >= 0.4) return 'Moderate';
    return 'Weak';
  }
}

/// Health score breakdown
class HealthScore {
  final int overallScore;           // 0-100
  final int sleepScore;
  final int stressScore;
  final int energyScore;
  final int activityScore;
  final int recoveryScore;
  final DateTime calculatedAt;
  final String summary;
  final List<String> topFactors;
  final List<String> improvementAreas;

  HealthScore({
    required this.overallScore,
    required this.sleepScore,
    required this.stressScore,
    required this.energyScore,
    required this.activityScore,
    required this.recoveryScore,
    required this.calculatedAt,
    required this.summary,
    required this.topFactors,
    required this.improvementAreas,
  });

  /// Get status based on overall score
  String get status {
    if (overallScore >= 80) return 'Excellent';
    if (overallScore >= 65) return 'Good';
    if (overallScore >= 50) return 'Fair';
    return 'Needs Attention';
  }

  /// Get color based on score
  Color get statusColor {
    if (overallScore >= 80) return const Color(0xFF10B981);
    if (overallScore >= 65) return const Color(0xFF06B6D4);
    if (overallScore >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }
}
