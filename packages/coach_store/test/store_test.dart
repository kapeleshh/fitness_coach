import 'dart:convert';
import 'dart:io';

import 'package:coach_engine/coach_engine.dart';
import 'package:coach_store/coach_store.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support/json_diff.dart';

/// The parity fixtures the Python engines wrote, shared with coach_engine.
Object? _fixture(String name) =>
    jsonDecode(File('../coach_engine/test/fixtures/$name.json').readAsStringSync());

const _key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _otherKey = 'ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100';

Json _minimalDay([Json overrides = const {}]) => {'date': '2026-07-01', ...overrides};

void main() {
  final wellness = (_fixture('wellness') as List).cast<Json>();
  final rawActivities = (_fixture('activities_raw') as List).cast<Json>();
  final api = _fixture('api') as Json;

  late CoachStore store;
  setUp(() => store = CoachStore.inMemory());
  tearDown(() => store.close());

  group('parity with db.py', () {
    test('wellness reads back exactly as the backend database returns it', () {
      store.upsertDays(wellness, origin: 'garmin');
      expect(store.allDays(), sameJson(wellness));
    });

    test('the legacy 0-filled read matches /api/health-data', () {
      store.upsertDays(wellness, origin: 'garmin');
      expect(store.allDays(legacyZeroFill: true), sameJson(api['/api/health-data']));
    });

    test('ingested activities read back with the same rows and duplicate links', () {
      final result = store.ingestActivities(rawActivities);
      expect(result, {'written': rawActivities.length, 'duplicates': 30});
      expect(store.activities(includeDuplicates: true), sameJson(_fixture('activities')));
      expect(store.activities(), hasLength(rawActivities.length - 30));
    });

    test('the engines on stored data give every API body the app reads', () {
      store
        ..upsertDays(wellness, origin: 'garmin')
        ..ingestActivities(rawActivities);
      final days = store.allDays();
      final rows = store.activities(includeDuplicates: true);
      final settings = store.allSettings();
      final bodies = <String, Object?>{
        '/api/readiness': readinessBody(days, rows, settings: settings),
        '/api/readiness/history?days=14': readinessHistoryBody(days, days: 14),
        '/api/training-load': trainingLoadBody(days, rows, settings: settings),
        '/api/insights': insightsBody(days),
        '/api/correlations': correlationsBody(days),
        '/api/correlations/pair?x=sleep_score&y=hrv&lag=0':
            correlationPairBody(days, 'sleep_score', 'hrv'),
        '/api/correlations/pair?x=avg_stress&y=sleep_score&lag=1':
            correlationPairBody(days, 'avg_stress', 'sleep_score', lag: 1),
        '/api/outlook': outlookBody(days),
        '/api/summary': summaryBody(days),
        '/api/health-data': healthDataBody(days),
      };
      expect(bodies.keys.toSet(), api.keys.toSet());
      for (final MapEntry(key: path, value: body) in bodies.entries) {
        expect(body, sameJson(api[path]), reason: path);
      }
    });
  });

  // Ported from backend/tests/test_db.py (TestStorage, TestSettings).
  group('storage', () {
    test('reads newest first', () {
      store.upsertDays(wellness.reversed.take(10).toList(), origin: 'garmin');
      final dates = [for (final r in store.allDays()) r['date'] as String];
      expect(dates, orderedEquals([...dates]..sort((a, b) => b.compareTo(a))));
    });

    test('a newer write from the same source replaces the day', () {
      store.upsertDays([_minimalDay({'sleep_score': 60})], origin: 'garmin');
      store.upsertDays([_minimalDay({'sleep_score': 75})], origin: 'garmin');
      expect(store.countDays(), 1);
      expect(store.day('2026-07-01')!['sleep_score'], 75);
    });

    test('the legacy zero fill restores the old shape', () {
      store.upsertDays([
        _minimalDay({
          'sleep_score': 0, 'hrv': 0, 'resting_hr': 0, 'sleep_insight': '',
          'hrv_status': 'UNKNOWN', 'steps': 5000,
        }),
      ], origin: 'garmin_export');
      final raw = store.day('2026-07-01')!;
      expect(raw['sleep_score'], isNull);
      expect(raw['hrv'], isNull);
      final legacy = store.day('2026-07-01', legacyZeroFill: true)!;
      expect([legacy['sleep_score'], legacy['hrv'], legacy['sleep_insight'], legacy['hrv_status'], legacy['steps']],
          [0, 0.0, '', 'UNKNOWN', 5000]);
    });

    test('sleep timestamps keep their type', () {
      // Epoch milliseconds from a sync, ISO strings from an export: each
      // must read back as written (NUMERIC affinity), not as text.
      store.upsertDays([
        {'date': '2026-07-02', 'sleep_score': 70, 'sleep_start_time': 1751490000000, 'sleep_end_time': 1751522400000},
        {'date': '2026-07-01', 'sleep_score': 71, 'sleep_start_time': '2026-06-30T22:30:00.0', 'sleep_end_time': '2026-07-01T06:30:00.0'},
      ], origin: 'garmin');
      expect(store.day('2026-07-02')!['sleep_start_time'], isA<int>().having((v) => v, 'value', 1751490000000));
      expect(store.day('2026-07-01')!['sleep_start_time'], '2026-06-30T22:30:00.0');
    });

    test('settings round-trip any JSON value', () {
      store
        ..setSetting('athlete_max_hr', 187)
        ..setSetting('zones', {'z2': [120, 140]});
      expect(store.setting('athlete_max_hr'), 187);
      expect(store.setting('zones'), {'z2': [120, 140]});
      expect(store.setting('absent', 'x'), 'x');
      expect(store.allSettings().keys.toSet(), {'athlete_max_hr', 'zones'});
    });
  });

  group('merging sources', () {
    test('a second source fills in fields without erasing the first', () {
      store.upsertDays([_minimalDay({'sleep_score': 80, 'body_battery_start': 70})], origin: 'garmin_export');
      store.upsertDays([_minimalDay({'steps': 9000, 'resting_hr': 51})], origin: 'health_connect');
      final day = store.day('2026-07-01')!;
      expect([day['sleep_score'], day['body_battery_start'], day['steps'], day['resting_hr']], [80, 70, 9000, 51]);
      expect(store.dayOrigins('2026-07-01'), {
        'sleep_score': 'garmin_export', 'body_battery_start': 'garmin_export',
        'steps': 'health_connect', 'resting_hr': 'health_connect',
      });
    });

    test("a source clears only values it wrote itself", () {
      store.upsertDays([_minimalDay({'sleep_score': 80, 'resting_hr': 50})], origin: 'garmin_export');
      store.upsertDays([_minimalDay({'steps': 9000})], origin: 'health_connect');
      // Health Connect now reports no steps and no resting HR for the day.
      store.upsertDays([_minimalDay({'steps': null, 'resting_hr': null})], origin: 'health_connect');
      final day = store.day('2026-07-01')!;
      expect(day['steps'], isNull); // its own value: cleared
      expect(day['resting_hr'], 50); // the export's value: kept
    });

    test('an impossible zero from one source does not erase another source', () {
      store.upsertDays([_minimalDay({'hrv': 55.0})], origin: 'garmin_export');
      store.upsertDays([_minimalDay({'hrv': 0})], origin: 'health_connect');
      expect(store.day('2026-07-01')!['hrv'], 55.0);
    });

    test('writing the same records again changes nothing', () {
      void importBoth() => store
        ..upsertDays(wellness, origin: 'garmin_export')
        ..upsertDays([_minimalDay({'steps': 1234})], origin: 'health_connect')
        ..ingestActivities(rawActivities);
      importBoth();
      final days = store.allDays();
      final origins = store.dayOrigins('2026-07-01');
      final activities = store.activities(includeDuplicates: true);
      importBoth();
      expect(store.allDays(), sameJson(days));
      expect(store.dayOrigins('2026-07-01'), origins);
      expect(store.activities(includeDuplicates: true), sameJson(activities));
    });

    test('when two sources write the same field, the later write wins', () {
      store
        ..upsertDays([_minimalDay({'steps': 1234})], origin: 'health_connect')
        ..upsertDays([_minimalDay({'steps': 9000})], origin: 'garmin_export');
      expect(store.day('2026-07-01')!['steps'], 9000);
      expect(store.dayOrigins('2026-07-01'), {'steps': 'garmin_export'});
    });
  });

  group('activities', () {
    test('filter by date and look up by id', () {
      store.ingestActivities(rawActivities);
      final first = store.activities().first;
      expect(store.activity(first['id'] as String), sameJson(first));
      expect(store.activity('nope:1'), isNull);
      final day = first['local_date'] as String;
      expect(store.activities(start: day, end: day).every((a) => a['local_date'] == day), isTrue);
    });

    test('remember the file each activity came from', () {
      store.ingestActivities([
        {...rawActivities.first, 'file_hash': 'abc123'},
      ]);
      expect(store.hasActivityFile('abc123'), isTrue);
      expect(store.hasActivityFile('other'), isFalse);
    });
  });

  test('import runs record how each import ended', () {
    final id = store.startImportRun('strava_export');
    store.finishImportRun(id, status: 'completed', counts: {'activities': 42});
    final failed = store.startImportRun('health_connect');
    store.finishImportRun(failed, status: 'failed', error: 'quota exceeded');
    final runs = store.importRuns();
    expect([for (final r in runs) r['status']], ['failed', 'completed']);
    expect(runs.last['counts'], {'activities': 42});
    expect(runs.first['error'], 'quota exceeded');
  });

  group('the encrypted file', () {
    late Directory dir;
    late String path;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('coach_store_test');
      path = '${dir.path}/maru.db';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('reopens with its key, keeping data and schema', () {
      CoachStore.open(path, key: _key)
        ..upsertDays(wellness, origin: 'garmin')
        ..close();
      final reopened = CoachStore.open(path, key: _key);
      addTearDown(reopened.close);
      expect(reopened.userVersion, CoachStore.schemaVersion);
      expect(reopened.countDays(), wellness.length);
    });

    test('cannot be read with another key or with no key', () {
      CoachStore.open(path, key: _key)
        ..upsertDays(wellness, origin: 'garmin')
        ..close();
      expect(() => CoachStore.open(path, key: _otherKey), throwsA(isA<StoreException>()));
      final plain = sqlite3.open(path);
      addTearDown(plain.close);
      expect(() => plain.select('SELECT * FROM daily_wellness'), throwsA(isA<SqliteException>()));
    });

    test('holds no plain text on disk', () {
      CoachStore.open(path, key: _key)
        ..upsertDays(wellness, origin: 'garmin')
        ..close();
      final bytes = File(path).readAsBytesSync();
      final text = latin1.decode(bytes);
      expect(text.startsWith('SQLite format 3'), isFalse);
      expect(text, isNot(contains(wellness.first['date'] as String)));
      expect(text, isNot(contains('daily_wellness')));
    });

    test('refuses a key that is not 32 random bytes in hex', () {
      expect(() => CoachStore.open(path, key: "secret'; DROP TABLE x"), throwsA(isA<StoreException>()));
    });
  });
}
