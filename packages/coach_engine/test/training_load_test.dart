import 'package:coach_engine/coach_engine.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'support/json_diff.dart';

const _defaultParams = {'max_hr': 190.0, 'max_hr_source': 'observed', 'trimp_sex': 'male'};

/// An activity row as the store returns it with duplicates included, as
/// `_row` in backend/tests/test_training_load.py.
Json _row(String source, Object sourceId, String localDate,
        {String sport = 'run', num? duration = 3600, int hour = 7, Json extra = const {}}) =>
    {
      'id': '$source:$sourceId', 'source': source, 'source_id': '$sourceId',
      'start_time_utc': '${localDate}T${hour.toString().padLeft(2, '0')}:00:00Z',
      'local_date': localDate, 'sport_type': sport, 'sport_family': sportFamily(sport),
      'name': null, 'duration_s': duration, 'moving_time_s': null, 'distance_m': null,
      'elevation_gain_m': null, 'avg_hr': null, 'max_hr': null, 'avg_power': null,
      'calories': null, 'suffer_score': null, 'training_load': null, 'duplicate_of': null,
      ...extra,
    };

/// [n] days of resting HR from [start] (50, 51, ...), newest first.
List<Json> _wellness({String start = '2026-07-01', int n = 7, int rhr0 = 50}) {
  final d0 = CivilDate.parse(start);
  return [
    for (var i = 0; i < n; i++) {'date': d0.addDays(i).toString(), 'resting_hr': rhr0 + i},
  ].reversed.toList();
}

List<Json> _sessionsEveryDay(int n, double load,
        {CivilDate? start, String method = 'garmin_load'}) =>
    [
      for (var i = 0; i < n; i++)
        {
          'local_date': (start ?? CivilDate(2026, 1, 1)).addDays(i).toString(),
          'load': load, 'method': method, 'minutes': 60.0,
        },
    ];

void main() {
  final wellness = (loadFixture('wellness') as List).cast<Json>();
  final activities = (loadFixture('activities') as List).cast<Json>();
  final api = loadFixture('api') as Json;
  final data = compute(wellness, activities);

  group('parity with training_load_engine.py', () {
    test('compute gives the same sessions, daily series and parameters', () {
      expect(data, sameJson(loadFixture('training_load')));
    });

    test('the training-load body the app requests matches the API', () {
      expect(trainingLoadToday(data), sameJson(api['/api/training-load']));
    });

    test('readiness with the fused training-load note matches /api/readiness', () {
      final readiness = readinessToday(wellness);
      final annotated = annotateReadiness(readiness, stateOn(readiness['date'] as String, data));
      expect(annotated, sameJson(api['/api/readiness']));
    });
  });

  group('trimp', () {
    test('matches hand-computed values', () {
      expect(trimp(60, 150, 50, 190), closeTo(108.1, 0.05));
      expect(trimp(60, 150, 50, 190, 'female'), closeTo(121.5, 0.05));
    });

    for (final (args, why) in [
      ([60, 45, 50, 190], 'average below resting'),
      ([60, 150, 50, 65], 'max minus resting under the minimum reserve'),
      ([null, 150, 50, 190], 'no minutes'),
      ([60, 150, null, 190], 'no resting HR'),
      ([0, 150, 50, 190], 'zero minutes'),
    ]) {
      test('rejects unusable inputs: $why', () {
        expect(trimp(args[0], args[1], args[2], args[3]), isNull);
      });
    }

    test('caps the reserve fraction', () {
      expect(trimp(60, 200, 50, 190), trimp(60, 190, 50, 190));
    });
  });

  group('restingHrLookup', () {
    test('is a point-in-time median with an earliest-readings fallback', () {
      final at = restingHrLookup(_wellness()); // 07-01..07-07 -> 50..56
      expect(at('2026-07-03'), 51); // median of 50, 51, 52
      expect(at('2026-08-01'), 53); // last 7 readings
      expect(at('2026-01-01'), 53); // predates all: earliest 7
    });

    test('is null without readings', () {
      expect(restingHrLookup([{'date': '2026-07-01', 'resting_hr': null}])('2026-07-01'), isNull);
    });
  });

  group('athleteParams', () {
    test('observed max HR ignores implausible values', () {
      final rows = [
        _row('garmin', 1, '2026-07-01', extra: {'max_hr': 185}),
        _row('garmin', 2, '2026-07-02', extra: {'max_hr': 250}),
      ];
      expect(athleteParams(rows, [{'max_hr': 170}], {}),
          {'max_hr': 185, 'max_hr_source': 'observed', 'trimp_sex': 'male'});
    });

    test('settings win, and bad values fall back to the defaults', () {
      final p = athleteParams([], [], {'athlete_max_hr': 180, 'trimp_sex': 'female'});
      expect(p['max_hr'], 180.0);
      expect(p['max_hr_source'], 'setting');
      expect(p['trimp_sex'], 'female');
      final bad = athleteParams([], [], {'athlete_max_hr': 'abc', 'trimp_sex': 'unknown'});
      expect(bad['max_hr'], isNull);
      expect(bad['trimp_sex'], 'male');
      expect(athleteParams([], [], {'athlete_max_hr': '192'})['max_hr'], 192.0);
    });
  });

  group('sessionLoads', () {
    test('follows the method priority', () {
      final rows = [
        _row('garmin', 1, '2026-07-02', extra: {'training_load': 120.0, 'avg_hr': 150}),
        _row('garmin', 2, '2026-07-03', extra: {'avg_hr': 150}), // -> trimp
        _row('strava', 3, '2026-07-04', extra: {'suffer_score': 80.0}), // -> relative effort
        _row('strava', 4, '2026-07-05', sport: 'Walk', duration: 1800), // -> estimate
        _row('strava', 5, '2026-07-06', duration: null), // -> none
      ];
      final byId = {
        for (final s in sessionLoads(rows, _wellness(), _defaultParams)) s['id']: s,
      };
      expect(byId['garmin:1']!['method'], 'garmin_load');
      expect(byId['garmin:1']!['load'], 120.0);
      expect(byId['garmin:2']!['method'], 'trimp');
      // resting HR on 07-03 is the median of 50, 51, 52
      expect(byId['garmin:2']!['load'] as num, closeTo(trimp(60, 150, 51, 190)!, 0.05));
      expect(byId['strava:3']!['method'], 'relative_effort');
      expect(byId['strava:4']!['method'], 'duration_estimate');
      expect(byId['strava:4']!['load'] as num, closeTo(30 * loadPerMinute['walk']!, 1e-9));
      expect(byId['strava:5']!['method'], 'none');
      expect(byId['strava:5']!['load'], 0.0);
    });

    test("a canonical session borrows its duplicate's signal", () {
      final garmin = _row('garmin', 1, '2026-07-02'); // no load, no HR
      final twin = _row('strava', 2, '2026-07-02',
          extra: {'suffer_score': 80.0, 'duplicate_of': 'garmin:1'});
      final [s] = sessionLoads([garmin, twin], [], _defaultParams);
      expect(s['id'], 'garmin:1');
      expect((s['method'], s['load']), ('relative_effort', 80.0));
      expect(s['sources'], ['garmin', 'strava']);
    });

    test('excluding a source drops what it lent', () {
      final garmin = _row('garmin', 1, '2026-07-02');
      final twin = _row('strava', 2, '2026-07-02',
          extra: {'suffer_score': 80.0, 'duplicate_of': 'garmin:1'});
      final [s] = sessionLoads([garmin], [], _defaultParams);
      expect(s['method'], 'duration_estimate');
      expect(s['load'] as num, closeTo(60 * loadPerMinute['run']!, 1e-9));
      expect(s['sources'], ['garmin']);
      final [borrowed] = sessionLoads([garmin, twin], [], _defaultParams);
      expect(borrowed['method'], 'relative_effort');
    });
  });

  group('dailySeries', () {
    test('a single impulse matches hand-computed values', () {
      final [day0, day1, day2] = dailySeries([
        {'local_date': '2026-01-01', 'load': 100.0, 'method': 'garmin_load', 'minutes': 60.0},
      ], end: CivilDate(2026, 1, 3));
      // Each row is the state ENTERING the day.
      expect([day0['ctl'], day0['atl'], day0['tsb'], day0['load']], [0.0, 0.0, 0.0, 100.0]);
      expect([day1['ctl'], day1['atl'], day1['tsb']], [2.4, 13.3, -10.9]);
      expect([day2['ctl'], day2['atl'], day2['load']], [2.3, 11.5, 0.0]);
    });

    test('steady load converges, and rest days are zero', () {
      final last = dailySeries(_sessionsEveryDay(400, 100.0)).last;
      expect([last['ctl'], last['atl'], last['tsb']], [100.0, 100.0, 0.0]);
      expect(last['form_band'], 'neutral');
      expect(last['acwr'] as num, closeTo(1.0, 0.01));
      expect(last['confidence'], 'high');
      expect(last['flags'], isEmpty);

      final gapped = dailySeries([
        ..._sessionsEveryDay(1, 100.0),
        ..._sessionsEveryDay(1, 100.0, start: CivilDate(2026, 1, 11)),
      ]);
      expect(gapped, hasLength(11));
      expect([for (final r in gapped.sublist(1, 10)) r['load']], List.filled(9, 0.0));
    });

    test('flags a load spike', () {
      final start = CivilDate(2026, 1, 1);
      final series = dailySeries([
        ..._sessionsEveryDay(60, 50.0),
        ..._sessionsEveryDay(3, 300.0, start: start.addDays(60)),
      ], end: start.addDays(63));
      expect(series[60]['flags'], isNot(contains('load_spike')));
      expect(series[63]['acwr'] as num, greaterThan(acwrSpike));
      expect(series[63]['flags'], contains('load_spike'));
    });

    test('applies the maturity gates', () {
      final series = dailySeries(_sessionsEveryDay(60, 80.0));
      final (early, warming, mature) = (series[10], series[20], series[50]);
      expect(early['form_band'], isNull);
      expect(early['acwr'], isNull);
      expect(warming['form_band'], isNotNull);
      expect(warming['flags'], contains('warming_up'));
      expect(warming['confidence'], 'low');
      expect(mature['flags'], isNot(contains('warming_up')));
      expect(mature['confidence'], 'high');
    });

    test('estimated load lowers confidence', () {
      final last = dailySeries(_sessionsEveryDay(60, 80.0, method: 'duration_estimate')).last;
      expect(last['measured_share'], 0.0);
      expect(last['confidence'], 'low');
    });

    const bands = {
      26: 'transition', 25: 'fresh', 6: 'fresh', 5: 'neutral',
      -9: 'neutral', -10: 'building', -30: 'overreaching', -50: 'overreaching',
    };
    for (final MapEntry(key: pct, value: band) in bands.entries) {
      test('form $pct% is $band', () => expect(formBand(pct), band));
    }
  });

  group('readiness fusion', () {
    Json state(String formBand) =>
        {'form_band': formBand, 'summary': 'Training load: x.', 'flags': <String>[]};

    for (final (readiness, form, expected) in [
      ('green', 'overreaching', 'capping intensity'),
      ('green', 'fresh', 'key session'),
      ('amber', 'overreaching', 'likely cause'),
      ('red', 'neutral', 'sleep, stress or illness'),
      ('amber', 'building', null),
      ('unknown', 'overreaching', null),
    ]) {
      test('$readiness readiness with $form load', () {
        final note = readinessNote(readiness, state(form));
        expect(note, startsWith('Training load: x.'));
        expect(note, expected == null ? 'Training load: x.' : contains(expected));
      });
    }

    test('an unscored briefing is kept, and no state means no training load', () {
      final full = {for (final k in readinessFields) k: null, ...state('fresh')};
      final out = annotateReadiness(
          {'date': '2026-07-07', 'score': null, 'band': 'unknown', 'briefing': 'UNKNOWN'}, full);
      expect(out['briefing'], 'UNKNOWN');
      expect((out['training_load'] as Json)['form_band'], 'fresh');
      expect(annotateReadiness({'score': 80, 'briefing': 'B'}, null)['training_load'], isNull);
    });
  });

  test('history is newest first and clamped', () {
    final hist = trainingLoadHistory(data, days: 5);
    final series = (hist['series'] as List).cast<Json>();
    expect(series, hasLength(5));
    expect(series.first['date'], (data['series'] as List).cast<Json>().last['date']);
    expect(trainingLoadHistory(data, days: 0)['days'], 1);
  });

  test('no activities gives the empty state', () {
    final today = trainingLoadToday(compute(wellness, []));
    expect(today['confidence'], 'none');
    expect(today['history_days'], 0);
  });
}
