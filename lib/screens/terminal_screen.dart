import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

import '../services/ssh_store.dart';
import '../theme/app_theme.dart';

enum _Phase { form, connecting, connected }

const _macTerminalTheme = TerminalTheme(
  cursor: Color(0xFF28C840),
  selection: Color(0x5528C840),
  foreground: Color(0xFFE5E5E7),
  background: Color(0xFF101114),
  black: Color(0xFF000000),
  red: Color(0xFFFF5F57),
  green: Color(0xFF28C840),
  yellow: Color(0xFFFEBC2E),
  blue: Color(0xFF0A84FF),
  magenta: Color(0xFFBF5AF2),
  cyan: Color(0xFF64D2FF),
  white: Color(0xFFE5E5E7),
  brightBlack: Color(0xFF636366),
  brightRed: Color(0xFFFF6961),
  brightGreen: Color(0xFF30D158),
  brightYellow: Color(0xFFFFD60A),
  brightBlue: Color(0xFF409CFF),
  brightMagenta: Color(0xFFDA8FFF),
  brightCyan: Color(0xFF70D7FF),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFFFFF2B),
  searchHitBackgroundCurrent: Color(0xFF31FF26),
  searchHitForeground: Color(0xFF000000),
);

const _windowsTerminalTheme = TerminalTheme(
  cursor: Color(0xFFCCCCCC),
  selection: Color(0x663A96DD),
  foreground: Color(0xFFCCCCCC),
  background: Color(0xFF0C0C0C),
  black: Color(0xFF0C0C0C),
  red: Color(0xFFC50F1F),
  green: Color(0xFF13A10E),
  yellow: Color(0xFFC19C00),
  blue: Color(0xFF0037DA),
  magenta: Color(0xFF881798),
  cyan: Color(0xFF3A96DD),
  white: Color(0xFFCCCCCC),
  brightBlack: Color(0xFF767676),
  brightRed: Color(0xFFE74856),
  brightGreen: Color(0xFF16C60C),
  brightYellow: Color(0xFFF9F1A5),
  brightBlue: Color(0xFF3B78FF),
  brightMagenta: Color(0xFFB4009E),
  brightCyan: Color(0xFF61D6D6),
  brightWhite: Color(0xFFF2F2F2),
  searchHitBackground: Color(0xFFFFFF2B),
  searchHitBackgroundCurrent: Color(0xFF31FF26),
  searchHitForeground: Color(0xFF000000),
);

/// Terminal SSH ASLI (protokol SSH2, langsung dari HP ke server — bukan lewat
/// agent). Emulator terminal penuh (xterm): vim/nano/htop/top jalan normal.
///  - Tampilan ala Terminal macOS (tombol merah/kuning/hijau)
///  - Cubit 2 jari untuk zoom, tombol A−/A+, fullscreen, putar vertikal/horizontal
///  - Verifikasi kunci host (trust-on-first-use) seperti ssh di komputer
class TerminalScreen extends StatefulWidget {
  final String defaultHost;
  final String localHost;
  final String tailscaleHost;
  final Widget Function(Widget child)? windowDragRegion;

  /// true = dipakai di dalam jendela overlay (tanpa Scaffold, tanpa kontrol
  /// system UI / orientasi — itu diatur oleh overlay).
  final bool embedded;
  final VoidCallback? onClose;
  final VoidCallback? onCloseOverlay;
  const TerminalScreen({
    super.key,
    this.defaultHost = '',
    this.localHost = '',
    this.tailscaleHost = '',
    this.embedded = false,
    this.onClose,
    this.onCloseOverlay,
    this.windowDragRegion,
  });

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  static const _quickCommandsKey = 'terminal_quick_commands_v1';
  static const _defaultQuickCommands = <String, String>{
    'pwd': 'pwd',
    'ls -la': 'ls -la',
    'clear': 'clear',
  };

  final _store = SshStore();
  final _terminal = Terminal(maxLines: 10000);
  final _termController = TerminalController();

  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _key = TextEditingController();
  final _passphrase = TextEditingController();
  bool _saveSecrets = true;
  bool _useKey = false;
  bool _showPass = false;

  _Phase _phase = _Phase.form;
  String? _error;
  String _title = '';

  SSHClient? _client;
  SSHSession? _session;

  // Font TERKECIL supaya banyak kolom muat (ASCII art / tabel / htop tidak terpotong).
  // Cubit hanya memperbesar tampilan (zoom visual) — jumlah kolom/baris TIDAK berubah,
  // jadi server tidak menerima resize dan layout tetap utuh.
  double _fontSize = 8;
  bool _fullscreen = false;
  bool _landscape = false;

  final TransformationController _zoomCtrl = TransformationController();
  bool _zoomed = false;
  Map<String, String> _quickCommands = _defaultQuickCommands;

  @override
  void initState() {
    super.initState();
    _host.text = widget.defaultHost;
    _zoomCtrl.addListener(_onZoomChanged);
    _loadQuickCommands();
    _loadProfile();
  }

  Future<void> _loadQuickCommands() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getString(_quickCommandsKey);
      if (stored == null) return;
      final decoded = jsonDecode(stored);
      if (decoded is! Map) throw const FormatException('Format shortcut salah');
      final commands = <String, String>{};
      for (final entry in decoded.entries) {
        final label = entry.key.toString().trim();
        final command = entry.value.toString();
        if (label.isNotEmpty && command.trim().isNotEmpty) {
          commands[label] = command;
        }
      }
      if (mounted) setState(() => _quickCommands = commands);
    } catch (error) {
      debugPrint('Tidak dapat membaca shortcut terminal tersimpan: $error');
      if (mounted) {
        setState(
            () => _error = 'Gagal membaca tombol perintah tersimpan: $error');
      }
    }
  }

  Future<void> _editQuickCommands() async {
    final controller = TextEditingController(
      text: _quickCommands.entries
          .map((entry) => '${entry.key}|${entry.value}')
          .join('\n'),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF202124),
        title: const Text(
          'Tombol perintah terminal',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
            decoration: const InputDecoration(
              hintText: 'Label|perintah\nmis. logs|pm2 logs --lines 50',
              helperText:
                  'Satu tombol per baris, maksimal 8 tombol. Perintah dimasukkan ke terminal, tidak otomatis dijalankan.',
              helperMaxLines: 3,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;

    final commands = <String, String>{};
    for (final line in result.split('\n')) {
      final separator = line.indexOf('|');
      if (separator <= 0) continue;
      final label = line.substring(0, separator).trim();
      final command = line.substring(separator + 1).trim();
      if (label.isEmpty || command.isEmpty) continue;
      commands[label] = command;
      if (commands.length == 8) break;
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_quickCommandsKey, jsonEncode(commands));
      if (mounted) setState(() => _quickCommands = commands);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Gagal menyimpan tombol perintah: $error');
      }
    }
  }

  void _onZoomChanged() {
    final z = _zoomCtrl.value.getMaxScaleOnAxis() > 1.02;
    if (z != _zoomed && mounted) setState(() => _zoomed = z);
  }

  void _resetZoom() => _zoomCtrl.value = Matrix4.identity();

  void _sendArrow(TerminalKey key, String escapeSequence) {
    if (!_terminal.keyInput(key)) {
      _terminal.textInput(escapeSequence);
    }
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _store.loadProfile();
      if (p == null || !mounted) return;
      setState(() {
        if (p.host.isNotEmpty) _host.text = p.host;
        _port.text = p.port.toString();
        _user.text = p.username;
        _pass.text = p.password;
        _key.text = p.privateKey;
        _passphrase.text = p.passphrase;
        _fontSize = p.terminalFontSize.clamp(6, 14).toDouble();
        _useKey = p.privateKey.isNotEmpty;
        _saveSecrets = true;
      });
      if (widget.embedded &&
          p.host.isNotEmpty &&
          p.username.isNotEmpty &&
          (p.password.isNotEmpty || p.privateKey.isNotEmpty)) {
        await _connect();
      }
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = 'Gagal membaca kredensial SSH tersimpan: $error');
      }
    }
  }

  @override
  void dispose() {
    _session?.close();
    _client?.close();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    _key.dispose();
    _passphrase.dispose();
    _zoomCtrl.dispose();
    if (!widget.embedded && !Platform.isWindows) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    super.dispose();
  }

  // ── Koneksi ────────────────────────────────────────────────────────────────
  Future<bool> _verifyHost(String host, int port, Uint8List fp) async {
    final hex = fp.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
    final known = await _store.knownFingerprint(host, port);
    if (known == hex) return true;
    if (!mounted) return false;
    final changed = known != null;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgBottom,
        title: Text(
          changed ? '⚠️ KUNCI HOST BERUBAH' : 'Percayai server ini?',
          style: TextStyle(
            color: changed ? AppColors.roseRed : AppColors.textPrimary,
          ),
        ),
        content: Text(
          changed
              ? 'Sidik jari kunci SSH $host:$port berbeda dari sebelumnya. Bisa jadi server diinstal ulang — atau ada penyadap (man-in-the-middle).\n\nBaru: $hex'
              : 'Pertama kali terhubung ke $host:$port.\nSidik jari (MD5):\n$hex',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              changed ? 'Tetap lanjut' : 'Percaya',
              style: TextStyle(
                color: changed ? AppColors.roseRed : AppColors.neonGreen,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await _store.trustFingerprint(host, port, hex);
    return ok == true;
  }

  Future<void> _connect() async {
    final requestedHost = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 22;
    final user = _user.text.trim();
    if (requestedHost.isEmpty || user.isEmpty) {
      setState(() => _error = 'Host dan username wajib diisi');
      return;
    }
    if (!_useKey && _pass.text.isEmpty) {
      setState(() => _error = 'Isi password, atau pakai private key');
      return;
    }
    setState(() {
      _phase = _Phase.connecting;
      _error = null;
    });

    var activeHost = requestedHost;
    try {
      final candidates = <String>{
        widget.localHost.trim(),
        widget.tailscaleHost.trim(),
        requestedHost,
      }..removeWhere((candidate) => candidate.isEmpty);
      SSHSocket? socket;
      String? connectedHost;
      Object? lastConnectError;
      for (final candidate in candidates) {
        try {
          socket = await SSHSocket.connect(
            candidate,
            port,
            timeout: const Duration(seconds: 2),
          );
          connectedHost = candidate;
          break;
        } catch (error) {
          lastConnectError = error;
        }
      }
      if (socket == null || connectedHost == null) {
        throw lastConnectError ??
            SocketException('Tidak ada alamat server yang bisa dijangkau');
      }
      final host = connectedHost;
      activeHost = host;
      List<SSHKeyPair>? identities;
      if (_useKey && _key.text.trim().isNotEmpty) {
        identities = SSHKeyPair.fromPem(
          _key.text.trim(),
          _passphrase.text.isEmpty ? null : _passphrase.text,
        );
      }
      final client = SSHClient(
        socket,
        username: user,
        identities: identities,
        onPasswordRequest: () => _pass.text,
        onVerifyHostKey: (type, fingerprint) =>
            _verifyHost(host, port, fingerprint),
      );
      _client = client;
      await client.authenticated.timeout(const Duration(seconds: 12));

      final session = await client
          .shell(
            pty: SSHPtyConfig(
              width: _terminal.viewWidth,
              height: _terminal.viewHeight,
            ),
          )
          .timeout(const Duration(seconds: 10));
      _session = session;

      _terminal.onOutput =
          (data) => session.write(Uint8List.fromList(utf8.encode(data)));
      _terminal.onResize =
          (w, h, pw, ph) => session.resizeTerminal(w, h, pw, ph);

      const dec = Utf8Decoder(allowMalformed: true);
      session.stdout.cast<List<int>>().transform(dec).listen(_terminal.write);
      session.stderr.cast<List<int>>().transform(dec).listen(_terminal.write);
      session.done.then((_) => _onClosed('Sesi SSH berakhir'));

      String? saveWarning;
      try {
        await _store.saveProfile(
          SshProfile(
            host: requestedHost,
            port: port,
            username: user,
            password: _pass.text,
            privateKey: _useKey ? _key.text : '',
            passphrase: _passphrase.text,
            terminalFontSize: _fontSize,
          ),
          saveSecrets: _saveSecrets,
        );
      } catch (error) {
        saveWarning =
            'SSH tersambung, tetapi kredensial gagal disimpan: $error';
      }
      if (!mounted) return;
      setState(() {
        _phase = _Phase.connected;
        _title = '$user@$host';
        _error = saveWarning;
      });
    } on SSHAuthFailError {
      _fail('Autentikasi gagal — username/password/kunci salah');
    } on SocketException catch (e) {
      _fail(
        'Tidak bisa terhubung ke $activeHost:$port (${e.osError?.message ?? e.message})',
      );
    } on TimeoutException {
      _fail(
        'Timeout — $activeHost:$port tidak merespon. Cek host/port dan firewall.',
      );
    } catch (e) {
      _fail(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _fail(String msg) {
    _session?.close();
    _client?.close();
    _session = null;
    _client = null;
    if (!mounted) return;
    setState(() {
      _phase = _Phase.form;
      _error = msg;
    });
  }

  void _onClosed(String why) {
    if (!mounted) return;
    _client?.close();
    _session = null;
    _client = null;
    _terminal.write('\r\n\x1b[33m[$why]\x1b[0m\r\n');
    setState(() => _phase = _Phase.form);
    _setFullscreen(false);
    _error = why;
  }

  void _disconnect() {
    _session?.close();
    _client?.close();
    _session = null;
    _client = null;
    _setFullscreen(false);
    _resetZoom();
    setState(() => _phase = _Phase.form);
  }

  // ── Tampilan ───────────────────────────────────────────────────────────────
  void _setFullscreen(bool v) {
    if (widget.embedded || Platform.isWindows) return;
    _fullscreen = v;
    SystemChrome.setEnabledSystemUIMode(
      v ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    if (mounted) setState(() {});
  }

  void _toggleOrientation() {
    if (widget.embedded) return;
    _landscape = !_landscape;
    SystemChrome.setPreferredOrientations(
      _landscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
    setState(() {});
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final content = _phase == _Phase.connected
        ? ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: _terminalView(),
            ),
          )
        : _form();
    if (widget.embedded) {
      return Container(color: Colors.black, child: content);
    }
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(top: !_fullscreen, bottom: !_fullscreen, child: content),
    );
  }

  Widget _terminalView() {
    final desktop = Platform.isWindows;
    final terminal = LayoutBuilder(
      builder: (context, constraints) {
        final fontSize =
            desktop ? (constraints.maxWidth < 620 ? 11.0 : 13.0) : _fontSize;
        return TerminalView(
          _terminal,
          controller: _termController,
          theme: desktop ? _windowsTerminalTheme : _macTerminalTheme,
          textStyle: TerminalStyle(fontSize: fontSize),
          cursorType: TerminalCursorType.block,
          alwaysShowCursor: !desktop,
          hardwareKeyboardOnly: desktop,
          deleteDetection: true,
          autofocus: true,
          padding: const EdgeInsets.all(8),
        );
      },
    );
    final viewport = desktop
        ? terminal
        : InteractiveViewer(
            transformationController: _zoomCtrl,
            minScale: 1.0,
            maxScale: 5.0,
            panEnabled: _zoomed,
            scaleEnabled: true,
            boundaryMargin: EdgeInsets.zero,
            child: terminal,
          );
    return Column(
      children: [
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            color: AppColors.roseRed.withOpacity(0.14),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.roseRed, fontSize: 11),
            ),
          ),
        if (desktop)
          _desktopTerminalHeader()
        else if (!_fullscreen)
          _titleBar(),
        Expanded(child: viewport),
        if (!desktop) _extraKeys(),
      ],
    );
  }

  Widget _desktopTerminalHeader() => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: const Color(0xFF1F1F1F),
        child: Row(
          children: [
            const Icon(
              Icons.terminal_rounded,
              color: Color(0xFFCCCCCC),
              size: 17,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'SSH  $_title',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFE5E5E7),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Putuskan SSH',
              visualDensity: VisualDensity.compact,
              onPressed: _disconnect,
              icon: const Icon(Icons.link_off_rounded, size: 18),
            ),
          ],
        ),
      );

  /// Bar judul ala Terminal macOS: merah = putus, kuning = keluar fullscreen, hijau = fullscreen.
  Widget _titleBar() {
    Widget dot(Color c, VoidCallback onTap, String tip) => Tooltip(
          message: tip,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
          ),
        );
    final titleBar = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF3A3A3C), Color(0xFF2A2A2C)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(bottom: BorderSide(color: Colors.black)),
      ),
      child: Row(
        children: [
          dot(const Color(0xFFFF5F57), _disconnect, 'Putuskan'),
          dot(const Color(0xFFFEBC2E), () {
            if (widget.embedded) {
              widget.onClose?.call();
            } else {
              _setFullscreen(false);
            }
          }, widget.embedded ? 'Kecilkan' : 'Normal'),
          dot(const Color(0xFF28C840), () {
            if (widget.embedded) {
              _resetZoom();
            } else {
              _setFullscreen(!_fullscreen);
            }
          }, widget.embedded ? 'Reset zoom' : 'Fullscreen'),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$_title — ${_terminal.viewWidth}×${_terminal.viewHeight}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFD0D0D0), fontSize: 12.5),
            ),
          ),
          if (_zoomed)
            _barBtn(Icons.zoom_out_map_rounded, _resetZoom, 'Reset zoom 1×'),
          if (widget.embedded) ...[
            _barBtn(
              Icons.remove_rounded,
              () => widget.onClose?.call(),
              'Kecilkan terminal',
            ),
            _barBtn(
              Icons.close_rounded,
              () => widget.onCloseOverlay?.call(),
              'Tutup overlay',
            ),
          ],
          if (!widget.embedded)
            _barBtn(
              _landscape
                  ? Icons.stay_current_portrait_rounded
                  : Icons.stay_current_landscape_rounded,
              _toggleOrientation,
              'Putar layar',
            ),
        ],
      ),
    );
    return widget.windowDragRegion?.call(titleBar) ?? titleBar;
  }

  Widget _barBtn(IconData i, VoidCallback f, String tip) => IconButton(
        onPressed: f,
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
        padding: EdgeInsets.zero,
        icon: Icon(i, color: const Color(0xFFD0D0D0), size: 19),
      );

  Widget _extraKeys() {
    Widget key(String label, VoidCallback f) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          child: InkWell(
            onTap: f,
            borderRadius: BorderRadius.circular(7),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        );
    return Container(
      color: const Color(0xFF1C1C1E),
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          for (final entry in _quickCommands.entries)
            key(entry.key, () => _terminal.textInput(entry.value)),
          key('Edit', _editQuickCommands),
          key('Esc', () => _terminal.keyInput(TerminalKey.escape)),
          key('Tab', () => _terminal.keyInput(TerminalKey.tab)),
          key('^C', () => _terminal.textInput('\x03')),
          key('^D', () => _terminal.textInput('\x04')),
          key('^Z', () => _terminal.textInput('\x1a')),
          key('^L', () => _terminal.textInput('\x0c')),
          key('^A', () => _terminal.textInput('\x01')),
          key('^E', () => _terminal.textInput('\x05')),
          key('^U', () => _terminal.textInput('\x15')),
          key('^K', () => _terminal.textInput('\x0b')),
          key('Home', () => _terminal.keyInput(TerminalKey.home)),
          key('End', () => _terminal.keyInput(TerminalKey.end)),
          key('↑', () => _sendArrow(TerminalKey.arrowUp, '\x1b[A')),
          key('↓', () => _sendArrow(TerminalKey.arrowDown, '\x1b[B')),
          key('←', () => _sendArrow(TerminalKey.arrowLeft, '\x1b[D')),
          key('→', () => _sendArrow(TerminalKey.arrowRight, '\x1b[C')),
          key('|', () => _terminal.textInput('|')),
          key('~', () => _terminal.textInput('~')),
          key('/', () => _terminal.textInput('/')),
          key('-', () => _terminal.textInput('-')),
          key('_', () => _terminal.textInput('_')),
          key('Paste', () async {
            final d = await Clipboard.getData(Clipboard.kTextPlain);
            if (d?.text != null) _terminal.paste(d!.text!);
          }),
        ],
      ),
    );
  }

  // ── Form login ─────────────────────────────────────────────────────────────
  Widget _form() {
    InputDecoration dec(String label, {String? hint}) => InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.glassBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.neonGreen),
          ),
          isDense: true,
        );
    const txt = TextStyle(color: AppColors.textPrimary, fontSize: 14);
    final busy = _phase == _Phase.connecting;
    final heading = Row(
      children: [
        IconButton(
          onPressed: () =>
              widget.embedded ? widget.onClose?.call() : Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        const Icon(Icons.terminal_rounded, color: AppColors.neonGreen),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'SSH TERMINAL',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ),
        if (widget.embedded) ...[
          _barBtn(
            Icons.remove_rounded,
            () => widget.onClose?.call(),
            'Kecilkan terminal',
          ),
          _barBtn(
            Icons.close_rounded,
            () => widget.onCloseOverlay?.call(),
            'Tutup overlay',
          ),
        ],
      ],
    );
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        widget.windowDragRegion?.call(heading) ?? heading,
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Koneksi SSH asli langsung dari HP ke server (port SSH, bukan lewat agent monitor). '
            'Jika domain memakai proxy Cloudflare, isi IP server atau domain tanpa proxy.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _host,
                style: txt,
                decoration: dec('Host / IP'),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _port,
                style: txt,
                decoration: dec('Port'),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _user,
          style: txt,
          decoration: dec('Username'),
          autocorrect: false,
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _useKey,
          onChanged: (v) => setState(() => _useKey = v),
          activeColor: AppColors.neonGreen,
          title: const Text(
            'Login pakai private key',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
        ),
        if (!_useKey)
          TextField(
            controller: _pass,
            obscureText: !_showPass,
            style: txt,
            decoration: dec('Password').copyWith(
              suffixIcon: IconButton(
                onPressed: () => setState(() => _showPass = !_showPass),
                icon: Icon(
                  _showPass
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
              ),
            ),
          )
        else ...[
          TextField(
            controller: _key,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
            maxLines: 6,
            decoration: dec(
              'Private key (PEM)',
              hint: '-----BEGIN OPENSSH PRIVATE KEY-----',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passphrase,
            obscureText: true,
            style: txt,
            decoration: dec('Passphrase (jika ada)'),
          ),
        ],
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _saveSecrets,
          onChanged: (v) => setState(() => _saveSecrets = v ?? false),
          activeColor: AppColors.neonGreen,
          title: const Text(
            'Ingat password/key dengan aman di perangkat',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.roseRed, fontSize: 12.5),
            ),
          ),
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.text_fields_rounded,
                color: AppColors.neonGreen,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Ukuran teks SSH',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: _fontSize,
                  min: 6,
                  max: 14,
                  divisions: 8,
                  label: '${_fontSize.round()} px',
                  onChanged: (value) => setState(() => _fontSize = value),
                ),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  '${_fontSize.round()}px',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.neonGreen,
              foregroundColor: Colors.black,
            ),
            onPressed: busy ? null : _connect,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Icon(Icons.login_rounded),
            label: Text(busy ? 'Menghubungkan…' : 'Hubungkan'),
          ),
        ),
      ],
    );
  }
}
