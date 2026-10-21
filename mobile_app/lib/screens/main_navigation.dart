import 'package:flutter/material.dart';
import '../services/app_data_source.dart';
import '../theme/app_theme.dart';
import 'analyze_screen.dart';
import 'coach_screen.dart';
import 'insights_feed_screen.dart';
import 'real_data_dashboard.dart';
import 'today_screen.dart';

/// Main navigation shell with bottom navigation bar. The Coach tab appears
/// only when the data source has a coach (the self-hosted backend does; the
/// public app's on-device source doesn't yet).
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key, this.service});

  /// Defaults to the app-wide [dataSource]; injectable for tests.
  final HealthDataSource? service;

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  late final HealthDataSource _service = widget.service ?? dataSource;

  late final _tabs = [
    // readiness + training load
    (icon: Icons.wb_sunny_rounded, label: 'Today', screen: TodayScreen(service: _service)),
    if (_service.hasCoach)
      (icon: Icons.forum_rounded, label: 'Coach', screen: CoachScreen(service: _service)),
    // raw wellness data
    (icon: Icons.analytics_rounded, label: 'My Data', screen: RealDataDashboard(service: _service)),
    (icon: Icons.auto_awesome_rounded, label: 'Insights', screen: InsightsFeedScreen(service: _service)),
    // Patterns, Predictions and, with the backend, AI Lab
    (icon: Icons.science_rounded, label: 'Analyze', screen: AnalyzeScreen(service: _service)),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [for (final tab in _tabs) tab.screen],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  _NavItem(
                    icon: _tabs[i].icon,
                    label: _tabs[i].label,
                    isSelected: _currentIndex == i,
                    onTap: () => setState(() => _currentIndex = i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? AppTheme.primaryColor : AppTheme.textTertiary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? AppTheme.primaryColor : AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
