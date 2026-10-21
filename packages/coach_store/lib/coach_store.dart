/// The Maru app's on-device database.
///
/// An encrypted SQLite file (SQLite3 Multiple Ciphers, bundled by
/// `package:sqlite3`) with the backend's tables and missing-data rules, so
/// the engines in `coach_engine` read exactly what the Python engines read.
library;

export 'src/store.dart';
