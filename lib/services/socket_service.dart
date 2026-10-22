import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/server_config.dart';
import 'api_service.dart';

enum SocketConnState { connecting, connected, disconnected, reconnecting }

class SocketService {
  final ServerConfig config;
  final ApiService   api;

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;       // ping tiap 5 detik
  Timer? _metricsWatchdog;      // jika 15 detik tidak ada metrics → disconnected
  int    _retryCount   = 0;
  bool   _manuallyClosed = false;
  DateTime? _lastMetricsAt;

  // Streams
  final _stateCtrl   = StreamController<SocketConnState>.broadcast();
  final _metricsCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _eventCtrl   = StreamController<Map<String, dynamic>>.broadcast();

  Stream<SocketConnState>      get stateStream   => _stateCtrl.stream;
  Stream<Map<String, dynamic>> get metricsStream  => _metricsCtrl.stream;
  Stream<Map<String, dynamic>> get eventStream    => _eventCtrl.stream;
  DateTime?                    get lastMetricsAt  => _lastMetricsAt;

  SocketService(this.config, this.api);

  Future<void> connect() async {
    if (_manuallyClosed) return;
    _stateCtrl.add(SocketConnState.connecting);

    try {
      final token = await api.token.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Login timeout'),
      );
      final uri = Uri.parse('${config.wsUrl}/ws?token=$token');
      _channel  = WebSocketChannel.connect(uri);

      // PENTING: tunggu koneksi BENAR-BENAR terbuka sebelum menganggap
      // "connected". WebSocketChannel.connect() langsung return tanpa
      // menunggu handshake — kalau langsung anggap connected di sini,
      // setiap percobaan reconnect yang gagal akan memicu pasangan
      // connected→disconnected palsu berturut-turut, dan itu bikin
      // notifikasi "server terputus" muncul berkali-kali padahal
      // seharusnya cukup 1x sampai benar-benar reconnect.
      await _channel!.ready;

      // Watchdog: jika 15 detik tidak ada pesan → anggap disconnect
      _startMetricsWatchdog();

      _channel!.stream.listen(
        (raw) {
          _lastMetricsAt = DateTime.now();
          _resetWatchdog();

          try {
            final envelope = jsonDecode(raw as String);
            if (envelope is! Map) return;

            final type = envelope['type'] as String?;
            final data = envelope['data'];

            if (type == 'event' && data is Map<String, dynamic>) {
              _eventCtrl.add(data);
            } else if (data is Map<String, dynamic>) {
              _metricsCtrl.add(data);
            }
          } catch (_) { /* ignore malformed frame */ }
        },
        onDone:  () => _onDisconnected(),
        onError: (_) => _onDisconnected(),
        cancelOnError: true,
      );

      // Handshake sukses (channel.ready sudah tidak error) → baru sekarang connected.
      _onConnected();
    } catch (_) {
      _onDisconnected();
    }
  }

  void _onConnected() {
    _retryCount = 0;
    if (!_stateCtrl.isClosed) _stateCtrl.add(SocketConnState.connected);
  }

  void _onDisconnected() {
    _heartbeatTimer?.cancel();
    _metricsWatchdog?.cancel();
    if (_manuallyClosed) return;
    if (!_stateCtrl.isClosed) _stateCtrl.add(SocketConnState.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manuallyClosed) return;
    if (!_stateCtrl.isClosed) _stateCtrl.add(SocketConnState.reconnecting);
    _retryCount++;
    // Backoff: 1s, 3s, 5s, 10s, 20s, 30s, 30s…
    final delaySec = [1, 3, 5, 10, 20, 30, 30][_retryCount.clamp(0, 6)];
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySec), connect);
  }

  /// Watchdog: jika 15 detik tidak ada frame metrics → trigger disconnect
  void _startMetricsWatchdog() {
    _metricsWatchdog?.cancel();
    _metricsWatchdog = Timer(const Duration(seconds: 15), () {
      if (!_manuallyClosed) _onDisconnected();
    });
  }

  void _resetWatchdog() {
    _startMetricsWatchdog();
  }

  /// Manual reconnect dari UI (tombol reconnect di dashboard)
  void reconnect() {
    _manuallyClosed = false;
    _retryCount     = 0;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    connect();
  }

  void disconnect() {
    _manuallyClosed = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _metricsWatchdog?.cancel();
    _channel?.sink.close();
    if (!_stateCtrl.isClosed) _stateCtrl.add(SocketConnState.disconnected);
  }

  void dispose() {
    disconnect();
    _stateCtrl.close();
    _metricsCtrl.close();
    _eventCtrl.close();
  }
}
