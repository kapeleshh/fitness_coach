import 'dart:convert';

import 'package:coach_engine/coach_engine.dart';
import 'package:sqlite3/sqlite3.dart';

/// The store refused to open or write, with a message to show or log.
class StoreException implements Exception {
  StoreException(this.message);

  final String message;

  @override
  String toString() => 'StoreException: $message';
}

/// Schema migrations, applied in order. The database's `user_version` is
/// the number already applied. Append new steps; never edit a shipped one.
const _migrations = <List<String>>[
  // 1: the backend's tables, plus which source wrote each wellness value,
  //    activity file hashes, and a log of import runs.
  [
    'CREATE TABLE daily_wellness (_WELLNESS_COLUMNS_, origins TEXT, synced_at TEXT)',
    'CREATE TABLE activities (_ACTIVITY_COLUMNS_, file_hash TEXT, synced_at TEXT)',
    'CREATE INDEX idx_activities_local_date ON activities (local_date)',
    'CREATE INDEX idx_activities_file_hash ON activities (file_hash)',
    'CREATE TABLE user_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    'CREATE TABLE import_runs ('
        'id INTEGER PRIMARY KEY, source TEXT NOT NULL, started_at TEXT NOT NULL, '
        'finished_at TEXT, status TEXT NOT NULL, counts TEXT, error TEXT)',
  ],
];

String _columns(Map<String, String> fields) =>
    [for (final MapEntry(:key, :value) in fields.entries) '$key $value'].join(', ');

final _hexKey = RegExp(r'^[0-9a-f]{64}$');

/// The public app's on-device database: an encrypted SQLite file holding
/// daily wellness, activities, settings and import runs.
///
/// It follows `backend/db.py`: the same tables and column types, so values
/// read back exactly as the Python engines saw them (REAL columns return
/// floats), and the same missing-data policy on write. The engines read
/// [allDays], [activities] with duplicates, and [allSettings].
///
/// Wellness writes merge field by field, because several sources feed the
/// same day: a record writes the fields it contains, and a source can clear
/// only values it wrote itself (see [upsertDays]).
class CoachStore {
  CoachStore._(this._db);

  final Database _db;

  /// The schema version this code writes.
  static int get schemaVersion => _migrations.length;

  /// Opens (and creates, if needed) the encrypted database at [path].
  ///
  /// [key] is 64 lowercase hex characters (32 random bytes), created once
  /// per install and kept in the platform keystore. Throws [StoreException]
  /// when the key doesn't open the file, or when the bundled SQLite has no
  /// encryption, which would otherwise write health data in plain text.
  static CoachStore open(String path, {required String key}) {
    if (!_hexKey.hasMatch(key)) {
      throw StoreException('The database key must be 64 lowercase hex characters');
    }
    final db = sqlite3.open(path);
    try {
      if (db.select('PRAGMA cipher').isEmpty) {
        throw StoreException('This SQLite build has no encryption. Set '
            'hooks.user_defines.sqlite3.source to sqlite3mc in the app pubspec.yaml.');
      }
      db.execute("PRAGMA key = '$key'");
      try {
        db.select('SELECT count(*) FROM sqlite_master');
      } on SqliteException {
        throw StoreException('The key does not open this database');
      }
      return CoachStore._(db).._prepare();
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  /// An unencrypted in-memory store, for tests.
  static CoachStore inMemory() => CoachStore._(sqlite3.openInMemory()).._prepare();

  void close() => _db.close();

  /// The schema version of the open database.
  int get userVersion => _db.select('PRAGMA user_version').first.values.first as int;

  void _prepare() {
    _db.execute('PRAGMA journal_mode = WAL');
    _db.execute('PRAGMA foreign_keys = ON');
    final current = userVersion;
    if (current > _migrations.length) {
      throw StoreException('The database is from a newer version of the app '
          '(schema $current, this version knows ${_migrations.length})');
    }
    for (var version = current; version < _migrations.length; version++) {
      _transaction(() {
        for (final statement in _migrations[version]) {
          _db.execute(statement
              .replaceFirst('_WELLNESS_COLUMNS_', _columns(dailyFields))
              .replaceFirst('_ACTIVITY_COLUMNS_', _columns(activityColumns)));
        }
        _db.execute('PRAGMA user_version = ${version + 1}');
      });
    }
  }

  T _transaction<T>(T Function() body) {
    _db.execute('BEGIN');
    try {
      final result = body();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  static String _now() => DateTime.now().toIso8601String().substring(0, 19);

  static Object? _sqlValue(Object? v) => v is bool ? (v ? 1 : 0) : v;

  // ============= DAILY WELLNESS =============

  /// Writes daily records from [origin] (e.g. `health_connect`,
  /// `garmin_export`) in one transaction, after the missing-data policy
  /// ([normalizeRecord]). Returns the number of records written.
  ///
  /// A record writes only the fields it contains. A field it sets to null,
  /// or that the policy turns into null, is cleared only if [origin] wrote
  /// the stored value; another source's value is kept. When two sources
  /// write the same field, the later write wins; preferring one source per
  /// field is WBS 4.6. Writing the same records again changes nothing.
  int upsertDays(List<Json> records, {required String origin}) {
    if (records.isEmpty) return 0;
    final fields = dailyFields.keys.toList();
    final now = _now();
    _transaction(() {
      final find = _db.prepare(
          'SELECT ${fields.join(', ')}, origins FROM daily_wellness WHERE date = ?');
      final insert = _db.prepare('INSERT OR REPLACE INTO daily_wellness '
          '(${fields.join(', ')}, origins, synced_at) '
          'VALUES (${List.filled(fields.length + 2, '?').join(', ')})');
      try {
        for (final raw in records) {
          final record = normalizeRecord(raw);
          final existing = find.select([record['date']]);
          final stored = existing.isEmpty ? const <String, Object?>{} : existing.first;
          final origins = <String, Object?>{
            if (stored['origins'] case final String json) ...jsonDecode(json) as Json,
          };
          final merged = <String, Object?>{'date': record['date']};
          for (final field in fields.skip(1)) {
            final value = record[field];
            if (value != null) {
              merged[field] = value;
              origins[field] = origin;
            } else if (raw.containsKey(field) && origins[field] == origin) {
              merged[field] = null;
              origins.remove(field);
            } else {
              merged[field] = stored[field];
            }
          }
          insert.execute([
            for (final f in fields) _sqlValue(merged[f]),
            jsonEncode(origins),
            now,
          ]);
        }
      } finally {
        find.close();
        insert.close();
      }
    });
    return records.length;
  }

  /// All daily records, newest first, with missing values as null; or in
  /// the legacy 0-filled shape when [legacyZeroFill] is set.
  List<Json> allDays({bool legacyZeroFill = false}) {
    final rows = _db.select(
        'SELECT ${dailyFields.keys.join(', ')} FROM daily_wellness ORDER BY date DESC');
    return [for (final row in rows) legacyZeroFill ? legacyFill(Map.of(row)) : Map.of(row)];
  }

  /// One day's record, or null when there is none.
  Json? day(String date, {bool legacyZeroFill = false}) {
    final rows = _db.select(
        'SELECT ${dailyFields.keys.join(', ')} FROM daily_wellness WHERE date = ?', [date]);
    if (rows.isEmpty) return null;
    final record = Map.of(rows.first);
    return legacyZeroFill ? legacyFill(record) : record;
  }

  /// Which source wrote each stored field of [date]'s record.
  Map<String, String> dayOrigins(String date) {
    final rows = _db.select('SELECT origins FROM daily_wellness WHERE date = ?', [date]);
    final json = rows.isEmpty ? null : rows.first['origins'] as String?;
    return json == null ? {} : (jsonDecode(json) as Map).cast<String, String>();
  }

  int countDays() => _db.select('SELECT COUNT(*) AS n FROM daily_wellness').first['n'] as int;

  // ============= ACTIVITIES =============

  /// Normalizes and writes [records], then recomputes duplicate links across
  /// every source, as `activities.ingest()`. A record may carry a
  /// `file_hash` for the activity file it came from.
  Json ingestActivities(List<Json> records) {
    final fields = activityFields.where((f) => f != 'duplicate_of').toList();
    final updates = [for (final f in fields) if (f != 'id') '$f = excluded.$f'].join(', ');
    final now = _now();
    final links = _transaction(() {
      final upsert = _db.prepare('INSERT INTO activities (${fields.join(', ')}, file_hash, synced_at) '
          'VALUES (${List.filled(fields.length + 2, '?').join(', ')}) '
          'ON CONFLICT(id) DO UPDATE SET $updates, '
          'file_hash = COALESCE(excluded.file_hash, file_hash), synced_at = excluded.synced_at');
      try {
        for (final raw in records) {
          final record = normalizeActivity(raw);
          upsert.execute([for (final f in fields) _sqlValue(record[f]), raw['file_hash'], now]);
        }
      } finally {
        upsert.close();
      }
      final links = findDuplicates(activities(includeDuplicates: true));
      _db.execute('UPDATE activities SET duplicate_of = NULL');
      final link = _db.prepare('UPDATE activities SET duplicate_of = ? WHERE id = ?');
      try {
        for (final MapEntry(key: duplicate, value: canonical) in links.entries) {
          link.execute([canonical, duplicate]);
        }
      } finally {
        link.close();
      }
      return links;
    });
    return {'written': records.length, 'duplicates': links.length};
  }

  /// Activities newest first, optionally limited to `local_date` in
  /// [start]..[end]. Only canonical rows unless [includeDuplicates].
  List<Json> activities({String? start, String? end, bool includeDuplicates = false}) {
    final clauses = <String>[];
    final params = <Object?>[];
    if (start != null) {
      clauses.add('local_date >= ?');
      params.add(start);
    }
    if (end != null) {
      clauses.add('local_date <= ?');
      params.add(end);
    }
    if (!includeDuplicates) clauses.add('duplicate_of IS NULL');
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = _db.select(
        'SELECT ${activityFields.join(', ')} FROM activities $where ORDER BY start_time_utc DESC',
        params);
    return [for (final row in rows) Map.of(row)];
  }

  /// One activity by id (`source:source_id`), or null.
  Json? activity(String id) {
    final rows =
        _db.select('SELECT ${activityFields.join(', ')} FROM activities WHERE id = ?', [id]);
    return rows.isEmpty ? null : Map.of(rows.first);
  }

  /// Whether an activity file with this hash was already imported.
  bool hasActivityFile(String fileHash) =>
      _db.select('SELECT 1 FROM activities WHERE file_hash = ? LIMIT 1', [fileHash]).isNotEmpty;

  // ============= SETTINGS =============

  /// A setting's value (any JSON value), or [fallback] when it isn't set.
  Object? setting(String key, [Object? fallback]) {
    final rows = _db.select('SELECT value FROM user_settings WHERE key = ?', [key]);
    return rows.isEmpty ? fallback : jsonDecode(rows.first['value'] as String);
  }

  void setSetting(String key, Object? value) => _db.execute(
      'INSERT OR REPLACE INTO user_settings (key, value) VALUES (?, ?)', [key, jsonEncode(value)]);

  Json allSettings() => {
        for (final row in _db.select('SELECT key, value FROM user_settings'))
          row['key'] as String: jsonDecode(row['value'] as String),
      };

  // ============= IMPORT RUNS =============

  /// Records the start of an import from [source] and returns its id.
  int startImportRun(String source) {
    _db.execute("INSERT INTO import_runs (source, started_at, status) VALUES (?, ?, 'running')",
        [source, _now()]);
    return _db.lastInsertRowId;
  }

  /// Records how import [id] ended: `completed` with its [counts], or
  /// `failed` with the [error].
  void finishImportRun(int id, {required String status, Json? counts, String? error}) {
    _db.execute(
        'UPDATE import_runs SET finished_at = ?, status = ?, counts = ?, error = ? WHERE id = ?',
        [_now(), status, counts == null ? null : jsonEncode(counts), error, id]);
  }

  /// Import runs, newest first.
  List<Json> importRuns() => [
        for (final row in _db.select('SELECT * FROM import_runs ORDER BY id DESC'))
          {
            ...row,
            'counts': row['counts'] == null ? null : jsonDecode(row['counts'] as String),
          },
      ];
}
