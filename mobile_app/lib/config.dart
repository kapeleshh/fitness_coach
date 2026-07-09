/// Base URL of the fitness-coach backend API.
///
/// Defaults to the local dev server. Override at build/run time, e.g. to
/// point a phone build at a machine on the LAN:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8081
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8081',
);
