/// The daily wellness columns and their SQLite types, in the order of
/// `db.DAILY_FIELDS` in the backend.
library;

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
