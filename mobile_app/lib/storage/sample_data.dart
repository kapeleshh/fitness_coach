import 'package:coach_engine/coach_engine.dart';
import 'package:coach_store/coach_store.dart';

/// Whether this build fills an empty store with [sampleData], from
/// `--dart-define=SAMPLE_DATA=true`. For trying the app on an emulator; off
/// in every other build.
const sampleDataEnabled = bool.fromEnvironment('SAMPLE_DATA');

/// 60 days of synthetic wellness ending [today], and a session every other
/// day. Deterministic, and never anyone's real data.
(List<Json> days, List<Json> sessions) sampleData({CivilDate? today}) {
  final now = DateTime.now();
  final end = today ?? CivilDate(now.year, now.month, now.day);
  const sports = ['running', 'road_biking', 'lap_swimming'];
  final days = <Json>[];
  final sessions = <Json>[];
  for (var i = 0; i < 60; i++) {
    final date = end.addDays(-i);
    days.add({
      'date': date.toString(),
      'hrv': 50.0 + ((i * 7) % 11) - 5,
      'hrv_status': 'BALANCED',
      'resting_hr': 50 + i % 3,
      'sleep_score': 70 + (i * 5) % 20,
      'deep_sleep_minutes': 70 + i % 20,
      'light_sleep_minutes': 240 + (i * 3) % 40,
      'rem_sleep_minutes': 90 + i % 15,
      'awake_minutes': 15 + i % 10,
      'body_battery_start': 60 + (i * 3) % 30,
      'body_battery_end': 25 + i % 10,
      'avg_stress': 25 + (i * 7) % 25,
      'steps': 6000 + (i * 733) % 7000,
      'total_calories': 2300 + (i * 37) % 400,
    });
    if (i.isEven) {
      sessions.add({
        'source': 'sample',
        'source_id': 7000 + i,
        'start_time_utc': '${date}T07:00:00Z',
        'local_date': date.toString(),
        'sport_type': sports[(i ~/ 2) % sports.length],
        'duration_s': 2400 + (i * 97) % 2400,
        'avg_hr': 130 + i % 25,
        'max_hr': 170 + i % 15,
      });
    }
  }
  return (days, sessions);
}

/// Writes [sampleData] into [store] when it holds no days yet.
void seedSampleDataIfEmpty(CoachStore store) {
  if (store.countDays() > 0) return;
  final (days, sessions) = sampleData();
  store
    ..upsertDays(days, origin: 'sample')
    ..ingestActivities(sessions);
}
