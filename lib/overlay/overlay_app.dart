import 'dart:async';
import 'dart:convert';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../models/server_config.dart';
import '../models/ram_metrics.dart';
import '../screens/terminal_screen.dart';
import '../services/api_service.dart';
import '../services/overlay_service.dart';
import '../services/socket_service.dart';
import '../services/storage_service.dart';
import '../theme/app_style.dart';
import '../theme/app_theme.dart';
import '../widgets/log_viewer_sheet.dart';

/// Root jendela overlay (engine terpisah dari app utama).
class OverlayApp extends StatelessWidget {
  const OverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StyleController.instance,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.themeFor(
          StyleController.instance.style,
          lightMode: StyleController.instance.isLightMode,
        ),
        builder: (context, child) =>
            StyleRebuilder(child: child ?? const SizedBox.shrink()),
        home: const Material(
          type: MaterialType.transparency,
          child: OverlayRoot(),
        ),
      ),
    );
  }
}

enum _Mode { bubble, small, medium, terminal }

/// Tombol bulat melayang:
///   1× ketuk  → kotak kecil (CPU, RAM, disk, suhu, core, statistik)
///   2× ketuk  → panel sedang (PM2 + service)
///   3× ketuk  → terminal SSH (layar penuh)
///   tekan lama → kembali ke tampilan app normal
class OverlayRoot extends StatefulWidget {
  const OverlayRoot({super.key});

  @override
  State<OverlayRoot> createState() => _OverlayRootState();
}

class _OverlayRootState extends State<OverlayRoot> {
  static const _appPackage = 'com.rfproject.rfmonitor';

  _Mode _mode = _Mode.bubble;
  ServerConfig? _config;
  ApiService? _api;
  SocketService? _socket;
  Map<String, dynamic>? _m;
  SocketConnState _conn = SocketConnState.disconnected;

  StreamSubscription? _dataSub;
  StreamSubscription? _metricsSub;
  StreamSubscription? _stateSub;
  Timer? _tapTimer;
  Timer? _longPressTimer;
  Timer? _listTimer;
  Timer? _positionTimer;
  Timer? _edgeTimer;
  int _taps = 0;
  int? _bubblePointer;
  Offset? _bubblePointerOrigin;
  Offset? _bubbleLastPointerPosition;
  Offset _bubblePendingDelta = Offset.zero;
  OverlayPosition? _bubbleDragPosition;
  Future<OverlayPosition?>? _bubbleDragPositionFuture;
  Timer? _bubbleMoveTimer;
  bool _bubbleMoveInProgress = false;
  bool _bubbleDragActive = false;
  bool _bubblePointerMoved = false;
  bool _bubbleLongPressed = false;
  Future<void> _modeTransition = Future<void>.value();
  bool _refreshingLists = false;
  bool _listsLoading = false;
  String? _listError;
  String? _busyListItem;
  bool _checkingPosition = false;
  bool _isPeeked = false;
  bool? _pendingRightEdge;
  double _bubbleSize = OverlayService.defaultBubbleSize;
  double _panelScale = OverlayService.defaultPanelScale;
  double _screenWidth = 0;
  double _screenHeight = 0;
  OverlayPosition? _panelDragOrigin;
  OverlayPosition? _panelPosition;
  OverlayPosition? _pendingPanelPosition;
  Timer? _panelMoveTimer;
  bool _flushingPanelMove = false;
  bool _panelDragActive = false;
  double _panelWidth = 0;
  double _panelHeight = 0;

  List<Map<String, dynamic>> _pm2 = [];
  List<Map<String, dynamic>> _services = [];
  int _tab = 0;
  String? _notice;
  OverlayPosition? _savedPos;

  double get _peekWidth => OverlayService.peekWidthFor(_bubbleSize);

  @override
  void initState() {
    super.initState();
    _dataSub = FlutterOverlayWindow.overlayListener.listen(_onData);
    _loadOverlayPreferences();
    _loadStored();
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    _longPressTimer?.cancel();
    _bubbleMoveTimer?.cancel();
    _listTimer?.cancel();
    _positionTimer?.cancel();
    _edgeTimer?.cancel();
    _panelMoveTimer?.cancel();
    _dataSub?.cancel();
    _stopSocket();
    super.dispose();
  }

  // ── Konfigurasi ────────────────────────────────────────────────────────────
  void _onData(dynamic raw) {
    try {
      if (raw is! String) return;
      final j = jsonDecode(raw);
      if (j is! Map) return;
      if (j['type'] == 'bubble_size') {
        final size = (j['size'] as num?)?.toDouble();
        if (size != null) _updateBubbleSize(size);
        return;
      }
      if (j['type'] == 'panel_scale') {
        final scale = (j['scale'] as num?)?.toDouble();
        if (scale != null) _updatePanelScale(scale);
        return;
      }
      if (j['type'] != 'config' && j['type'] != 'activate') return;
      StyleController.instance.applyName(
        j['style']?.toString(),
        lightMode: j['lightMode'] == true,
      );
      final c = ServerConfig.fromJson(
        (j['config'] as Map).cast<String, dynamic>(),
      );
      _setConfig(c);
      if (j['type'] == 'activate') {
        _resetBubbleGesture();
        final bubbleSize = (j['bubbleSize'] as num?)?.toDouble();
        if (bubbleSize != null) _updateBubbleSize(bubbleSize);
        final screenWidth = (j['screenWidth'] as num?)?.toDouble();
        if (screenWidth != null && screenWidth > 0) {
          _screenWidth = screenWidth;
        }
        final screenHeight = (j['screenHeight'] as num?)?.toDouble();
        if (screenHeight != null && screenHeight > 0) {
          _screenHeight = screenHeight;
        }
        _setMode(_Mode.bubble, force: true);
      }
    } catch (error) {
      debugPrint('Unable to process overlay message: $error');
    }
  }

  void _resetBubbleGesture() {
    _tapTimer?.cancel();
    _longPressTimer?.cancel();
    _bubbleMoveTimer?.cancel();
    _taps = 0;
    _bubblePointer = null;
    _bubblePointerOrigin = null;
    _bubbleLastPointerPosition = null;
    _bubbleDragPosition = null;
    _bubbleDragPositionFuture = null;
    _bubblePendingDelta = Offset.zero;
    _bubbleDragActive = false;
    _bubblePointerMoved = false;
    _bubbleLongPressed = false;
  }

  void _bubblePointerDown(PointerDownEvent event) {
    _longPressTimer?.cancel();
    _bubblePointer = event.pointer;
    _bubblePointerOrigin = event.position;
    _bubbleLastPointerPosition = event.position;
    _bubbleDragPosition = null;
    _bubblePendingDelta = Offset.zero;
    _bubbleDragPositionFuture = _readBubbleDragPosition();
    _bubblePointerMoved = false;
    _bubbleLongPressed = false;
    _longPressTimer = Timer(const Duration(milliseconds: 500), () {
      if (_bubblePointer != event.pointer || _bubblePointerMoved) return;
      _bubbleLongPressed = true;
      _tapTimer?.cancel();
      _taps = 0;
      _openApp();
    });
  }

  Future<OverlayPosition?> _readBubbleDragPosition() async {
    try {
      return await FlutterOverlayWindow.getOverlayPosition();
    } catch (error) {
      debugPrint('Unable to read overlay position at drag start: $error');
      return _savedPos;
    }
  }

  Future<void> _flushBubbleDrag() async {
    if (_bubbleMoveInProgress) return;
    _bubbleMoveInProgress = true;
    try {
      _bubbleDragPosition ??= await _bubbleDragPositionFuture ?? _savedPos;
      if (_bubbleDragPosition == null) return;
      while (_bubblePendingDelta != Offset.zero) {
        final delta = _bubblePendingDelta;
        _bubblePendingDelta = Offset.zero;
        final maxX = _screenWidth > 0
            ? (_screenWidth - _bubbleSize).clamp(0, double.infinity).toDouble()
            : double.infinity;
        final maxY = _screenHeight > 0
            ? (_screenHeight - _bubbleSize).clamp(0, double.infinity).toDouble()
            : double.infinity;
        final current = _bubbleDragPosition!;
        final next = OverlayPosition(
          (current.x + delta.dx).clamp(0, maxX).toDouble(),
          (current.y + delta.dy).clamp(0, maxY).toDouble(),
        );
        if (await FlutterOverlayWindow.moveOverlay(next) == false) {
          throw StateError('Android menolak posisi tombol baru');
        }
        _bubbleDragPosition = next;
        _savedPos = next;
      }
    } catch (error) {
      debugPrint('Unable to move overlay bubble: $error');
      _bubblePendingDelta = Offset.zero;
      if (mounted) setState(() => _notice = 'Gagal memindahkan tombol: $error');
    } finally {
      _bubbleMoveInProgress = false;
      if (_bubblePendingDelta != Offset.zero && mounted) {
        _bubbleMoveTimer ??= Timer(const Duration(milliseconds: 16), () {
          _bubbleMoveTimer = null;
          unawaited(_flushBubbleDrag());
        });
      }
    }
  }

  void _bubblePointerMove(PointerMoveEvent event) {
    if (_bubblePointer != event.pointer) return;
    final origin = _bubblePointerOrigin;
    final last = _bubbleLastPointerPosition;
    if (origin == null || last == null) return;
    if (!_bubbleDragActive) {
      if ((origin - event.position).distance < 4) return;
      _bubblePointerMoved = true;
      _bubbleDragActive = true;
      _edgeTimer?.cancel();
      _edgeTimer = null;
      _longPressTimer?.cancel();
      _bubblePendingDelta += event.position - origin;
    } else {
      _bubblePendingDelta += event.position - last;
    }
    _bubbleLastPointerPosition = event.position;
    _bubbleMoveTimer ??= Timer(const Duration(milliseconds: 16), () {
      _bubbleMoveTimer = null;
      unawaited(_flushBubbleDrag());
    });
  }

  void _bubblePointerUp(PointerEvent event) {
    if (_bubblePointer != event.pointer) return;
    _longPressTimer?.cancel();
    final moved = _bubblePointerMoved;
    final longPressed = _bubbleLongPressed;
    _bubblePointer = null;
    _bubblePointerOrigin = null;
    _bubbleLastPointerPosition = null;
    _bubblePointerMoved = false;
    _bubbleLongPressed = false;
    if (moved) {
      _bubbleMoveTimer?.cancel();
      _bubbleMoveTimer = null;
      unawaited(_persistBubblePositionAfterDrag());
      return;
    }
    if (longPressed) return;
    if (_isPeeked) {
      _expandPeekOnTap();
    } else {
      _handleTap();
    }
  }

  Future<void> _persistBubblePositionAfterDrag() async {
    try {
      await _flushBubbleDrag();
      while (_bubbleMoveInProgress || _bubblePendingDelta != Offset.zero) {
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
      final position = await FlutterOverlayWindow.getOverlayPosition();
      if (!mounted || _mode != _Mode.bubble || _isPeeked) return;
      _savedPos = position;
      await OverlayService.savePosition(position);
    } catch (error) {
      debugPrint('Unable to save dragged overlay position: $error');
      if (mounted) setState(() => _notice = 'Gagal menyimpan posisi tombol: $error');
    } finally {
      _bubbleDragActive = false;
      _bubbleDragPosition = null;
      _bubbleDragPositionFuture = null;
      _bubblePendingDelta = Offset.zero;
    }
  }

  void _bubblePointerCancel(PointerCancelEvent event) {
    if (_bubblePointer != event.pointer) return;
    _longPressTimer?.cancel();
    _bubbleMoveTimer?.cancel();
    _bubbleMoveTimer = null;
    if (_bubbleDragActive) {
      unawaited(_persistBubblePositionAfterDrag());
    }
    _bubblePointer = null;
    _bubblePointerOrigin = null;
    _bubbleLastPointerPosition = null;
    _bubblePointerMoved = false;
    _bubbleLongPressed = false;
  }

  Future<void> _loadOverlayPreferences() async {
    final size = await OverlayService.bubbleSize();
    final width = await OverlayService.storedScreenWidth();
    final height = await OverlayService.storedScreenHeight();
    final panelScale = await OverlayService.panelScale();
    if (!mounted) return;
    setState(() {
      _bubbleSize = size;
      _screenWidth = width;
      _screenHeight = height;
      _panelScale = panelScale;
    });
  }

  Future<void> _updatePanelScale(double scale) {
    final next = _modeTransition.then((_) async {
      _panelScale = scale
          .clamp(
            OverlayService.minPanelScale,
            OverlayService.maxPanelScale,
          )
          .toDouble();
      if (_mode != _Mode.bubble) {
        await _configureWindow(_mode);
      }
      if (mounted) setState(() {});
    });
    _modeTransition = next.catchError((Object error, StackTrace stackTrace) {
      debugPrint('Overlay panel resize failed: $error');
      return null;
    });
    return _modeTransition;
  }

  void _startPanelDrag(DragStartDetails details) {
    _panelDragActive = true;
    _panelDragOrigin = _panelPosition;
    _panelDragDelta = Offset.zero;
  }

  void _updatePanelDrag(DragUpdateDetails details) {
    if (!_panelDragActive) return;
    _panelDragDelta += details.delta;
    _queuePanelDragPosition();
  }

  Offset _panelDragDelta = Offset.zero;

  void _queuePanelDragPosition() {
    final origin = _panelDragOrigin;
    if (!_panelDragActive || origin == null) return;
    final maxX = _screenWidth > 0
        ? (_screenWidth - _panelWidth).clamp(0, double.infinity).toDouble()
        : double.infinity;
    final maxY = _screenHeight > 0
        ? (_screenHeight - _panelHeight).clamp(0, double.infinity).toDouble()
        : double.infinity;
    _pendingPanelPosition = OverlayPosition(
      (origin.x + _panelDragDelta.dx).round().clamp(0, maxX).toDouble(),
      (origin.y + _panelDragDelta.dy).round().clamp(0, maxY).toDouble(),
    );
    _panelMoveTimer ??= Timer(const Duration(milliseconds: 16), () {
      _panelMoveTimer = null;
      _flushPanelMoves();
    });
  }

  Future<void> _flushPanelMoves() async {
    if (_flushingPanelMove) return;
    _flushingPanelMove = true;
    try {
      while (_pendingPanelPosition != null) {
        final position = _pendingPanelPosition!;
        _pendingPanelPosition = null;
        if (await FlutterOverlayWindow.moveOverlay(position) == false) {
          throw StateError('Android menolak posisi panel baru');
        }
        _panelPosition = position;
      }
    } catch (error) {
      debugPrint('Unable to move overlay panel: $error');
      if (mounted) setState(() => _notice = 'Gagal memindahkan panel: $error');
    } finally {
      _flushingPanelMove = false;
      if (_pendingPanelPosition != null && mounted) {
        _panelMoveTimer ??= Timer(const Duration(milliseconds: 16), () {
          _panelMoveTimer = null;
          _flushPanelMoves();
        });
      }
    }
  }

  void _endPanelDrag(DragEndDetails details) {
    _panelDragActive = false;
    _panelDragOrigin = null;
    _panelDragDelta = Offset.zero;
    _panelMoveTimer?.cancel();
    _panelMoveTimer = null;
    _flushPanelMoves();
  }

  Future<void> _expandPeekOnTap() async {
    try {
      await _restoreBubbleFromPeek();
      _pendingRightEdge = null;
    } catch (error) {
      debugPrint('Unable to expand overlay handle: $error');
      if (mounted) setState(() => _notice = 'Gagal membuka tombol: $error');
    }
  }

  Future<void> _updateBubbleSize(double size) {
    final next = _modeTransition.then((_) => _applyBubbleSize(size));
    _modeTransition = next.catchError((Object error, StackTrace stackTrace) {
      debugPrint('Overlay size change failed: $error');
    });
    return _modeTransition;
  }

  Future<void> _applyBubbleSize(double size) async {
    final previousSize = _bubbleSize;
    final wasPeeked = _isPeeked;
    final rightEdge = wasPeeked
        ? _pendingRightEdge == true
        : _screenWidth > previousSize &&
            _savedPos != null &&
            _savedPos!.x >= _screenWidth - previousSize - 2;
    _bubbleSize = size
        .clamp(OverlayService.minBubbleSize, OverlayService.maxBubbleSize)
        .toDouble();
    if (_mode != _Mode.bubble &&
        rightEdge &&
        _savedPos != null &&
        _screenWidth > 0) {
      _savedPos = OverlayPosition(
        _screenWidth > _bubbleSize ? _screenWidth - _bubbleSize : 0,
        _savedPos!.y,
      );
      await OverlayService.savePosition(_savedPos!);
    }
    if (_mode == _Mode.bubble) {
      _edgeTimer?.cancel();
      if (!wasPeeked) _pendingRightEdge = null;
      try {
        final position = await FlutterOverlayWindow.getOverlayPosition();
        if (wasPeeked) {
          _pendingRightEdge = rightEdge;
          _savedPos = OverlayPosition(
            rightEdge && _screenWidth > _bubbleSize
                ? _screenWidth - _bubbleSize
                : 0,
            _savedPos?.y ?? position.y,
          );
          await OverlayService.savePosition(_savedPos!);
          await _restoreBubbleFromPeek();
          _pendingRightEdge = null;
        } else {
          final wasAtRightEdge = _screenWidth > previousSize &&
              position.x >= _screenWidth - previousSize - 2;
          _savedPos = OverlayPosition(
            wasAtRightEdge && _screenWidth > _bubbleSize
                ? _screenWidth - _bubbleSize
                : position.x,
            position.y,
          );
          await OverlayService.savePosition(_savedPos!);
        }
        await _configureWindow(_Mode.bubble);
      } catch (e) {
        debugPrint('Unable to apply new overlay size: $e');
        if (mounted)
          setState(() => _notice = 'Gagal mengubah ukuran tombol: $e');
      }
    }
    if (mounted) setState(() {});
  }

  /// Cadangan: baca profil server tersimpan bila data dari app belum datang.
  Future<void> _loadStored() async {
    try {
      final st = StorageService();
      final list = await st.loadProfiles();
      if (list.isEmpty || _config != null) return;
      final idx = await st.getActiveProfileIndex();
      _setConfig(list[idx.clamp(0, list.length - 1)]);
    } catch (_) {
      /* plugin storage tidak tersedia di overlay — tunggu data dari app */
    }
  }

  void _setConfig(ServerConfig c) {
    final old = _config;
    if (old != null &&
        old.baseUrl == c.baseUrl &&
        old.apiKey == c.apiKey &&
        old.id == c.id) {
      return;
    }
    _stopSocket();
    _config = c;
    _api = ApiService(c);
    if (mounted) setState(() {});
    if (_mode != _Mode.bubble) _startSocket();
  }

  // ── Koneksi data (hanya aktif saat panel terbuka → hemat baterai & kuota) ───
  void _startSocket() {
    final cfg = _config, api = _api;
    if (cfg == null || api == null || _socket != null) return;
    final sock = SocketService(cfg, api);
    _socket = sock;
    _metricsSub = sock.metricsStream.listen((m) {
      if (mounted) setState(() => _m = m);
    });
    _stateSub = sock.stateStream.listen((s) {
      if (mounted) setState(() => _conn = s);
    });
    sock.connect();
  }

  void _stopSocket() {
    _metricsSub?.cancel();
    _stateSub?.cancel();
    _metricsSub = null;
    _stateSub = null;
    _socket?.dispose();
    _socket = null;
  }

  Future<void> _refreshLists() async {
    final api = _api;
    if (_refreshingLists) return;
    if (api == null) {
      if (mounted) {
        setState(() {
          _listError = 'Konfigurasi server belum tersedia.';
          _listsLoading = false;
        });
      }
      return;
    }
    _refreshingLists = true;
    if (mounted) {
      setState(() {
        _listsLoading = true;
        _listError = null;
      });
    }
    try {
      List<Map<String, dynamic>> convert(List<dynamic> result) => result
          .whereType<Map>()
          .map(
            (item) => item.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
          .toList();
      final errors = <String>[];
      Future<void> loadPm2() async {
        try {
          final result = convert(
            await api.getPm2List(timeout: const Duration(seconds: 15)),
          );
          if (mounted) setState(() => _pm2 = result);
        } catch (error) {
          errors.add('PM2: $error');
          if (mounted) setState(() => _listError = errors.join('\n'));
        }
      }

      Future<void> loadServices() async {
        try {
          final result = convert(
            await api.getServicesList(timeout: const Duration(seconds: 15)),
          ).where((item) => item['type'] != 'pm2').toList();
          if (mounted) setState(() => _services = result);
        } catch (error) {
          errors.add('Service: $error');
          if (mounted) setState(() => _listError = errors.join('\n'));
        }
      }

      await Future.wait([loadPm2(), loadServices()]);
      if (mounted) {
        setState(() => _listError = errors.isEmpty ? null : errors.join('\n'));
      }
    } finally {
      _refreshingLists = false;
      if (mounted) setState(() => _listsLoading = false);
    }
  }

  Future<void> _runListAction(Map<String, dynamic> item, String action) async {
    final api = _api;
    final name = item['name']?.toString();
    if (api == null || name == null || name.isEmpty) return;
    final type = _tab == 0 ? 'pm2' : item['type']?.toString();
    if (type == null || type.isEmpty) return;
    if (item['controllable'] != true) return;
    final key = '$type:$name';
    if (_busyListItem != null) return;
    setState(() {
      _busyListItem = key;
      _notice = null;
    });
    try {
      if (type == 'pm2') {
        await api.pm2Action(name, action);
      } else {
        await api.serviceAction(type, name, action);
      }
      await _refreshLists();
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Gagal $action $name: $error');
      }
    } finally {
      if (mounted) setState(() => _busyListItem = null);
    }
  }

  Future<void> _showListLogs(Map<String, dynamic> item) async {
    final api = _api;
    final name = item['name']?.toString();
    final type = _tab == 0 ? 'pm2' : item['type']?.toString();
    if (api == null || name == null || name.isEmpty || type == null) return;
    try {
      await showLogViewer(context, api: api, type: type, name: name);
    } catch (error) {
      if (mounted) setState(() => _notice = 'Gagal membuka log: $error');
    }
  }

  // ── Mode & ukuran jendela ──────────────────────────────────────────────────
  void _handleTap() {
    _taps++;
    if (_taps >= 3) {
      _tapTimer?.cancel();
      _taps = 0;
      _setMode(_Mode.terminal);
      return;
    }
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(milliseconds: 450), () {
      final n = _taps;
      _taps = 0;
      if (n >= 3) {
        _setMode(_Mode.terminal);
      } else if (n == 2) {
        _setMode(_Mode.medium);
      } else {
        _setMode(_mode == _Mode.small ? _Mode.bubble : _Mode.small);
      }
    });
  }

  Future<void> _setMode(_Mode m, {bool force = false}) {
    final next = _modeTransition.then((_) => _applyMode(m, force: force));
    _modeTransition = next.catchError((Object error, StackTrace stackTrace) {
      debugPrint('Overlay mode change failed: $error');
    });
    return _modeTransition;
  }

  Future<void> _applyMode(_Mode m, {bool force = false}) async {
    if (m == _mode && !force) return;
    final previousMode = _mode;
    if (previousMode == _Mode.bubble && !_isPeeked) {
      try {
        _savedPos = await FlutterOverlayWindow.getOverlayPosition();
        if (_savedPos != null) await OverlayService.savePosition(_savedPos!);
      } catch (e) {
        debugPrint('Unable to save overlay position: $e');
      }
    }

    try {
      if (previousMode == _Mode.bubble && _isPeeked && m != _Mode.bubble) {
        await _restoreBubbleFromPeek();
      }
      await _configureWindow(m);
    } catch (e) {
      debugPrint('Unable to change overlay mode: $e');
      if (previousMode != _Mode.bubble || !_isPeeked) {
        try {
          await _configureWindow(previousMode);
        } catch (rollbackError) {
          debugPrint('Unable to restore overlay window: $rollbackError');
        }
      }
      if (mounted) {
        setState(() => _notice = 'Gagal mengubah ukuran overlay: $e');
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _mode = m;
      _notice = null;
      if (m == _Mode.bubble) _isPeeked = false;
    });

    // Data hanya mengalir saat panel terbuka.
    if (m == _Mode.bubble) {
      _stopSocket();
      _listTimer?.cancel();
      _startPositionTracking();
    } else {
      _positionTimer?.cancel();
      _edgeTimer?.cancel();
      _pendingRightEdge = null;
      _startSocket();
    }
    if (m == _Mode.medium) {
      _refreshLists();
      _listTimer?.cancel();
      _listTimer = Timer.periodic(
        const Duration(seconds: 12),
        (_) => _refreshLists(),
      );
    } else {
      _listTimer?.cancel();
    }
  }

  Future<void> _configureWindow(_Mode mode) async {
    final flag = mode == _Mode.terminal
        ? OverlayFlag.focusPointer
        : OverlayFlag.defaultFlag;
    if (await FlutterOverlayWindow.updateFlag(flag) == false) {
      throw StateError('Gagal mengatur fokus overlay');
    }

    switch (mode) {
      case _Mode.bubble:
        if (await FlutterOverlayWindow.resizeOverlay(
              _bubbleSize.round(),
              _bubbleSize.round(),
              true,
            ) ==
            false) {
          throw StateError('Gagal mengubah ukuran tombol overlay');
        }
        final position = _savedPos;
        if (position != null &&
            await FlutterOverlayWindow.moveOverlay(position) == false) {
          throw StateError('Gagal mengembalikan posisi tombol overlay');
        }
        break;
      case _Mode.small:
        final maxWidth = _screenWidth > 0
            ? (_screenWidth - 12).clamp(220, double.infinity).toDouble()
            : 600.0;
        final width = (292 * _panelScale).clamp(220, maxWidth).round();
        final height = (372 * _panelScale).round();
        if (await FlutterOverlayWindow.resizeOverlay(width, height, false) ==
            false) {
          throw StateError('Gagal membuka panel monitor');
        }
        await _positionPanel(width, height);
        break;
      case _Mode.medium:
        final maxWidth = _screenWidth > 0
            ? (_screenWidth - 12).clamp(220, double.infinity).toDouble()
            : 600.0;
        final width =
            ((_screenWidth > 0 ? _screenWidth * 0.92 : 340) * _panelScale)
                .clamp(220, maxWidth)
                .round();
        final height = (500 * _panelScale).round();
        if (await FlutterOverlayWindow.resizeOverlay(
              width,
              height,
              false,
            ) ==
            false) {
          throw StateError('Gagal membuka panel PM2/service');
        }
        await _positionPanel(width, height);
        break;
      case _Mode.terminal:
        final maxWidth = _screenWidth > 0
            ? (_screenWidth - 12).clamp(220, double.infinity).toDouble()
            : 600.0;
        final width =
            ((_screenWidth > 0 ? _screenWidth * 0.92 : 340) * _panelScale)
                .clamp(220, maxWidth)
                .round();
        final height = (500 * _panelScale).round();
        if (await FlutterOverlayWindow.resizeOverlay(width, height, false) ==
            false) {
          throw StateError('Gagal membuka terminal');
        }
        await _positionPanel(width, height);
        break;
    }
  }

  Future<void> _positionPanel(int width, int height) async {
    _panelWidth = width.toDouble();
    _panelHeight = height.toDouble();
    final current = await FlutterOverlayWindow.getOverlayPosition();
    final origin = _mode == _Mode.bubble ? (_savedPos ?? current) : current;
    final maxX = _screenWidth > 0
        ? (_screenWidth - width).clamp(0, double.infinity).toDouble()
        : double.infinity;
    final maxY = _screenHeight > 0
        ? (_screenHeight - height).clamp(0, double.infinity).toDouble()
        : double.infinity;
    final x = (origin.x + (_bubbleSize - width) / 2).clamp(0, maxX).toDouble();
    final y = (origin.y + (_bubbleSize - height) / 2).clamp(0, maxY).toDouble();
    final position = OverlayPosition(x, y);
    if (await FlutterOverlayWindow.moveOverlay(position) == false) {
      throw StateError('Gagal menempatkan panel overlay');
    }
    _panelPosition = position;
  }

  void _startPositionTracking() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _trackBubblePosition(),
    );
  }

  Future<void> _trackBubblePosition() async {
    if (_checkingPosition || !mounted || _mode != _Mode.bubble) return;
    if (_bubblePointer != null || _bubblePointerMoved || _bubbleDragActive) return;
    _checkingPosition = true;
    try {
      final position = await FlutterOverlayWindow.getOverlayPosition();
      if (!mounted || _mode != _Mode.bubble) return;
      if (_isPeeked) {
        final rightX = _screenWidth - _peekWidth;
        final draggedOut = _pendingRightEdge == true
            ? position.x < rightX - 3
            : position.x > 3;
        if (draggedOut) await _expandAfterDrag(position);
        return;
      }
      final saved = _savedPos;
      if (saved == null ||
          (saved.x - position.x).abs() >= 1 ||
          (saved.y - position.y).abs() >= 1) {
        _savedPos = position;
        await OverlayService.savePosition(position);
      }
      if (_screenWidth <= _bubbleSize) return;
      final left = position.x <= 2;
      final right = position.x >= _screenWidth - _bubbleSize - 2;
      if (!left && !right) {
        _edgeTimer?.cancel();
        _edgeTimer = null;
        _pendingRightEdge = null;
        return;
      }
      final rightEdge = right && !left;
      if (_pendingRightEdge == rightEdge && _edgeTimer != null) return;
      _edgeTimer?.cancel();
      _pendingRightEdge = rightEdge;
      _edgeTimer = Timer(const Duration(milliseconds: 450), () {
        _dockBubble(rightEdge);
      });
    } catch (e) {
      debugPrint('Unable to track overlay position: $e');
    } finally {
      _checkingPosition = false;
    }
  }

  Future<void> _dockBubble(bool rightEdge) async {
    _edgeTimer = null;
    if (!mounted || _mode != _Mode.bubble || _isPeeked) return;
    try {
      final position = await FlutterOverlayWindow.getOverlayPosition();
      final atEdge = rightEdge
          ? position.x >= _screenWidth - _bubbleSize - 3
          : position.x <= 3;
      if (!atEdge) return;
      _savedPos = OverlayPosition(
        rightEdge ? _screenWidth - _bubbleSize : 0,
        position.y,
      );
      await OverlayService.savePosition(_savedPos!);
      final width = _peekWidth.round();
      if (await FlutterOverlayWindow.resizeOverlay(
            width,
            _bubbleSize.round(),
            true,
          ) ==
          false) {
        throw StateError('Gagal membuat pegangan overlay');
      }
      final peekPosition = OverlayPosition(
        rightEdge ? _screenWidth - _peekWidth : 0,
        position.y,
      );
      if (await FlutterOverlayWindow.moveOverlay(peekPosition) == false) {
        throw StateError('Gagal menempelkan pegangan overlay');
      }
      _pendingRightEdge = rightEdge;
      _isPeeked = true;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Unable to dock overlay handle: $e');
      try {
        await FlutterOverlayWindow.resizeOverlay(
          _bubbleSize.round(),
          _bubbleSize.round(),
          true,
        );
        final position = _savedPos;
        if (position != null) {
          await FlutterOverlayWindow.moveOverlay(position);
        }
      } catch (restoreError) {
        debugPrint('Unable to restore full overlay button: $restoreError');
      }
      if (mounted)
        setState(() => _notice = 'Tombol belum bisa ditempelkan: $e');
    }
  }

  Future<void> _restoreBubbleFromPeek() async {
    if (!_isPeeked) return;
    final rightEdge = _pendingRightEdge == true;
    final current = await FlutterOverlayWindow.getOverlayPosition();
    final fullWidth = _bubbleSize.round();
    final position = _savedPos ??
        OverlayPosition(
          rightEdge ? _screenWidth - _bubbleSize : 0,
          current.y,
        );
    var resized = false;
    try {
      if (await FlutterOverlayWindow.resizeOverlay(
            fullWidth,
            fullWidth,
            true,
          ) ==
          false) {
        throw StateError('Gagal menampilkan kembali tombol overlay');
      }
      resized = true;
      if (await FlutterOverlayWindow.moveOverlay(position) == false) {
        throw StateError('Gagal mengembalikan tombol overlay');
      }
    } catch (_) {
      if (resized) {
        try {
          await FlutterOverlayWindow.resizeOverlay(
            _peekWidth.round(),
            fullWidth,
            true,
          );
          await FlutterOverlayWindow.moveOverlay(
            OverlayPosition(
              rightEdge ? _screenWidth - _peekWidth : 0,
              current.y,
            ),
          );
        } catch (rollbackError) {
          debugPrint('Unable to restore overlay handle: $rollbackError');
        }
      }
      rethrow;
    }
    _isPeeked = false;
    if (mounted) setState(() {});
  }

  Future<void> _expandAfterDrag(OverlayPosition current) async {
    final rightEdge = _pendingRightEdge == true;
    _edgeTimer?.cancel();
    _edgeTimer = null;
    final x = rightEdge ? current.x - (_bubbleSize - _peekWidth) : current.x;
    final position = OverlayPosition(x, current.y);
    try {
      if (await FlutterOverlayWindow.resizeOverlay(
            _bubbleSize.round(),
            _bubbleSize.round(),
            true,
          ) ==
          false) {
        throw StateError('Gagal memperbesar tombol setelah digeser');
      }
      if (await FlutterOverlayWindow.moveOverlay(position) == false) {
        throw StateError('Gagal memindahkan tombol setelah digeser');
      }
    } catch (e) {
      try {
        await FlutterOverlayWindow.resizeOverlay(
          _peekWidth.round(),
          _bubbleSize.round(),
          true,
        );
        await FlutterOverlayWindow.moveOverlay(
          OverlayPosition(
            rightEdge ? _screenWidth - _peekWidth : 0,
            current.y,
          ),
        );
      } catch (rollbackError) {
        debugPrint(
          'Unable to restore overlay handle after drag: $rollbackError',
        );
      }
      if (mounted) {
        setState(() => _notice = 'Gagal mengeluarkan tombol dari tepi: $e');
      }
      rethrow;
    }
    _savedPos = position;
    _isPeeked = false;
    _pendingRightEdge = null;
    await OverlayService.savePosition(position);
    if (mounted) setState(() {});
  }

  Future<void> _openApp() async {
    try {
      await AndroidIntent(
        action: 'android.intent.action.MAIN',
        category: 'android.intent.category.LAUNCHER',
        package: _appPackage,
        componentName: '$_appPackage.MainActivity',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
      await FlutterOverlayWindow.closeOverlay();
    } catch (e) {
      debugPrint('Unable to open RFMonitor from overlay: $e');
      if (mounted) {
        setState(
          () => _notice = 'Tidak bisa membuka aplikasi: $e',
        );
      }
    }
  }

  Future<void> _closeOverlay() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (error) {
      debugPrint('Unable to close overlay: $error');
      if (mounted) setState(() => _notice = 'Gagal menutup overlay: $error');
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    switch (_mode) {
      case _Mode.bubble:
        return _bubble();
      case _Mode.small:
        return _frame(title: 'MONITOR', body: _smallBody());
      case _Mode.medium:
        return _frame(title: 'PM2 · SERVICE', body: _mediumBody());
      case _Mode.terminal:
        return Container(
          color: Colors.black,
          child: TerminalScreen(
            embedded: true,
            defaultHost: _hostOf(_config),
            localHost: _config?.localHost ?? '',
            tailscaleHost: _config?.tailscaleHost ?? '',
            onClose: () => _setMode(_Mode.bubble),
            onCloseOverlay: _closeOverlay,
            windowDragRegion: _panelDragRegion,
          ),
        );
    }
  }

  Widget _panelDragRegion(Widget child) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _startPanelDrag,
        onPanUpdate: _updatePanelDrag,
        onPanEnd: _endPanelDrag,
        child: child,
      );

  String _hostOf(ServerConfig? c) {
    try {
      return c == null ? '' : Uri.parse(c.baseUrl).host;
    } catch (_) {
      return '';
    }
  }

  Widget _appIcon(double size) => ClipOval(
        child: Image.asset(
          'assets/icon/app_icon.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            Icons.monitor_heart_rounded,
            color: AppColors.neonCyan,
            size: size * 0.7,
          ),
        ),
      );

  Widget _bubble() {
    final online = _conn == SocketConnState.connected;
    if (_isPeeked) {
      final arrow = _pendingRightEdge == true
          ? Icons.chevron_left_rounded
          : Icons.chevron_right_rounded;
      return Center(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _bubblePointerDown,
          onPointerMove: _bubblePointerMove,
          onPointerUp: _bubblePointerUp,
          onPointerCancel: _bubblePointerCancel,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: _peekWidth,
            height: _bubbleSize,
            decoration: BoxDecoration(
              color: AppStyleKit.neoSurface,
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(
                  _pendingRightEdge == true ? _peekWidth * 0.6 : 0,
                ),
                right: Radius.circular(
                  _pendingRightEdge == true ? 0 : _peekWidth * 0.6,
                ),
              ),
              border: Border.all(color: AppColors.neonCyan, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.neonCyan,
                  offset: Offset(2, 2),
                  blurRadius: 0,
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) => SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.3, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                arrow,
                key: ValueKey(arrow),
                color: AppColors.neonCyan,
                size: (_peekWidth * 0.8).clamp(16, 29).toDouble(),
              ),
            ),
          ),
        ),
      );
    }
    BoxDecoration deco;
    if (AppStyleKit.isNeo) {
      deco = BoxDecoration(
        shape: BoxShape.circle,
        color: AppStyleKit.neoSurface,
        border: Border.all(color: AppStyleKit.neoInk, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: AppColors.neonCyan,
            offset: Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      );
    } else if (AppStyleKit.isMinimal) {
      deco = BoxDecoration(
        shape: BoxShape.circle,
        color: AppStyleKit.minimalSurface,
        border: Border.all(color: Colors.white24),
      );
    } else {
      deco = BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: Colors.white.withOpacity(0.45), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonCyan.withOpacity(0.55),
            blurRadius: 16,
            spreadRadius: -2,
          ),
        ],
      );
    }
    return Center(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _bubblePointerDown,
        onPointerMove: _bubblePointerMove,
        onPointerUp: _bubblePointerUp,
        onPointerCancel: _bubblePointerCancel,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: _bubbleSize,
              height: _bubbleSize,
              padding: const EdgeInsets.all(6),
              decoration: deco,
              child: _appIcon(_bubbleSize - 12),
            ),
            if (_socket != null)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: online ? AppColors.neonGreen : AppColors.roseRed,
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                ),
              ),
            if (_notice != null)
              const Positioned(
                left: 1,
                top: 1,
                child: Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.roseRed,
                  size: 16,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Bingkai panel: header (ikon app = ketuk 1/2/3×, tekan lama = buka app) + isi.
  Widget _frame({required String title, required Widget body}) {
    final online = _conn == SocketConnState.connected;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Container(
        decoration: AppStyleKit.card(accent: AppColors.neonCyan, radius: 18),
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        child: Column(
          children: [
            _panelDragRegion(
              Row(
                children: [
                  GestureDetector(
                    onTap: _handleTap,
                    onLongPress: _openApp,
                    child: Container(
                      width: 36,
                      height: 36,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: _appIcon(30),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          _config?.displayName ?? 'Belum ada server',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: online ? AppColors.neonGreen : AppColors.roseRed,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Jadikan tombol',
                    onPressed: () => _setMode(_Mode.bubble),
                    icon: const Icon(
                      Icons.remove_circle_outline_rounded,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Tutup',
                    onPressed: _closeOverlay,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.roseRed,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 10),
            Expanded(child: body),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _notice!,
                  style: const TextStyle(
                    color: AppColors.neonGold,
                    fontSize: 10.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Kotak kecil: statistik singkat ─────────────────────────────────────────
  Widget _smallBody() {
    final m = _m;
    if (_config == null) {
      return const Center(
        child: Text(
          'Konfigurasi server belum diterima.\nBuka app sekali lalu coba lagi.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }
    if (m == null) {
      return Center(
        child: Text(
          _conn == SocketConnState.disconnected
              ? 'Terputus — mencoba menyambung…'
              : 'Menghubungkan…',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }
    double d(dynamic x) => (x as num?)?.toDouble() ?? 0;
    final cpu = (m['cpu'] as Map?) ?? const {};
    final ram = (m['ram'] as Map?) ?? const {};
    final disk = (m['disk'] as Map?) ?? const {};
    final net = (m['network'] as Map?) ?? const {};
    final power = (m['power'] as Map?) ?? const {};
    final cores = ((cpu['perCore'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    final la = ((cpu['loadAvg'] as List?) ?? const [])
        .map((e) => (e as num).toStringAsFixed(2))
        .toList();
    final temp = cpu['tempC'] as num?;
    final watts = power['currentWatts'] as num?;
    final up = (m['uptimeSeconds'] as num?)?.toInt() ?? 0;

    String kbps(dynamic bytes) {
      final b = d(bytes);
      return b >= 1048576
          ? '${(b / 1048576).toStringAsFixed(1)} MB/s'
          : '${(b / 1024).toStringAsFixed(0)} KB/s';
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          _bar(
            'CPU',
            d(cpu['usagePercent']),
            '${d(cpu['usagePercent']).toStringAsFixed(0)}%',
            AppColors.roseRed,
          ),
          _bar(
            'RAM',
            d(ram['usedPercent']),
            'sisa ${RamMetrics.freeLabel(ram)}',
            AppColors.neonCyan,
          ),
          _bar(
            'DISK',
            d(disk['usedPercent']),
            'sisa ${d(disk['freeGB']).toStringAsFixed(1)} GB',
            AppColors.neonGold,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _kv(
                  'SUHU',
                  temp == null ? '--' : '${temp.toStringAsFixed(1)}°C',
                ),
              ),
              Expanded(
                child: _kv(
                  'DAYA',
                  watts == null ? '--' : '${watts.toStringAsFixed(1)} W',
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(child: _kv('↓', kbps(net['rxBytesPerSec']))),
              Expanded(child: _kv('↑', kbps(net['txBytesPerSec']))),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _kv(
                  'UPTIME',
                  '${up ~/ 86400}h ${(up ~/ 3600) % 24}j ${(up ~/ 60) % 60}m',
                ),
              ),
              Expanded(child: _kv('LOAD', la.isEmpty ? '--' : la.first)),
            ],
          ),
          if (cores.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (var i = 0; i < cores.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.roseRed.withOpacity(
                        0.10 + 0.30 * (cores[i] / 100),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'C$i ${cores[i]}%',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
            if (la.length == 3)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'load avg ${la.join(' / ')}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _bar(String label, double pct, String trailing, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 78,
            child: Text(
              trailing,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(
              '$k ',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10.5,
              ),
            ),
            Flexible(
              child: Text(
                v,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );

  // ── Panel sedang: PM2 + service ────────────────────────────────────────────
  Widget _mediumBody() {
    final list = _tab == 0 ? _pm2 : _services;
    Widget tab(String t, int i) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _tab = i),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _tab == i
                    ? AppColors.neonCyan.withOpacity(0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _tab == i ? AppColors.neonCyan : Colors.white12,
                ),
              ),
              child: Text(
                t,
                style: TextStyle(
                  color:
                      _tab == i ? AppColors.neonCyan : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );

    return Column(
      children: [
        Row(
          children: [
            tab('PM2 (${_pm2.length})', 0),
            const SizedBox(width: 6),
            tab('SERVICE (${_services.length})', 1),
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Muat ulang PM2 dan service',
              onPressed: _refreshingLists ? null : _refreshLists,
              icon: _listsLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.neonCyan,
                      ),
                    )
                  : const Icon(
                      Icons.refresh_rounded,
                      color: AppColors.neonCyan,
                      size: 20,
                    ),
            ),
          ],
        ),
        if (_listError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
              _listError!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.roseRed,
                fontSize: 10,
              ),
            ),
          ),
        const SizedBox(height: 6),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: _listsLoading
                      ? const CircularProgressIndicator(
                          color: AppColors.neonCyan,
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _listError == null
                                  ? 'Tidak ada data PM2/service.'
                                  : 'Belum ada data. Tekan muat ulang.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextButton.icon(
                              onPressed:
                                  _refreshingLists ? null : _refreshLists,
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Coba lagi'),
                            ),
                          ],
                        ),
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (_, i) => _row(list[i]),
                ),
        ),
      ],
    );
  }

  Widget _row(Map<String, dynamic> it) {
    final status = (it['status'] ?? '').toString();
    final ok = status == 'online';
    final bad = status == 'errored';
    final color = ok
        ? AppColors.neonGreen
        : (bad ? AppColors.roseRed : AppColors.neonGold);
    final cpu = it['cpuPercent'] as num?;
    final mem = it['memoryMB'] as num?;
    final extra = [
      if (it['type'] != null && it['type'] != 'pm2') '${it['type']}',
      if (cpu != null) 'CPU ${cpu.toStringAsFixed(1)}%',
      if (mem != null) '${mem.toStringAsFixed(0)} MB',
    ].join(' · ');
    final type = _tab == 0 ? 'pm2' : it['type']?.toString();
    final controllable = it['controllable'] == true;
    final busy = _busyListItem == '$type:${it['name']}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${it['name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (extra.isNotEmpty)
                      Text(
                        extra,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                status,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          if (busy)
            const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.neonCyan,
                ),
              ),
            )
          else
            Row(
              children: [
                if (controllable) ...[
                  _listActionButton('Start', it, 'start', AppColors.neonGreen),
                  const SizedBox(width: 4),
                  _listActionButton('Stop', it, 'stop', AppColors.roseRed),
                  const SizedBox(width: 4),
                  _listActionButton(
                    'Restart',
                    it,
                    'restart',
                    AppColors.neonCyan,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showListLogs(it),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.neonGold,
                      side: const BorderSide(color: AppColors.neonGold),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 5,
                      ),
                      minimumSize: Size.zero,
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Logs', style: TextStyle(fontSize: 10)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _listActionButton(
    String label,
    Map<String, dynamic> item,
    String action,
    Color color,
  ) {
    return Expanded(
      child: OutlinedButton(
        onPressed: () => _runListAction(item, action),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          minimumSize: Size.zero,
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: const TextStyle(fontSize: 10)),
      ),
    );
  }
}
