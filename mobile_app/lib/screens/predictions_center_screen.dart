import 'package:flutter/material.dart';
import '../config.dart';
import '../theme/app_theme.dart';
import '../services/health_api_service.dart';

/// Predictions Center: tomorrow's body battery from the backend
/// (/api/outlook), shown with the heuristic's measured error, plus this
/// week's averages and trends.
class PredictionsCenterScreen extends StatefulWidget {
  const PredictionsCenterScreen({super.key, this.service});

  /// Defaults to the app-wide [healthApiService]; injectable for tests.
  final HealthApiService? service;

  @override
  State<PredictionsCenterScreen> createState() => _PredictionsCenterScreenState();
}

class _PredictionsCenterScreenState extends State<PredictionsCenterScreen> {
  Map<String, dynamic>? _prediction;
  String? _error;
  bool _isLoading = true;

  Map<String, dynamic>? get _today => _prediction?['today'] as Map<String, dynamic>?;
  Map<String, dynamic> get _weekAvg =>
      (_prediction?['weekly'] as Map<String, dynamic>?) ?? const {};
  Map<String, dynamic> get _trends =>
      (_prediction?['trends'] as Map<String, dynamic>?) ?? const {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    Map<String, dynamic>? outlook;
    String? error;
    try {
      outlook = await (widget.service ?? healthApiService).fetchOutlook();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      debugPrint('Outlook fetch failed: $e');
      error = "Couldn't reach the API at $apiBaseUrl. Make sure the backend server is running.";
    }
    if (!mounted) return;
    setState(() {
      _prediction = outlook;
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
      appBar: AppBar(
        title: const Text('🔮 Predictions'),
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
                    // Tomorrow's Prediction Card
                    _buildTomorrowPrediction(),
                    const SizedBox(height: 24),
                    
                    // Prediction Factors
                    _buildPredictionFactors(),
                    const SizedBox(height: 24),
                    
                    // Weekly Forecast
                    _buildWeeklyForecast(),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildTomorrowPrediction() {
    if (_prediction == null || _prediction!['available'] != true) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(_error != null ? Icons.cloud_off : Icons.hourglass_empty,
                size: 48, color: AppTheme.textTertiary),
            const SizedBox(height: 12),
            Text(
              _error ?? (_prediction?['message'] as String?) ?? 'Need more data for predictions',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    final intensity = _prediction!['recommended_intensity'] as String;
    final predicted = _prediction!['predicted_body_battery'] as num;
    final backtest = _prediction!['backtest'] as Map<String, dynamic>?;
    Color intensityColor;
    IconData intensityIcon;
    
    switch (intensity) {
      case 'high':
        intensityColor = AppTheme.successColor;
        intensityIcon = Icons.flash_on;
        break;
      case 'moderate':
        intensityColor = Colors.orange;
        intensityIcon = Icons.directions_run;
        break;
      default:
        intensityColor = AppTheme.sleepColor;
        intensityIcon = Icons.self_improvement;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [intensityColor, intensityColor.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: intensityColor.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(intensityIcon, color: Colors.white, size: 32),
              const SizedBox(width: 12),
              const Text(
                'Tomorrow\'s Prediction',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Predicted Body Battery
          Row(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 70,
                      height: 70,
                      child: CircularProgressIndicator(
                        value: (predicted / 100).clamp(0, 1).toDouble(),
                        strokeWidth: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.3),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$predicted',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Battery',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${intensity.toUpperCase()} INTENSITY',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      'Recommended',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      // Measured by replaying the same heuristic over past days.
                      child: Text(
                        backtest == null
                            ? 'Accuracy not measured yet'
                            : 'Usually off by ~${(backtest['mean_abs_error'] as num).round()} '
                                '(tested on ${backtest['days']} days)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _prediction!['recommendation'] ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionFactors() {
    final factors = _prediction?['factors'] as List<dynamic>? ?? [];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📊 Prediction Factors',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'What\'s influencing tomorrow\'s prediction',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 16),
        
        ...factors.map((factor) => _buildFactorCard(factor)),
        
        // Current day stats
        if (_today != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Today\'s Status',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _miniStatusCard('Sleep', _fmt(_today!['sleep_score']), AppTheme.sleepColor),
                    _miniStatusCard('Battery', _fmt(_today!['body_battery_end']), AppTheme.bodyBatteryColor),
                    _miniStatusCard('Stress', _fmt(_today!['avg_stress']), AppTheme.stressColor),
                    _miniStatusCard('HRV', _fmt(_today!['hrv']), AppTheme.hrvColor),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFactorCard(Map<String, dynamic> factor) {
    final impact = factor['impact'] as String;
    final isPositive = impact == 'positive';
    // "unknown": the metric wasn't measured, so it can't push either way.
    final isNeutral = impact == 'neutral' || impact == 'unknown';
    
    Color impactColor = isPositive 
        ? AppTheme.successColor 
        : (isNeutral ? Colors.grey : AppTheme.stressColor);
    IconData impactIcon = isPositive 
        ? Icons.thumb_up 
        : (isNeutral ? Icons.remove : Icons.thumb_down);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: impactColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: impactColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(impactIcon, color: impactColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  factor['name'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Value: ${factor['value'] ?? 'N/A'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: impactColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              impact.toUpperCase(),
              style: TextStyle(
                color: impactColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStatusCard(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyForecast() {
    if (_weekAvg.values.every((v) => v == null)) return const SizedBox();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📈 Weekly Outlook',
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
              _buildForecastRow(
                'Sleep Trend',
                _weekAvg['sleep'] as num?,
                100,
                AppTheme.sleepColor,
                _trends['sleep'] as String? ?? 'unknown',
              ),
              const Divider(height: 24),
              _buildForecastRow(
                'HRV Baseline',
                _weekAvg['hrv'] as num?,
                100,
                AppTheme.hrvColor,
                _trends['hrv'] as String? ?? 'unknown',
              ),
              const Divider(height: 24),
              _buildForecastRow(
                'Stress Pattern',
                _weekAvg['stress'] as num?,
                100,
                AppTheme.stressColor,
                _trends['stress'] as String? ?? 'unknown',
              ),
              const Divider(height: 24),
              _buildForecastRow(
                'Activity Level',
                _weekAvg['steps'] as num?,
                15000,
                AppTheme.activityColor,
                _trends['steps'] as String? ?? 'unknown',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildForecastRow(String label, num? value, double max, Color color, String trend) {
    String trendEmoji;
    String trendText;
    
    switch (trend) {
      case 'improving':
        trendEmoji = '📈';
        trendText = 'Improving';
        break;
      case 'declining':
        trendEmoji = '📉';
        trendText = 'Declining';
        break;
      case 'stable':
        trendEmoji = '➡️';
        trendText = 'Stable';
        break;
      default:
        trendEmoji = '·';
        trendText = 'Not enough data yet';
    }
    
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(trendEmoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(
                    trendText,
                    style: TextStyle(
                      fontSize: 12,
                      color: trend == 'improving' 
                          ? AppTheme.successColor 
                          : (trend == 'declining' ? AppTheme.stressColor : AppTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value == null
                    ? '—'
                    : label.contains('Activity')
                        ? '${(value / 1000).toStringAsFixed(1)}k'
                        : value.round().toString(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ((value ?? 0) / max).clamp(0, 1).toDouble(),
                  backgroundColor: color.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation(color),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
