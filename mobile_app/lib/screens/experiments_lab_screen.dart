import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Experiments Lab Screen - A/B testing for health habits
class ExperimentsLabScreen extends StatelessWidget {
  const ExperimentsLabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.science_rounded,
                          color: Color(0xFF06B6D4),
                          size: 28,
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Experiments Lab',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Test changes and measure real results',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Active Experiment
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _ActiveExperimentCard(),
              ),
            ),

            // Suggested Experiments
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  'SUGGESTED EXPERIMENTS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const _SuggestedExperimentCard(
                    title: 'Morning runs vs evening runs',
                    description: 'Your data suggests potential performance differences',
                    duration: '2 weeks',
                    icon: Icons.directions_run_rounded,
                    color: AppTheme.activityColor,
                  ),
                  const _SuggestedExperimentCard(
                    title: 'Pre-meeting breathing',
                    description: 'Test stress reduction technique before meetings',
                    duration: '2 weeks',
                    icon: Icons.self_improvement_rounded,
                    color: AppTheme.stressColor,
                  ),
                  const _SuggestedExperimentCard(
                    title: 'No screen 1h before bed',
                    description: 'May improve your deep sleep quality',
                    duration: '1 week',
                    icon: Icons.bedtime_rounded,
                    color: AppTheme.sleepColor,
                  ),
                ]),
              ),
            ),

            // Completed Experiments
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: Text(
                  'COMPLETED EXPERIMENTS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _CompletedExperimentCard(
                  title: 'No caffeine after 2 PM',
                  result: 'Sleep +15%',
                  verdict: 'Worth it!',
                  isPositive: true,
                ),
              ),
            ),

            // Bottom padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveExperimentCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFCFFAFE), Color(0xFFE0F2FE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF06B6D4).withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF06B6D4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'ACTIVE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'Day 5 of 14',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(
                Icons.bedtime_rounded,
                color: Color(0xFF06B6D4),
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                'Sleep 30 min earlier',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: const LinearProgressIndicator(
              value: 5 / 14,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF06B6D4)),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Results so far:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              _ResultIndicator(
                label: 'Deep sleep',
                value: '+12%',
                isPositive: true,
              ),
              SizedBox(width: 16),
              _ResultIndicator(
                label: 'Morning energy',
                value: '+8%',
                isPositive: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF06B6D4),
                    side: const BorderSide(color: Color(0xFF06B6D4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('View Details'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: const BorderSide(color: AppTheme.textTertiary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('End Early'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultIndicator extends StatelessWidget {
  final String label;
  final String value;
  final bool isPositive;

  const _ResultIndicator({
    required this.label,
    required this.value,
    required this.isPositive,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          color: isPositive ? AppTheme.successColor : AppTheme.errorColor,
          size: 20,
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isPositive ? AppTheme.successColor : AppTheme.errorColor,
          ),
        ),
      ],
    );
  }
}

class _SuggestedExperimentCard extends StatelessWidget {
  final String title;
  final String description;
  final String duration;
  final IconData icon;
  final Color color;

  const _SuggestedExperimentCard({
    required this.title,
    required this.description,
    required this.duration,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  duration,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Start',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedExperimentCard extends StatelessWidget {
  final String title;
  final String result;
  final String verdict;
  final bool isPositive;

  const _CompletedExperimentCard({
    required this.title,
    required this.result,
    required this.verdict,
    required this.isPositive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.successColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.successColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppTheme.successColor,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Result: $result',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.successColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.successColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              verdict,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
