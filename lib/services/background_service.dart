import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tts_service.dart';
import 'stt_service.dart';
import 'llm_service.dart';

class MekaBackgroundService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  static Future<void> initialize() async {
    final FlutterLocalNotificationsPlugin notifications =
        FlutterLocalNotificationsPlugin();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'meka_foreground',
      'Meka Assistant',
      description: 'Meka is listening for your voice',
      importance: Importance.low,
    );

    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'meka_foreground',
        initialNotificationTitle: 'Meka is ready',
        initialNotificationContent: 'Say "Hey Meka" to get started',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
      ),
    );

    await _service.startService();
  }

  static Future<void> stop() async {
    await _service.invoke('stop');
  }

  static ServiceInstance? _instance;

  static Future<void> onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    _instance = service;

    service.on('stop').listen((_) {
      service.stopSelf();
    });

    service.on('speak').listen((data) async {
      if (data != null && data['text'] != null) {
        final tts = TtsService();
        await tts.speak(data['text'] as String);
      }
    });

    // Update notification periodically
    Timer.periodic(const Duration(seconds: 30), (_) async {
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Meka is listening',
          content: 'Say "Hey Meka" anytime',
        );
      }
    });
  }

  static FlutterBackgroundService get instance => _service;

  static void sendToUI(String event, Map<String, dynamic> data) {
    _instance?.invoke(event, data);
  }
}
