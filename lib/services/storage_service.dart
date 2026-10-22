import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/server_config.dart';

class SecureStorageCorruptedException implements Exception {
  const SecureStorageCorruptedException();

  @override
  String toString() =>
      'Data aman tidak dapat dibuka. Pemulihan perlu menghapus profil tersimpan.';
}

/// Persists server profiles (multi-server support) + which one is active.
/// API keys never touch plain SharedPreferences — secure storage only.
class StorageService {
  static const _storage = FlutterSecureStorage();
  static const _profilesKey = 'rfmonitor_profiles';
  static const _activeKey = 'rfmonitor_active_profile';
  static const _sshProfileKey = 'rfmonitor_ssh_profile';
  static const _sshHostsKey = 'rfmonitor_ssh_known_hosts';

  Future<List<ServerConfig>> loadProfiles() async {
    try {
      final raw = await _storage.read(key: _profilesKey);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List;
      return list.map((e) => ServerConfig.fromJson(e)).toList();
    } on PlatformException catch (error) {
      if (_isCipherFailure(error)) {
        throw const SecureStorageCorruptedException();
      }
      rethrow;
    }
  }

  Future<void> saveProfiles(List<ServerConfig> profiles) async {
    final raw = jsonEncode(profiles.map((p) => p.toJson()).toList());
    await _storage.write(key: _profilesKey, value: raw);
  }

  Future<void> setActiveProfileIndex(int index) async {
    await _storage.write(key: _activeKey, value: index.toString());
  }

  Future<int> getActiveProfileIndex() async {
    try {
      final raw = await _storage.read(key: _activeKey);
      return raw == null ? 0 : int.tryParse(raw) ?? 0;
    } on PlatformException catch (error) {
      if (_isCipherFailure(error)) {
        throw const SecureStorageCorruptedException();
      }
      rethrow;
    }
  }

  Future<void> clearUnreadableProfileData() async {
    await _storage.delete(key: _profilesKey);
    await _storage.delete(key: _activeKey);
    await _storage.delete(key: _sshProfileKey);
    await _storage.delete(key: _sshHostsKey);
  }

  static bool _isCipherFailure(PlatformException error) {
    final details =
        '${error.code} ${error.message} ${error.details}'.toLowerCase();
    return details.contains('badpaddingexception') ||
        details.contains('bad_padding') ||
        details.contains('bad decrypt') ||
        details.contains('invalidkeyexception');
  }
}
