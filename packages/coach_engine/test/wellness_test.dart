import 'package:coach_engine/coach_engine.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

Json _minimalDay([Json overrides = const {}]) => {'date': '2026-07-01', ...overrides};

// Ported from backend/tests/test_db.py (TestNormalizeRecord, and the legacy
// zero-fill half of TestStorage).
void main() {
  group('normalizeRecord', () {
    test('impossible zeros become null', () {
      final rec = normalizeRecord(_minimalDay({
        'hrv': 0, 'sleep_score': 0, 'resting_hr': 0, 'body_battery_start': 0,
        'avg_stress': 0, 'total_calories': 0,
      }));
      for (final field in ['hrv', 'sleep_score', 'resting_hr', 'body_battery_start', 'avg_stress', 'total_calories']) {
        expect(rec[field], isNull, reason: field);
      }
    });

    test('real values are kept', () {
      final rec = normalizeRecord(_minimalDay({'hrv': 58.9, 'sleep_score': 71, 'steps': 9231}));
      expect([rec['hrv'], rec['sleep_score'], rec['steps']], [58.9, 71, 9231]);
    });

    test('fields that can be 0 keep their zero', () {
      final rec = normalizeRecord(_minimalDay({
        'steps': 0, 'floors_climbed': 0, 'active_minutes': 0, 'stress_high_minutes': 0,
      }));
      expect([rec['steps'], rec['floors_climbed'], rec['active_minutes'], rec['stress_high_minutes']],
          [0, 0, 0, 0]);
    });

    test('sleep stages become null only when the sleep record is missing', () {
      final missing = normalizeRecord(_minimalDay({
        'sleep_score': 0, 'deep_sleep_minutes': 0, 'light_sleep_minutes': 0,
        'rem_sleep_minutes': 0, 'awake_minutes': 0,
      }));
      expect(missing['deep_sleep_minutes'], isNull);
      expect(missing['awake_minutes'], isNull);
      final tracked = normalizeRecord(
          _minimalDay({'sleep_score': 64, 'deep_sleep_minutes': 0, 'awake_minutes': 0}));
      expect(tracked['deep_sleep_minutes'], 0);
      expect(tracked['awake_minutes'], 0);
    });

    test('a Health Connect night without a sleep score keeps its zero stages', () {
      final rec = normalizeRecord(_minimalDay({
        'deep_sleep_minutes': 0, 'light_sleep_minutes': 300, 'awake_minutes': 0,
        'sleep_start_time': '2026-06-30T23:00:00Z', 'sleep_end_time': '2026-07-01T06:00:00Z',
      }));
      expect(rec['deep_sleep_minutes'], 0);
      expect(rec['awake_minutes'], 0);
    });

    test('UNKNOWN HRV status is null when HRV is missing', () {
      expect(normalizeRecord(_minimalDay({'sleep_score': 0, 'hrv': 0, 'hrv_status': 'UNKNOWN'}))['hrv_status'],
          isNull);
      expect(normalizeRecord(_minimalDay({'sleep_score': 70, 'hrv': 0, 'hrv_status': 'UNKNOWN'}))['hrv_status'],
          'UNKNOWN');
    });

    test('empty strings become null', () {
      final rec = normalizeRecord(_minimalDay({'sleep_insight': '', 'sleep_feedback': ''}));
      expect(rec['sleep_insight'], isNull);
      expect(rec['sleep_feedback'], isNull);
    });

    test('a date is required', () {
      expect(() => normalizeRecord({'sleep_score': 70}), throwsArgumentError);
    });

    test('stored records come back unchanged', () {
      for (final r in (loadFixture('wellness') as List).cast<Json>()) {
        expect(normalizeRecord(r), r);
      }
    });
  });

  test('legacyFill restores the old 0-filled shape', () {
    final legacy = legacyFill(normalizeRecord(_minimalDay({
      'sleep_score': 0, 'hrv': 0, 'resting_hr': 0, 'sleep_insight': '',
      'hrv_status': 'UNKNOWN', 'steps': 5000,
    })));
    expect(legacy['sleep_score'], 0);
    expect(legacy['hrv'], 0.0);
    expect(legacy['hrv'], isA<double>());
    expect(legacy['sleep_insight'], '');
    expect(legacy['hrv_status'], 'UNKNOWN');
    expect(legacy['steps'], 5000);
    expect(legacy['sleep_start_time'], isNull);
  });
}
