import 'dart:io';

import 'package:fitness_coach/storage/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// On a device: the real Android Keystore and the Android build of SQLite3
/// Multiple Ciphers. Run with
///   flutter test integration_test/local_store_test.dart -d <device>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the on-device database is encrypted and reopens with its key', (tester) async {
    final store = await openLocalStore();
    store.upsertDays([
      {'date': '2026-07-07', 'resting_hr': 52, 'steps': 9000},
    ], origin: 'health_connect');
    store.close();

    final reopened = await openLocalStore();
    expect(reopened.day('2026-07-07')!['resting_hr'], 52);
    reopened.close();

    final dir = await getApplicationSupportDirectory();
    final bytes = File('${dir.path}/$localStoreFileName').readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(15)), isNot('SQLite format 3'));
    expect(String.fromCharCodes(bytes), isNot(contains('2026-07-07')));
  });
}
