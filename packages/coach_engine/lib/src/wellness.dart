/// Daily wellness records: the columns and the missing-data policy of
/// `backend/db.py`.
///
/// Metric values are nullable. Physiologically impossible zeros (HRV 0,
/// sleep score 0, resting HR 0, ...) mean "not measured" and are stored as
/// null. [legacyFill] restores the old 0-filled shape for the two responses
/// whose contract still expects it.
library;

import 'json.dart';

/// The daily wellness columns and their SQLite types, in the order of
/// `db.DAILY_FIELDS`.
const dailyFields = {
  'date': 'TEXT PRIMARY KEY',
  // Sleep
  'sleep_score': 'INTEGER',
  'deep_sleep_minutes': 'INTEGER',
  'light_sleep_minutes': 'INTEGER',
  'rem_sleep_minutes': 'INTEGER',
  'awake_minutes': 'INTEGER',
  'sleep_start_time': 'NUMERIC',
  'sleep_end_time': 'NUMERIC',
  'avg_sleep_stress': 'REAL',
  'sleep_insight': 'TEXT',
  'sleep_feedback': 'TEXT',
  // Heart rate & HRV
  'resting_hr': 'INTEGER',
  'min_hr': 'INTEGER',
  'max_hr': 'INTEGER',
  'hrv': 'REAL',
  'hrv_status': 'TEXT',
  // Body battery
  'body_battery_start': 'INTEGER',
  'body_battery_end': 'INTEGER',
  'body_battery_high': 'INTEGER',
  'body_battery_low': 'INTEGER',
  'body_battery_charged': 'INTEGER',
  'body_battery_drained': 'INTEGER',
  // Stress
  'avg_stress': 'INTEGER',
  'max_stress': 'INTEGER',
  'stress_rest_minutes': 'INTEGER',
  'stress_low_minutes': 'INTEGER',
  'stress_medium_minutes': 'INTEGER',
  'stress_high_minutes': 'INTEGER',
  // Activity
  'steps': 'INTEGER',
  'distance_meters': 'REAL',
  'active_calories': 'INTEGER',
  'total_calories': 'INTEGER',
  'floors_climbed': 'INTEGER',
  'active_minutes': 'INTEGER',
  // Respiration
  'avg_respiration': 'REAL',
  'lowest_respiration': 'REAL',
  'highest_respiration': 'REAL',
};

/// The numeric (INTEGER or REAL) wellness fields: the metrics any two of
/// which can be correlated.
final Set<String> numericDailyFields = {
  for (final MapEntry(:key, :value) in dailyFields.entries)
    if (value == 'INTEGER' || value == 'REAL') key,
};

final Set<String> _textDailyFields = {
  for (final MapEntry(:key, :value) in dailyFields.entries)
    if (value == 'TEXT' && key != 'date') key,
};

/// A value of exactly 0 in these fields cannot be a real measurement: it
/// means the metric was missing.
const impossibleZeroFields = {
  'sleep_score', 'avg_sleep_stress', 'resting_hr', 'min_hr', 'max_hr', 'hrv',
  'body_battery_start', 'body_battery_end', 'body_battery_high',
  'body_battery_low', 'avg_stress', 'max_stress', 'total_calories',
  'avg_respiration', 'lowest_respiration', 'highest_respiration',
};

/// Sleep-stage minutes can legitimately be 0 within a tracked night, but
/// are meaningless when there was no sleep record at all.
const sleepStageFields = {
  'deep_sleep_minutes', 'light_sleep_minutes', 'rem_sleep_minutes', 'awake_minutes',
};

/// The legacy 0-filled defaults, matching the backend's `DailyHealthData`
/// dataclass.
final Json legacyDefaults = {
  for (final f in numericDailyFields) f: 0,
  'avg_sleep_stress': 0.0,
  'hrv': 0.0,
  'distance_meters': 0.0,
  'avg_respiration': 0.0,
  'lowest_respiration': 0.0,
  'highest_respiration': 0.0,
  'sleep_insight': '',
  'sleep_feedback': '',
  'hrv_status': 'UNKNOWN',
  'sleep_start_time': null,
  'sleep_end_time': null,
};

/// Apply the missing-data policy to one daily record, as
/// `db.normalize_record`: unknown keys are dropped and missing keys become
/// null, impossible zeros become null, empty text becomes null, and an
/// `UNKNOWN` HRV status next to a missing HRV reading becomes null.
///
/// One rule differs, for records without a Garmin sleep score: Python treats
/// zero stage minutes as missing whenever the sleep score is, which is right
/// for Garmin but would erase real zeros from a Health Connect night. Here
/// they are treated as missing only when the night has no sleep start and
/// end time either.
Json normalizeRecord(Json raw) {
  final record = <String, Object?>{
    for (final field in dailyFields.keys)
      field: _textDailyFields.contains(field) && raw[field] == '' ? null : raw[field],
  };
  for (final field in impossibleZeroFields) {
    if (record[field] == 0) record[field] = null;
  }
  if (record['sleep_score'] == null) {
    final hasSession = record['sleep_start_time'] != null && record['sleep_end_time'] != null;
    if (!hasSession) {
      for (final field in sleepStageFields) {
        if (record[field] == 0) record[field] = null;
      }
    }
    if (record['hrv'] == null && record['hrv_status'] == 'UNKNOWN') record['hrv_status'] = null;
  }
  final date = record['date'];
  if (date == null || date == '') throw ArgumentError("daily record requires a 'date'");
  return record;
}

/// The legacy 0-filled shape of a stored record (null -> 0, "" or
/// "UNKNOWN"), as `db._legacy_fill`. Only the wellness columns are kept.
Json legacyFill(Json record) => {
      for (final field in dailyFields.keys)
        field: field == 'date' ? record[field] : (record[field] ?? legacyDefaults[field]),
    };
