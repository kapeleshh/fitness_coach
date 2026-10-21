import 'package:flutter/material.dart';
import '../config.dart';
import '../theme/app_theme.dart';
import '../services/health_api_service.dart';

/// Insights Feed: readiness, rule-based insights and weekly averages, all
/// computed by the backend (/api/insights) — missing metrics arrive as null.
class InsightsFeedScreen extends StatefulWidget {
  const InsightsFeedScreen({super.key, this.service});

  /// Defaults to the app-wide [healthApiService]; injectable for tests.
  final HealthApiService? service;

  @override
  State<InsightsFeedScreen> createState() => _InsightsFeedScreenState();
}

class _InsightsFeedScreenState extends State<InsightsFeedScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _isLoading = true;

  List<Map<String, dynamic>> get _insights =>
      ((_data?['insights'] as List?) ?? const []).cast<Map<String, dynamic>>();
  Map<String, dynamic>? get _today => _data?['today'] as Map<String, dynamic>?;
  Map<String, dynamic> get _readiness =>
      (_data?['readiness'] as Map<String, dynamic>?) ?? const {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    Map<String, dynamic>? data;
    String? error;
    try {
      data = await (widget.service ?? healthApiService).fetchInsights();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      debugPrint('Insights fetch failed: $e');
      error = "Couldn't reach the API at $apiBaseUrl. Make sure the backend server is running.";
    }
    if (!mounted) return;
    setState(() {
      _data = data;
      _error = error;
      _isLoading = false;
    });
  }

  /// A whole-number display value, or "—" when the metric wasn't measured.
  static String _fmt(Object? value) => value is num ? '${value.round()}' : '—';

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
                        AppTheme.primaryColor.withValues(alpha: 0.1),
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
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
                      ],
                    ),
                  ),
                ),
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
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.check_circle, 
                            size: 64, color: AppTheme.successColor),
                        SizedBox(height: 16),
                        Text(
                          'All Looking Good! 🎉',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        SizedBox(height: 8),
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
  
  /// The backend's readiness score (the same one the Today tab shows).
  Widget _buildHealthScoreCard() {
    final score = _readiness['score'] as num?;
    final scoreLabel = switch (_readiness['band']) {
      'green' => 'Ready',
      'amber' => 'Take it easy',
      'red' => 'Recover',
      _ => 'No score',
    };
    final scoreColor = switch (_readiness['band']) {
      'green' => AppTheme.successColor,
      'amber' => Colors.orange,
      'red' => AppTheme.stressColor,
      _ => Colors.white,
    };
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.3),
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
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 90,
                      height: 90,
                      child: CircularProgressIndicator(
                        value: (score ?? 0) / 100,
                        strokeWidth: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.3),
                        valueColor: AlwaysStoppedAnimation(scoreColor),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _fmt(score),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          scoreLabel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
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
                      'Readiness',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (_data?['date'] as String?) ?? 'Today',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _miniStat('Sleep', _fmt(_today?['sleep_score'])),
                        const SizedBox(width: 16),
                        _miniStat('HRV', _fmt(_today?['hrv'])),
                        const SizedBox(width: 16),
                        _miniStat('Stress', _fmt(_today?['avg_stress'])),
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
            color: Colors.white.withValues(alpha: 0.7),
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
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
              color: color.withValues(alpha: 0.1),
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
                        color: color.withValues(alpha: 0.1),
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
    final weekly = (_data?['weekly'] as Map<String, dynamic>?) ?? const {};
    final weekAvg = (weekly['this_week'] as Map<String, dynamic>?) ?? const {};
    final trends = (weekly['trends'] as Map<String, dynamic>?) ?? const {};
    final steps = weekAvg['steps'] as num?;
    
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
                _fmt(weekAvg['sleep']),
                AppTheme.sleepColor,
                _getTrendIcon(trends['sleep']),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statCard(
                'HRV',
                weekAvg['hrv'] == null ? '—' : '${_fmt(weekAvg['hrv'])}ms',
                AppTheme.hrvColor,
                _getTrendIcon(trends['hrv']),
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
                _fmt(weekAvg['stress']),
                AppTheme.stressColor,
                _getTrendIcon(trends['stress']), // the backend knows lower is better
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statCard(
                'Steps',
                steps == null ? '—' : '${(steps / 1000).toStringAsFixed(1)}k',
                AppTheme.activityColor,
                _getTrendIcon(trends['steps']),
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  /// Week-over-week trend from the backend; blank when it can't tell yet.
  String _getTrendIcon(Object? trend) => switch (trend) {
        'improving' => '📈',
        'declining' => '📉',
        'stable' => '➡️',
        _ => '',
      };
  
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
