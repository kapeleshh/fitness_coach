import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';

/// Analytics Deep Dive - AI Pattern Analysis from YOUR Garmin data
/// Shows correlations, anomalies, weekly patterns, and personal baselines
class AnalyticsDeepDiveScreen extends StatefulWidget {
  const AnalyticsDeepDiveScreen({super.key});

  @override
  State<AnalyticsDeepDiveScreen> createState() => _AnalyticsDeepDiveScreenState();
}

class _AnalyticsDeepDiveScreenState extends State<AnalyticsDeepDiveScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  Map<String, dynamic>? _correlations;
  Map<String, dynamic>? _anomalies;
  Map<String, dynamic>? _weeklyPatterns;
  Map<String, dynamic>? _baselines;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAnalytics();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);
    
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('http://localhost:8081/api/analytics/correlations')),
        http.get(Uri.parse('http://localhost:8081/api/analytics/anomalies')),
        http.get(Uri.parse('http://localhost:8081/api/analytics/weekly')),
        http.get(Uri.parse('http://localhost:8081/api/analytics/baselines')),
      ]);
      
      setState(() {
        _correlations = json.decode(responses[0].body);
        _anomalies = json.decode(responses[1].body);
        _weeklyPatterns = json.decode(responses[2].body);
        _baselines = json.decode(responses[3].body);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('🧠 AI Analytics'),
        centerTitle: true,
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primaryColor,
          tabs: const [
            Tab(text: 'Matrix'),
            Tab(text: 'Weekly'),
            Tab(text: 'Anomalies'),
            Tab(text: 'Baselines'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCorrelationTab(),
                _buildWeeklyTab(),
                _buildAnomaliesTab(),
                _buildBaselinesTab(),
              ],
            ),
    );
  }

  // ============= CORRELATION MATRIX TAB =============
  Widget _buildCorrelationTab() {
    final strongCorrs = _correlations?['strong_correlations'] as List? ?? [];
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.grid_view, color: Colors.white, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Correlation Analysis',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${strongCorrs.length} significant patterns found',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '🔗 Strongest Correlations',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...strongCorrs.map((c) => _buildCorrelationItem(c)).toList(),
        ],
      ),
    );
  }

  Widget _buildCorrelationItem(Map<String, dynamic> corr) {
    final strength = corr['strength'] as String;
    final correlation = corr['correlation'] as double;
    final isPositive = correlation > 0;
    
    Color color = strength == 'strong' ? AppTheme.successColor : Colors.orange;
    
    final metricLabels = {
      'sleep_score': 'Sleep Score',
      'hrv': 'HRV',
      'avg_stress': 'Stress',
      'body_battery_start': 'Morning Battery',
      'body_battery_end': 'Evening Battery',
      'steps': 'Steps',
      'deep_sleep_minutes': 'Deep Sleep',
      'rem_sleep_minutes': 'REM Sleep',
      'resting_hr': 'Resting HR',
      'total_calories': 'Calories',
    };
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '${(correlation * 100).round()}%',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${metricLabels[corr['metric1']] ?? corr['metric1']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      isPositive ? '↗️ positively affects' : '↘️ negatively affects',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${metricLabels[corr['metric2']] ?? corr['metric2']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              strength.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============= WEEKLY PATTERNS TAB =============
  Widget _buildWeeklyTab() {
    final patterns = _weeklyPatterns?['patterns'] as Map<String, dynamic>? ?? {};
    final insights = _weeklyPatterns?['insights'] as List? ?? [];
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Insights cards
          const Text(
            '💡 Weekly Insights',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...insights.map((i) => _buildInsightCard(i)).toList(),
          const SizedBox(height: 24),
          
          // Pattern charts
          const Text(
            '📊 Patterns by Day',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (patterns['sleep_score'] != null)
            _buildWeeklyChart('Sleep Score', patterns['sleep_score'], AppTheme.sleepColor),
          if (patterns['avg_stress'] != null)
            _buildWeeklyChart('Stress', patterns['avg_stress'], AppTheme.stressColor),
          if (patterns['hrv'] != null)
            _buildWeeklyChart('HRV', patterns['hrv'], AppTheme.hrvColor),
        ],
      ),
    );
  }

  Widget _buildInsightCard(Map<String, dynamic> insight) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: AppTheme.primaryColor, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  insight['category'] ?? '',
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                insight['impact'] == 'high' ? '⚠️ High Impact' : 'ℹ️ Moderate',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            insight['insight'] ?? '',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyChart(String title, Map<String, dynamic> data, Color color) {
    final byDay = data['by_day'] as List? ?? [];
    final bestDay = data['best_day'] as Map<String, dynamic>?;
    final worstDay = data['worst_day'] as Map<String, dynamic>?;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              if (bestDay != null)
                Text(
                  '🏆 ${bestDay['day']?.substring(0, 3)}',
                  style: TextStyle(color: color, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: byDay.map<Widget>((d) {
              final value = d['average'] as double;
              final maxValue = byDay.map((x) => x['average'] as double).reduce((a, b) => a > b ? a : b);
              final height = (value / maxValue * 60).clamp(8.0, 60.0);
              
              return Column(
                children: [
                  Container(
                    width: 32,
                    height: 60,
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 28,
                      height: height,
                      decoration: BoxDecoration(
                        color: d['day'] == bestDay?['day'] 
                            ? color 
                            : (d['day'] == worstDay?['day'] 
                                ? color.withOpacity(0.3) 
                                : color.withOpacity(0.6)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    d['day'].substring(0, 2),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    '${value.round()}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ============= ANOMALIES TAB =============
  Widget _buildAnomaliesTab() {
    final summary = _anomalies?['summary'] as Map<String, dynamic>? ?? {};
    final worstDays = _anomalies?['worst_days'] as List? ?? [];
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.stressColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.stressColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: AppTheme.stressColor, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Anomaly Detection',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        '${summary['total_anomalies'] ?? 0} anomalies detected in ${summary['days_with_anomalies'] ?? 0} days',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text(
                      '${summary['severe_count'] ?? 0}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                        color: AppTheme.stressColor,
                      ),
                    ),
                    const Text(
                      'Severe',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          const Text(
            '📅 Most Affected Days',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...worstDays.take(5).map((d) => _buildAnomalyDay(d)).toList(),
        ],
      ),
    );
  }

  Widget _buildAnomalyDay(Map<String, dynamic> day) {
    final anomalies = day['anomalies'] as List? ?? [];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                day['date'] ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: day['severe_count'] > 0 
                      ? AppTheme.stressColor.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${day['anomaly_count']} issues',
                  style: TextStyle(
                    color: day['severe_count'] > 0 ? AppTheme.stressColor : Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: anomalies.map<Widget>((a) {
              final severity = a['severity'] as String;
              Color sevColor = severity == 'severe' 
                  ? AppTheme.stressColor 
                  : (severity == 'moderate' ? Colors.orange : Colors.grey);
              
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: sevColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${a['metric_name']}: ${a['value']} (${a['direction']} ${a['deviation_pct']}%)',
                  style: TextStyle(fontSize: 11, color: sevColor),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ============= BASELINES TAB =============
  Widget _buildBaselinesTab() {
    final baselines = _baselines?['baselines'] as Map<String, dynamic>? ?? {};
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📊 Your Personal Baselines',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Based on 86 days of your data',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          ...baselines.entries.map((e) => _buildBaselineCard(e.key, e.value)).toList(),
        ],
      ),
    );
  }

  Widget _buildBaselineCard(String metric, Map<String, dynamic> data) {
    final status = data['status'] as String? ?? 'good';
    final name = data['name'] as String? ?? metric;
    final percentiles = data['percentiles'] as Map<String, dynamic>? ?? {};
    
    Color statusColor;
    String statusEmoji;
    switch (status) {
      case 'excellent':
        statusColor = AppTheme.successColor;
        statusEmoji = '🌟';
        break;
      case 'good':
        statusColor = AppTheme.bodyBatteryColor;
        statusEmoji = '✅';
        break;
      case 'fair':
        statusColor = Colors.orange;
        statusEmoji = '⚠️';
        break;
      default:
        statusColor = AppTheme.stressColor;
        statusEmoji = '❗';
    }
    
    final metricColors = {
      'sleep_score': AppTheme.sleepColor,
      'hrv': AppTheme.hrvColor,
      'avg_stress': AppTheme.stressColor,
      'body_battery_start': AppTheme.bodyBatteryColor,
      'steps': AppTheme.activityColor,
      'deep_sleep_minutes': AppTheme.sleepColor,
      'resting_hr': AppTheme.hrvColor,
    };
    
    final color = metricColors[metric] ?? AppTheme.primaryColor;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              Text(statusEmoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _baselineStat('Current', '${data['current_avg']}', color),
              _baselineStat('Average', '${data['mean']}', AppTheme.textSecondary),
              _baselineStat('Min', '${data['min']}', AppTheme.textTertiary),
              _baselineStat('Max', '${data['max']}', AppTheme.textTertiary),
            ],
          ),
          const SizedBox(height: 12),
          // Range bar
          Container(
            height: 24,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                // Optimal range
                Positioned.fill(
                  child: FractionallySizedBox(
                    widthFactor: 0.3,
                    alignment: const Alignment(0.5, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                // Current position marker
                Positioned(
                  left: _calculatePosition(data),
                  top: 2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${percentiles['p10']}', style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary)),
              Text('Optimal: ${data['optimal_range']?['low']} - ${data['optimal_range']?['high']}',
                  style: TextStyle(fontSize: 10, color: color)),
              Text('${percentiles['p90']}', style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary)),
            ],
          ),
        ],
      ),
    );
  }

  double _calculatePosition(Map<String, dynamic> data) {
    final current = (data['current_avg'] ?? 0).toDouble();
    final min = (data['min'] ?? 0).toDouble();
    final max = (data['max'] ?? 100).toDouble();
    final range = max - min;
    if (range == 0) return 0;
    return ((current - min) / range * 280).clamp(0, 280);
  }

  Widget _baselineStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 16,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
