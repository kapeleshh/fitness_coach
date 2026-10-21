/// The coach's engines in pure Dart, so the public app computes readiness,
/// training load and insights on the phone.
///
/// Every engine is a port of its Python counterpart in `backend/` and must
/// produce the same output for the same input. The parity tests in `test/`
/// compare against fixtures written by `backend/tests/parity_fixtures.py`;
/// when a result differs, fix the Dart code, never the fixture.
library;

export 'src/activities.dart';
export 'src/api.dart';
export 'src/civil_date.dart';
export 'src/insights.dart';
export 'src/json.dart';
export 'src/readiness.dart';
export 'src/training_load.dart';
export 'src/wellness_fields.dart';
