import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/notification_service.dart';
import 'home_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    _initVideoAndBootstrap();
  }

  Future<void> _initVideoAndBootstrap() async {
    _initializeNotifications();

    if (!Platform.isWindows) {
      final videoController = VideoPlayerController.asset(
        'assets/video/splash_video.mp4',
      );
      _videoController = videoController;
      try {
        await videoController.initialize().timeout(
              const Duration(seconds: 4),
            );
        videoController.setLooping(false);
        videoController.setVolume(1.0);

        if (mounted) {
          setState(() => _isVideoInitialized = true);
          await videoController.play();
        }
      } catch (e) {
        debugPrint('Error loading splash video: $e');
      }
    }

    if (_isVideoInitialized) {
      final remainingDuration =
          _videoController!.value.duration - _videoController!.value.position;
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

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeShell()),
    );
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
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isVideoInitialized
          ? SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            )
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/icon/app_icon.png',
                      width: 132,
                      height: 132,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'RFMonitor',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF00F2FE),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
