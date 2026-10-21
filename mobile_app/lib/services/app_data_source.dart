import 'health_data_source.dart';
import 'data_source_factory_web.dart' if (dart.library.ffi) 'data_source_factory_native.dart';

export 'health_data_source.dart';

/// Where the app's screens get their data, chosen once at startup.
///
/// On Android it is the on-device store, unless the app was built with
/// `--dart-define=DATA_SOURCE=api` to read the self-hosted backend instead.
/// On the web, which can't open the encrypted database, it is always the
/// backend.
final HealthDataSource dataSource = createDataSource();
