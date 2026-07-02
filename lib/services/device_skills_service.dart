import 'dart:convert';
import 'dart:io';
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

        case 'list_files':
          final path = params['path'] ?? '/sdcard/Download';
          try {
            final dir = Directory(path);
            if (await dir.exists()) {
              final list = dir.listSync().take(15).map((e) => e.path.split('/').last).join(', ');
              return ActionResult(
                text: "Here are the files in $path: $list",
                actionPerformed: true,
                success: true,
              );
            } else {
              return ActionResult(
                text: "The directory $path does not exist.",
                actionPerformed: true,
                success: false,
              );
            }
          } catch (e) {
            return ActionResult(
              text: "Could not access files: $e",
              actionPerformed: true,
              success: false,
            );
          }

        case 'read_file_content':
          final path = params['path'];
          if (path == null) {
            return ActionResult(text: "No file path specified.", actionPerformed: true, success: false);
          }
          try {
            final file = File(path);
            if (await file.exists()) {
              final content = await file.readAsString();
              final truncated = content.length > 500 ? content.substring(0, 500) + "..." : content;
              return ActionResult(
                text: "The content of $path is:\n$truncated",
                actionPerformed: true,
                success: true,
              );
            } else {
              return ActionResult(
                text: "File $path not found.",
                actionPerformed: true,
                success: false,
              );
            }
          } catch (e) {
            return ActionResult(
              text: "Could not read file: $e",
              actionPerformed: true,
              success: false,
            );
          }

        case 'find_files':
          final query = (params['query'] as String?)?.toLowerCase();
          if (query == null) {
            return ActionResult(text: "No query specified.", actionPerformed: true, success: false);
          }
          try {
            final List<String> found = [];
            final searchDirs = ['/sdcard/Download', '/sdcard/Documents', '/sdcard/DCIM'];
            for (final dPath in searchDirs) {
              final dir = Directory(dPath);
              if (await dir.exists()) {
                await for (final entity in dir.list(recursive: true, followLinks: false)) {
                  final name = entity.path.split('/').last.toLowerCase();
                  if (name.contains(query)) {
                    found.add(entity.path);
                    if (found.length >= 10) break;
                  }
                }
              }
              if (found.length >= 10) break;
            }
            final resultText = found.isEmpty
                ? "No files found matching '$query'."
                : "Found files:\n" + found.join('\n');
            return ActionResult(
              text: resultText,
              actionPerformed: true,
              success: true,
            );
          } catch (e) {
            return ActionResult(
              text: "Failed to search files: $e",
              actionPerformed: true,
              success: false,
            );
          }

        case 'request_battery_optimization_ignore':
          await _channel.invokeMethod('ignoreBatteryOptimizations');
          return ActionResult(
            text: "Requesting battery optimization exclusion.",
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

  static Future<ActionResult> handleOfflineCommand(String command) async {
    final query = command.toLowerCase().trim();

    // 1. Open App Skill
    final openMatch = RegExp(r'(?:open|launch)\s+([a-zA-Z0-9\s]+)').firstMatch(query);
    if (openMatch != null) {
      final appName = openMatch.group(1)!.trim();
      return _execute('open_app', {'app': appName});
    }

    // 2. Set Alarm Skill
    final alarmMatch = RegExp(r'set\s+alarm\s+for\s+(\d+)(?::(\d+))?\s*(am|pm)?').firstMatch(query);
    if (alarmMatch != null) {
      int hour = int.parse(alarmMatch.group(1)!);
      int minute = alarmMatch.group(2) != null ? int.parse(alarmMatch.group(2)!) : 0;
      final amPm = alarmMatch.group(3);
      if (amPm != null) {
        if (amPm == 'pm' && hour < 12) hour += 12;
        if (amPm == 'am' && hour == 12) hour = 0;
      }
      return _execute('set_alarm', {
        'hour': hour,
        'minute': minute,
        'label': 'Offline Alarm',
      });
    }

    // 3. Make Call Skill
    final callMatch = RegExp(r'(?:call|dial)\s+([a-zA-Z0-9\s+]+)').firstMatch(query);
    if (callMatch != null) {
      final target = callMatch.group(1)!.trim();
      return _execute('make_call', {'to': target});
    }

    // 4. Send SMS Skill
    final smsMatch = RegExp(r'(?:send\s+message\s+to|message|sms)\s+([a-zA-Z0-9\s+]+)\s+(?:saying|texting)?\s*(.+)').firstMatch(query);
    if (smsMatch != null) {
      final to = smsMatch.group(1)!.trim();
      final message = smsMatch.group(2)!.trim();
      return _execute('send_sms', {'to': to, 'message': message});
    }

    // 5. Set Volume Skill
    final volMatch = RegExp(r'set\s+volume\s+to\s+(\d+)').firstMatch(query);
    if (volMatch != null) {
      final level = int.parse(volMatch.group(1)!);
      return _execute('set_volume', {'level': level});
    }

    // 6. Generic Offline Response
    if (query.contains('hello') || query.contains('hi')) {
      return ActionResult(
        text: "Hello! I am Meka. I am offline, but I can still launch apps, set alarms, or make calls.",
        actionPerformed: false,
        success: true,
      );
    } else if (query.contains('who are you') || query.contains('your name')) {
      return ActionResult(
        text: "I am Meka, your personal offline assistant.",
        actionPerformed: false,
        success: true,
      );
    } else if (query.contains('how are you')) {
      return ActionResult(
        text: "I'm doing well, running completely locally on your system.",
        actionPerformed: false,
        success: true,
      );
    }

    return ActionResult(
      text: "I couldn't understand that command offline. You can say 'open contacts', 'set alarm for 7:30 am', 'call Mom', or 'set volume to 80'.",
      actionPerformed: false,
      success: false,
    );
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
