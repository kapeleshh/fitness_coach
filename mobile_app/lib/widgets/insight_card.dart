import 'package:flutter/material.dart';
import '../models/insight.dart';
import '../theme/app_theme.dart';

/// Card widget for displaying AI-generated insights
class InsightCard extends StatelessWidget {
  final Insight insight;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
  final VoidCallback? onPrimaryAction;
  final VoidCallback? onSecondaryAction;

  const InsightCard({
    super.key,
    required this.insight,
    this.onTap,
    this.onDismiss,
    this.onPrimaryAction,
    this.onSecondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(insight.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss?.call(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: Colors.red.shade700,
        ),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: insight.backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: insight.color.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type Label & Icon
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: insight.color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                insight.icon,
                                size: 14,
                                color: insight.color,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                insight.typeLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: insight.color,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _getTimeAgo(insight.createdAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Title
                    Text(
                      insight.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Message
                    Text(
                      insight.message,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Actions
              if (insight.primaryAction != null || insight.secondaryAction != null)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      if (insight.primaryAction != null)
                        Expanded(
                          child: ElevatedButton(
                            onPressed: onPrimaryAction,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: insight.color,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              insight.primaryAction!.label,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      if (insight.primaryAction != null && insight.secondaryAction != null)
                        const SizedBox(width: 12),
                      if (insight.secondaryAction != null)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onSecondaryAction,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: insight.color,
                              side: BorderSide(color: insight.color),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              insight.secondaryAction!.label,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}

/// Compact version of insight card for smaller displays
class InsightCardCompact extends StatelessWidget {
  final Insight insight;
  final VoidCallback? onTap;

  const InsightCardCompact({
    super.key,
    required this.insight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: insight.backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: insight.color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: insight.color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                insight.icon,
                color: insight.color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    insight.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    insight.message,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
