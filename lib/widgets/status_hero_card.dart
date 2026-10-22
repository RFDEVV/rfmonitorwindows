import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/app_style.dart';
import '../services/socket_service.dart';

/// SERVER STATUS hero card.
/// - Jika reconnecting > 15 detik → tampilkan tombol "RECONNECT"
/// - Pulsing dot untuk status online
/// - Font: Orbitron (judul besar) + Rajdhani (sublabel) + Chakra Petch (badge)
class StatusHeroCard extends StatefulWidget {
  final bool? online;
  final SocketConnState connState;
  final VoidCallback? onReconnect;

  const StatusHeroCard({
    super.key,
    required this.online,
    required this.connState,
    this.onReconnect,
  });

  @override
  State<StatusHeroCard> createState() => _StatusHeroCardState();
}

class _StatusHeroCardState extends State<StatusHeroCard> with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  Timer? _timeoutTimer;
  bool _showReconnect = false;
  DateTime? _reconnectingStart;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _checkReconnectTimer();
  }

  @override
  void didUpdateWidget(StatusHeroCard old) {
    super.didUpdateWidget(old);
    _checkReconnectTimer();
  }

  void _checkReconnectTimer() {
    final isReconnecting = widget.connState == SocketConnState.reconnecting ||
        (widget.connState == SocketConnState.disconnected && widget.online != true);

    if (isReconnecting && _reconnectingStart == null) {
      _reconnectingStart = DateTime.now();
      _timeoutTimer?.cancel();
      // Tampilkan tombol reconnect setelah 15 detik
      _timeoutTimer = Timer(const Duration(seconds: 15), () {
        if (mounted && widget.online != true) {
          setState(() => _showReconnect = true);
        }
      });
    } else if (!isReconnecting) {
      _timeoutTimer?.cancel();
      _reconnectingStart = null;
      if (_showReconnect) setState(() => _showReconnect = false);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOnline   = widget.online == true;
    final isKnown    = widget.online != null;
    final isReconn   = widget.connState == SocketConnState.reconnecting;

    final color = !isKnown
        ? AppColors.textSecondary
        : isOnline
            ? AppColors.neonGreen
            : AppColors.roseRed;

    final statusLabel = !isKnown
        ? 'CONNECTING'
        : isOnline
            ? 'ONLINE'
            : isReconn
                ? 'RECONNECTING'
                : 'OFFLINE';

    final badgeLabel = !isKnown
        ? 'WAIT'
        : isOnline
            ? 'RUNNING'
            : 'DOWN';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: AppStyleKit.isGlass
          ? BoxDecoration(
              color: const Color(0xFF0E1218).withOpacity(0.8),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withOpacity(0.55), width: 1.4),
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.22), blurRadius: 24, spreadRadius: -4),
                BoxShadow(color: color.withOpacity(0.10), blurRadius: 60, spreadRadius: 0),
              ],
            )
          : AppStyleKit.card(accent: color, radius: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Pulsing dot
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    color: isKnown ? color : Colors.grey.shade700,
                    shape: BoxShape.circle,
                    boxShadow: isKnown
                        ? [BoxShadow(color: color.withOpacity(_pulseAnim.value * 0.9), blurRadius: 10, spreadRadius: 2)]
                        : [],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // "SERVER STATUS" — Chakra Petch label
                    Text(
                      'SERVER STATUS',
                      style: AppTheme.chakraPetch.copyWith(
                        color: color, fontSize: 10.5, letterSpacing: 3, fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // "ONLINE" / "OFFLINE" — Orbitron besar
                    Text(
                      statusLabel,
                      style: AppTheme.orbitron.copyWith(
                        color: color, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              // Badge pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: color.withOpacity(0.5)),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.25), blurRadius: 10)],
                ),
                child: Text(
                  badgeLabel,
                  style: AppTheme.chakraPetch.copyWith(
                    color: color, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),

          // Tombol RECONNECT — muncul setelah timeout 15 detik
          if (_showReconnect && widget.onReconnect != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _showReconnect = false;
                    _reconnectingStart = null;
                  });
                  widget.onReconnect!();
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(
                  'CONNECT ULANG',
                  style: AppTheme.chakraPetch.copyWith(fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.neonCyan,
                  side: const BorderSide(color: AppColors.neonCyan, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],

          // Progress bar tipis saat reconnecting
          if (isReconn && !_showReconnect) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                backgroundColor: Colors.white.withOpacity(0.05),
                valueColor: AlwaysStoppedAnimation(color.withOpacity(0.6)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
