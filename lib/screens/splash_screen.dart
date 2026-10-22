import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/server_config.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import 'home_shell.dart';
import 'settings_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late VideoPlayerController _videoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    _initVideoAndBootstrap();
  }

  Future<void> _initVideoAndBootstrap() async {
    _videoController = VideoPlayerController.asset(
      'assets/video/splash_video.mp4',
    );
    final profilesFuture = _loadProfiles();
    _initializeNotifications();

    try {
      await _videoController.initialize().timeout(const Duration(seconds: 4));
      _videoController.setLooping(false);
      _videoController.setVolume(1.0);

      if (mounted) {
        setState(() => _isVideoInitialized = true);
        await _videoController.play();
      }
    } catch (e) {
      debugPrint('Error loading splash video: $e');
    }

    final profiles = await profilesFuture;

    // Tunggu sampai video selesai diputar
    if (_isVideoInitialized) {
      final remainingDuration =
          _videoController.value.duration - _videoController.value.position;
      if (remainingDuration > Duration.zero) {
        await Future.delayed(
          remainingDuration > const Duration(seconds: 7)
              ? const Duration(seconds: 7)
              : remainingDuration,
        );
      }
    } else {
      await Future.delayed(const Duration(milliseconds: 700));
    }

    if (!mounted) return;

    // Navigasi ke halaman utama
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => profiles == null || profiles.isNotEmpty
            ? const HomeShell()
            : const SettingsScreen(firstRun: true),
      ),
    );
  }

  Future<List<ServerConfig>?> _loadProfiles() async {
    try {
      return await StorageService().loadProfiles().timeout(
            const Duration(seconds: 5),
          );
    } catch (e) {
      debugPrint('Error loading saved server profiles: $e');
      return null;
    }
  }

  void _initializeNotifications() {
    NotificationService.instance
        .init()
        .timeout(const Duration(seconds: 4))
        .catchError((Object error) {
      debugPrint('Notification initialization failed: $error');
    });
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isVideoInitialized
          ? SizedBox.expand(
              child: FittedBox(
                fit: BoxFit
                    .cover, // Memaksa video Fullscreen (Crop halus di bagian tepi)
                child: SizedBox(
                  width: _videoController.value.size.width,
                  height: _videoController.value.size.height,
                  child: VideoPlayer(_videoController),
                ),
              ),
            )
          : const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00F2FE)),
              ),
            ),
    );
  }
}
