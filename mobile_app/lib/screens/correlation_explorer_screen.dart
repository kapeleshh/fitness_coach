import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/health_api_service.dart';

/// Pattern Explorer showing real correlations discovered in YOUR Garmin data
class CorrelationExplorerScreen extends StatefulWidget {
  const CorrelationExplorerScreen({super.key});

  @override
  State<CorrelationExplorerScreen> createState() => _CorrelationExplorerScreenState();
}

class _CorrelationExplorerScreenState extends State<CorrelationExplorerScreen> {
  List<Map<String, dynamic>> _correlations = [];
  bool _isLoading = true;
  String _selectedMetric1 = 'sleep_score';
  String _selectedMetric2 = 'body_battery_start';
  Map<String, dynamic>? _customCorrelation;

  final Map<String, String> _metricLabels = {
    'sleep_score': 'Sleep Score',
    'hrv': 'HRV',
    'avg_stress': 'Stress Level',
    'body_battery_start': 'Body Battery (Morning)',
    'body_battery_end': 'Body Battery (Evening)',
    'steps': 'Steps',
    'deep_sleep_minutes': 'Deep Sleep',
    'resting_hr': 'Resting HR',
    'total_calories': 'Calories',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    await healthApiService.initialize();
    
    setState(() {
      _correlations = healthApiService.discoverCorrelations();
      _isLoading = false;
    });
  }

  void _calculateCustomCorrelation() {
    setState(() {
      _customCorrelation = healthApiService.calculateCorrelation(
        _selectedMetric1,
        _selectedMetric2,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('🔍 Pattern Explorer'),
        centerTitle: true,
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.insights, color: Colors.white, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Your Health Patterns',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Based on ${healthApiService.totalDays} days of data',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Discovered Correlations
                    const Text(
                      '🔬 Discovered Correlations',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Patterns found in your data',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    if (_correlations.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.search_off, size: 48, color: AppTheme.textTertiary),
                            SizedBox(height: 12),
                            Text(
                              'No strong correlations found yet',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._correlations.map((c) => _buildCorrelationCard(c)).toList(),
                    
                    const SizedBox(height: 24),
                    
                    // Custom Correlation Explorer
                    const Text(
                      '🧪 Explore Your Own Patterns',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select two metrics to compare:',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Metric 1 dropdown
                          _buildDropdown(
                            'First Metric',
                            _selectedMetric1,
                            (value) => setState(() => _selectedMetric1 = value!),
                          ),
                          const SizedBox(height: 12),
                          
                          // Metric 2 dropdown
                          _buildDropdown(
                            'Second Metric',
                            _selectedMetric2,
                            (value) => setState(() => _selectedMetric2 = value!),
                          ),
                          const SizedBox(height: 16),
                          
                          // Analyze button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _calculateCustomCorrelation,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Analyze Correlation',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          
                          // Result
                          if (_customCorrelation != null) ...[
                            const SizedBox(height: 16),
                            _buildCustomCorrelationResult(),
                          ],
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Data visualization - Recent trends
                    _buildRecentTrendsChart(),
                    
                    const SizedBox(height: 100),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildDropdown(String label, String value, void Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.textTertiary),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              items: _metricLabels.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCorrelationCard(Map<String, dynamic> correlation) {
    final strength = correlation['strength'] as String;
    final corr = correlation['correlation'] as double;
    final isPositive = corr > 0;
    
    Color strengthColor;
    String strengthLabel;
    switch (strength) {
      case 'strong':
        strengthColor = AppTheme.successColor;
        strengthLabel = 'Strong';
        break;
      case 'moderate':
        strengthColor = Colors.orange;
        strengthLabel = 'Moderate';
        break;
      default:
        strengthColor = AppTheme.textTertiary;
        strengthLabel = 'Weak';
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: strengthColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: strengthColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  strengthLabel,
                  style: TextStyle(
                    color: strengthColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (correlation['lagged'] == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Next Day',
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontSize: 12,
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                isPositive ? '📈' : '📉',
                style: const TextStyle(fontSize: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            correlation['label'] ?? '',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Correlation',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    Text(
                      '${(corr * 100).round()}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: strengthColor,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Data Points',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    Text(
                      '${correlation['sampleSize']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _getCorrelationExplanation(correlation),
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String _getCorrelationExplanation(Map<String, dynamic> correlation) {
    final m1 = _metricLabels[correlation['metric1']] ?? correlation['metric1'];
    final m2 = _metricLabels[correlation['metric2']] ?? correlation['metric2'];
    final corr = correlation['correlation'] as double;
    final strength = correlation['strength'] as String;
    
    if (corr > 0) {
      return 'When your $m1 increases, your $m2 tends to increase as well. '
             'This is a ${strength} positive relationship.';
    } else {
      return 'When your $m1 increases, your $m2 tends to decrease. '
             'This is a ${strength} negative relationship.';
    }
  }

  Widget _buildCustomCorrelationResult() {
    final corr = _customCorrelation!['correlation'] as double;
    final strength = _customCorrelation!['strength'] as String;
    
    if (strength == 'insufficient_data') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.info, color: Colors.orange),
            SizedBox(width: 8),
            Text('Not enough data to calculate correlation'),
          ],
        ),
      );
    }
    
    Color strengthColor;
    switch (strength) {
      case 'strong':
        strengthColor = AppTheme.successColor;
        break;
      case 'moderate':
        strengthColor = Colors.orange;
        break;
      case 'weak':
        strengthColor = AppTheme.textTertiary;
        break;
      default:
        strengthColor = Colors.grey;
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: strengthColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: strengthColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _metricLabels[_selectedMetric1] ?? _selectedMetric1,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                corr > 0 ? '↔️' : '↕️',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 8),
              Text(
                _metricLabels[_selectedMetric2] ?? _selectedMetric2,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${(corr * 100).round()}%',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: strengthColor,
            ),
          ),
          Text(
            '${strength.toUpperCase()} ${corr > 0 ? 'POSITIVE' : 'NEGATIVE'} correlation',
            style: TextStyle(
              color: strengthColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Based on ${_customCorrelation!['sampleSize']} data points',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTrendsChart() {
    final week = healthApiService.last7Days;
    if (week.isEmpty) return const SizedBox();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📊 7-Day Trends',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _buildTrendRow('Sleep', week, 'sleep_score', AppTheme.sleepColor, 100),
              const SizedBox(height: 16),
              _buildTrendRow('Body Battery', week, 'body_battery_start', AppTheme.bodyBatteryColor, 100),
              const SizedBox(height: 16),
              _buildTrendRow('HRV', week, 'hrv', AppTheme.hrvColor, 100),
              const SizedBox(height: 16),
              _buildTrendRow('Stress', week, 'avg_stress', AppTheme.stressColor, 100),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrendRow(String label, List<Map<String, dynamic>> data, 
                         String field, Color color, double maxValue) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: data.reversed.take(7).map((day) {
              final value = (day[field] ?? 0).toDouble();
              final height = (value / maxValue * 40).clamp(4.0, 40.0);
              final dateStr = day['date']?.toString().substring(8, 10) ?? '';
              
              return Column(
                children: [
                  Container(
                    width: 24,
                    height: 40,
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 20,
                      height: height,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateStr,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${data.first[field]?.round() ?? 0}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
