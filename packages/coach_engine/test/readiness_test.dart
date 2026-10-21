import 'package:coach_engine/coach_engine.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'support/json_diff.dart';

final _end = CivilDate(2026, 7, 7);

/// [n] synthetic days, newest first, as `_series` in
/// backend/tests/test_readiness.py. Jitter gives a realistic ln-HRV SD.
List<Json> _series({
  int n = 60,
  double hrvBase = 55.0,
  bool jitter = true,
  int rhr = 50,
  int sleep = 82,
  int bb = 72,
  String? status = 'BALANCED',
  int deep = 90,
  int light = 240,
  int rem = 90,
}) =>
    [
      for (var i = 0; i < n; i++)
        {
          'date': _end.addDays(-i).toString(),
          'hrv': hrvBase + (jitter ? ((i % 7) - 3) * 2.0 : 0.0),
          'hrv_status': status,
          'resting_hr': rhr,
          'sleep_score': sleep,
          'body_battery_start': bb,
          'deep_sleep_minutes': deep,
          'light_sleep_minutes': light,
          'rem_sleep_minutes': rem,
        },
    ];

List<Json> _setRecent(List<Json> rows, int k, Json fields) {
  for (var i = 0; i < k; i++) {
    rows[i].addAll(fields);
  }
  return rows;
}

Json _component(Json r, String name) => (r['components'] as Json)[name] as Json;

void main() {
  final wellness = (loadFixture('wellness') as List).cast<Json>();

  group('parity with readiness_engine.py', () {
    test('score_date matches for every day of the synthetic dataset', () {
      final expected = loadFixture('readiness') as Json;
      for (final MapEntry(key: date, value: want) in expected.entries) {
        expect(scoreDate(wellness, date), sameJson(want), reason: date);
      }
    });

    test('readiness_today matches every scenario from the Python tests', () {
      for (final scenario in (loadFixture('readiness_scenarios') as List).cast<Json>()) {
        final records = (scenario['records'] as List).cast<Json>();
        expect(readinessToday(records), sameJson(scenario['expected']),
            reason: scenario['name'] as String);
      }
    });

    test('the history the app requests matches the API body', () {
      final api = loadFixture('api') as Json;
      expect(readinessHistory(wellness, days: 14), sameJson(api['/api/readiness/history?days=14']));
    });
  });

  // Ported from backend/tests/test_readiness.py: behavioral guarantees that
  // stay true if the constants are retuned.
  group('scoring', () {
    test('a normal full baseline is green with high confidence', () {
      final r = readinessToday(_series());
      expect(r['baseline_status'], 'full');
      expect(r['band'], 'green');
      expect(r['score'] as int, greaterThanOrEqualTo(70));
      expect(r['confidence'], 'high');
      expect(_component(r, 'hrv')['source'], 'baseline');
    });

    test('suppressed HRV scores lower than normal', () {
      final normal = readinessToday(_series())['score'] as int;
      final supp = readinessToday(_setRecent(_series(), 5, {'hrv': 38.0}));
      expect(supp['score'] as int, lessThan(normal));
      expect(supp['band'], isIn(['amber', 'red']));
      expect(_component(supp, 'hrv')['z'] as num, lessThan(0));
    });

    test('the illness override forces red with a flag', () {
      final r = readinessToday(_setRecent(_series(), 3, {'hrv': 34.0, 'resting_hr': 60}));
      expect(r['flags'], contains('illness_watch'));
      expect(r['band'], 'red');
      expect(r['score'] as int, lessThanOrEqualTo(35));
    });

    test('cold start falls back to the Garmin status', () {
      final r = readinessToday(_series(n: 10));
      expect(r['baseline_status'], 'cold_start');
      expect(_component(r, 'hrv')['source'], 'status');
      expect(_component(r, 'hrv')['z'], isNull);
      expect(r['confidence'], isIn(['low', 'medium']));
      expect(r['score'], isNotNull);
      expect(r['days_to_full'], 18);
    });

    test('HRV is stale when recent days are missing', () {
      final r = readinessToday(
          _setRecent(_series(), 5, {'hrv': null, 'hrv_status': 'BALANCED'}));
      expect(r['flags'], contains('stale_hrv'));
      expect(_component(r, 'hrv')['source'], 'status');
    });

    test('the short-sleep guard caps the sleep axis', () {
      final r = readinessToday(_setRecent(_series(sleep: 92), 1, {
        'deep_sleep_minutes': 40,
        'light_sleep_minutes': 120,
        'rem_sleep_minutes': 60,
      }));
      expect(_component(r, 'sleep_duration')['guard_applied'], isTrue);
      expect(_component(r, 'sleep_score')['sub'] as num, lessThanOrEqualTo(0.5));
    });

    test('missing HRV and status drops the component but still scores', () {
      final r = readinessToday(_setRecent(_series(), 8, {'hrv': null, 'hrv_status': null}));
      expect(_component(r, 'hrv')['available'], isFalse);
      expect(r['score'], isNotNull);
      expect(((r['axes'] as Json)['autonomic'] as Json)['present'], isTrue);
    });

    test('no usable data returns unknown', () {
      final r = readinessToday([
        {
          'date': '2026-07-07', 'hrv': null, 'hrv_status': null, 'resting_hr': null,
          'sleep_score': null, 'body_battery_start': null,
        },
      ]);
      expect(r['score'], isNull);
      expect(r['band'], 'unknown');
      expect(r['confidence'], 'none');
    });

    test('the briefing names the score and is deterministic', () {
      final rows = _series();
      final a = readinessToday(rows)['briefing'] as String;
      expect(readinessToday(rows)['briefing'], a);
      expect(a.toLowerCase(), contains('readiness'));
      expect(a, contains('/100'));
    });

    test('history is point in time, newest first', () {
      final hist = readinessHistory(_series(), days: 5);
      final series = (hist['series'] as List).cast<Json>();
      expect(series, hasLength(5));
      expect(series.every((s) => s.containsKey('score') && s.containsKey('band')), isTrue);
    });
  });

  group('fixes from the adversarial review', () {
    test('warming with an unknown status fades from the anchor', () {
      final r = readinessToday(_series(n: 14, status: 'UNKNOWN'));
      expect(r['baseline_status'], 'warming');
      expect(_component(r, 'hrv')['source'], 'blend');
      expect(((_component(r, 'hrv')['sub'] as num) - neutralAnchor).abs(), lessThan(0.06));
    });

    test('the illness override does not fire while warming', () {
      final r = readinessToday(
          _setRecent(_series(n: 20, status: 'UNKNOWN'), 3, {'hrv': 34.0, 'resting_hr': 62}));
      expect(r['baseline_status'], 'warming');
      expect(r['flags'], isNot(contains('illness_watch')));
      expect(r['flags'], isNot(contains('hrv_suppressed')));
    });

    test('body battery is capped under dual autonomic suppression', () {
      final rows = _setRecent(_series(bb: 72), 7, {'hrv': 50.0, 'resting_hr': 53});
      _setRecent(rows, 1, {'hrv': 50.0, 'resting_hr': 53, 'body_battery_start': 95});
      expect(readinessToday(rows)['flags'], contains('body_battery_capped'));
      final normal = readinessToday(_setRecent(_series(bb: 72), 1, {'body_battery_start': 95}));
      expect(normal['flags'], isNot(contains('body_battery_capped')));
    });

    test('a severe isolated HRV suppression forces red', () {
      final rows = _setRecent(_series(bb: 72), 7, {'hrv': 35.0});
      _setRecent(rows, 1, {'hrv': 35.0, 'body_battery_start': 95, 'sleep_score': 96});
      final r = readinessToday(rows);
      expect(r['flags'], contains('hrv_suppressed'));
      expect(r['band'], 'red');
    });

    test('a row with a malformed date is skipped, not fatal', () {
      final rows = _series(n: 30)
        ..add({
          'date': 'not-a-date', 'hrv': 50, 'hrv_status': 'BALANCED', 'resting_hr': 50,
          'sleep_score': 80, 'body_battery_start': 70,
        });
      expect(readinessToday(rows)['score'], isNotNull);
    });

    test('cold start clears the baseline metadata', () {
      final c = _component(readinessToday(_series(n: 10)), 'hrv');
      expect(c['z'], isNull);
      expect(c['pct_dev'], isNull);
      expect(c['cv_7'], isNull);
    });
  });

  test('the shared curve has its deadband and anchors and never decreases', () {
    expect(sharedCurve(0.0), 0.85);
    expect(sharedCurve(0.4), 0.85);
    expect(sharedCurve(2.0), 1.0);
    expect(sharedCurve(-3.5), 0.0);
    final ys = [for (final x in [-4, -2, -1, -0.5, 0, 0.5, 1, 2]) sharedCurve(x)];
    expect(ys, orderedEquals([...ys]..sort()));
  });

  test('with no records the answer is unknown for today', () {
    final r = readinessToday([], today: _end);
    expect(r['date'], '2026-07-07');
    expect(r['band'], 'unknown');
  });
}
