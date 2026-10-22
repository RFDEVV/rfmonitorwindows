import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/server_config.dart';

Future<ServerConfig?> showAddServerDialog(BuildContext context, {ServerConfig? existing}) {
  return showDialog<ServerConfig>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.75), // gelap biar dialog kontras
    builder: (ctx) => _AddServerDialog(existing: existing),
  );
}

class _AddServerDialog extends StatefulWidget {
  final ServerConfig? existing;
  const _AddServerDialog({this.existing});

  @override
  State<_AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends State<_AddServerDialog> {
  late final _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
  late final _urlCtrl = TextEditingController(text: widget.existing?.baseUrl ?? '');
  late final _localUrlCtrl =
      TextEditingController(text: widget.existing?.localBaseUrl ?? '');
  late final _tailscaleUrlCtrl =
      TextEditingController(text: widget.existing?.tailscaleBaseUrl ?? '');
  late final _keyCtrl = TextEditingController(text: widget.existing?.apiKey ?? '');
  late final _tariffCtrl = TextEditingController(text: (widget.existing?.tariffPerKwh ?? 1445).toString());
  late final _internetCtrl = TextEditingController(text: (widget.existing?.monthlyInternetCostRp ?? 0).toString());
  late final _idleWattCtrl = TextEditingController(text: (widget.existing?.idleWatt ?? 30).toString());
  late final _maxWattCtrl = TextEditingController(text: (widget.existing?.maxExtraWatt ?? 90).toString());
  String? _error;

  void _submit() {
    if (_urlCtrl.text.trim().isEmpty || _keyCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Server URL dan API Key wajib diisi');
      return;
    }
    if (!_isValidEndpoint(_urlCtrl.text) ||
        !_isValidOptionalEndpoint(_localUrlCtrl.text) ||
        !_isValidOptionalEndpoint(_tailscaleUrlCtrl.text)) {
      setState(() => _error = 'URL server harus valid dan memakai HTTP atau HTTPS');
      return;
    }
    final config = ServerConfig(
      id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _nameCtrl.text.trim(),
      baseUrl: _urlCtrl.text.trim().replaceAll(RegExp(r'/$'), ''),
      localBaseUrl: _localUrlCtrl.text.trim().replaceAll(RegExp(r'/$'), ''),
      tailscaleBaseUrl:
          _tailscaleUrlCtrl.text.trim().replaceAll(RegExp(r'/$'), ''),
      apiKey: _keyCtrl.text.trim(),
      idleWatt: double.tryParse(_idleWattCtrl.text) ?? 30,
      maxExtraWatt: double.tryParse(_maxWattCtrl.text) ?? 90,
      tariffPerKwh: double.tryParse(_tariffCtrl.text) ?? 1445,
      monthlyInternetCostRp: double.tryParse(_internetCtrl.text) ?? 0,
    );
    Navigator.of(context).pop(config);
  }

  bool _isValidEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  bool _isValidOptionalEndpoint(String value) =>
      value.trim().isEmpty || _isValidEndpoint(value);

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _urlCtrl,
      _localUrlCtrl,
      _tailscaleUrlCtrl,
      _keyCtrl,
      _tariffCtrl,
      _internetCtrl,
      _idleWattCtrl,
      _maxWattCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final isEdit = widget.existing != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: Container(
          // SOLID background — tidak tembus ke belakang agar konten terbaca jelas
          decoration: BoxDecoration(
            color: const Color(0xFF0E1117), // solid dark, bukan transparan
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isEdit ? AppColors.neonGold : AppColors.neonCyan,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (isEdit ? AppColors.neonGold : AppColors.neonCyan).withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: -5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header bar
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                decoration: BoxDecoration(
                  color: (isEdit ? AppColors.neonGold : AppColors.neonCyan).withOpacity(0.08),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                  border: Border(
                    bottom: BorderSide(
                      color: (isEdit ? AppColors.neonGold : AppColors.neonCyan).withOpacity(0.2),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isEdit ? Icons.edit_rounded : Icons.add_circle_outline_rounded,
                      color: isEdit ? AppColors.neonGold : AppColors.neonCyan,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isEdit ? 'EDIT SERVER' : 'ADD SERVER',
                      style: AppTheme.orbitron.copyWith(
                        color: isEdit ? AppColors.neonGold : AppColors.neonCyan,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),

              // Scrollable form body
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 12 + viewInsets.bottom),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('INFO SERVER'),
                      const SizedBox(height: 8),
                      _field(_nameCtrl, 'Server Name (optional label)', Icons.label_outline),
                      const SizedBox(height: 10),
                      _field(_urlCtrl, 'Server URL (https://monitor.domain.com)', Icons.link_rounded),
                      const SizedBox(height: 10),
                      _field(
                        _localUrlCtrl,
                        'Local URL (http://192.168.x.x:port)',
                        Icons.router_outlined,
                      ),
                      const SizedBox(height: 10),
                      _field(
                        _tailscaleUrlCtrl,
                        'Tailscale URL (http://100.x.x.x:port)',
                        Icons.vpn_lock_outlined,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Urutan koneksi otomatis: Local → Tailscale → Server URL. Kosongkan alamat opsional jika tidak digunakan.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _field(_keyCtrl, 'API Key', Icons.key_rounded, obscure: true),
                      const SizedBox(height: 14),

                      // Expandable electricity section
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.glassBase,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                            iconColor: AppColors.neonGold,
                            collapsedIconColor: AppColors.neonGold,
                            leading: const Icon(Icons.bolt_rounded, color: AppColors.neonGold, size: 18),
                            title: const Text(
                              'Listrik & Internet (opsional)',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                            children: [
                              _field(_tariffCtrl, 'Tarif PLN (Rp/kWh)', Icons.electric_bolt_outlined, numeric: true),
                              const SizedBox(height: 10),
                              _field(_internetCtrl, 'Biaya Internet / Bulan (Rp)', Icons.wifi_rounded, numeric: true),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(child: _field(_idleWattCtrl, 'Idle Watt', Icons.power_outlined, numeric: true)),
                                  const SizedBox(width: 10),
                                  Expanded(child: _field(_maxWattCtrl, 'Max Extra Watt', Icons.power_outlined, numeric: true)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.roseRed.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.roseRed.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: AppColors.roseRed, size: 16),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.roseRed, fontSize: 12))),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded, size: 16),
                              label: const Text('Batal'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                side: const BorderSide(color: AppColors.glassBorder),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _submit,
                              icon: Icon(isEdit ? Icons.save_rounded : Icons.link_rounded, size: 16),
                              label: Text(isEdit ? 'Simpan' : 'Sambungkan'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: (isEdit ? AppColors.neonGold : AppColors.neonCyan).withOpacity(0.18),
                                foregroundColor: isEdit ? AppColors.neonGold : AppColors.neonCyan,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                side: BorderSide(
                                  color: (isEdit ? AppColors.neonGold : AppColors.neonCyan).withOpacity(0.5),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTheme.chakraPetch.copyWith(
        color: AppColors.textSecondary,
        fontSize: 10,
        letterSpacing: 2,
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData prefixIcon, {
    bool obscure = false,
    bool numeric = false,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        prefixIcon: Icon(prefixIcon, color: AppColors.textSecondary, size: 18),
        filled: true,
        fillColor: const Color(0xFF14181F),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.neonCyan),
        ),
      ),
    );
  }
}
