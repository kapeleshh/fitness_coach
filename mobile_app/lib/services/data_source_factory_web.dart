import 'health_api_service.dart';

/// The web reads the self-hosted backend: the on-device store needs native
/// SQLite, which the web build doesn't have.
HealthDataSource createDataSource() => HealthApiService();
