/// Per-session activity records: normalization and cross-source dedup, a
/// port of `backend/activities.py`.
///
/// The same session usually arrives more than once: Garmin uploads to
/// Strava, and the public app also sees it through Health Connect and in
/// export files. Every row is kept so re-imports stay idempotent, and each
/// non-canonical copy points at its group's canonical row through
/// `duplicate_of`. Absent metrics are null, and physiologically impossible
/// zeros (HR 0, power 0, ...) become null.
library;

import 'json.dart';
import 'py.dart';

/// Same session if same sport family, starts within this window, and
/// durations differ by less than [dedupDurationTolerance] (relative).
const dedupStartWindow = Duration(minutes: 5);
const dedupDurationTolerance = 0.10;

/// Lower rank wins when choosing the canonical row of a duplicate group.
///
/// Garmin's own records come first because they carry Garmin's training
/// load, then the device's activity files, then Health Connect's summaries,
/// then Strava's copies. `garmin` and `strava` keep the order they have in
/// the Python engine. Unknown sources rank last.
const sourcePriority = {
  'garmin': 0,
  'garmin_export': 1,
  'fit_file': 2,
  'health_connect': 3,
  'strava': 4,
  'strava_export': 5,
};

/// The activity columns and their SQLite types, as `db.ACTIVITY_FIELDS`.
const activityColumns = {
  'id': 'TEXT PRIMARY KEY', // "<source>:<source_id>"
  'source': 'TEXT NOT NULL',
  'source_id': 'TEXT NOT NULL',
  'start_time_utc': 'TEXT NOT NULL', // "YYYY-MM-DDTHH:MM:SSZ"
  'local_date': 'TEXT NOT NULL', // YYYY-MM-DD in the athlete's time zone
  'sport_type': 'TEXT', // the source's own name (e.g. TrailRun)
  'sport_family': 'TEXT', // shared family (run/ride/swim/...)
  'name': 'TEXT',
  'duration_s': 'REAL', // elapsed time
  'moving_time_s': 'REAL',
  'distance_m': 'REAL',
  'elevation_gain_m': 'REAL',
  'avg_hr': 'REAL',
  'max_hr': 'REAL',
  'avg_power': 'REAL',
  'calories': 'REAL',
  'suffer_score': 'REAL', // Strava Relative Effort
  'training_load': 'REAL', // Garmin activity training load
  'duplicate_of': 'TEXT REFERENCES activities(id) ON DELETE SET NULL',
};

/// The activity columns, in order.
final List<String> activityFields = activityColumns.keys.toList();

/// Columns stored as SQLite REAL: a number written there reads back as a
/// float, even when it was an int.
final Set<String> realActivityFields = {
  for (final MapEntry(:key, :value) in activityColumns.entries)
    if (value == 'REAL') key,
};

const zeroIsMissing = {
  'avg_hr', 'max_hr', 'avg_power', 'calories',
  'suffer_score', 'training_load', 'duration_s', 'moving_time_s',
};

// Ordered keyword -> family rules; first match wins. Keys are matched
// against the type lowercased with non-letters stripped, so Strava
// "TrailRun" and Garmin "trail_running" both become "trailrun..." and map to
// "run".
const _familyRules = [
  ('run', 'run'),
  ('swim', 'swim'),
  ('ride', 'ride'),
  ('cycl', 'ride'),
  ('bik', 'ride'),
  ('walk', 'walk'),
  ('hik', 'hike'),
  ('weight', 'strength'),
  ('strength', 'strength'),
  ('yoga', 'yoga'),
  ('row', 'row'),
  ('ski', 'ski'),
];

final _nonLetters = RegExp('[^a-z]');
final _utcIso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$');

/// Collapse source-specific sport names into a shared family.
String sportFamily(String? sportType) {
  final key = (sportType ?? '').toLowerCase().replaceAll(_nonLetters, '');
  for (final (needle, family) in _familyRules) {
    if (key.contains(needle)) return family;
  }
  return key.isEmpty ? 'other' : key;
}

/// Parses the canonical start-time encoding, `YYYY-MM-DDTHH:MM:SSZ`.
DateTime parseUtcIso(String value) {
  final m = _utcIso.firstMatch(value);
  if (m == null) throw FormatException('not YYYY-MM-DDTHH:MM:SSZ', value);
  return DateTime.utc(
    int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!),
    int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!),
  );
}

/// Apply the missing-data policy and derive id/family for one activity.
/// Throws [ArgumentError] when the identity or start time is missing.
Json normalizeActivity(Json raw) {
  final record = <String, Object?>{for (final f in activityFields) f: raw[f]};
  final source = record['source'];
  final sourceId = record['source_id'];
  if (source == null || source == '' || sourceId == null || sourceId == '') {
    throw ArgumentError("activity requires 'source' and 'source_id'");
  }
  final start = record['start_time_utc'];
  final localDate = record['local_date'];
  if (start == null || start == '' || localDate == null || localDate == '') {
    throw ArgumentError("activity requires 'start_time_utc' and 'local_date'");
  }

  record['source_id'] = pyStr(sourceId);
  record['id'] = '$source:${record['source_id']}';
  record['sport_family'] = sportFamily(record['sport_type'] as String?);
  for (final field in zeroIsMissing) {
    if (record[field] == 0) record[field] = null;
  }
  if (record['name'] == '') record['name'] = null;
  // duplicate_of is owned by findDuplicates(), never by the source.
  record['duplicate_of'] = null;
  return record;
}

/// [record] as the activities table reads it back: numbers in REAL columns
/// become floats.
Json storedActivity(Json record) => {
      for (final MapEntry(:key, :value) in record.entries)
        key: realActivityFields.contains(key) && value is num ? value.toDouble() : value,
    };

/// Sport and duration check for two activities already known to start
/// within [dedupStartWindow] of each other.
bool _sameSession(Json a, Json b) {
  if (a['source'] == b['source'] || a['sport_family'] != b['sport_family']) return false;
  final da = a['duration_s'] as num?;
  final db = b['duration_s'] as num?;
  // Without durations the start-time + sport match is the only signal.
  if (da == null || db == null) return true;
  final longer = db > da ? db : da;
  return (da - db).abs() / longer < dedupDurationTolerance;
}

/// Map each non-canonical activity id to its group's canonical id.
///
/// Candidate pairs are cross-source only: two sessions from the same source
/// starting minutes apart (e.g. a warm-up recorded separately) are distinct.
/// Pairs are merged closest-start first, and a group never takes a second
/// activity from a source it already has, so one Strava upload can't bridge
/// two separate Garmin sessions into one group.
Map<String, String> findDuplicates(List<Json> records) {
  // Python's sorted() is stable; Dart's sort isn't, so ties keep input order
  // through the index.
  final indexed = [for (var i = 0; i < records.length; i++) (i, records[i])]
    ..sort((a, b) {
      final byStart = (a.$2['start_time_utc'] as String).compareTo(b.$2['start_time_utc'] as String);
      return byStart != 0 ? byStart : a.$1.compareTo(b.$1);
    });
  final ordered = [for (final (_, r) in indexed) r];
  final starts = [for (final r in ordered) parseUtcIso(r['start_time_utc'] as String)];

  final candidates = <(Duration, int, int)>[];
  for (var i = 0; i < ordered.length; i++) {
    for (var j = i + 1; j < ordered.length; j++) {
      final gap = starts[j].difference(starts[i]);
      if (gap > dedupStartWindow) break;
      if (_sameSession(ordered[i], ordered[j])) candidates.add((gap, i, j));
    }
  }
  candidates.sort((a, b) {
    final byGap = a.$1.compareTo(b.$1);
    if (byGap != 0) return byGap;
    final byI = a.$2.compareTo(b.$2);
    return byI != 0 ? byI : a.$3.compareTo(b.$3);
  });

  final groupOf = [for (var g = 0; g < ordered.length; g++) g];
  final members = {for (final g in groupOf) g: [g]};
  final sources = {for (final g in groupOf) g: {ordered[g]['source']}};
  for (final (_, i, j) in candidates) {
    final gi = groupOf[i];
    final gj = groupOf[j];
    if (gi == gj || sources[gi]!.intersection(sources[gj]!).isNotEmpty) continue;
    for (final k in members[gj]!) {
      groupOf[k] = gi;
    }
    members[gi]!.addAll(members.remove(gj)!);
    sources[gi]!.addAll(sources.remove(gj)!);
  }

  final links = <String, String>{};
  for (final indices in members.values) {
    if (indices.length < 2) continue;
    final group = [for (final k in indices) ordered[k]];
    var canonical = group.first;
    for (final r in group.skip(1)) {
      if (_rankBefore(r, canonical)) canonical = r;
    }
    for (final r in group) {
      if (r['id'] != canonical['id']) links[r['id'] as String] = canonical['id'] as String;
    }
  }
  return links;
}

/// Whether [a] sorts before [b] by (source priority, id).
bool _rankBefore(Json a, Json b) {
  final pa = sourcePriority[a['source']] ?? 99;
  final pb = sourcePriority[b['source']] ?? 99;
  if (pa != pb) return pa < pb;
  return (a['id'] as String).compareTo(b['id'] as String) < 0;
}

/// Copies of [records] with `duplicate_of` recomputed across all of them,
/// as `activities.ingest()` leaves the table.
List<Json> linkDuplicates(List<Json> records) {
  final links = findDuplicates(records);
  return [
    for (final r in records) {...r, 'duplicate_of': links[r['id']]},
  ];
}
