import 'package:flutter/material.dart';
import '../services/app_data_source.dart';
import '../theme/app_theme.dart';
import 'analytics_deep_dive_screen.dart';
import 'correlation_explorer_screen.dart';
import 'predictions_center_screen.dart';

/// Hub for the exploratory analysis screens, which open as full pages so the
/// bottom navigation stays short. AI Lab is listed only when the data source
/// has its legacy analytics (the self-hosted backend does).
class AnalyzeScreen extends StatelessWidget {
  const AnalyzeScreen({super.key, this.service});

  /// Defaults to the app-wide [dataSource]; injectable for tests.
  final HealthDataSource? service;

  @override
  Widget build(BuildContext context) {
    final source = service ?? dataSource;
    final entries = <({IconData icon, String title, String subtitle, WidgetBuilder builder})>[
      (
        icon: Icons.hub_rounded,
        title: 'Patterns',
        subtitle: 'How your sleep, HRV, stress and activity move together',
        builder: (_) => CorrelationExplorerScreen(service: source),
      ),
      (
        icon: Icons.auto_graph_rounded,
        title: 'Predictions',
        subtitle: "Tomorrow's outlook from your recent trends",
        builder: (_) => PredictionsCenterScreen(service: source),
      ),
      if (source.hasAnalytics)
        (
          icon: Icons.science_rounded,
          title: 'AI Lab',
          subtitle: 'Correlations, anomalies, weekly patterns and baselines',
          builder: (_) => const AnalyticsDeepDiveScreen(),
        ),
    ];
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Analyze'),
        centerTitle: true,
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final e in entries)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                  child: Icon(e.icon, color: AppTheme.primaryColor),
                ),
                title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(e.subtitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: e.builder)),
              ),
            ),
        ],
      ),
    );
  }
}
