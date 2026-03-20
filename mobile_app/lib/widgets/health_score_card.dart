import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/insight.dart';
import '../theme/app_theme.dart';

/// Card displaying the holistic health score
class HealthScoreCard extends StatelessWidget {
  final HealthScore healthScore;
  final VoidCallback? onTap;

  const HealthScoreCard({
    super.key,
    required this.healthScore,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              healthScore.statusColor.withOpacity(0.1),
              healthScore.statusColor.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: healthScore.statusColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Score Circle
                _ScoreCircle(
                  score: healthScore.overallScore,
                  color: healthScore.statusColor,
                ),
                const SizedBox(width: 20),
                
                // Score Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Health Score',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        healthScore.status,
                        style: TextStyle(
                          fontSize: 22,
                          color: healthScore.statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        healthScore.summary,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Component Scores
            Row(
              children: [
                _ScoreComponent(
                  label: 'Sleep',
                  value: healthScore.sleepScore,
                  color: AppTheme.sleepColor,
                ),
                _ScoreComponent(
                  label: 'Stress',
                  value: healthScore.stressScore,
                  color: AppTheme.stressColor,
                ),
                _ScoreComponent(
                  label: 'Energy',
                  value: healthScore.energyScore,
                  color: AppTheme.bodyBatteryColor,
                ),
                _ScoreComponent(
                  label: 'Activity',
                  value: healthScore.activityScore,
                  color: AppTheme.activityColor,
                ),
                _ScoreComponent(
                  label: 'Recovery',
                  value: healthScore.recoveryScore,
                  color: AppTheme.hrvColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreCircle extends StatelessWidget {
  final int score;
  final Color color;

  const _ScoreCircle({
    required this.score,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        children: [
          // Background circle
          CustomPaint(
            size: const Size(80, 80),
            painter: _CircleProgressPainter(
              progress: score / 100,
              color: color,
              backgroundColor: color.withOpacity(0.2),
              strokeWidth: 8,
            ),
          ),
          // Score text
          Center(
            child: Text(
              score.toString(),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;

  _CircleProgressPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background circle
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircleProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _ScoreComponent extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _ScoreComponent({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value / 100,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact health score display
class HealthScoreMini extends StatelessWidget {
  final int score;
  final Color color;
  final String? label;

  const HealthScoreMini({
    super.key,
    required this.score,
    required this.color,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            Text(
              label!,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            score.toString(),
            style: TextStyle(
              fontSize: 18,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
