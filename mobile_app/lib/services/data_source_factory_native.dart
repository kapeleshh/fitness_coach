import '../storage/local_store.dart';
import '../storage/sample_data.dart';
import 'health_api_service.dart';
import 'local_data_source.dart';

/// `local` (the default) or `api`, from `--dart-define=DATA_SOURCE=...`.
const _dataSource = String.fromEnvironment('DATA_SOURCE', defaultValue: 'local');

HealthDataSource createDataSource() => _dataSource == 'api'
    ? HealthApiService()
    : LocalDataSource(openStore: () async {
        final store = await openLocalStore();
        if (sampleDataEnabled) seedSampleDataIfEmpty(store);
        return store;
      });
