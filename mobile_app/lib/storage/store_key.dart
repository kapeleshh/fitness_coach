import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The key that unlocks the on-device database: 32 random bytes as hex,
/// created on first run and kept in the platform keystore (the Android
/// Keystore, through flutter_secure_storage). It never leaves the device,
/// and without it the database file can't be read.
class StoreKeyProvider {
  StoreKeyProvider({FlutterSecureStorage? storage, Random? random})
      : _storage = storage ?? const FlutterSecureStorage(),
        _random = random ?? Random.secure();

  static const keyName = 'maru_store_key_v1';
  static final _valid = RegExp(r'^[0-9a-f]{64}$');

  final FlutterSecureStorage _storage;
  final Random _random;

  /// The stored key, or a new one when there is none yet. `created` is true
  /// for a new key. A stored value that isn't a key throws rather than being
  /// replaced, since replacing it would lock the user out of their data.
  Future<(String key, bool created)> readOrCreate() async {
    final existing = await _storage.read(key: keyName);
    if (existing != null) {
      if (!_valid.hasMatch(existing)) {
        throw StateError('The stored database key is not a valid key');
      }
      return (existing, false);
    }
    final key = [
      for (var i = 0; i < 32; i++) _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    await _storage.write(key: keyName, value: key);
    return (key, true);
  }
}
