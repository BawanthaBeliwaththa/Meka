import 'dart:convert';
import 'package:flutter/services.dart';

/// Routes AI-generated action JSON commands to actual device operations
class DeviceSkillsService {
  static const MethodChannel _channel =
      MethodChannel('com.meka.assistant/device');

  /// Parse Gemini response and execute any embedded action commands
  /// Returns the text portion of the response (or the full string if not JSON)
  static Future<ActionResult> handleResponse(String response) async {
    // Try to extract JSON action from response
    final jsonMatch = RegExp(r'\{[^}]+\}').firstMatch(response);
    if (jsonMatch != null) {
      try {
        final json = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        final action = json['action'] as String?;
        if (action != null) {
          final textBeforeJson =
              response.substring(0, jsonMatch.start).trim();
          final result = await _execute(action, json);
          return ActionResult(
            text: textBeforeJson.isNotEmpty ? textBeforeJson : result.text,
            actionPerformed: result.actionPerformed,
            success: result.success,
          );
        }
      } catch (_) {
        // Not valid action JSON, treat as plain text
      }
    }
    return ActionResult(text: response, actionPerformed: false, success: true);
  }

  static Future<ActionResult> _execute(
      String action, Map<String, dynamic> params) async {
    try {
      switch (action) {
        case 'open_app':
          await _channel.invokeMethod('openApp', {'app': params['app']});
          return ActionResult(
            text: "Opening ${params['app']} now.",
            actionPerformed: true,
            success: true,
          );

        case 'set_alarm':
          await _channel.invokeMethod('setAlarm', {
            'hour': params['hour'],
            'minute': params['minute'],
            'label': params['label'] ?? 'Meka Alarm',
          });
          final h = params['hour'];
          final m = params['minute'].toString().padLeft(2, '0');
          final period = (h as int) >= 12 ? 'PM' : 'AM';
          final h12 = h > 12 ? h - 12 : h == 0 ? 12 : h;
          return ActionResult(
            text: "Alarm set for $h12:$m $period.",
            actionPerformed: true,
            success: true,
          );

        case 'send_sms':
          await _channel.invokeMethod('sendSms', {
            'to': params['to'],
            'message': params['message'],
          });
          return ActionResult(
            text: "Sending message to ${params['to']}.",
            actionPerformed: true,
            success: true,
          );

        case 'make_call':
          await _channel.invokeMethod('makeCall', {'to': params['to']});
          return ActionResult(
            text: "Calling ${params['to']}.",
            actionPerformed: true,
            success: true,
          );

        case 'set_volume':
          await _channel
              .invokeMethod('setVolume', {'level': params['level']});
          return ActionResult(
            text: "Volume set to ${params['level']}%.",
            actionPerformed: true,
            success: true,
          );

        case 'web_search':
          await _channel
              .invokeMethod('webSearch', {'query': params['query']});
          return ActionResult(
            text: "Searching for ${params['query']}.",
            actionPerformed: true,
            success: true,
          );

        case 'take_photo':
          await _channel.invokeMethod('takePhoto');
          return ActionResult(
            text: "Opening the camera.",
            actionPerformed: true,
            success: true,
          );

        case 'toggle_wifi':
          await _channel.invokeMethod('toggleWifi');
          return ActionResult(
            text: "Toggling Wi-Fi.",
            actionPerformed: true,
            success: true,
          );

        case 'toggle_bluetooth':
          await _channel.invokeMethod('toggleBluetooth');
          return ActionResult(
            text: "Toggling Bluetooth.",
            actionPerformed: true,
            success: true,
          );

        default:
          return ActionResult(
            text: "I understood the command but couldn't execute it yet.",
            actionPerformed: false,
            success: false,
          );
      }
    } on PlatformException catch (e) {
      return ActionResult(
        text: "I tried but couldn't do that: ${e.message}",
        actionPerformed: true,
        success: false,
      );
    }
  }
}

class ActionResult {
  final String text;
  final bool actionPerformed;
  final bool success;

  ActionResult({
    required this.text,
    required this.actionPerformed,
    required this.success,
  });
}
