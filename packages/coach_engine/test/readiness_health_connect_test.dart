import 'package:coach_engine/coach_engine.dart';
import 'package:test/test.dart';

final _end = CivilDate(2026, 7, 7);

/// [n] nights from a phone with Health Connect data only, newest first:
/// sleep stages and times, resting HR and (optionally) HRV RMSSD, but no
/// Garmin sleep score, body battery or HRV status.
List<Json> _healthConnectSeries({
  int n = 60,
  bool withHrv = true,
  int deep = 80,
  int light = 260,
  int rem = 100,
  int awake = 15,
  int extraInBed = 0,
}) =>
    [
      for (var i = 0; i < n; i++)
        () {
          final wake = DateTime.utc(_end.year, _end.month, _end.day, 6, 30).subtract(Duration(days: i));
          final inBed = deep + light + rem + awake + extraInBed;
          return <String, Object?>{
            'date': _end.addDays(-i).toString(),
            'hrv': withHrv ? 48.0 + ((i % 7) - 3) * 2.0 : null,
            'hrv_status': null,
            'resting_hr': 52,
            'sleep_score': null,
            'body_battery_start': null,
            'deep_sleep_minutes': deep,
            'light_sleep_minutes': light,
            'rem_sleep_minutes': rem,
            'awake_minutes': awake,
            'sleep_start_time': wake.subtract(Duration(minutes: inBed)).toIso8601String(),
            'sleep_end_time': wake.toIso8601String(),
          };
        }(),
    ];

Json _sleep(Json r) => (r['components'] as Json)['sleep_score'] as Json;

void main() {
  group('estimateSleepScore', () {
    test('a long, efficient, unbroken night scores 100', () {
      final night = {
        'deep_sleep_minutes': 90, 'light_sleep_minutes': 280, 'rem_sleep_minutes': 120,
        'awake_minutes': 10,
        'sleep_start_time': '2026-07-06T22:00:00Z', 'sleep_end_time': '2026-07-07T06:20:00Z',
      };
      final e = estimateSleepScore(night)!;
      expect(e['score'], 100);
      expect(e['tst_min'], 490);
      expect(e['efficiency'], closeTo(0.98, 0.001));
    });

    test('shorter, more broken nights score lower, in order', () {
      int score(int tstMin, int awake, int extraInBed) => estimateSleepScore({
            'deep_sleep_minutes': 0, 'light_sleep_minutes': tstMin, 'rem_sleep_minutes': 0,
            'awake_minutes': awake,
            'sleep_start_time': 0,
            'sleep_end_time': (tstMin + awake + extraInBed) * 60000,
          })!['score'] as int;
      final good = score(480, 10, 0);
      final short = score(360, 10, 0);
      final broken = score(480, 70, 30);
      final bad = score(300, 90, 60);
      expect(good, greaterThan(short));
      expect(good, greaterThan(broken));
      expect(short, greaterThan(bad));
      expect(broken, greaterThan(bad));
    });

    test('uses only what is there, and nothing without stage minutes', () {
      final durationOnly = estimateSleepScore(
          {'deep_sleep_minutes': 60, 'light_sleep_minutes': 240, 'rem_sleep_minutes': 120})!;
      expect(durationOnly['efficiency'], isNull);
      expect(durationOnly['waso_min'], isNull);
      expect(durationOnly['score'], 85); // 7 h on the duration curve alone
      expect(estimateSleepScore({'deep_sleep_minutes': 60, 'light_sleep_minutes': null}), isNull);
    });

    test('ignores an efficiency that the times contradict', () {
      final e = estimateSleepScore({
        'deep_sleep_minutes': 60, 'light_sleep_minutes': 240, 'rem_sleep_minutes': 120,
        'sleep_start_time': '2026-07-07T05:00:00Z', 'sleep_end_time': '2026-07-07T06:00:00Z',
      })!;
      expect(e['efficiency'], isNull);
    });
  });

  group('readiness for a Health Connect-only athlete', () {
    test('scores with an estimated sleep score and says so', () {
      final r = readinessToday(_healthConnectSeries());
      expect(r['score'], isNotNull);
      expect(r['baseline_status'], 'full');
      expect(_sleep(r)['estimated'], isTrue);
      expect(r['flags'], contains('sleep_estimated'));
      expect(r['components'], containsPair('body_battery', containsPair('available', false)));
    });

    test('an estimated night lowers confidence one step', () {
      // HRV + resting HR + sleep is enough data for "high", but not with an
      // estimated sleep score.
      final r = readinessToday(_healthConnectSeries());
      expect(r['data_completeness'], greaterThanOrEqualTo(0.70));
      expect(r['confidence'], 'medium');
    });

    test('names the estimate when sleep drives the briefing', () {
      final rows = _healthConnectSeries(deep: 30, light: 150, rem: 40, awake: 60, extraInBed: 30);
      final r = readinessToday(rows);
      expect(r['drivers'], containsPair('limiter', 'sleep_score'));
      expect(r['briefing'], contains('estimated sleep score'));
    });

    test('without HRV it scores from resting HR and sleep, at lower confidence', () {
      final r = readinessToday(_healthConnectSeries(withHrv: false));
      expect(r['score'], isNotNull);
      expect((r['components'] as Json)['hrv'], containsPair('available', false));
      expect(r['confidence'], isIn(['low', 'medium']));
      expect(r['confidence'], isNot('high'));
    });

    test('a short night still trips the short-sleep guard', () {
      final rows = _healthConnectSeries(deep: 40, light: 160, rem: 60);
      final r = readinessToday(rows);
      expect(((r['components'] as Json)['sleep_duration'] as Json)['guard_applied'], isTrue);
      expect(_sleep(r)['sub'] as num, lessThanOrEqualTo(0.5));
    });

    test('a Garmin-scored night is never estimated', () {
      final rows = _healthConnectSeries()..first['sleep_score'] = 81;
      final r = readinessToday(rows);
      expect(_sleep(r)['value'], 81);
      expect(_sleep(r).containsKey('estimated'), isFalse);
      expect(r['flags'], isNot(contains('sleep_estimated')));
    });
  });
}
