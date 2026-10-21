/// The numbers behind the app's Insights, Patterns and Predictions tabs, a
/// port of `backend/insights_engine.py`.
///
/// A missing metric is null: rules that need it are skipped and averages
/// ignore it. Weekly summaries use calendar weeks ending at the latest day,
/// correlations pair days by calendar date, and the outlook reports its
/// accuracy as an error measured by replaying it over past days.
library;

import 'civil_date.dart';
import 'json.dart';
import 'py.dart';
import 'stats.dart';
import 'wellness_fields.dart';

const weekDays = 7;
const minDaysPerWeek = 3; // values needed in each week to compare them

/// Display key -> record field. Trends for these compare this week with last.
const weekMetrics = {
  'sleep': 'sleep_score',
  'hrv': 'hrv',
  'stress': 'avg_stress',
  'steps': 'steps',
  'body_battery': 'body_battery_start',
  'resting_hr': 'resting_hr',
};
const lowerIsBetter = {'stress', 'resting_hr'};

/// A week-over-week change smaller than this is "stable" (in the metric's units).
const trendThresholds = {
  'sleep': 3, 'hrv': 3, 'stress': 3, 'steps': 500, 'body_battery': 5, 'resting_hr': 2,
};

// ---- Insight rules (latest day) ----
const sleepPoor = 50;
const sleepExcellent = 80;
const hrvDropMs = 10; // below the week's average by more than this
const bodyBatteryLow = 30;
const bodyBatteryHigh = 80;
const stressElevated = 50;
const stepGoal = 10000;
const sleepTrendUp = 5; // week-over-week sleep gain worth calling out

// ---- Correlations ----
final Set<String> correlationMetrics = numericDailyFields;
const minPairs = 5;
const maxLagDays = 7;
const sameDayPairs = [
  ('sleep_score', 'body_battery_start', 'Sleep → Body Battery'),
  ('avg_stress', 'hrv', 'Stress ↔ HRV'),
  ('steps', 'total_calories', 'Steps → Calories'),
  ('deep_sleep_minutes', 'hrv', 'Deep Sleep → HRV'),
];
const nextDayPairs = [
  ('sleep_score', 'body_battery_start', "Last Night's Sleep → Today's Energy"),
  ('avg_stress', 'sleep_score', "Yesterday's Stress → Tonight's Sleep"),
];

// ---- Outlook: tomorrow's morning body battery ----
const outlookWeekWeight = 0.6; // weight of this week's average morning battery
const outlookEveningWeight = 0.4; // weight of today's end-of-day battery
const outlookHighStress = 50; // avg stress above this...
const outlookStressFactor = 0.9; // ...scales the prediction down
const intensityHigh = 70;
const intensityModerate = 50;
const backtestDays = 60;
const backtestMinPairs = 10;

num? _round(num? x, [int digits = 1]) => x == null ? null : pyRound(x, digits);

/// {date: record} for records with a parseable date, and the latest date.
(Map<CivilDate, Json>, CivilDate?) _dated(List<Json> records) {
  final byDate = <CivilDate, Json>{};
  for (final r in records) {
    final d = CivilDate.tryParse(r['date']);
    if (d != null) byDate[d] = r;
  }
  CivilDate? latest;
  for (final d in byDate.keys) {
    if (latest == null || d > latest) latest = d;
  }
  return (byDate, latest);
}

/// Present values of [field] over the [days] calendar days ending at [end].
List<num> _values(Map<CivilDate, Json> byDate, CivilDate end, int days, String field) => [
      for (var i = 0; i < days; i++)
        if (byDate[end.addDays(-i)]?[field] case final num v) v,
    ];

/// This week's average of [field], if there are enough readings to compare
/// a single day against it ([minDaysPerWeek]); otherwise null.
double? _baseline(Map<CivilDate, Json> byDate, CivilDate end, String field) {
  final values = _values(byDate, end, weekDays, field);
  return values.length >= minDaysPerWeek ? meanOrNull(values) : null;
}

// ============= WEEKLY SUMMARY =============

String _trend(String key, num? change) {
  if (change == null) return 'unknown';
  if (change.abs() < trendThresholds[key]!) return 'stable';
  final better = lowerIsBetter.contains(key) ? change < 0 : change > 0;
  return better ? 'improving' : 'declining';
}

/// This week's and last week's averages, the change and a trend per metric.
/// A change needs [minDaysPerWeek] values in both weeks; otherwise null.
Json weeklySummary(List<Json> records) {
  final (byDate, latest) = _dated(records);
  final thisWeek = <String, Object?>{};
  final lastWeek = <String, Object?>{};
  final change = <String, Object?>{};
  final trends = <String, Object?>{};
  for (final MapEntry(key: key, value: field) in weekMetrics.entries) {
    final now = latest != null ? _values(byDate, latest, weekDays, field) : <num>[];
    final before =
        latest != null ? _values(byDate, latest.addDays(-weekDays), weekDays, field) : <num>[];
    thisWeek[key] = _round(meanOrNull(now));
    lastWeek[key] = _round(meanOrNull(before));
    final comparable = now.length >= minDaysPerWeek && before.length >= minDaysPerWeek;
    change[key] = comparable ? _round(mean(now) - mean(before)) : null;
    trends[key] = _trend(key, change[key] as num?);
  }
  return {
    'date': latest?.toString(),
    'this_week': thisWeek,
    'last_week': lastWeek,
    'change': change,
    'trends': trends,
  };
}

// ============= INSIGHTS =============

Json _insight(String kind, String category, String title, String description, String icon,
        String metric, Object? value, Object? benchmark) =>
    {
      'type': kind, 'category': category, 'title': title,
      'description': description, 'icon': icon, 'metric': metric,
      'value': value, 'benchmark': benchmark,
    };

/// Rule-based callouts for the latest day. A rule whose metric is missing is
/// skipped. `benchmark` is always this week's average (the app labels it
/// "Avg"), or null when the week has no data for it.
List<Json> insights(List<Json> records, [Json? week]) {
  final (byDate, latest) = _dated(records);
  if (latest == null) return [];
  final t = byDate[latest]!;
  week ??= weeklySummary(records);
  final avg = week['this_week'] as Json;
  final out = <Json>[];

  int? bench(String key) => avg[key] == null ? null : pyRound(avg[key] as num) as int;

  final sleep = t['sleep_score'] as num?;
  if (sleep != null && sleep < sleepPoor) {
    out.add(_insight('warning', 'Sleep', 'Poor Sleep Quality',
        'Your sleep score of ${pyStr(sleep)} is below average. Consider going to bed earlier.',
        '😴', 'sleep_score', sleep, bench('sleep')));
  } else if (sleep != null && sleep > sleepExcellent) {
    out.add(_insight('positive', 'Sleep', 'Excellent Sleep!',
        'Great sleep score of ${pyStr(sleep)}. Your body is well-rested.',
        '🌟', 'sleep_score', sleep, bench('sleep')));
  }

  final hrv = t['hrv'] as num?;
  final hrvBaseline = _baseline(byDate, latest, 'hrv');
  if (hrv != null && hrvBaseline != null && hrv < hrvBaseline - hrvDropMs) {
    out.add(_insight('warning', 'Recovery', 'Lower HRV Today',
        'HRV of ${pyRound(hrv)}ms is below your average. Consider lighter activity.',
        '\u{2764}\u{FE0F}', 'hrv', hrv, bench('hrv')));
  }

  final battery = t['body_battery_start'] as num?;
  if (battery != null && battery < bodyBatteryLow) {
    out.add(_insight('warning', 'Energy', 'Low Energy Reserves',
        'Starting the day with Body Battery at ${pyStr(battery)}%. Prioritize rest.',
        '🔋', 'body_battery_start', battery, bench('body_battery')));
  } else if (battery != null && battery > bodyBatteryHigh) {
    out.add(_insight('positive', 'Energy', 'Fully Charged!',
        'Body Battery at ${pyStr(battery)}%. Great day for high-intensity activity!',
        '⚡', 'body_battery_start', battery, bench('body_battery')));
  }

  final stress = t['avg_stress'] as num?;
  if (stress != null && stress > stressElevated) {
    out.add(_insight('warning', 'Stress', 'Elevated Stress',
        'Average stress of ${pyStr(stress)} is higher than ideal. Try breathing exercises.',
        '😰', 'avg_stress', stress, bench('stress')));
  }

  final steps = t['steps'] as num?;
  if (steps != null && steps > stepGoal) {
    out.add(_insight('positive', 'Activity', 'Step Goal Achieved!',
        "You've walked ${pyStr(steps)} steps today. Keep it up!",
        '🚶', 'steps', steps, bench('steps')));
  }

  final sleepChange = (week['change'] as Json)['sleep'] as num?;
  if (sleepChange != null && sleepChange > sleepTrendUp) {
    out.add(_insight('positive', 'Trend', 'Sleep Improving',
        'Your sleep score is up ${pyRound(sleepChange)} points from last week!',
        '📈', 'sleep_trend', sleepChange, null));
  }
  return out;
}

// ============= CORRELATIONS =============

/// (xs, ys): [m1] on day d against [m2] on day d + [lag] calendar days, for
/// every d where both are present, in record order (newest first), as
/// `analytics_engine.lagged_pairs`.
(List<double>, List<double>) laggedPairs(List<Json> data, String m1, String m2, int lag) {
  final byDate = <Object?, Json>{for (final d in data) d['date']: d};
  final xs = <double>[];
  final ys = <double>[];
  for (final day in data) {
    final partner = byDate[CivilDate.tryParse(day['date'])?.addDays(lag).toString()];
    if (partner == null) continue;
    final v1 = day[m1];
    final v2 = partner[m2];
    if (v1 is! num || v2 is! num) continue;
    xs.add(v1.toDouble());
    ys.add(v2.toDouble());
  }
  return (xs, ys);
}

/// Pearson r between [x] on day d and [y] on day d + [lag] (calendar days).
Json correlation(List<Json> records, String x, String y, [int lag = 0]) {
  final (xs, ys) = laggedPairs(records, x, y, lag);
  final r = xs.length >= minPairs ? pearson(xs, ys) : null;
  if (r == null) {
    // Too few pairs, or a metric that never varied: nothing to report.
    return {'correlation': null, 'strength': 'insufficient_data', 'sample_size': xs.length};
  }
  return {
    'correlation': pyRound(r, 3),
    'strength': categorizeStrength(r),
    'sample_size': xs.length,
    'metric1_avg': _round(meanOrNull(xs)),
    'metric2_avg': _round(meanOrNull(ys)),
  };
}

/// The curated same-day and next-day pairs with at least a weak
/// relationship, strongest first.
List<Json> discoverCorrelations(List<Json> records) {
  final found = <Json>[];
  for (final (lag, pairs) in [(0, sameDayPairs), (1, nextDayPairs)]) {
    for (final (x, y, label) in pairs) {
      final result = correlation(records, x, y, lag);
      if (result['strength'] == 'insufficient_data' || result['strength'] == 'minimal') continue;
      found.add({'metric1': x, 'metric2': y, 'label': label, 'lagged': lag > 0, ...result});
    }
  }
  // sort(reverse=True) is stable: equal strengths keep their order.
  final indexed = [for (var i = 0; i < found.length; i++) (i, found[i])]
    ..sort((a, b) {
      final byStrength = (b.$2['correlation'] as num).abs().compareTo((a.$2['correlation'] as num).abs());
      return byStrength != 0 ? byStrength : a.$1.compareTo(b.$1);
    });
  return [for (final (_, c) in indexed) c];
}

// ============= OUTLOOK =============

/// Tomorrow's morning body battery from data up to [day], or null when the
/// inputs are missing.
double? _predict(Map<CivilDate, Json> byDate, CivilDate day) {
  final week = meanOrNull(_values(byDate, day, weekDays, 'body_battery_start'));
  final row = byDate[day] ?? const <String, Object?>{};
  final evening = row['body_battery_end'] as num?;
  if (week == null || evening == null) return null;
  var predicted = outlookWeekWeight * week + outlookEveningWeight * evening;
  final stress = row['avg_stress'] as num?;
  if (stress != null && stress > outlookHighStress) predicted *= outlookStressFactor;
  return predicted;
}

/// Mean absolute error of [_predict] over the last [backtestDays] days: each
/// day's prediction against the next morning's actual battery.
Json? _backtest(Map<CivilDate, Json> byDate, CivilDate latest) {
  final errors = <double>[];
  for (var i = 1; i <= backtestDays; i++) {
    final day = latest.addDays(-i);
    final predicted = _predict(byDate, day);
    final actual = byDate[day.addDays(1)]?['body_battery_start'] as num?;
    if (predicted != null && actual != null) errors.add((predicted - actual).abs());
  }
  if (errors.length < backtestMinPairs) return null;
  return {'mean_abs_error': pyRound(mean(errors), 1), 'days': errors.length};
}

String _impact(num? value, bool Function(num) good) =>
    value == null ? 'unknown' : (good(value) ? 'positive' : 'negative');

/// Tomorrow's predicted morning body battery, a training intensity and the
/// factors behind it. `available` is false when today's inputs are missing.
Json outlook(List<Json> records, [Json? week]) {
  final (byDate, latest) = _dated(records);
  week ??= weeklySummary(records);
  final t = (latest != null ? byDate[latest] : null) ?? const <String, Object?>{};
  final today = {for (final k in ['sleep_score', 'body_battery_end', 'avg_stress', 'hrv']) k: t[k]};
  final base = <String, Object?>{
    'date': week['date'],
    'today': today,
    'weekly': week['this_week'],
    'trends': week['trends'],
  };

  final predicted = latest != null ? _predict(byDate, latest) : null;
  if (predicted == null) {
    return {
      ...base,
      'available': false,
      'message': "Need a week of body battery data, including today's, for a prediction.",
    };
  }

  final String intensity;
  final String recommendation;
  if (predicted > intensityHigh) {
    intensity = 'high';
    recommendation = 'Great recovery predicted. Good day for intense workout!';
  } else if (predicted > intensityModerate) {
    intensity = 'moderate';
    recommendation = 'Moderate energy expected. Balanced workout recommended.';
  } else {
    intensity = 'low';
    recommendation = 'Lower energy predicted. Consider light activity or rest.';
  }

  final hrvBaseline = _baseline(byDate, latest!, 'hrv');
  final hrv = t['hrv'] as num?;
  return {
    ...base,
    'available': true,
    'predicted_body_battery': pyRound(predicted),
    'backtest': _backtest(byDate, latest),
    'recommended_intensity': intensity,
    'recommendation': recommendation,
    'factors': [
      {
        'name': 'Recent Sleep', 'value': t['sleep_score'],
        'impact': _impact(t['sleep_score'] as num?, (v) => v > 70),
      },
      {
        'name': 'Current Stress', 'value': t['avg_stress'],
        'impact': _impact(t['avg_stress'] as num?, (v) => v < 40),
      },
      {
        'name': 'HRV Status', 'value': hrv,
        'impact': hrv == null || hrvBaseline == null
            ? 'unknown'
            : (hrv > hrvBaseline ? 'positive' : 'neutral'),
      },
    ],
  };
}
