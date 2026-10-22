import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/server_config.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Dilempar ApiService.execCommand() ketika server minta kode verifikasi
/// 2FA (kode 6-digit yang cuma muncul di console/log server, bukan API).
class ExecVerificationException implements Exception {
  final String message;
  ExecVerificationException(this.message);
  @override
  String toString() => message;
}

/// Wraps every REST call to the server-agent.
/// Handles the API-key -> JWT login exchange and attaches bearer token.
class ApiService {
  final ServerConfig config;
  String? _token;

  ApiService(this.config);

  Uri _u(String path) => Uri.parse('${config.baseUrl}$path');

  /// Getter publik untuk WebSocket / service lain yang butuh token aktif.
  /// Otomatis menjalankan login jika token masih kosong.
  Future<String> get token async {
    if (_token == null) await login();
    return _token!;
  }

  Future<void> login({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final res = await http.post(_u('/auth/login'), headers: {
      'x-api-key': config.apiKey
    }).timeout(timeout);
    if (res.statusCode != 200) {
      throw ApiException('Login failed (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    _token = body['token'] as String?;
    if (_token == null) throw ApiException('Login: token kosong dari server');
  }

  Map<String, String> get _authHeaders => {
        'Authorization': "Bearer ${_token ?? ''}",
        'Content-Type': 'application/json',
      };

  Future<Map<String, dynamic>> _get(
    String path, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    await token; // Menggunakan getter public token untuk memastikan autentikasi
    var res = await http.get(_u(path), headers: _authHeaders).timeout(timeout);
    if (res.statusCode == 401) {
      // Token expired → refresh sekali dan retry
      await login();
      res = await http.get(_u(path), headers: _authHeaders).timeout(timeout);
    }
    return _decode(res);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await token; // Menggunakan getter public token untuk memastikan autentikasi
    var res = await http
        .post(_u(path), headers: _authHeaders, body: jsonEncode(body))
        .timeout(timeout);
    if (res.statusCode == 401) {
      await login();
      res = await http
          .post(_u(path), headers: _authHeaders, body: jsonEncode(body))
          .timeout(timeout);
    }
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    late Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Server response bukan JSON (HTTP ${res.statusCode})');
    }
    if (res.statusCode >= 400 || body['ok'] == false) {
      throw ApiException(
          body['error']?.toString() ?? 'Request failed (${res.statusCode})');
    }
    return body;
  }

  // ── Metrics / health ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getMetrics() => _get('/metrics');

  /// Ping ringan — pakai /ping (no auth) untuk cek reachability,
  /// fallback ke /system/uptime jika server lama.
  Future<bool> ping({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      // Coba /ping dulu (no auth, cepat)
      final res = await http.get(_u('/ping')).timeout(timeout);
      if (res.statusCode == 200) return true;
      // Fallback ke authenticated endpoint
      await login(timeout: timeout);
      await _get('/system/uptime', timeout: timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Power / listrik ─────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getPowerEstimate(double cpuUsagePercent) =>
      _post('/power/estimate', {
        'cpuUsagePercent': cpuUsagePercent,
        'idleWatt': config.idleWatt,
        'maxExtraWatt': config.maxExtraWatt,
        'tariffPerKwh': config.tariffPerKwh,
        'monthlyInternetCost': config.monthlyInternetCostRp,
      });

  Future<Map<String, dynamic>> getPowerSummary() => _get(
        '/power/summary?tariffPerKwh=${config.tariffPerKwh}&monthlyInternetCost=${config.monthlyInternetCostRp}',
      );

  // ── Network ─────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getNetworkSummary() => _get('/network/summary');

  /// Data vnstat mentah untuk tampilkan tabel per periode
  Future<Map<String, dynamic>> getNetworkVnstat({String period = 'd'}) =>
      _get('/network/vnstat?period=$period');

  // ── PM2 ─────────────────────────────────────────────────────────────────────
  Future<List<dynamic>> getPm2List({
    Duration timeout = const Duration(seconds: 12),
  }) async =>
      (await _get('/pm2/list', timeout: timeout))['data'] as List;

  Future<void> pm2Action(String name, String action) =>
      _post('/pm2/action', {'name': name, 'action': action});

  Future<Map<String, dynamic>> getPm2Logs(String name, {int lines = 150}) =>
      _get('/pm2/logs?name=${Uri.encodeQueryComponent(name)}&lines=$lines');

  Future<Map<String, dynamic>> getLogs({int lines = 200}) =>
      _get('/logs?lines=$lines');

  /// Hapus log yang tersimpan di server (buffer di-reset).
  Future<void> clearLogs() async {
    await token;
    var res = await http
        .delete(_u('/logs'), headers: _authHeaders)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 401) {
      await login();
      res = await http
          .delete(_u('/logs'), headers: _authHeaders)
          .timeout(const Duration(seconds: 10));
    }
    _decode(res);
  }

  /// Jalankan command shell bebas di server. Butuh verifikasi 2FA (kode
  /// 6-digit yang muncul di console/log server) untuk request pertama —
  /// selanjutnya sesi valid 10 menit tanpa perlu kode lagi.
  ///
  /// Kalau server balas needsVerification=true, lempar [ExecVerificationException]
  /// supaya UI bisa munculkan dialog input kode.
  Future<Map<String, dynamic>> execCommand(String cmd,
      {String? verifyCode}) async {
    await token;
    final body = jsonEncode(
        {'cmd': cmd, if (verifyCode != null) 'verifyCode': verifyCode});
    var res = await http
        .post(_u('/system/exec'), headers: _authHeaders, body: body)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 401) {
      Map<String, dynamic> decoded = {};
      try {
        decoded = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      if (decoded['needsVerification'] == true) {
        throw ExecVerificationException(
            decoded['error']?.toString() ?? 'Perlu kode verifikasi');
      }
      // Bisa juga 401 karena JWT expired biasa → refresh & retry sekali
      await login();
      res = await http
          .post(_u('/system/exec'), headers: _authHeaders, body: body)
          .timeout(const Duration(seconds: 30));
    }
    return _decode(res);
  }

  // ── Unified Services ─────────────────────────────────────────────────────────
  Future<List<dynamic>> getServicesList({
    Duration timeout = const Duration(seconds: 12),
  }) async =>
      (await _get('/services/list', timeout: timeout))['data'] as List;

  Future<void> serviceAction(String type, String name, String action) =>
      _post('/services/action', {'type': type, 'name': name, 'action': action});

  Future<Map<String, dynamic>> getServiceLogs(String type, String name,
          {int lines = 150}) =>
      _get('/services/logs?type=$type&name=$name&lines=$lines');

  // ── Command Presets ──────────────────────────────────────────────────────────
  Future<List<dynamic>> getPresets() async =>
      (await _get('/presets/list'))['data'] as List;

  Future<String> runPreset(String name) async =>
      ((await _post('/presets/run', {'name': name}))['data']
          as Map<String, dynamic>)['output'] as String? ??
      '';

  // ── Hardware Spec ────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getSpec() async =>
      (await _get('/system/spec'))['data'] as Map<String, dynamic>;

  // ── System power / uptime ────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getUptime() => _get('/system/uptime');

  Future<void> systemPower(String action, String confirmPhrase) =>
      _post('/system/$action', {'confirmPhrase': confirmPhrase});

  // ── Speedtest — 100% di SERVER (bukan HP) ────────────────────────────────────
  /// Ping, download, upload semuanya diukur server ↔ Cloudflare. Request ini
  /// tidak mengirim data apa pun dari HP (tidak memakai kuota). Progress
  /// realtime datang lewat WebSocket (event 'speedtest_progress').
  Future<Map<String, dynamic>> runSpeedtest() =>
      _post('/speedtest/run', {}, timeout: const Duration(seconds: 120));

  // ── Log inkremental: hanya baris BARU sejak cursor (hemat kuota) ─────────────
  Future<LogChunk> streamLogs(String type, String name,
      {String? cursor, int lines = 200}) async {
    final q = StringBuffer('type=${Uri.encodeQueryComponent(type)}')
      ..write('&name=${Uri.encodeQueryComponent(name)}')
      ..write('&lines=$lines');
    if (cursor != null && cursor.isNotEmpty)
      q.write('&cursor=${Uri.encodeQueryComponent(cursor)}');
    final res =
        await _get('/logs/stream?$q', timeout: const Duration(seconds: 15));
    final d = (res['data'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return LogChunk(
      lines:
          ((d['lines'] as List?) ?? const []).map((e) => e.toString()).toList(),
      cursor: d['cursor']?.toString(),
      reset: d['reset'] == true,
    );
  }

  /// Hapus log di SERVER (PM2: file dikosongkan; docker/systemd: batas waktu).
  Future<void> clearLogsFor(String type, String name) async {
    await token;
    final path =
        '/logs/stream?type=${Uri.encodeQueryComponent(type)}&name=${Uri.encodeQueryComponent(name)}';
    var res = await http
        .delete(_u(path), headers: _authHeaders)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 401) {
      await login();
      res = await http
          .delete(_u(path), headers: _authHeaders)
          .timeout(const Duration(seconds: 10));
    }
    _decode(res);
  }

  // ── Dashboard: riwayat 6 menit, proses terberat ──────────────────────────────
  Future<Map<String, dynamic>> getMetricsHistory({int minutes = 6}) async =>
      ((await _get('/metrics/history?minutes=$minutes'))['data'] as Map)
          .cast<String, dynamic>();

  Future<Map<String, dynamic>> getTop() async =>
      ((await _get('/system/top'))['data'] as Map).cast<String, dynamic>();

  Future<void> refreshTopDirs() => _post('/system/top/refresh', {});
}

/// Potongan log dari server: baris baru + cursor untuk polling berikutnya.
/// `reset` = true → ganti seluruh isi tampilan (pertama kali / log dihapus / di-rotate).
class LogChunk {
  final List<String> lines;
  final String? cursor;
  final bool reset;
  const LogChunk(
      {required this.lines, required this.cursor, required this.reset});
}
