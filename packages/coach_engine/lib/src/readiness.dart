/// Daily readiness (0-100, green/amber/red) from wellness data: a port of
/// `backend/readiness_engine.py`.
///
/// Two axes: autonomic (ln-HRV 7-day mean against a 60-day baseline with a
/// smallest-worthwhile-change deadband and a CV penalty, morning body
/// battery, resting HR) weighted 0.65, and sleep weighted 0.35. Missing
/// components drop out and the weights renormalize; nothing is zero-filled.
/// Before a personal HRV baseline exists, Garmin's `hrv_status` stands in.
/// Baselines are point-in-time: scoring a date only reads records up to it.
///
/// Records are the NULL-aware wellness rows (newest first) as JSON maps, and
/// results are the same JSON maps the Python engine returns. Retune the
/// constants here, at the top, as in the Python module.
library;

import 'dart:math' as math;

import 'civil_date.dart';
import 'json.dart';
import 'py.dart';

// ---------- Methodology constants (keep in step with readiness_engine.py) ----------
const hrvRollingWindow = 7; // days, acute ln-HRV mean (Plews/Buchheit)
const hrvRecent7MinPresent = 4; // need >=4 of last 7 days to trust HRV_7
const baselineWindow = 60; // days, chronic reference
const hrvTrustMin = 14; // valid HRV nights: below -> hrv_status fallback
const hrvTrustFull = 28; // valid HRV nights: at/above -> personal baseline
const rhrRecentWindow = 3; // days, smooths one bad resting-HR reading
const rhrTrustMin = 14; // valid RHR days before the RHR term is used

const sdLnFloor = 0.05; // ln units, floor on baseline ln-HRV SD
const sdRhrFloor = 2.0; // bpm, floor on baseline resting-HR SD
const neutralAnchor = 0.85; // sub-score of an at-baseline day

const hrvCvRatioLow = 1.25;
const hrvCvRatioHigh = 2.0;
const hrvCvAbsFloor = 8.0; // %, below this no penalty regardless of ratio
const hrvCvPenaltyMax = 0.15;

const wAutonomic = 0.65;
const wSleep = 0.35;
const autoWHrv = 0.50;
const autoWBodyBattery = 0.30;
const autoWRhr = 0.20;

const shareHrv = wAutonomic * autoWHrv; // 0.325
const shareBodyBattery = wAutonomic * autoWBodyBattery; // 0.195
const shareRhr = wAutonomic * autoWRhr; // 0.13
const shareSleep = wSleep; // 0.35

const shortSleepTst = 300; // min; sleep axis capped at 0.50 below 5h
const shortSleepCap = 0.50;

const hrvStatusMap = {'BALANCED': 0.85, 'UNBALANCED': 0.50, 'LOW': 0.30};

const illnessHrvZ = -1.0;
const illnessRhrZr = 2.0;
const illnessCap = 0.35;

const severeHrvZ = -2.0;
const severeHrvCap = 0.45;

const coldStartDropMinNights = 7;
const coldStartDropZ = -2.5;

const bandGreenMin = 70;
const bandAmberMin = 50;

const _confidenceTiers = ['none', 'low', 'medium', 'high'];

// Python's min(a, b) keeps a unless b is smaller; max(a, b) keeps a unless b
// is larger. Spelled out so ties return the same operand as in Python.
num _min(num a, num b) => b < a ? b : a;
num _max(num a, num b) => b > a ? b : a;

num _clamp(num x, [num lo = 0.0, num hi = 1.0]) => _max(lo, _min(hi, x));

double _mean(List<num> xs) => pySum(xs) / xs.length;

double _sampleSd(List<num> xs) {
  if (xs.length < 2) return 0.0;
  final m = _mean(xs);
  return math.sqrt(pySum(xs.map((x) => (x - m) * (x - m))) / (xs.length - 1));
}

/// Map a goodness-z (positive = better) to a 0..1 sub-score.
///
/// Flat [neutralAnchor] inside the +/-0.5 SD SWC deadband; asymmetric:
/// gentle above baseline, steep below, because suppression is the actionable
/// direction. Used for both HRV (x=z) and resting-HR (x=-zr).
double sharedCurve(num x) {
  if (x >= 1.5) return 1.0;
  if (x >= 0.5) return 0.85 + 0.15 * (x - 0.5);
  if (x >= -0.5) return 0.85;
  if (x >= -1.5) return 0.85 + 0.45 * (x + 0.5);
  if (x >= -3.0) return 0.40 + (0.40 / 1.5) * (x + 1.5);
  return 0.0;
}

/// Present (non-NULL) values of [field] over the trailing calendar days
/// ending at [target] (inclusive), from offset [start] to [days]. Gaps just
/// lower the count. [start] lets callers exclude the most-recent week.
List<num> _windowValues(
  Map<CivilDate, Json> rowsByDate,
  CivilDate target,
  int days,
  String field, {
  num Function(num)? transform,
  int start = 0,
}) {
  final out = <num>[];
  for (var i = start; i < days; i++) {
    final row = rowsByDate[target.addDays(-i)];
    if (row == null) continue;
    final v = row[field];
    if (v == null) continue;
    if (field == 'hrv' && (v is! num || v <= 0)) continue; // ln needs a positive value
    final value = v as num;
    out.add(transform != null ? transform(value) : value);
  }
  return out;
}

double _bodyBatterySub(num bb) {
  if (bb >= 75) return 1.0;
  if (bb >= 25) return 0.40 + 0.012 * (bb - 25);
  if (bb >= 5) return 0.05 + 0.0175 * (bb - 5);
  return 0.05;
}

String _band(int? score) {
  if (score == null) return 'unknown';
  if (score >= bandGreenMin) return 'green';
  if (score >= bandAmberMin) return 'amber';
  return 'red';
}

const _bandLabel = {
  'green': 'Train as planned',
  'amber': 'Train easy',
  'red': 'Rest / recover',
  'unknown': 'Not enough data yet',
};
const _bandGuidance = {
  'green': 'Recovery looks good — train as planned; quality/hard work is fine.',
  'amber': 'Recovery is slightly down — keep it easy-to-moderate and skip the hard session.',
  'red': 'Recovery is low — rest or light active recovery, and check sleep/illness/life stress.',
  'unknown': 'Sync your watch and check back.',
};

String _demote(String conf, [int steps = 1]) =>
    _confidenceTiers[math.max(0, _confidenceTiers.indexOf(conf) - steps)];

/// Score readiness for [targetDate] (`YYYY-MM-DD`) using only records up to
/// that date. Returns the full readiness object.
Json scoreDate(List<Json> records, String targetDate) {
  final target = CivilDate.parse(targetDate);
  // Skip records with an unparseable date rather than letting one bad row
  // (e.g. a malformed legacy import) fail every readiness call.
  final rowsByDate = <CivilDate, Json>{};
  for (final r in records) {
    final d = CivilDate.tryParse(r['date']);
    if (d != null && d <= target) rowsByDate[d] = r;
  }
  final today = rowsByDate[target] ?? const <String, Object?>{};
  final flags = <String>[];

  // ---------- HRV sub-score ----------
  final ln60 = _windowValues(rowsByDate, target, baselineWindow, 'hrv', transform: math.log);
  // CV baseline excludes the most recent 7 days, so an unstable acute week
  // can't inflate its own reference and self-mask the instability penalty.
  final rawCvBaseline =
      _windowValues(rowsByDate, target, baselineWindow, 'hrv', start: hrvRollingWindow);
  final nHrv = ln60.length;
  final recent7Raw = _windowValues(rowsByDate, target, hrvRollingWindow, 'hrv');
  final recent7Ln = [for (final v in recent7Raw) math.log(v)];
  final status = today['hrv_status'];
  final statusSub = hrvStatusMap[status];

  final hrv = <String, Object?>{
    'available': false, 'sub': null, 'source': null, 'value_ms': null,
    'baseline_ms': null, 'pct_dev': null, 'z': null, 'cv_7': null,
    'cv_ratio': null, 'cv_penalty': 0.0, 'n_days': nHrv,
  };

  double? z;
  final canFormRecent = recent7Raw.length >= hrvRecent7MinPresent;
  if (canFormRecent && nHrv >= 2) {
    final hrv7 = _mean(recent7Ln);
    final baseMean = _mean(ln60);
    final baseSd = _max(_sampleSd(ln60), sdLnFloor);
    z = (hrv7 - baseMean) / baseSd;
    final subBase = sharedCurve(z);
    hrv['value_ms'] = pyRound(math.exp(hrv7), 1);
    hrv['baseline_ms'] = pyRound(math.exp(baseMean), 1);
    hrv['pct_dev'] = pyRound((math.exp(hrv7) / math.exp(baseMean) - 1) * 100, 1);
    hrv['z'] = pyRound(z, 2);

    // CV "variation in variability" penalty (base excludes recent 7 days)
    num penalty = 0.0;
    if (recent7Raw.length >= 2 && rawCvBaseline.length >= 2 && _mean(rawCvBaseline) > 0) {
      final cv7 = _sampleSd(recent7Raw) / _mean(recent7Raw) * 100;
      final baseCv = _sampleSd(rawCvBaseline) / _mean(rawCvBaseline) * 100;
      hrv['cv_7'] = pyRound(cv7, 1);
      if (baseCv > 0) {
        final cvRatio = cv7 / baseCv;
        hrv['cv_ratio'] = pyRound(cvRatio, 2);
        if (cvRatio > hrvCvRatioLow && cv7 >= hrvCvAbsFloor) {
          const span = hrvCvRatioHigh - hrvCvRatioLow;
          penalty = hrvCvPenaltyMax * _clamp((cvRatio - hrvCvRatioLow) / span);
        }
      }
    }

    if (nHrv >= hrvTrustFull) {
      hrv.addAll({
        'available': true, 'source': 'baseline',
        'sub': _clamp(subBase - penalty), 'cv_penalty': pyRound(penalty, 3),
      });
    } else if (nHrv >= hrvTrustMin) {
      // Linear fade-in of the personal baseline. Garmin often still reports
      // hrv_status='UNKNOWN' through this window, so when no status is
      // available we blend toward the neutral anchor (0.85) instead of
      // snapping to a full-trust 14-day baseline.
      final w = (nHrv - hrvTrustMin) / (hrvTrustFull - hrvTrustMin);
      final proxy = statusSub ?? neutralAnchor;
      final blended = w * subBase + (1 - w) * proxy - 0.5 * penalty;
      hrv.addAll({
        'available': true, 'source': 'blend',
        'sub': _clamp(blended), 'cv_penalty': pyRound(0.5 * penalty, 3),
      });
    } else {
      // nHrv < hrvTrustMin -> cold start: status only, no z/CV
      z = null; // untrusted; must not feed the illness/severe overrides
      for (final k in ['value_ms', 'baseline_ms', 'pct_dev', 'z', 'cv_7', 'cv_ratio']) {
        hrv[k] = null;
      }
      hrv['cv_penalty'] = 0.0;
      if (statusSub != null) {
        hrv.addAll({'available': true, 'source': 'status', 'sub': statusSub});
      }
    }
  } else {
    // Can't form a trusted acute mean today -> Garmin status fallback.
    if (statusSub != null) {
      hrv.addAll({'available': true, 'source': 'status', 'sub': statusSub});
      if (nHrv >= hrvTrustMin && !canFormRecent) flags.add('stale_hrv');
    }
  }

  // ---------- Resting-HR sub-score ----------
  final rhr60 = _windowValues(rowsByDate, target, baselineWindow, 'resting_hr');
  final rhrRecent = _windowValues(rowsByDate, target, rhrRecentWindow, 'resting_hr');
  final rhr = <String, Object?>{
    'available': false, 'sub': null, 'value': null, 'baseline': null,
    'delta_bpm': null, 'zr': null, 'n_days': rhr60.length,
  };
  double? zr;
  if (rhr60.length >= rhrTrustMin && rhrRecent.isNotEmpty) {
    final rRecent = _mean(rhrRecent);
    final rBase = _mean(rhr60);
    final rSd = _max(_sampleSd(rhr60), sdRhrFloor);
    zr = (rRecent - rBase) / rSd;
    rhr.addAll({
      'available': true, 'sub': sharedCurve(-zr), 'value': pyRound(rRecent, 1),
      'baseline': pyRound(rBase, 1), 'delta_bpm': pyRound(rRecent - rBase, 1),
      'zr': pyRound(zr, 2),
    });
  }

  // ---------- Body-battery sub-score ----------
  final bbVal = today['body_battery_start'] as num?;
  final bodyBattery = <String, Object?>{'available': false, 'sub': null, 'value': bbVal};
  if (bbVal != null) {
    bodyBattery.addAll({'available': true, 'sub': _bodyBatterySub(bbVal)});
  }

  // ---------- Sleep axis ----------
  final sleepVal = today['sleep_score'] as num?;
  final sleep = <String, Object?>{'available': false, 'sub': null, 'value': sleepVal};
  final sleepDur = <String, Object?>{'available': false, 'tst_min': null, 'guard_applied': false};
  if (sleepVal != null) {
    var sub = _clamp(sleepVal / 100.0);
    final stages = [
      for (final k in ['deep_sleep_minutes', 'light_sleep_minutes', 'rem_sleep_minutes'])
        today[k] as num?,
    ];
    if (stages.every((s) => s != null)) {
      final tst = pySum(stages.cast<num>());
      sleepDur.addAll({'available': true, 'tst_min': tst});
      if (tst < shortSleepTst) {
        sub = _min(sub, shortSleepCap);
        sleepDur['guard_applied'] = true;
      }
    }
    sleep.addAll({'available': true, 'sub': sub});
  }

  final hrvOn = hrv['available'] == true;
  final rhrOn = rhr['available'] == true;
  final bbOn = bodyBattery['available'] == true;
  final sleepOn = sleep['available'] == true;

  // ---------- Autonomic axis (renormalized over present sub-components) ----------
  final autoParts = <(num, num)>[];
  if (hrvOn) autoParts.add((autoWHrv, hrv['sub'] as num));
  if (bbOn) {
    var bbAxis = bodyBattery['sub'] as num;
    // Morning body battery is dominated by overnight sleep charging, so it
    // can read high even when HRV is depressed. When BOTH HRV and resting HR
    // are below their neutral anchor, cap body battery at the stronger of
    // those two direct autonomic signals.
    if (hrvOn &&
        rhrOn &&
        (hrv['sub'] as num) < neutralAnchor &&
        (rhr['sub'] as num) < neutralAnchor) {
      final capped = _min(bbAxis, _max(hrv['sub'] as num, rhr['sub'] as num));
      if (capped < bbAxis) {
        bbAxis = capped;
        flags.add('body_battery_capped');
      }
    }
    autoParts.add((autoWBodyBattery, bbAxis));
  }
  if (rhrOn) autoParts.add((autoWRhr, rhr['sub'] as num));
  final autonomicScore = autoParts.isEmpty
      ? null
      : pySum([for (final (w, s) in autoParts) w * s]) / pySum([for (final (w, _) in autoParts) w]);

  // ---------- Final composite (renormalized over present axes) ----------
  final axisParts = <(num, num)>[];
  if (autonomicScore != null) axisParts.add((wAutonomic, autonomicScore));
  if (sleepOn) axisParts.add((wSleep, sleep['sub'] as num));

  if (axisParts.isEmpty) return _insufficient(targetDate);

  num composite =
      pySum([for (final (w, s) in axisParts) w * s]) / pySum([for (final (w, _) in axisParts) w]);

  final baselineFull = nHrv >= hrvTrustFull;

  // Illness / overreaching override: only on a trusted (full) baseline, so a
  // thin 14-day baseline can't slam the score to red off two noisy weeks.
  if (baselineFull && z != null && zr != null && z <= illnessHrvZ && zr >= illnessRhrZr) {
    composite = _min(composite, illnessCap);
    flags.add('illness_watch');
  }

  // A large isolated HRV suppression must force red even on great sleep/battery.
  if (baselineFull && z != null && z <= severeHrvZ) {
    composite = _min(composite, severeHrvCap);
    if (!flags.contains('hrv_suppressed')) flags.add('hrv_suppressed');
  }

  // Cold start: no trusted baseline for a score cap, but still surface an
  // extreme same-week HRV drop as an informational flag (e.g. week-2 illness).
  if (!baselineFull && nHrv >= coldStartDropMinNights && canFormRecent && ln60.length >= 2) {
    final csZ = (_mean(recent7Ln) - _mean(ln60)) / _max(_sampleSd(ln60), sdLnFloor);
    if (csZ <= coldStartDropZ) flags.add('hrv_drop_watch');
  }

  final score = pyRound(100 * _clamp(composite)) as int;
  final band = _band(score);

  // ---------- Data completeness & confidence ----------
  // Plain left-to-right addition with int zeros, as in the Python expression.
  final num completeness = (hrvOn ? shareHrv : 0) +
      (bbOn ? shareBodyBattery : 0) +
      (rhrOn ? shareRhr : 0) +
      (sleepOn ? shareSleep : 0);
  final String baselineStatus;
  if (nHrv >= hrvTrustFull) {
    baselineStatus = 'full';
  } else if (nHrv >= hrvTrustMin) {
    baselineStatus = 'warming';
  } else {
    baselineStatus = 'cold_start';
  }

  String confidence;
  if (completeness == 0) {
    confidence = 'none';
  } else if (completeness < 0.35) {
    confidence = 'low';
  } else if (completeness >= 0.70 && baselineStatus == 'full') {
    confidence = 'high';
  } else {
    confidence = 'medium';
  }
  if (flags.contains('stale_hrv')) confidence = _demote(confidence);

  // ---------- Drivers (limiter / support) ----------
  final driverParts = <(String, num, num)>[
    if (hrvOn) ('hrv', shareHrv, hrv['sub'] as num),
    if (bbOn) ('body_battery', shareBodyBattery, bodyBattery['sub'] as num),
    if (rhrOn) ('resting_hr', shareRhr, rhr['sub'] as num),
    if (sleepOn) ('sleep_score', shareSleep, sleep['sub'] as num),
  ];
  final gaps = [for (final (name, share, sub) in driverParts) (name, share * (sub - neutralAnchor))];
  // min()/max() with a key return the first of equal keys.
  var limiter = gaps.first;
  var support = gaps.first;
  for (final g in gaps.skip(1)) {
    if (g.$2 < limiter.$2) limiter = g;
    if (g.$2 > support.$2) support = g;
  }

  final totalW = pySum([for (final (w, _) in axisParts) w]);
  final result = <String, Object?>{
    'date': targetDate,
    'score': score,
    'band': band,
    'label': _bandLabel[band],
    'confidence': confidence,
    'baseline_status': baselineStatus,
    'days_to_full': math.max(0, hrvTrustFull - nHrv),
    'data_completeness': pyRound(completeness, 3),
    'drivers': {'limiter': limiter.$1, 'support': support.$1},
    'flags': flags,
    'axes': {
      'autonomic': {
        'score': autonomicScore != null ? pyRound(autonomicScore, 3) : null,
        'weight': wAutonomic,
        'present': autonomicScore != null,
      },
      'sleep': {
        'score': sleepOn ? pyRound(sleep['sub'] as num, 3) : null,
        'weight': wSleep,
        'present': sleepOn,
      },
    },
    'components': {
      'hrv': hrv,
      'resting_hr': rhr,
      'body_battery': bodyBattery,
      'sleep_score': sleep,
      'sleep_duration': sleepDur,
    },
    'weights_effective': {
      'autonomic': autonomicScore != null ? pyRound(wAutonomic / totalW, 3) : 0,
      'sleep': sleepOn ? pyRound(wSleep / totalW, 3) : 0,
    },
  };
  result['briefing'] = _renderBriefing(result);
  return result;
}

Json _insufficient(String date) => {
      'date': date,
      'score': null,
      'band': 'unknown',
      'label': _bandLabel['unknown'],
      'confidence': 'none',
      'baseline_status': 'cold_start',
      'data_completeness': 0.0,
      'drivers': {'limiter': null, 'support': null},
      'flags': <String>[],
      'axes': {
        'autonomic': {'score': null, 'weight': wAutonomic, 'present': false},
        'sleep': {'score': null, 'weight': wSleep, 'present': false},
      },
      'components': <String, Object?>{},
      'briefing': 'UNKNOWN — no readiness score. No HRV, body battery or sleep '
          'recorded for $date. Sync your watch and check back.',
    };

/// The phrase for one driver, or null when a value it needs is missing
/// (where the Python lambda would raise and the caller falls back to the
/// component's name).
String? _componentPhrase(String name, Json c) {
  switch (name) {
    case 'hrv':
      final valueMs = c['value_ms'] as num?;
      if (c['z'] != null && valueMs != null && valueMs != 0) {
        final pctDev = c['pct_dev'] as num?;
        if (pctDev == null) return null;
        return 'HRV ${pyFixed(valueMs, 0)}ms, ${pyFixed(pctDev, 0, sign: true)}% vs your '
            '60-day baseline (z ${pyFixed(c['z'] as num, 1, sign: true)})';
      }
      return 'Garmin HRV status';
    case 'resting_hr':
      final delta = c['delta_bpm'] as num?;
      final value = c['value'] as num?;
      if (delta == null || value == null) return null;
      return 'resting HR ${pyFixed(delta, 0, sign: true)} bpm vs baseline (${pyFixed(value, 0)} bpm)';
    case 'body_battery':
      if (!c.containsKey('value')) return null;
      return 'morning body battery ${pyStr(c['value'])}';
    case 'sleep_score':
      if (!c.containsKey('value')) return null;
      return 'sleep score ${pyStr(c['value'])}';
  }
  return null;
}

String _confidencePhrase(Json r) {
  final conf = r['confidence'];
  final base = r['baseline_status'];
  final dtf = r['days_to_full'] ?? 0;
  if (conf == 'high') return 'high confidence';
  if (conf == 'medium' && base == 'full') return 'medium confidence';
  if (conf == 'medium' && base == 'warming') {
    return 'medium confidence, baseline still building (${dtf}d to go)';
  }
  if (base == 'cold_start' && conf != 'low') {
    return 'provisional — using Garmin signals while your baseline builds (${dtf}d to go)';
  }
  if (conf == 'low') return 'low confidence, limited data today';
  return 'no data';
}

String _renderBriefing(Json r) {
  final band = r['band'] as String;
  final comps = r['components'] as Json;
  final drivers = r['drivers'] as Json;
  final limiter = drivers['limiter'] as String?;
  final support = drivers['support'] as String?;

  String phrase(String name) =>
      _componentPhrase(name, (comps[name] as Json?) ?? const <String, Object?>{}) ?? name;

  var driver = '';
  if (limiter != null && limiter.isNotEmpty) {
    driver = 'Main limiter: ${phrase(limiter)}';
    if (support != null && support.isNotEmpty && support != limiter) {
      driver += '; support ${phrase(support)}';
    }
    driver += '. ';
  }

  var text = '${band.toUpperCase()} — readiness ${pyStr(r['score'])}/100 '
      '(${_confidencePhrase(r)}). $driver${_bandGuidance[band]}';
  if ((r['flags'] as List).contains('illness_watch')) {
    text = 'Heads-up — HRV down and resting HR up (possible illness/overreaching): $text';
  }
  return text;
}

/// Readiness for the newest record's date. With no records at all, the
/// "not enough data" answer for [today] (the current date by default).
Json readinessToday(List<Json> records, {CivilDate? today}) {
  if (records.isEmpty) {
    final now = DateTime.now();
    return _insufficient((today ?? CivilDate(now.year, now.month, now.day)).toString());
  }
  return scoreDate(records, records.first['date'] as String);
}

/// Point-in-time readiness for the most recent [days] scored dates.
Json readinessHistory(List<Json> records, {int days = 30}) {
  final clamped = math.max(1, math.min(days, 180));
  final series = <Json>[];
  for (final r in records.take(clamped)) {
    final s = scoreDate(records, r['date'] as String);
    final axes = s['axes'] as Json;
    series.add({
      'date': s['date'],
      'score': s['score'],
      'band': s['band'],
      'confidence': s['confidence'],
      'autonomic': (axes['autonomic'] as Json)['score'],
      'sleep': (axes['sleep'] as Json)['score'],
    });
  }
  return {'days': clamped, 'series': series};
}
