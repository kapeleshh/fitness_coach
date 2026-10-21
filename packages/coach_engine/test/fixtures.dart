import 'dart:convert';
import 'dart:io';

/// Loads a parity fixture written by `backend/tests/parity_fixtures.py`.
///
/// `dart test` runs from the package root, so paths are relative to it.
Object? loadFixture(String name) {
  final file = File('test/fixtures/$name.json');
  if (!file.existsSync()) {
    throw StateError(
      'Missing fixture ${file.path}. Regenerate the fixtures from backend/: '
      'uv run python -m tests.parity_fixtures',
    );
  }
  return jsonDecode(file.readAsStringSync());
}
