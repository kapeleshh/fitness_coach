/// The response bodies the app reads, built on the phone exactly as
/// `backend/api_server.py` builds them, so the screens can't tell the local
/// data source from the HTTP one.
///
/// Inputs are the NULL-aware wellness records (newest first) and the
/// activity rows with duplicates.
library;

import 'insights.dart';
import 'json.dart';
import 'py.dart';
import 'readiness.dart';
import 'training_load.dart';
import 'wellness.dart';

/// `GET /api/health-data`: every record in the legacy 0-filled shape.
List<Json> healthDataBody(List<Json> wellness) => [for (final r in wellness) legacyFill(r)];

/// `GET /api/summary`: averages over the days that have each metric (null,
/// not 0, when none do), and the newest day in the legacy 0-filled shape.
Json summaryBody(List<Json> wellness) {
  if (wellness.isEmpty) return {'error': 'No data available'};

  num? avg(String key, int digits) {
    final values = [for (final d in wellness) if (d[key] case final num v) v];
    return values.isEmpty ? null : pyRound(pySum(values) / values.length, digits);
  }

  return {
    'total_days': wellness.length,
    'date_range': {'start': wellness.last['date'], 'end': wellness.first['date']},
    'averages': {
      'sleep_score': avg('sleep_score', 1),
      'hrv': avg('hrv', 1),
      'stress': avg('avg_stress', 1),
      'steps': avg('steps', 0),
    },
    'recent_day': legacyFill(wellness.first),
  };
}

/// `GET /api/readiness`: today's readiness with the training-load state for
/// that date and the fused note in the briefing.
Json readinessBody(List<Json> wellness, List<Json> activities, {Json settings = const {}}) {
  final readiness = readinessToday(wellness);
  final data = compute(wellness, activities, settings: settings);
  return annotateReadiness(readiness, stateOn(readiness['date'] as String, data));
}

/// `GET /api/readiness/history?days=N`
Json readinessHistoryBody(List<Json> wellness, {int days = 30}) =>
    readinessHistory(wellness, days: days);

/// `GET /api/training-load`
Json trainingLoadBody(List<Json> wellness, List<Json> activities, {Json settings = const {}}) =>
    trainingLoadToday(compute(wellness, activities, settings: settings));

/// `GET /api/insights`
Json insightsBody(List<Json> wellness) {
  final week = weeklySummary(wellness);
  final readiness = readinessToday(wellness);
  final latest = wellness.isNotEmpty ? wellness.first : const <String, Object?>{};
  return {
    'date': week['date'],
    'readiness': {for (final k in ['score', 'band', 'label']) k: readiness[k]},
    'today': {for (final k in ['sleep_score', 'hrv', 'avg_stress']) k: latest[k]},
    'insights': insights(wellness, week),
    'weekly': week,
  };
}

/// `GET /api/correlations`
Json correlationsBody(List<Json> wellness) =>
    {'days': wellness.length, 'correlations': discoverCorrelations(wellness)};

/// `GET /api/correlations/pair?x=&y=&lag=`. Throws [ArgumentError] with the
/// server's message for an unknown metric or a lag out of range.
Json correlationPairBody(List<Json> wellness, String? x, String? y, {int lag = 0}) {
  for (final metric in [x, y]) {
    if (metric == null || !correlationMetrics.contains(metric)) {
      throw ArgumentError('Unknown or missing metric: ${metric == null ? 'None' : "'$metric'"}');
    }
  }
  if (lag < 0 || lag > maxLagDays) {
    throw ArgumentError('lag must be 0-$maxLagDays days');
  }
  return {'metric1': x, 'metric2': y, 'lag_days': lag, ...correlation(wellness, x!, y!, lag)};
}

/// `GET /api/outlook`
Json outlookBody(List<Json> wellness) => outlook(wellness);
