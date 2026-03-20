import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/health_api_service.dart';

/// Insights Feed showing AI-generated insights from YOUR real Garmin data
class InsightsFeedScreen extends StatefulWidget {
  const InsightsFeedScreen({super.key});

  @override
  State<InsightsFeedScreen> createState() => _InsightsFeedScreenState();
}

class _InsightsFeedScreenState extends State<InsightsFeedScreen> {
  List<Map<String, dynamic>> _insights = [];
  Map<String, dynamic>? _today;
  bool _isLoading = true;
  int _healthScore = 0;
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    await healthApiService.initialize();
    
    setState(() {
      _insights = healthApiService.generateInsights();
      _today = healthApiService.today;
      if (_today != null) {
        _healthScore = healthApiService.calculateHealthScore(_today!);
      }
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            // App Bar
            SliverAppBar(
              expandedHeight: 120,
              floating: false,
              pinned: true,
              backgroundColor: AppTheme.backgroundColor,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                title: const Text(
                  'Health Insights',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppTheme.primaryColor.withOpacity(0.1),
                        AppTheme.backgroundColor,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              // Health Score Card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildHealthScoreCard(),
                ),
              ),
              
              // Insights Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text(
                        '✨ Today\'s Insights',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_insights.length} found',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Insights List
              if (_insights.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        const Icon(Icons.check_circle, 
                            size: 64, color: AppTheme.successColor),
                        const SizedBox(height: 16),
                        const Text(
                          'All Looking Good! 🎉',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your metrics are within healthy ranges today.',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final insight = _insights[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                        child: _buildInsightCard(insight),
                      );
                    },
                    childCount: _insights.length,
                  ),
                ),
              
              // Quick Stats
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildQuickStats(),
                ),
              ),
              
              const SliverToBoxAdapter(
                child: SizedBox(height: 100),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildHealthScoreCard() {
    Color scoreColor;
    String scoreLabel;
    
    if (_healthScore >= 80) {
      scoreColor = AppTheme.successColor;
      scoreLabel = 'Excellent';
    } else if (_healthScore >= 60) {
      scoreColor = AppTheme.bodyBatteryColor;
      scoreLabel = 'Good';
    } else if (_healthScore >= 40) {
      scoreColor = Colors.orange;
      scoreLabel = 'Fair';
    } else {
      scoreColor = AppTheme.stressColor;
      scoreLabel = 'Needs Attention';
    }
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Score Circle
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.2),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 90,
                      height: 90,
                      child: CircularProgressIndicator(
                        value: _healthScore / 100,
                        strokeWidth: 8,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        valueColor: AlwaysStoppedAnimation(scoreColor),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$_healthScore',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          scoreLabel,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Overall Health Score',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _today?['date'] ?? 'Today',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _miniStat('Sleep', '${_today?['sleep_score'] ?? 0}'),
                        const SizedBox(width: 16),
                        _miniStat('HRV', '${_today?['hrv']?.round() ?? 0}'),
                        const SizedBox(width: 16),
                        _miniStat('Stress', '${_today?['avg_stress'] ?? 0}'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
  
  Widget _buildInsightCard(Map<String, dynamic> insight) {
    final isWarning = insight['type'] == 'warning';
    final color = isWarning ? AppTheme.stressColor : AppTheme.successColor;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                insight['icon'] ?? (isWarning ? '⚠️' : '✅'),
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        insight['category'] ?? 'Health',
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  insight['title'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  insight['description'] ?? '',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                if (insight['value'] != null && insight['benchmark'] != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Your value: ${insight['value']}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Avg: ${insight['benchmark']}',
                        style: const TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildQuickStats() {
    final weekAvg = healthApiService.getWeeklyAverages();
    final trends = healthApiService.getWeekOverWeekChange();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📊 Weekly Averages',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _statCard(
                'Sleep',
                '${weekAvg['sleep']?.round() ?? 0}',
                AppTheme.sleepColor,
                _getTrendIcon(trends['sleep'] ?? 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statCard(
                'HRV',
                '${weekAvg['hrv']?.round() ?? 0}ms',
                AppTheme.hrvColor,
                _getTrendIcon(trends['hrv'] ?? 0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _statCard(
                'Stress',
                '${weekAvg['stress']?.round() ?? 0}',
                AppTheme.stressColor,
                _getTrendIcon(-(trends['stress'] ?? 0)), // Lower is better
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statCard(
                'Steps',
                '${((weekAvg['steps'] ?? 0) / 1000).toStringAsFixed(1)}k',
                AppTheme.activityColor,
                _getTrendIcon(trends['steps'] ?? 0),
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  String _getTrendIcon(double change) {
    if (change > 3) return '📈';
    if (change < -3) return '📉';
    return '➡️';
  }
  
  Widget _statCard(String label, String value, Color color, String trend) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Text(trend, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
