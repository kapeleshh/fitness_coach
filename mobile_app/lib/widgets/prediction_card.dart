import 'package:flutter/material.dart';
import '../models/prediction.dart';
import '../theme/app_theme.dart';

/// Card displaying workout time prediction
class WorkoutPredictionCard extends StatelessWidget {
  final BodyBatteryPrediction prediction;
  final VoidCallback? onSetReminder;
  final VoidCallback? onTap;

  const WorkoutPredictionCard({
    super.key,
    required this.prediction,
    this.onSetReminder,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final window = prediction.optimalWorkoutWindow;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFFE0E7FF),
              Color(0xFFF0E6FF),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.primaryColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.fitness_center_rounded,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Best Workout Time',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'Tomorrow',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${window.predictedEnergyLevel}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Time Window
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    color: AppTheme.primaryColor,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    window.timeRange,
                    style: const TextStyle(
                      fontSize: 20,
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // Recommendation
            Text(
              window.recommendation,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            
            // Action Button
            if (onSetReminder != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onSetReminder,
                  icon: const Icon(Icons.alarm_add_rounded, size: 18),
                  label: const Text('Set Reminder'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Card displaying health risk assessment
class HealthRiskCard extends StatelessWidget {
  final HealthRiskAssessment assessment;
  final VoidCallback? onTap;

  const HealthRiskCard({
    super.key,
    required this.assessment,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: assessment.overallRisk.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: assessment.overallRisk.color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: assessment.overallRisk.color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.shield_rounded,
                    color: assessment.overallRisk.color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Health Risk Monitor',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: assessment.overallRisk.color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${assessment.overallRisk.emoji} ${assessment.overallRisk.displayName}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Summary
            Text(
              assessment.summary,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.3,
              ),
            ),
            
            // Risk Factors
            if (assessment.riskFactors.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...assessment.riskFactors.take(3).map((factor) => _RiskFactorItem(factor: factor)),
            ],
          ],
        ),
      ),
    );
  }
}

class _RiskFactorItem extends StatelessWidget {
  final RiskFactor factor;

  const _RiskFactorItem({required this.factor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: factor.level.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              factor.name,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(
            factor.isImproving ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 16,
            color: factor.isImproving ? AppTheme.successColor : AppTheme.errorColor,
          ),
        ],
      ),
    );
  }
}

/// Mini prediction card for quick glance
class PredictionMiniCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const PredictionMiniCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Body Battery Forecast Chart Card
class BodyBatteryForecastCard extends StatelessWidget {
  final BodyBatteryPrediction prediction;
  final VoidCallback? onTap;

  const BodyBatteryForecastCard({
    super.key,
    required this.prediction,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_graph_rounded,
                  color: AppTheme.bodyBatteryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Tomorrow\'s Energy Forecast',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(prediction.confidence * 100).toInt()}% confident',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Simple bar chart representation
            SizedBox(
              height: 100,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: prediction.hourlyPredictions
                    .where((p) => p.hour >= 6 && p.hour <= 22 && p.hour % 2 == 0)
                    .map((p) => _HourBar(prediction: p, maxValue: prediction.predictedPeak))
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
            
            // Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _PredictionLegend(
                  label: 'Peak',
                  value: '${prediction.predictedPeak}',
                  time: '${prediction.predictedPeakHour}:00',
                  color: AppTheme.successColor,
                ),
                _PredictionLegend(
                  label: 'Low',
                  value: '${prediction.predictedLow}',
                  time: '${prediction.predictedLowHour}:00',
                  color: AppTheme.warningColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HourBar extends StatelessWidget {
  final HourlyPrediction prediction;
  final int maxValue;

  const _HourBar({
    required this.prediction,
    required this.maxValue,
  });

  @override
  Widget build(BuildContext context) {
    final height = (prediction.predictedValue / maxValue) * 80;
    final color = prediction.predictedValue >= 60 
        ? AppTheme.successColor 
        : prediction.predictedValue >= 40 
            ? AppTheme.warningColor 
            : AppTheme.errorColor;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              height: height.clamp(10.0, 80.0),
              decoration: BoxDecoration(
                color: color.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${prediction.hour}',
              style: const TextStyle(
                fontSize: 9,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PredictionLegend extends StatelessWidget {
  final String label;
  final String value;
  final String time;
  final Color color;

  const _PredictionLegend({
    required this.label,
    required this.value,
    required this.time,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$label: $value',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              'at $time',
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
