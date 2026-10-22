import 'package:flutter_test/flutter_test.dart';
import 'package:rfmonitor/models/server_config.dart';
import 'package:rfmonitor/services/ssh_store.dart';

void main() {
  group('ServerConfig endpoint addresses', () {
    test('round-trips local and Tailscale URLs', () {
      const config = ServerConfig(
        id: 'home-server',
        name: 'Home server',
        baseUrl: 'https://monitor.example.com',
        localBaseUrl: 'http://192.168.1.20:8080',
        tailscaleBaseUrl: 'http://100.90.80.70:8080',
        apiKey: 'test-key',
      );

      final restored = ServerConfig.fromJson(config.toJson());

      expect(restored.baseUrl, config.baseUrl);
      expect(restored.localBaseUrl, config.localBaseUrl);
      expect(restored.tailscaleBaseUrl, config.tailscaleBaseUrl);
      expect(restored.localHost, '192.168.1.20');
      expect(restored.tailscaleHost, '100.90.80.70');
    });

    test('accepts older profiles without optional endpoint fields', () {
      final config = ServerConfig.fromJson({
        'id': 'legacy',
        'baseUrl': 'https://monitor.example.com',
        'apiKey': 'test-key',
      });

      expect(config.localBaseUrl, isEmpty);
      expect(config.tailscaleBaseUrl, isEmpty);
    });

    test('copyWith keeps the configured failover URLs', () {
      const config = ServerConfig(
        id: 'home-server',
        baseUrl: 'https://monitor.example.com',
        localBaseUrl: 'http://192.168.1.20:8080',
        tailscaleBaseUrl: 'http://100.90.80.70:8080',
        apiKey: 'test-key',
      );

      final active = config.copyWith(baseUrl: config.localBaseUrl);

      expect(active.baseUrl, config.localBaseUrl);
      expect(active.tailscaleBaseUrl, config.tailscaleBaseUrl);
    });
  });

  group('SshProfile credentials', () {
    test('round-trips username, password, and private-key credentials', () {
      const profile = SshProfile(
        host: 'server.example.com',
        port: 2222,
        username: 'admin',
        password: 'test-password',
        privateKey: 'test-private-key',
        passphrase: 'test-passphrase',
        terminalFontSize: 10,
      );

      final restored = SshProfile.fromJson(profile.toJson());

      expect(restored.host, profile.host);
      expect(restored.port, profile.port);
      expect(restored.username, profile.username);
      expect(restored.password, profile.password);
      expect(restored.privateKey, profile.privateKey);
      expect(restored.passphrase, profile.passphrase);
      expect(restored.terminalFontSize, profile.terminalFontSize);
    });
  });
}
