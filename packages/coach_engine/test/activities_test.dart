import 'package:coach_engine/coach_engine.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'support/json_diff.dart';

Json _act(String source, Object sourceId, String start,
        {String sport = 'Run', num? duration = 3600, Json extra = const {}}) =>
    {
      'source': source,
      'source_id': sourceId,
      'start_time_utc': start,
      'local_date': start.substring(0, 10),
      'sport_type': sport,
      'duration_s': duration,
      ...extra,
    };

List<Json> _normalized(List<Json> raws) => [for (final r in raws) normalizeActivity(r)];

void main() {
  group('parity with activities.py', () {
    test('ingesting the synthetic activities gives the same rows and links', () {
      final raw = (loadFixture('activities_raw') as List).cast<Json>();
      final expected = loadFixture('activities') as List;
      final rows = [for (final r in linkDuplicates(_normalized(raw))) storedActivity(r)]
        // db.get_activities: newest start first
        ..sort((a, b) => (b['start_time_utc'] as String).compareTo(a['start_time_utc'] as String));
      expect(rows, sameJson(expected));
    });
  });

  // Ported from backend/tests/test_activities.py (TestSportFamily,
  // TestNormalize, TestDedup). The ingest and endpoint tests there exercise
  // the database and the API, which the data store and local data source
  // cover on the phone.
  group('sportFamily', () {
    const cases = {
      'Run': 'run', 'TrailRun': 'run', 'trail_running': 'run',
      'treadmill_running': 'run', 'Ride': 'ride', 'road_biking': 'ride',
      'EBikeRide': 'ride', 'indoor_cycling': 'ride', 'Swim': 'swim',
      'lap_swimming': 'swim', 'WeightTraining': 'strength',
      'strength_training': 'strength', 'Hike': 'hike',
    };
    for (final MapEntry(key: sport, value: family) in cases.entries) {
      test('$sport is $family', () => expect(sportFamily(sport), family));
    }
    test('no type is other', () => expect(sportFamily(null), 'other'));
  });

  group('normalizeActivity', () {
    test('builds the id and maps impossible zeros to null', () {
      final rec = normalizeActivity(_act('strava', 123, '2026-07-01T07:00:00Z',
          extra: {'avg_hr': 0, 'avg_power': 0, 'name': ''}));
      expect(rec['id'], 'strava:123');
      expect(rec['source_id'], '123');
      expect(rec['avg_hr'], isNull);
      expect(rec['avg_power'], isNull);
      expect(rec['name'], isNull);
      expect(rec['sport_family'], 'run');
    });

    test('requires identity and start time', () {
      expect(() => normalizeActivity({'source': 'strava', 'source_id': 1}), throwsArgumentError);
    });
  });

  group('findDuplicates', () {
    test("Garmin's upload to Strava is a duplicate", () {
      final recs = _normalized([
        _act('garmin', 1, '2026-07-01T07:00:00Z', sport: 'running', duration: 3600),
        _act('strava', 2, '2026-07-01T07:00:40Z', duration: 3610),
      ]);
      expect(findDuplicates(recs), {'strava:2': 'garmin:1'});
    });

    for (final (start, sport, duration, why) in [
      ('2026-07-01T07:06:00Z', 'Run', 3600, 'starts more than 5 min apart'),
      ('2026-07-01T07:00:30Z', 'Ride', 3600, 'different sport family'),
      ('2026-07-01T07:00:30Z', 'Run', 3000, 'duration differs by more than 10%'),
    ]) {
      test('not duplicates: $why', () {
        final recs = _normalized([
          _act('garmin', 1, '2026-07-01T07:00:00Z', sport: 'running', duration: 3600),
          _act('strava', 2, start, sport: sport, duration: duration),
        ]);
        expect(findDuplicates(recs), isEmpty);
      });
    }

    test('back-to-back sessions from the same source stay distinct', () {
      final recs = _normalized([
        _act('strava', 1, '2026-07-01T07:00:00Z', duration: 600),
        _act('strava', 2, '2026-07-01T07:02:00Z', duration: 620),
      ]);
      expect(findDuplicates(recs), isEmpty);
    });

    test('one upload cannot bridge two Garmin sessions', () {
      final recs = _normalized([
        _act('garmin', 1, '2026-07-01T07:00:00Z', duration: 180),
        _act('garmin', 2, '2026-07-01T07:04:00Z', duration: 180),
        _act('strava', 3, '2026-07-01T07:03:50Z', duration: 182),
      ]);
      expect(findDuplicates(recs), {'strava:3': 'garmin:2'});
    });

    test('a missing duration falls back to start time and sport', () {
      final recs = _normalized([
        _act('garmin', 1, '2026-07-01T07:00:00Z', duration: null),
        _act('strava', 2, '2026-07-01T07:01:00Z', duration: 3600),
      ]);
      expect(findDuplicates(recs), {'strava:2': 'garmin:1'});
    });

    test('the synthetic dataset gives the expected links', () {
      final raw = (loadFixture('activities_raw') as List).cast<Json>();
      final expected = {
        for (final r in (loadFixture('activities') as List).cast<Json>())
          if (r['duplicate_of'] != null) r['id']: r['duplicate_of'],
      };
      expect(findDuplicates(_normalized(raw)), expected);
    });
  });

  group('public-app sources', () {
    test('a Garmin session seen in Health Connect and a Strava export counts once', () {
      final recs = _normalized([
        _act('health_connect', 'hc-1', '2026-07-01T07:00:05Z', sport: 'running', duration: 3590),
        _act('strava_export', 42, '2026-07-01T07:00:30Z', duration: 3600),
      ]);
      expect(findDuplicates(recs), {'strava_export:42': 'health_connect:hc-1'});
    });

    test("Garmin's own record outranks the Health Connect copy", () {
      final recs = _normalized([
        _act('health_connect', 'hc-1', '2026-07-01T07:00:05Z', sport: 'running'),
        _act('garmin_export', 7, '2026-07-01T07:00:00Z', sport: 'running'),
        _act('strava_export', 42, '2026-07-01T07:00:30Z'),
      ]);
      expect(findDuplicates(recs), {
        'health_connect:hc-1': 'garmin_export:7',
        'strava_export:42': 'garmin_export:7',
      });
    });

    test('stored rows read REAL columns back as floats', () {
      final stored = storedActivity(normalizeActivity(
          _act('garmin', 1, '2026-07-01T07:00:00Z', extra: {'avg_hr': 140})));
      expect(stored['duration_s'], isA<double>());
      expect(stored['avg_hr'], 140.0);
      expect(stored['source_id'], '1');
    });
  });
}
