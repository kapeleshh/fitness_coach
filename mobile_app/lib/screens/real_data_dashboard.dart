import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';

/// Dashboard showing YOUR real Garmin data from API
class RealDataDashboard extends StatefulWidget {
  const RealDataDashboard({super.key});

  @override
  State<RealDataDashboard> createState() => _RealDataDashboardState();
}

class _RealDataDashboardState extends State<RealDataDashboard> {
  Map<String, dynamic>? _summary;
  List<dynamic>? _healthData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Fetch from API
      final summaryRes = await http.get(Uri.parse('http://localhost:8081/api/summary'));
      final dataRes = await http.get(Uri.parse('http://localhost:8081/api/health-data'));
      
      if (summaryRes.statusCode == 200 && dataRes.statusCode == 200) {
        setState(() {
          _summary = json.decode(summaryRes.body);
          _healthData = json.decode(dataRes.body);
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not connect to API. Make sure the server is running on port 8081.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading your Garmin data...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Connection Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _error = null;
                    });
                    _loadData();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final today = _summary?['recent_day'] ?? {};
    final averages = _summary?['averages'] ?? {};
    final totalDays = _summary?['total_days'] ?? 0;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('📊 Your Real Data'),
        centerTitle: true,
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary Card
              _buildSummaryCard(totalDays, averages),
              const SizedBox(height: 16),
              
              // Today's Data
              const Text(
                "Today's Snapshot",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _buildTodayCard(today),
              const SizedBox(height: 24),
              
              // Recent Days
              const Text(
                'Recent 7 Days',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ..._buildRecentDaysList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(int totalDays, Map<String, dynamic> averages) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                '$totalDays Days of Data',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _miniStatCard(
                  'Avg Sleep',
                  '${averages['sleep_score']?.toStringAsFixed(0) ?? 'N/A'}',
                  Icons.bedtime,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniStatCard(
                  'Avg HRV',
                  '${averages['hrv']?.toStringAsFixed(0) ?? 'N/A'}ms',
                  Icons.favorite,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniStatCard(
                  'Avg Stress',
                  '${averages['stress']?.toStringAsFixed(0) ?? 'N/A'}',
                  Icons.psychology,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 4),
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
              color: Colors.white.withOpacity(0.8),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayCard(Map<String, dynamic> today) {
    return Container(
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
        children: [
          // Date
          Text(
            today['date'] ?? 'Today',
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          // Stats Grid
          Row(
            children: [
              Expanded(child: _statTile('💤 Sleep', '${today['sleep_score'] ?? 0}', AppTheme.sleepColor)),
              Expanded(child: _statTile('💚 Battery', '${today['body_battery_start'] ?? 0}→${today['body_battery_end'] ?? 0}', AppTheme.bodyBatteryColor)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _statTile('❤️ HRV', '${today['hrv']?.toStringAsFixed(0) ?? 0}ms', AppTheme.hrvColor)),
              Expanded(child: _statTile('😰 Stress', '${today['avg_stress'] ?? 0}', AppTheme.stressColor)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _statTile('🚶 Steps', '${today['steps'] ?? 0}', AppTheme.activityColor)),
              Expanded(child: _statTile('🔥 Calories', '${today['total_calories'] ?? 0}', Colors.orange)),
            ],
          ),
          const SizedBox(height: 16),
          // Sleep breakdown
          if (today['sleep_feedback'] != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.sleepColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insights, color: AppTheme.sleepColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatSleepFeedback(today['sleep_feedback']),
                      style: const TextStyle(fontSize: 13, color: AppTheme.sleepColor),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatSleepFeedback(String feedback) {
    return feedback
        .replaceAll('POSITIVE_', '✅ ')
        .replaceAll('NEGATIVE_', '⚠️ ')
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(' ')
        .map((word) => word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '')
        .join(' ');
  }

  Widget _statTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRecentDaysList() {
    if (_healthData == null || _healthData!.isEmpty) {
      return [const Text('No data available')];
    }

    return _healthData!.take(7).map((day) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Date
            SizedBox(
              width: 80,
              child: Text(
                day['date']?.substring(5) ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            // Sleep
            Expanded(
              child: _miniMetric('💤', day['sleep_score']?.toString() ?? '-', AppTheme.sleepColor),
            ),
            // Body Battery
            Expanded(
              child: _miniMetric('💚', '${day['body_battery_start'] ?? '-'}', AppTheme.bodyBatteryColor),
            ),
            // HRV
            Expanded(
              child: _miniMetric('❤️', '${day['hrv']?.toStringAsFixed(0) ?? '-'}', AppTheme.hrvColor),
            ),
            // Stress
            Expanded(
              child: _miniMetric('😰', '${day['avg_stress'] ?? '-'}', AppTheme.stressColor),
            ),
            // Steps
            Expanded(
              child: _miniMetric('🚶', '${((day['steps'] ?? 0) / 1000).toStringAsFixed(1)}k', AppTheme.activityColor),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _miniMetric(String emoji, String value, Color color) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
