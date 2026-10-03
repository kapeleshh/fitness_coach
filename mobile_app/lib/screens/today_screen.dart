import 'package:flutter/material.dart';
import '../config.dart';
import '../services/health_api_service.dart';
import '../theme/app_theme.dart';

/// Home screen: today's readiness (with its training-load note), the last
/// two weeks of readiness, training load and recent sessions. Every number
/// is computed by the backend; this screen only lays it out.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, this.service});

  /// Defaults to the app-wide [healthApiService]; injectable for tests.
  final HealthApiService? service;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

/// One endpoint's result: the decoded body, or a message saying why not.
typedef _Fetched = ({Map<String, dynamic>? data, String? error});

class _TodayScreenState extends State<TodayScreen> {
  _Fetched? _readiness;
  _Fetched? _history;
  _Fetched? _load;
  bool _isLoading = true;

  HealthApiService get _service => widget.service ?? healthApiService;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<_Fetched> _fetch(Future<Map<String, dynamic>> Function() call) async {
    try {
      return (data: await call(), error: null);
    } on ApiException catch (e) {
      return (data: null, error: e.message);
    } catch (e) {
      debugPrint('Today screen fetch failed: $e');
      return (data: null, error: "Couldn't reach the API at $apiBaseUrl.");
    }
  }

  Future<void> _loadData() async {
    // Independent requests: one failing endpoint still leaves the others.
    final results = await Future.wait([
      _fetch(_service.fetchReadiness),
      _fetch(() => _service.fetchReadinessHistory(days: 14)),
      _fetch(_service.fetchTrainingLoad),
    ]);
    if (!mounted) return;
    setState(() {
      _readiness = results[0];
      _history = results[1];
      _load = results[2];
      _isLoading = false;
    });
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
              Text("Loading today's readiness..."),
            ],
          ),
        ),
      );
    }

    if (_readiness!.data == null && _load!.data == null) {
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
                Text(
                  _readiness!.error ?? 'Unable to load readiness.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _isLoading = true);
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

    final series = (_history?.data?['series'] as List?) ?? const [];
    final sessions = (_load?.data?['recent_sessions'] as List?) ?? const [];

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Today'),
        centerTitle: true,
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _ReadinessCard(fetched: _readiness!),
            if (series.isNotEmpty) ...[
              const SizedBox(height: 16),
              _ReadinessStrip(series: series.cast<Map<String, dynamic>>()),
            ],
            const SizedBox(height: 16),
            _TrainingLoadCard(fetched: _load!),
            if (sessions.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'Recent sessions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              for (final s in sessions.cast<Map<String, dynamic>>())
                _SessionTile(session: s),
            ],
          ],
        ),
      ),
    );
  }
}

// ============= SHARED PIECES =============

Color _readinessColor(String? band) => switch (band) {
      'green' => AppTheme.successColor,
      'amber' => AppTheme.warningColor,
      'red' => AppTheme.errorColor,
      _ => AppTheme.textTertiary,
    };

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "2026-07-05" -> "Sun 5 Jul"; anything unparseable is returned as-is.
String _shortDate(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso);
  if (d == null) return iso ?? '';
  return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.what, required this.message});

  final String what;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline, color: AppTheme.textTertiary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            "$what isn't available: ${message ?? 'unknown error'}",
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

// ============= READINESS =============

/// Readiness flags worth surfacing; internal ones are left out.
const _readinessFlagLabels = {
  'illness_watch': 'Possible illness or overreaching',
  'hrv_suppressed': 'HRV strongly suppressed',
  'hrv_drop_watch': 'Sharp HRV drop',
  'stale_hrv': 'HRV data is stale',
};

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.fetched});

  final _Fetched fetched;

  @override
  Widget build(BuildContext context) {
    final r = fetched.data;
    if (r == null) {
      return _Panel(child: _InlineError(what: 'Readiness', message: fetched.error));
    }
    final score = r['score'] as num?;
    final color = _readinessColor(r['band'] as String?);
    final flags = ((r['flags'] as List?) ?? const [])
        .where(_readinessFlagLabels.containsKey)
        .map((f) => _readinessFlagLabels[f]!)
        .toList();

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: (score ?? 0) / 100,
                        strokeWidth: 7,
                        color: color,
                        backgroundColor: color.withValues(alpha: 0.15),
                      ),
                    ),
                    Text(
                      score?.toString() ?? '—',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (r['label'] as String?) ?? 'Readiness',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Readiness · ${r['confidence']} confidence',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    Text(
                      _shortDate(r['date'] as String?),
                      style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (flags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in flags)
                  _Chip(
                    label: f,
                    color: AppTheme.errorColor,
                    icon: Icons.warning_amber_rounded,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            (r['briefing'] as String?) ?? '',
            style: const TextStyle(fontSize: 14, height: 1.45, color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// Last 14 days of readiness as bars, oldest on the left.
class _ReadinessStrip extends StatelessWidget {
  const _ReadinessStrip({required this.series});

  /// Newest first, as /api/readiness/history returns it.
  final List<Map<String, dynamic>> series;

  @override
  Widget build(BuildContext context) {
    final days = series.reversed.toList();
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Readiness, last 14 days',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in days)
                  Expanded(
                    child: Tooltip(
                      message: '${_shortDate(d['date'] as String?)}: '
                          '${d['score'] ?? 'no score'}',
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: d['score'] == null
                            ? 4
                            : 6 + 54 * (d['score'] as num) / 100,
                        decoration: BoxDecoration(
                          color: _readinessColor(d['band'] as String?),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_shortDate(days.first['date'] as String?),
                  style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
              Text(_shortDate(days.last['date'] as String?),
                  style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
            ],
          ),
        ],
      ),
    );
  }
}

// ============= TRAINING LOAD =============

const _formBandLabels = {
  'transition': 'Very fresh',
  'fresh': 'Fresh',
  'neutral': 'Balanced',
  'building': 'Building',
  'overreaching': 'High fatigue',
};

Color _formBandColor(String? band) => switch (band) {
      'transition' => AppTheme.infoColor,
      'fresh' => AppTheme.successColor,
      'building' => AppTheme.primaryColor,
      'overreaching' => AppTheme.errorColor,
      _ => AppTheme.textSecondary,
    };

class _TrainingLoadCard extends StatelessWidget {
  const _TrainingLoadCard({required this.fetched});

  final _Fetched fetched;

  @override
  Widget build(BuildContext context) {
    final t = fetched.data;
    if (t == null) {
      return _Panel(child: _InlineError(what: 'Training load', message: fetched.error));
    }
    final title = Row(
      children: [
        const Icon(Icons.fitness_center, color: AppTheme.activityColor),
        const SizedBox(width: 8),
        const Text(
          'Training load',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const Spacer(),
        if (t['ctl'] != null)
          _Chip(
            label: _formBandLabels[t['form_band']] ?? 'Warming up',
            color: _formBandColor(t['form_band'] as String?),
          ),
      ],
    );
    // No activities at all: the backend's summary says what to do about it.
    if (t['ctl'] == null) {
      return _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: 12),
            Text((t['summary'] as String?) ?? '',
                style: const TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    final formPct = t['form_pct'] as num?;
    final week = (t['last_7_days'] as Map?) ?? const {};
    final flags = (t['flags'] as List?) ?? const [];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat(label: 'Fitness', value: '${(t['ctl'] as num).round()}'),
              _Stat(label: 'Fatigue', value: '${(t['atl'] as num).round()}'),
              _Stat(
                label: formPct == null
                    ? 'Form'
                    : 'Form (${formPct >= 0 ? '+' : ''}${formPct.round()}%)',
                value: '${(t['tsb'] as num) >= 0 ? '+' : ''}${(t['tsb'] as num).round()}',
              ),
            ],
          ),
          if (flags.contains('load_spike')) ...[
            const SizedBox(height: 12),
            _Chip(
              label: 'Load spike: acute:chronic ${(t['acwr'] as num).toStringAsFixed(2)}',
              color: AppTheme.warningColor,
              icon: Icons.trending_up,
            ),
          ],
          // While the baseline builds, the summary explains why there's no band.
          if (t['form_band'] == null) ...[
            const SizedBox(height: 12),
            Text((t['summary'] as String?) ?? '',
                style: const TextStyle(color: AppTheme.textSecondary)),
          ],
          const SizedBox(height: 12),
          Text(
            'Last 7 days: ${week['sessions'] ?? 0} sessions · ${week['minutes'] ?? 0} min · '
            'load ${((week['load'] as num?) ?? 0).round()} · ${t['confidence']} confidence',
            style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

// ============= SESSIONS =============

IconData _sportIcon(String? family) => switch (family) {
      'run' => Icons.directions_run,
      'ride' => Icons.directions_bike,
      'swim' => Icons.pool,
      'walk' => Icons.directions_walk,
      'hike' => Icons.hiking,
      'strength' => Icons.fitness_center,
      'yoga' => Icons.self_improvement,
      'row' => Icons.rowing,
      'ski' => Icons.downhill_skiing,
      _ => Icons.sports,
    };

const _methodLabels = {
  'garmin_load': 'Garmin load',
  'trimp': 'Heart-rate TRIMP',
  'relative_effort': 'Relative Effort',
  'duration_estimate': 'Estimated',
  'none': 'No load data',
};

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final family = session['sport_family'] as String?;
    final minutes = session['minutes'] as num?;
    final sport = (family == null || family.isEmpty)
        ? 'Activity'
        : '${family[0].toUpperCase()}${family.substring(1)}';
    final sources = ((session['sources'] as List?) ?? const [])
        .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
        .join(' + ');
    final estimated = session['method'] == 'duration_estimate';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _Panel(
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.activityColor.withValues(alpha: 0.12),
              child: Icon(_sportIcon(family), color: AppTheme.activityColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    minutes == null ? sport : '$sport · ${minutes.round()} min',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    '${_shortDate(session['local_date'] as String?)} · $sources',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${((session['load'] as num?) ?? 0).round()}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  _methodLabels[session['method']] ?? 'Load',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                    fontStyle: estimated ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
