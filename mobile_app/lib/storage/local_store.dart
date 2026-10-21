import 'dart:io';

import 'package:coach_store/coach_store.dart';
import 'package:path_provider/path_provider.dart';

import 'store_key.dart';

/// The database file name inside the app's private storage.
const localStoreFileName = 'maru.db';

/// Opens the encrypted on-device database in the app's private storage,
/// creating it and its key on first run.
///
/// When the key is new but a database file already exists (the keystore was
/// cleared, e.g. by a restore onto another phone), that file can never be
/// read again. It is deleted and a fresh database starts in its place; its
/// contents come back by importing from Health Connect and the export files.
Future<CoachStore> openLocalStore({StoreKeyProvider? keys, Directory? directory}) async {
  final dir = directory ?? await getApplicationSupportDirectory();
  final path = '${dir.path}/$localStoreFileName';
  final (key, created) = await (keys ?? StoreKeyProvider()).readOrCreate();
  if (created) {
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (file.existsSync()) file.deleteSync();
    }
  }
  return CoachStore.open(path, key: key);
}
