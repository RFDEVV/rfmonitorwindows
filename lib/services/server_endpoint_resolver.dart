import '../models/server_config.dart';
import 'api_service.dart';

class ServerEndpointResolver {
  const ServerEndpointResolver._();

  static Future<ServerConfig?> selectReachable(ServerConfig config) async {
    final endpoints = <String>{
      config.localBaseUrl.trim(),
      config.tailscaleBaseUrl.trim(),
      config.baseUrl.trim(),
    }..removeWhere((endpoint) => endpoint.isEmpty);

    for (final endpoint in endpoints) {
      final candidate = config.copyWith(baseUrl: endpoint);
      if (await ApiService(candidate).ping(
        timeout: const Duration(milliseconds: 1400),
      )) {
        return candidate;
      }
    }
    return null;
  }
}
