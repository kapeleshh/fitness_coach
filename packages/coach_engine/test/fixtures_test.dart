import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('parity fixtures', () {
    test('wellness inputs cover 90 days, newest first', () {
      final days = (loadFixture('wellness') as List).cast<Map<String, dynamic>>();
      expect(days, hasLength(90));
      final dates = days.map((d) => d['date'] as String).toList();
      expect(dates, orderedEquals([...dates]..sort((a, b) => b.compareTo(a))));
    });

    test('every Strava twin of a Garmin session is linked as a duplicate', () {
      final raw = loadFixture('activities_raw') as List;
      final rows = (loadFixture('activities') as List).cast<Map<String, dynamic>>();
      expect(rows, hasLength(raw.length));
      final duplicates = rows.where((r) => r['duplicate_of'] != null).toList();
      expect(duplicates, isNotEmpty);
      for (final row in duplicates) {
        expect(row['source'], 'strava');
        expect(row['duplicate_of'] as String, startsWith('garmin:'));
      }
    });

    test('readiness is scored for every wellness day', () {
      final days = (loadFixture('wellness') as List).cast<Map<String, dynamic>>();
      final readiness = loadFixture('readiness') as Map<String, dynamic>;
      expect(readiness.keys.toSet(), days.map((d) => d['date']).toSet());
    });

    test('API bodies exist for every request the app makes', () {
      final api = loadFixture('api') as Map<String, dynamic>;
      expect(
        api.keys,
        containsAll([
          '/api/readiness',
          '/api/readiness/history?days=14',
          '/api/training-load',
          '/api/insights',
          '/api/correlations',
          '/api/outlook',
          '/api/summary',
          '/api/health-data',
        ]),
      );
      for (final MapEntry(:key, :value) in api.entries) {
        if (value is Map) {
          expect(value.containsKey('error'), isFalse, reason: key);
        }
      }
    });
  });
}
