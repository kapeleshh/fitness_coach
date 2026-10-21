import 'dart:io';

import 'package:coach_store/coach_store.dart';
import 'package:fitness_coach/storage/local_store.dart';
import 'package:fitness_coach/storage/store_key.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('StoreKeyProvider', () {
    test('creates a 32-byte hex key once, then returns the same key', () async {
      final keys = StoreKeyProvider();
      final (first, created) = await keys.readOrCreate();
      expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(created, isTrue);
      final (again, createdAgain) = await keys.readOrCreate();
      expect(again, first);
      expect(createdAgain, isFalse);
    });

    test('refuses to replace a stored value that is not a key', () async {
      FlutterSecureStorage.setMockInitialValues({StoreKeyProvider.keyName: 'not a key'});
      expect(StoreKeyProvider().readOrCreate(), throwsStateError);
    });
  });

  group('openLocalStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('maru_store'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('opens an encrypted store that keeps its data across opens', () async {
      final store = await openLocalStore(directory: dir);
      store.upsertDays([
        {'date': '2026-07-07', 'resting_hr': 52},
      ], origin: 'health_connect');
      store.close();

      final reopened = await openLocalStore(directory: dir);
      addTearDown(reopened.close);
      expect(reopened.day('2026-07-07')!['resting_hr'], 52);
      final header = File('${dir.path}/$localStoreFileName').readAsBytesSync().take(15);
      expect(String.fromCharCodes(header), isNot('SQLite format 3'));
    });

    test('starts fresh when the key was lost and the old file is unreadable', () async {
      (await openLocalStore(directory: dir))
        ..upsertDays([{'date': '2026-07-07', 'steps': 9000}], origin: 'health_connect')
        ..close();
      FlutterSecureStorage.setMockInitialValues({}); // the keystore was cleared

      final store = await openLocalStore(directory: dir);
      addTearDown(store.close);
      expect(store.countDays(), 0);
      expect(store.userVersion, CoachStore.schemaVersion);
    });
  });
}
