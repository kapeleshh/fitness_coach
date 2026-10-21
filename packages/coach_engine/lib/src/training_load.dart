/// Training load: per-session load and daily fitness/fatigue/form, a port of
/// `backend/training_load_engine.py`.
///
/// Session load is one number per canonical activity (a dedup group), taken
/// from the best signal anywhere in the group, in this order: Garmin's
/// activity training load, Banister TRIMP from average HR, Strava Relative
/// Effort, then minutes times a per-sport rate. Every session records its
/// `method`, and each day reports how much of the recent load was measured
/// rather than estimated.
///
/// Daily state follows the Banister impulse-response model (CTL 42-day and
/// ATL 7-day exponential load, TSB = CTL - ATL, form % = TSB / CTL) plus a
/// 7:28-day EWMA acute:chronic ratio that only raises a neutral
/// `load_spike` flag. Every daily metric is the state ENTERING the day: load
/// through the previous day. A day with no activity is a rest day (load 0).
///
/// Constants live here, at the top, as in the Python module.
library;

import 'dart:math' as math;

import 'activities.dart' show sourcePriority;
import 'civil_date.dart';
import 'json.dart';
import 'py.dart';

// ---- Fitness / fatigue (exponential decay, alpha = 1 - e^(-1/tau)) ----
const ctlTimeConstant = 42; // days
const atlTimeConstant = 7; // days

// ---- Acute:chronic ratio (EWMA, alpha = 2 / (N + 1), Williams 2017) ----
const acwrAcuteDays = 7;
const acwrChronicDays = 28;
const acwrMinHistory = 28; // days of history before the ratio is reported
const acwrSpike = 1.5; // neutral "load jumped" flag, not an injury cut-off

// ---- Maturity gates ----
const historyMinDays = 14; // below this, no form band at all
const historyFullDays = 42; // one CTL time constant; below this, low confidence
const minCtlForForm = 5.0; // form % (and ACWR) are noise when fitness is ~0

// ---- Form % bands (tsb / ctl x 100): coaching convention, not validated ----
const formBands = [
  // (exclusive lower bound, band); else "overreaching"
  (25.0, 'transition'),
  (5.0, 'fresh'),
  (-10.0, 'neutral'),
  (-30.0, 'building'),
];

// ---- Confidence: share of the last 42 days' load that was measured ----
const measuredMethods = {'garmin_load', 'trimp', 'relative_effort'};
const confidenceWindow = ctlTimeConstant;
const measuredShareHigh = 0.8;
const measuredShareMedium = 0.5;

// ---- TRIMP (Banister 1991): load/min = HRr * a * e^(b * HRr) ----
const trimpCoefficients = {'male': (0.64, 1.92), 'female': (0.86, 1.67)};
const defaultTrimpSex = 'male'; // Banister's original curve
const restingHrReadings = 7; // median of this many nearest resting-HR readings
const minHrReserve = 20; // bpm; a smaller max - rest means bad HR inputs
const minPlausibleMaxHr = 100;
const maxPlausibleHr = 220;

/// Rough TRIMP-equivalent load per minute at a typical effort, for sessions
/// with no HR, load or effort score at all. Deliberately coarse: any session
/// that needs it counts as estimated, which lowers that period's confidence.
const loadPerMinute = {
  'run': 1.2, 'ride': 0.9, 'swim': 1.0, 'row': 1.0, 'ski': 1.0,
  'hike': 0.7, 'strength': 0.6, 'walk': 0.35, 'yoga': 0.3,
};
const defaultLoadPerMinute = 0.7;

const recentSessionsMax = 10;
const historyMaxDays = 730;

const _confidenceTiers = ['none', 'low', 'medium', 'high'];

/// Python truthiness for the values these rows hold.
bool _truthy(Object? v) => v != null && v != 0 && v != '' && v != false;

double _alphaTimeConstant(int tau) => 1.0 - math.exp(-1.0 / tau);

double _alphaSpan(int n) => 2.0 / (n + 1);

num? _round(num? x, int digits) => x == null ? null : pyRound(x, digits);

/// Active minutes: moving time when known (average HR is over moving time),
/// else elapsed time.
double? _minutes(Json row) {
  final seconds = _truthy(row['moving_time_s']) ? row['moving_time_s'] : row['duration_s'];
  return seconds is num && seconds != 0 && seconds > 0 ? seconds / 60.0 : null;
}

/// Banister TRIMP for one session, or null when the inputs can't support it.
double? trimp(num? minutes, num? avgHr, num? restingHr, num? maxHr,
    [String sex = defaultTrimpSex]) {
  if (minutes == null || avgHr == null || restingHr == null || maxHr == null || minutes <= 0) {
    return null;
  }
  final reserve = maxHr - restingHr;
  if (reserve < minHrReserve) return null;
  var hrr = (avgHr - restingHr) / reserve;
  if (hrr <= 0) return null;
  if (1.0 < hrr) hrr = 1.0;
  final (a, b) = trimpCoefficients[sex]!;
  return minutes * hrr * a * math.exp(b * hrr);
}

/// A function from a local date to resting HR: the median of the last
/// [restingHrReadings] readings on or before that date (point-in-time), or
/// of the earliest readings for sessions that predate all wellness data.
num? Function(String localDate) restingHrLookup(List<Json> wellness) {
  final readings = [
    for (final r in wellness)
      if (r['resting_hr'] != null && r['date'] is String)
        (r['date'] as String, r['resting_hr'] as num),
  ]..sort((a, b) {
      final byDate = a.$1.compareTo(b.$1);
      return byDate != 0 ? byDate : a.$2.compareTo(b.$2);
    });
  final dates = [for (final (d, _) in readings) d];
  final values = [for (final (_, v) in readings) v];

  return (String localDate) {
    if (values.isEmpty) return null;
    // bisect_right: the number of readings on or before localDate
    var i = 0;
    while (i < dates.length && dates[i].compareTo(localDate) <= 0) {
      i++;
    }
    final window = i != 0
        ? values.sublist(math.max(0, i - restingHrReadings), i)
        : values.sublist(0, math.min(restingHrReadings, values.length));
    return pyMedian(window);
  };
}

double? _number(Object? value) {
  if (value == null || value == '') return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

/// Max HR and the TRIMP curve. Each comes from the athlete's settings
/// (`athlete_max_hr`, `trimp_sex`) or the default; max HR otherwise falls
/// back to the highest plausible value observed in the given rows.
Json athleteParams(List<Json> activityRows, List<Json> wellness, Json settings) {
  final rawSex = settings['trimp_sex'];
  var sex = (_truthy(rawSex) ? pyStr(rawSex) : defaultTrimpSex).toLowerCase();
  if (!trimpCoefficients.containsKey(sex)) sex = defaultTrimpSex;
  final override = _number(settings['athlete_max_hr']);
  if (override != null && override != 0) {
    return {'max_hr': override, 'max_hr_source': 'setting', 'trimp_sex': sex};
  }
  num? observed;
  for (final v in [
    for (final r in activityRows) r['max_hr'],
    for (final r in wellness) r['max_hr'],
  ]) {
    if (v is num && minPlausibleMaxHr <= v && v <= maxPlausibleHr) {
      // max() keeps the first of equal values
      if (observed == null || v > observed) observed = v;
    }
  }
  return {
    'max_hr': observed,
    'max_hr_source': observed != null ? 'observed' : null,
    'trimp_sex': sex,
  };
}

/// Load for one dedup group; [members] are ordered best source first.
Json _resolve(List<Json> members, num? Function(String) restAt, Json params) {
  final lead = members.first;
  double? minutes;
  for (final m in members) {
    final value = _minutes(m);
    if (value != null) {
      minutes = value;
      break;
    }
  }
  num? load;
  String? method;

  for (final m in members) {
    if (m['training_load'] != null) {
      load = m['training_load'] as num;
      method = 'garmin_load';
      break;
    }
  }

  if (load == null) {
    final resting = restAt(lead['local_date'] as String);
    for (final m in members) {
      final t = trimp(_minutes(m), m['avg_hr'] as num?, resting, params['max_hr'] as num?,
          params['trimp_sex'] as String);
      if (t != null) {
        load = t;
        method = 'trimp';
        break;
      }
    }
  }

  if (load == null) {
    for (final m in members) {
      if (m['suffer_score'] != null) {
        load = m['suffer_score'] as num;
        method = 'relative_effort';
        break;
      }
    }
  }

  if (load == null && minutes != null) {
    final rate = loadPerMinute[lead['sport_family']] ?? defaultLoadPerMinute;
    load = minutes * rate;
    method = 'duration_estimate';
  }

  if (load == null) {
    load = 0.0;
    method = 'none';
  }

  return {
    'id': lead['id'],
    'local_date': lead['local_date'],
    'start_time_utc': lead['start_time_utc'],
    'sport_family': lead['sport_family'],
    'sport_type': lead['sport_type'],
    'name': lead['name'],
    'minutes': _round(minutes, 1),
    'load': pyRound(load, 1),
    'method': method,
    'sources': ({for (final m in members) m['source'] as String}.toList()..sort()),
  };
}

/// One load per dedup group, newest first. [activityRows] must include
/// duplicates so a canonical session can borrow a signal its duplicate has,
/// e.g. a Strava Relative Effort for a Garmin session recorded without HR.
List<Json> sessionLoads(List<Json> activityRows, List<Json> wellness, Json params) {
  final restAt = restingHrLookup(wellness);
  final groups = <String, List<Json>>{};
  for (final r in activityRows) {
    final key = _truthy(r['duplicate_of']) ? r['duplicate_of'] as String : r['id'] as String;
    (groups[key] ??= []).add(r);
  }
  final sessions = <Json>[];
  for (final members in groups.values) {
    members.sort((a, b) {
      final pa = sourcePriority[a['source']] ?? 99;
      final pb = sourcePriority[b['source']] ?? 99;
      return pa != pb ? pa.compareTo(pb) : (a['id'] as String).compareTo(b['id'] as String);
    });
    sessions.add(_resolve(members, restAt, params));
  }
  // sort(reverse=True) is stable: equal start times keep their order.
  final indexed = [for (var i = 0; i < sessions.length; i++) (i, sessions[i])]
    ..sort((a, b) {
      final byStart =
          (b.$2['start_time_utc'] as String).compareTo(a.$2['start_time_utc'] as String);
      return byStart != 0 ? byStart : a.$1.compareTo(b.$1);
    });
  return [for (final (_, s) in indexed) s];
}

String formBand(num formPct) {
  for (final (floor, band) in formBands) {
    if (formPct > floor) return band;
  }
  return 'overreaching';
}

String _confidence(int historyDays, num? measuredShare) {
  if (measuredShare == null) return historyDays != 0 ? 'low' : 'none';
  String tier;
  if (measuredShare >= measuredShareHigh) {
    tier = 'high';
  } else if (measuredShare >= measuredShareMedium) {
    tier = 'medium';
  } else {
    tier = 'low';
  }
  if (historyDays < historyFullDays) {
    tier = _confidenceTiers[math.min(_confidenceTiers.indexOf(tier), 1)];
  }
  return tier;
}

/// Daily state, oldest first, from the first session's day through [end]
/// (or the last session's day, if later).
List<Json> dailySeries(List<Json> sessions, {CivilDate? end}) {
  if (sessions.isEmpty) return [];
  final byDay = <CivilDate, double>{};
  final measured = <CivilDate, double>{};
  for (final s in sessions) {
    final d = CivilDate.parse(s['local_date'] as String);
    final load = s['load'] as num;
    byDay[d] = (byDay[d] ?? 0.0) + load;
    if (measuredMethods.contains(s['method'])) measured[d] = (measured[d] ?? 0.0) + load;
  }

  final days = byDay.keys.toList()..sort();
  final first = days.first;
  final latest = days.last;
  final last = (end ?? first) > latest ? end! : latest;
  final aCtl = _alphaTimeConstant(ctlTimeConstant);
  final aAtl = _alphaTimeConstant(atlTimeConstant);
  final aAcute = _alphaSpan(acwrAcuteDays);
  final aChronic = _alphaSpan(acwrChronicDays);

  var ctl = 0.0, atl = 0.0, acute = 0.0, chronic = 0.0;
  // load over the confidenceWindow days before d
  var windowTotal = 0.0, windowMeasured = 0.0;
  final rows = <Json>[];
  for (var d = first; d <= last; d = d.addDays(1)) {
    final prev = d.addDays(-1);
    final dropped = prev.addDays(-confidenceWindow);
    windowTotal += (byDay[prev] ?? 0.0) - (byDay[dropped] ?? 0.0);
    windowMeasured += (measured[prev] ?? 0.0) - (measured[dropped] ?? 0.0);

    final history = d.daysSince(first);
    final ctlR = pyRound(ctl, 1);
    final atlR = pyRound(atl, 1);
    final formPct = ctl >= minCtlForForm ? (ctl - atl) / ctl * 100 : null;
    final acwr =
        history >= acwrMinHistory && chronic >= minCtlForForm ? acute / chronic : null;
    final share = windowTotal > 1e-9 ? windowMeasured / windowTotal : null;
    final flags = <String>[
      if (acwr != null && acwr > acwrSpike) 'load_spike',
      if (history < historyFullDays) 'warming_up',
    ];
    rows.add({
      'date': d.toString(),
      'load': pyRound(byDay[d] ?? 0.0, 1),
      'ctl': ctlR,
      'atl': atlR,
      'tsb': pyRound(ctlR - atlR, 1),
      'form_pct': _round(formPct, 1),
      'form_band': formPct != null && history >= historyMinDays ? formBand(formPct) : null,
      'acwr': _round(acwr, 2),
      'history_days': history,
      'measured_share': _round(share, 2),
      'confidence': _confidence(history, share),
      'flags': flags,
    });

    final load = byDay[d] ?? 0.0;
    ctl += (load - ctl) * aCtl;
    atl += (load - atl) * aAtl;
    acute += (load - acute) * aAcute;
    chronic += (load - chronic) * aChronic;
  }
  return rows;
}

const _formPhrase = {
  'transition': 'very fresh — recent load is well below your fitness',
  'fresh': 'fresh',
  'neutral': 'balanced',
  'building': 'carrying productive training fatigue',
  'overreaching': 'carrying high training fatigue',
};

String _summary(Json s) {
  final fitness = 'fitness ${pyFixed(s['ctl'] as num, 0)}, fatigue ${pyFixed(s['atl'] as num, 0)}';
  final flags = s['flags'] as List;
  String text;
  if (s['form_band'] != null) {
    text = 'Training load: ${_formPhrase[s['form_band']]} '
        '(form ${pyFixed(s['form_pct'] as num, 0, sign: true)}% — $fitness).';
    if (flags.contains('warming_up')) {
      text += ' Baseline still building (${s['history_days']} of $historyFullDays days).';
    }
  } else if ((s['history_days'] as int) < historyMinDays) {
    text = 'Training load: still building a baseline (${s['history_days']} of '
        '$historyFullDays days) — $fitness.';
  } else {
    text = 'Training load: too little recent training to rate form ($fitness).';
  }
  if (flags.contains('load_spike')) {
    text += ' Load jumped well above your recent norm '
        '(acute:chronic ${pyFixed(s['acwr'] as num, 2)}).';
  }
  return text;
}

/// A daily row plus the last 7 days of sessions and a templated summary.
Json describe(Json row, List<Json> sessions) {
  final d = CivilDate.parse(row['date'] as String);
  final weekStart = d.addDays(-6);
  final week = [
    for (final s in sessions)
      if (weekStart <= CivilDate.parse(s['local_date'] as String) &&
          CivilDate.parse(s['local_date'] as String) <= d)
        s,
  ];
  final state = <String, Object?>{...row};
  state['last_7_days'] = {
    'sessions': week.length,
    'load': pyRound(pySum([for (final s in week) s['load'] as num]), 1),
    'minutes': pyRound(pySum([
      for (final s in week) _truthy(s['minutes']) ? s['minutes'] as num : 0,
    ])),
  };
  state['recent_sessions'] = week.take(recentSessionsMax).toList();
  state['summary'] = _summary(state);
  return state;
}

/// [describe] for one date, or null if it falls outside the series.
Json? stateOn(String date, Json data) {
  for (final r in (data['series'] as List).cast<Json>()) {
    if (r['date'] == date) return describe(r, (data['sessions'] as List).cast<Json>());
  }
  return null;
}

/// Fuse the two axes: the load summary plus what it means for today's
/// readiness band. Readiness itself stays wellness-only.
String readinessNote(String? readinessBand, Json state) {
  final band = state['form_band'];
  var note = state['summary'] as String;
  if (readinessBand == 'green') {
    if (band == 'overreaching') {
      note += ' Recovery markers look fine, but fatigue is high — consider capping intensity today.';
    } else if (band == 'fresh' || band == 'transition') {
      note += " You're fresh as well — a good day for a key session.";
    }
  } else if (readinessBand == 'amber' || readinessBand == 'red') {
    if (band == 'overreaching') {
      note += ' High training fatigue is the likely cause — prioritise recovery.';
    } else if (band == 'fresh' || band == 'transition' || band == 'neutral') {
      note += " Training load isn't high, so look at sleep, stress or illness instead.";
    }
  }
  return note;
}

const readinessFields = [
  'date', 'ctl', 'atl', 'tsb', 'form_pct', 'form_band', 'acwr', 'confidence', 'flags',
];

/// The readiness response plus a `training_load` object, with the fused
/// note appended to the briefing when both axes are available.
Json annotateReadiness(Json readiness, Json? state) {
  final out = <String, Object?>{...readiness};
  out['training_load'] = state != null ? {for (final k in readinessFields) k: state[k]} : null;
  if (state != null && readiness['score'] != null) {
    out['briefing'] =
        '${readiness['briefing']} ${readinessNote(readiness['band'] as String?, state)}';
  }
  return out;
}

CivilDate? _latestDate(List<Json> wellness, List<Json> sessions) {
  final dates = <Object?>[
    for (final s in sessions) s['local_date'],
    for (final r in wellness.take(1))
      if (r['date'] is String) r['date'],
  ];
  CivilDate? latest;
  for (final d in dates) {
    final parsed = CivilDate.tryParse(d);
    if (parsed != null && (latest == null || parsed > latest)) latest = parsed;
  }
  return latest;
}

/// Sessions, the daily series and athlete parameters, from the wellness
/// records (newest first) and the activity rows including duplicates.
/// [excludeSources] drops every row from those sources, and so anything
/// derived from them, such as borrowed effort scores or observed max HR.
Json compute(
  List<Json> wellness,
  List<Json> activityRows, {
  Json settings = const {},
  Set<String> excludeSources = const {},
}) {
  final rows = [for (final r in activityRows) if (!excludeSources.contains(r['source'])) r];
  final params = athleteParams(rows, wellness, settings);
  final sessions = sessionLoads(rows, wellness, params);
  return {
    'sessions': sessions,
    'series': dailySeries(sessions, end: _latestDate(wellness, sessions)),
    'params': params,
  };
}

/// The latest daily state from a [compute] result, as `/api/training-load`.
Json trainingLoadToday(Json data) {
  final series = (data['series'] as List).cast<Json>();
  if (series.isEmpty) {
    return {
      'date': null, 'load': null, 'ctl': null, 'atl': null, 'tsb': null,
      'form_pct': null, 'form_band': null, 'acwr': null, 'history_days': 0,
      'measured_share': null, 'confidence': 'none', 'flags': <String>[],
      'last_7_days': {'sessions': 0, 'load': 0.0, 'minutes': 0},
      'recent_sessions': <Json>[], 'parameters': data['params'],
      'summary': 'No activities recorded yet — import your Strava history or sync Garmin.',
    };
  }
  final state = describe(series.last, (data['sessions'] as List).cast<Json>());
  state['parameters'] = data['params'];
  return state;
}

/// Daily state for the most recent [days] days, newest first.
Json trainingLoadHistory(Json data, {int days = 90}) {
  final clamped = math.max(1, math.min(days, historyMaxDays));
  final series = (data['series'] as List).cast<Json>();
  return {
    'days': clamped,
    'series': series.sublist(math.max(0, series.length - clamped)).reversed.toList(),
  };
}
