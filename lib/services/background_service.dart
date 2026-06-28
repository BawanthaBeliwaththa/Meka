import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tts_service.dart';

class MekaBackgroundService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  static Future<void> initialize() async {
    final FlutterLocalNotificationsPlugin notifications =
        FlutterLocalNotificationsPlugin();

    // SILENT channel — no sound, no vibration, no lights, lowest importance
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'meka_silent',
      'Meka Assistant',
      description: 'Meka is ready',
      importance: Importance.min,
      playSound: false,
      enableVibration: false,
      enableLights: false,
      showBadge: false,
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
        notificationChannelId: 'meka_silent',
        initialNotificationTitle: 'Meka',
        initialNotificationContent: '',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.microphone],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
      ),
    );

    await _service.startService();
  }

  static ServiceInstance? _instance;

  static Future<void> onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    _instance = service;

    service.on('stop').listen((_) => service.stopSelf());

    service.on('speak').listen((data) async {
      if (data != null && data['text'] != null) {
        await TtsService().speak(data['text'] as String);
      }
    });
  }

  static void stop() => _instance?.invoke('stop');

  static FlutterBackgroundService get instance => _service;
}
