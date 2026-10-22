import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Profil SSH terakhir. Rahasia hanya disimpan di secure storage
/// (Android Keystore/iOS Keychain), tidak di storage biasa aplikasi.
class SshProfile {
  final String host;
  final int port;
  final String username;
  final String password;
  final String privateKey;
  final String passphrase;
  final double terminalFontSize;

  const SshProfile({
    required this.host,
    this.port = 22,
    this.username = '',
    this.password = '',
    this.privateKey = '',
    this.passphrase = '',
    this.terminalFontSize = 8,
  });

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'privateKey': privateKey,
        'passphrase': passphrase,
        'terminalFontSize': terminalFontSize,
      };

  factory SshProfile.fromJson(Map<String, dynamic> j) => SshProfile(
        host: (j['host'] ?? '').toString(),
        port: (j['port'] as num?)?.toInt() ?? 22,
        username: (j['username'] ?? '').toString(),
        password: (j['password'] ?? '').toString(),
        privateKey: (j['privateKey'] ?? '').toString(),
        passphrase: (j['passphrase'] ?? '').toString(),
        terminalFontSize: (j['terminalFontSize'] as num?)?.toDouble() ?? 8,
      );
}

class SshStore {
  static const _s = FlutterSecureStorage();
  static const _profileKey = 'rfmonitor_ssh_profile';
  static const _hostsKey = 'rfmonitor_ssh_known_hosts';

  Future<SshProfile?> loadProfile() async {
    final raw = await _s.read(key: _profileKey);
    if (raw == null) return null;
    return SshProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveProfile(SshProfile p, {required bool saveSecrets}) async {
    final safe = SshProfile(
      host: p.host,
      port: p.port,
      username: p.username,
      password: saveSecrets ? p.password : '',
      privateKey: saveSecrets ? p.privateKey : '',
      passphrase: saveSecrets ? p.passphrase : '',
      terminalFontSize: p.terminalFontSize,
    );
    await _s.write(key: _profileKey, value: jsonEncode(safe.toJson()));
  }

  // ── Known hosts (trust-on-first-use, seperti ~/.ssh/known_hosts) ───────────
  Future<Map<String, dynamic>> _hosts() async {
    final raw = await _s.read(key: _hostsKey);
    return raw == null ? {} : (jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<String?> knownFingerprint(String host, int port) async =>
      (await _hosts())['$host:$port']?.toString();

  Future<void> trustFingerprint(
    String host,
    int port,
    String fingerprint,
  ) async {
    final h = await _hosts();
    h['$host:$port'] = fingerprint;
    await _s.write(key: _hostsKey, value: jsonEncode(h));
  }
}
