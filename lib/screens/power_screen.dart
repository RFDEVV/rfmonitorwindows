import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../theme/app_theme.dart';
import '../theme/app_icons.dart';
import '../widgets/glass_card.dart';
import '../widgets/app_header_bar.dart';
import '../services/api_service.dart';
import 'terminal_screen.dart';

/// "Power & CMD" tab: system reboot/shutdown controls + preset commands +
/// command bebas (free-form shell) yang dilindungi verifikasi 2FA — kode
/// 6-digit hanya muncul di console/log server, tidak pernah lewat API,
/// jadi walau token JWT bocor, orang lain tetap tidak bisa eksekusi command.
class PowerScreen extends StatefulWidget {
  final ApiService api;
  const PowerScreen({super.key, required this.api});

  @override
  State<PowerScreen> createState() => _PowerScreenState();
}

class _PowerScreenState extends State<PowerScreen> {
  int? _uptimeSeconds;
  bool _busy = false;
  final _auth = LocalAuthentication();

  List<String> _presets = [];
  bool _loadingPresets = true;
  String? _presetError;
  String? _busyPreset;
  final List<_ConsoleLine> _console = [];
  final _consoleScroll = ScrollController();
  final _cmdController = TextEditingController();
  bool _cmdRunning = false;

  @override
  void initState() {
    super.initState();
    _loadUptime();
    _loadPresets();
  }

  Future<void> _loadUptime() async {
    try {
      final res = await widget.api.getUptime();
      final raw = res['data']['uptimeSeconds'];
      // JSON numbers decode as int OR double in Dart depending on whether the
      // JS side emitted a whole number - casting straight to int crashed here
      // silently whenever uptime had a fractional part, which is most of the
      // time. (num).toInt() handles both cases safely -> fixes the "--" bug.
      if (mounted) setState(() => _uptimeSeconds = (raw as num).toInt());
    } catch (_) {
      // dashboard's own connection banner already communicates offline state
    }
  }

  Future<void> _loadPresets() async {
    setState(() {
      _loadingPresets = true;
      _presetError = null;
    });
    try {
      final list = await widget.api.getPresets();
      setState(() => _presets = list.cast<String>());
    } catch (e) {
      setState(() => _presetError = e.toString());
    } finally {
      setState(() => _loadingPresets = false);
    }
  }

  Future<void> _runPreset(String name) async {
    setState(() {
      _busyPreset = name;
      _console.add(_ConsoleLine('\$ $name', isCommand: true));
    });
    _scrollConsoleToEnd();
    try {
      final output = await widget.api.runPreset(name);
      setState(() => _console.add(_ConsoleLine(output.isEmpty ? '(no output)' : output)));
    } catch (e) {
      setState(() => _console.add(_ConsoleLine('Error: $e', isError: true)));
    } finally {
      setState(() => _busyPreset = null);
      _scrollConsoleToEnd();
    }
  }

  void _scrollConsoleToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_consoleScroll.hasClients) {
        _consoleScroll.animateTo(_consoleScroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  /// Minta user masukkan kode verifikasi 6-digit (kode itu sendiri cuma
  /// muncul di console/log server — dialog ini cuma tempat mengetiknya).
  Future<String?> _askVerifyCode(String message) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgBottom,
        title: const Text('Verifikasi Diperlukan', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            const Text(
              'Kode 6-digit HANYA muncul di console/log server (bukan di HP). Buka tab Logs untuk melihatnya, lalu masukkan di sini.',
              style: TextStyle(color: AppColors.neonGold, fontSize: 11.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textPrimary, letterSpacing: 6, fontSize: 22),
              decoration: const InputDecoration(counterText: '', border: OutlineInputBorder(), hintText: '000000'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Verifikasi', style: TextStyle(color: AppColors.neonGreen)),
          ),
        ],
      ),
    );
  }

  /// Jalankan command bebas via /system/exec — loop sampai berhasil,
  /// dibatalkan, atau error non-verifikasi.
  Future<void> _runFreeCommand() async {
    final cmd = _cmdController.text.trim();
    if (cmd.isEmpty || _cmdRunning) return;
    _cmdController.clear();
    setState(() {
      _cmdRunning = true;
      _console.add(_ConsoleLine('\$ $cmd', isCommand: true));
    });
    _scrollConsoleToEnd();

    String? code;
    try {
      while (true) {
        try {
          final res = await widget.api.execCommand(cmd, verifyCode: code);
          final data = res['data'] as Map<String, dynamic>?;
          final output = (data?['output'] ?? '').toString();
          setState(() => _console.add(_ConsoleLine(output.trim().isEmpty ? '(no output)' : output)));
          break;
        } on ExecVerificationException catch (e) {
          if (!mounted) return;
          code = await _askVerifyCode(e.message);
          if (code == null || code.isEmpty) {
            setState(() => _console.add(_ConsoleLine('Dibatalkan — verifikasi diperlukan untuk command bebas.', isError: true)));
            break;
          }
          // ulangi loop dengan kode baru
        } catch (e) {
          setState(() => _console.add(_ConsoleLine('Error: $e', isError: true)));
          break;
        }
      }
    } finally {
      if (mounted) setState(() => _cmdRunning = false);
      _scrollConsoleToEnd();
    }
  }

  /// Biometric one-tap fast path when available (per spec: "tap konfirmasi
  /// cepat dengan passwordless sudo backend"); falls back to requiring the
  /// typed confirmation phrase when biometrics aren't set up on the device.
  Future<bool> _biometricGate() async {
    try {
      final canCheck = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (!canCheck) return false;
      return await _auth.authenticate(
        localizedReason: 'Confirm identity to control the server',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _handlePowerAction(String action) async {
    final phraseExpected = action == 'reboot' ? 'CONFIRM REBOOT' : 'CONFIRM SHUTDOWN';

    // Fast path: biometric success alone confirms the action, no typing
    // required. Bug fix: the old flow required an exact-match phrase even
    // after a successful biometric check, causing spurious "did not match"
    // errors — biometric success now short-circuits straight to execution.
    final biometricOk = await _biometricGate();
    bool confirmed = biometricOk;

    if (!confirmed) {
      if (!mounted) return;
      final controller = TextEditingController();
      confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.bgBottom,
              title: Text(action == 'reboot' ? 'Reboot server?' : 'Shutdown server?', style: const TextStyle(color: AppColors.textPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Type "$phraseExpected" to confirm.', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, _normalizePhrase(controller.text) == _normalizePhrase(phraseExpected)),
                  child: const Text('Execute', style: TextStyle(color: AppColors.roseRed)),
                ),
              ],
            ),
          ) ??
          false;

      if (!confirmed) {
        if (mounted && controller.text.trim().isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Confirmation phrase did not match')));
        }
        return;
      }
    }

    setState(() => _busy = true);
    try {
      await widget.api.systemPower(action, phraseExpected);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$action command sent')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _normalizePhrase(String s) => s.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

  String _formatUptime(int seconds) {
    final d = Duration(seconds: seconds);
    return '${d.inDays}d ${d.inHours % 24}h ${d.inMinutes % 60}m';
  }

  @override
  void dispose() {
    _consoleScroll.dispose();
    _cmdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppHeaderBar(
          title: 'POWER & CMD',
          subtitle: 'SYSTEM CONTROL',
          iconWidget: AppHeaderBar.svgIcon(AppIcons.power, AppColors.neonOrange),
          accent: AppColors.neonOrange,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
        GlassCard(
          glowColor: AppColors.neonCyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Server Uptime', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                _uptimeSeconds == null ? '--' : _formatUptime(_uptimeSeconds!),
                style: const TextStyle(color: AppColors.neonGreen, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('System Controls', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),
        _powerButton('Reboot Server', AppColors.neonGold, 'reboot'),
        const SizedBox(height: 12),
        _powerButton('Shutdown Server', AppColors.roseRed, 'shutdown'),
        const SizedBox(height: 24),
        const Text('Terminal SSH', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),
        _sshCard(),
        const SizedBox(height: 22),
        const Text('Interactive Command Console', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),
        _presetsCard(),
        const SizedBox(height: 12),
        _consoleCard(),
        const SizedBox(height: 16),
        const Text('Command Bebas (Advanced)', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),
        _freeCommandInput(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sshCard() {
    String host = '';
    try { host = Uri.parse(widget.api.config.baseUrl).host; } catch (_) {}
    return GlassCard(
      glowColor: AppColors.neonGreen,
      child: Row(
        children: [
          const Icon(Icons.terminal_rounded, color: AppColors.neonGreen, size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SSH Terminal', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Text('SSH asli ke server · zoom · fullscreen · vertikal/horizontal',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.neonGreen, foregroundColor: Colors.black),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TerminalScreen(
                  defaultHost: host,
                  localHost: widget.api.config.localHost,
                  tailscaleHost: widget.api.config.tailscaleHost,
                ),
              ),
            ),
            child: const Text('Buka'),
          ),
        ],
      ),
    );
  }

  Widget _freeCommandInput() {
    return GlassCard(
      glowColor: AppColors.roseRed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: AppColors.roseRed, size: 16),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Ketik command apa pun untuk dijalankan langsung di shell server. Dilindungi verifikasi 2FA — kode muncul di log server.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cmdController,
                  enabled: !_cmdRunning,
                  onSubmitted: (_) => _runFreeCommand(),
                  style: const TextStyle(color: AppColors.neonGreen, fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    hintText: _cmdRunning ? 'Menjalankan...' : 'contoh: df -h',
                    hintStyle: const TextStyle(color: AppColors.textSecondary),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _cmdRunning
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.neonGreen))
                  : IconButton(
                      onPressed: _runFreeCommand,
                      icon: const Icon(Icons.send_rounded, color: AppColors.neonGreen),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _powerButton(String label, Color color, String action) {
    return GlassCard(
      glowColor: color,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          _busy
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.neonCyan))
              : ElevatedButton(
                  onPressed: () => _handlePowerAction(action),
                  style: ElevatedButton.styleFrom(backgroundColor: color.withOpacity(0.2), foregroundColor: color, elevation: 0),
                  child: const Text('Execute'),
                ),
        ],
      ),
    );
  }

  Widget _presetsCard() {
    return GlassCard(
      glowColor: AppColors.neonOrange,
      child: _loadingPresets
          ? const Center(child: CircularProgressIndicator(color: AppColors.neonOrange))
          : _presetError != null
              ? Text('Error: $_presetError', style: const TextStyle(color: AppColors.roseRed, fontSize: 12))
              : _presets.isEmpty
                  ? const Text('No command presets configured. Add COMMAND_PRESETS in the agent\'s .env.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _presets.map((name) {
                        final busy = _busyPreset == name;
                        return OutlinedButton(
                          onPressed: busy ? null : () => _runPreset(name),
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.neonOrange), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                          child: busy
                              ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.neonOrange))
                              : Text(name, style: const TextStyle(color: AppColors.neonOrange, fontSize: 12)),
                        );
                      }).toList(),
                    ),
    );
  }

  Widget _consoleCard() {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.neonGreen.withOpacity(0.4)),
        boxShadow: [BoxShadow(color: AppColors.neonGreen.withOpacity(0.12), blurRadius: 18)],
      ),
      child: _console.isEmpty
          ? const Text('// Output console — run a preset above.', style: TextStyle(color: AppColors.textSecondary, fontFamily: 'monospace', fontSize: 12))
          : ListView.builder(
              controller: _consoleScroll,
              itemCount: _console.length,
              itemBuilder: (ctx, i) {
                final line = _console[i];
                final color = line.isCommand ? AppColors.neonCyan : (line.isError ? AppColors.roseRed : AppColors.neonGreen);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: SelectableText(line.text, style: TextStyle(color: color, fontFamily: 'monospace', fontSize: 11)),
                );
              },
            ),
    );
  }
}

class _ConsoleLine {
  final String text;
  final bool isCommand;
  final bool isError;
  _ConsoleLine(this.text, {this.isCommand = false, this.isError = false});
}
