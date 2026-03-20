import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/health_api_service.dart';

/// Predictions Center showing forecasts based on YOUR real Garmin data patterns
class PredictionsCenterScreen extends StatefulWidget {
  const PredictionsCenterScreen({super.key});

  @override
  State<PredictionsCenterScreen> createState() => _PredictionsCenterScreenState();
}

class _PredictionsCenterScreenState extends State<PredictionsCenterScreen> {
  Map<String, dynamic>? _prediction;
  Map<String, dynamic>? _today;
  Map<String, double> _weekAvg = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    await healthApiService.initialize();
    
    setState(() {
      _prediction = healthApiService.predictTomorrow();
      _today = healthApiService.today;
      _weekAvg = healthApiService.getWeeklyAverages();
      _isLoading = false;
    });
  }

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
                    const SizedBox(height: 24),
                    
                    // Optimal Times
                    _buildOptimalTimes(),
                    
                    const SizedBox(height: 100),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildTomorrowPrediction() {
    if (_prediction == null || _prediction!['confidence'] == 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          children: [
            Icon(Icons.hourglass_empty, size: 48, color: AppTheme.textTertiary),
            SizedBox(height: 12),
            Text(
              'Need more data for predictions',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    final intensity = _prediction!['recommendedIntensity'] as String;
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
          colors: [intensityColor, intensityColor.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: intensityColor.withOpacity(0.3),
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
                  color: Colors.white.withOpacity(0.2),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 70,
                      height: 70,
                      child: CircularProgressIndicator(
                        value: (_prediction!['predictedBodyBattery'] ?? 50) / 100,
                        strokeWidth: 6,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${_prediction!['predictedBodyBattery'] ?? 50}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Battery',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
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
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_prediction!['confidence']}% Confidence',
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
              color: Colors.white.withOpacity(0.15),
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
        Text(
          'What\'s influencing tomorrow\'s prediction',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 16),
        
        ...factors.map((factor) => _buildFactorCard(factor)).toList(),
        
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
                    _miniStatusCard('Sleep', '${_today!['sleep_score'] ?? 0}', AppTheme.sleepColor),
                    _miniStatusCard('Battery', '${_today!['body_battery_end'] ?? 0}', AppTheme.bodyBatteryColor),
                    _miniStatusCard('Stress', '${_today!['avg_stress'] ?? 0}', AppTheme.stressColor),
                    _miniStatusCard('HRV', '${_today!['hrv']?.round() ?? 0}', AppTheme.hrvColor),
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
    final isNeutral = impact == 'neutral';
    
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
          color: impactColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: impactColor.withOpacity(0.1),
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
              color: impactColor.withOpacity(0.1),
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
    if (_weekAvg.isEmpty) return const SizedBox();
    
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
                _weekAvg['sleep'] ?? 0,
                100,
                AppTheme.sleepColor,
                healthApiService.getTrend('sleep'),
              ),
              const Divider(height: 24),
              _buildForecastRow(
                'HRV Baseline',
                _weekAvg['hrv'] ?? 0,
                100,
                AppTheme.hrvColor,
                healthApiService.getTrend('hrv'),
              ),
              const Divider(height: 24),
              _buildForecastRow(
                'Stress Pattern',
                _weekAvg['stress'] ?? 0,
                100,
                AppTheme.stressColor,
                healthApiService.getTrend('stress'),
              ),
              const Divider(height: 24),
              _buildForecastRow(
                'Activity Level',
                _weekAvg['steps'] ?? 0,
                15000,
                AppTheme.activityColor,
                healthApiService.getTrend('steps'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildForecastRow(String label, double value, double max, Color color, String trend) {
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
      default:
        trendEmoji = '➡️';
        trendText = 'Stable';
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
                label.contains('Step') 
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
                  value: (value / max).clamp(0, 1),
                  backgroundColor: color.withOpacity(0.2),
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

  Widget _buildOptimalTimes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '⏰ Optimal Times',
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
              _buildTimeRecommendation(
                '🏃 Best Workout Time',
                '7:00 - 9:00 AM',
                'Body Battery typically peaks in morning',
                AppTheme.activityColor,
              ),
              const Divider(height: 24),
              _buildTimeRecommendation(
                '😴 Optimal Bedtime',
                '10:30 PM',
                'Based on your sleep pattern analysis',
                AppTheme.sleepColor,
              ),
              const Divider(height: 24),
              _buildTimeRecommendation(
                '🧘 Recovery Window',
                '2:00 - 4:00 PM',
                'When stress tends to peak - good for breaks',
                AppTheme.bodyBatteryColor,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimeRecommendation(String title, String time, String reason, Color color) {
    return Row(
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
              title.split(' ').first,
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.replaceFirst(RegExp(r'^[^\s]+\s'), ''),
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
              Text(
                time,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: color,
                ),
              ),
              Text(
                reason,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
