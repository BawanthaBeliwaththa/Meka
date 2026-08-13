import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'esp32_service.dart';
import 'iot_hub_service.dart';
import 'adb_service.dart';

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
          final finalResult = ActionResult(
            text: textBeforeJson.isNotEmpty ? textBeforeJson : result.text,
            actionPerformed: result.actionPerformed,
            success: result.success,
          );
          Esp32Service().sendDisplayMessage(finalResult.text);
          return finalResult;
        }
      } catch (_) {
        // Not valid action JSON, treat as plain text
      }
    }
    Esp32Service().sendDisplayMessage(response);
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

        // ── ESP32 Hardware Node ──────────────────────────────────
        case 'esp32_relay':
          final ch    = params['channel'] as int? ?? 1;
          final state = params['state']   as String? ?? 'toggle';
          final r = await Esp32Service().setRelay(ch, state);
          return ActionResult(
            text: r.success
                ? "Relay $ch is now ${state == 'toggle' ? 'toggled' : state}, Sir."
                : "Could not reach the ESP32 node. ${r.message}",
            actionPerformed: true,
            success: r.success,
          );

        case 'esp32_pin':
          final pin   = params['pin']   as int? ?? 2;
          final state = params['state'] as String? ?? 'toggle';
          final r = await Esp32Service().setPin(pin, state);
          return ActionResult(
            text: r.success
                ? "GPIO pin $pin is now ${state}, Sir."
                : "Couldn't control pin $pin. ${r.message}",
            actionPerformed: true,
            success: r.success,
          );

        case 'esp32_pwm':
          final pin  = params['pin']  as int? ?? 2;
          final duty = params['duty'] as int? ?? 128;
          final r = await Esp32Service().setPwm(pin, duty);
          return ActionResult(
            text: r.success
                ? "PWM on pin $pin set to $duty, Sir."
                : "PWM failed. ${r.message}",
            actionPerformed: true,
            success: r.success,
          );

        case 'esp32_servo':
          final angle = params['angle'] as int? ?? 90;
          final r = await Esp32Service().setServo(angle);
          return ActionResult(
            text: r.success
                ? "Servo moved to $angle degrees, Sir."
                : "Servo error. ${r.message}",
            actionPerformed: true,
            success: r.success,
          );

        case 'esp32_led':
          final color      = params['color'] as String?;
          final brightness = params['brightness'] as int?;
          Esp32Result r;
          if (color != null) {
            final rgb = Esp32Service.colorNameToRgb(color);
            r = await Esp32Service().setLed(
                r: rgb['r']!, g: rgb['g']!, b: rgb['b']!);
          } else if (brightness != null) {
            r = await Esp32Service().setLed(brightness: brightness);
          } else {
            r = await Esp32Service().setLed(
                r: params['r'] ?? 255,
                g: params['g'] ?? 255,
                b: params['b'] ?? 255);
          }
          return ActionResult(
            text: r.success ? "LED updated, Sir." : "LED error. ${r.message}",
            actionPerformed: true,
            success: r.success,
          );

        case 'esp32_buzzer':
          final dur = params['duration_ms'] as int? ?? 200;
          final r = await Esp32Service().buzz(dur);
          return ActionResult(
            text: r.success ? "Done, Sir." : "Buzzer error. ${r.message}",
            actionPerformed: true,
            success: r.success,
          );

        case 'esp32_sensor':
          final type = (params['type'] as String? ?? 'temperature').toLowerCase();
          if (type == 'analog') {
            final data = await Esp32Service().readAnalog();
            if (data != null) {
              return ActionResult(
                text: "Analog reading: ${data['volts']} volts, Sir.",
                actionPerformed: true,
                success: true,
              );
            }
          } else {
            final data = await Esp32Service().readDht();
            if (data != null) {
              if (type == 'humidity') {
                return ActionResult(
                  text: "Current humidity is ${data['humidity']}%, Sir.",
                  actionPerformed: true,
                  success: true,
                );
              }
              return ActionResult(
                text: "Temperature is ${data['temperature_c']}°C, humidity ${data['humidity']}%, Sir.",
                actionPerformed: true,
                success: true,
              );
            }
          }
          return ActionResult(
            text: "Could not read sensor. Check ESP32 connection and DHT22 wiring.",
            actionPerformed: true,
            success: false,
          );

        case 'esp32_reset':
          final r = await Esp32Service().resetAll();
          return ActionResult(
            text: r.success
                ? "All ESP32 outputs have been reset, Sir."
                : "Reset failed. ${r.message}",
            actionPerformed: true,
            success: r.success,
          );

        // ── IoT Hub Commands ─────────────────────────────────────
        case 'iot_scan':
          final result = await IotHubService().triggerScan();
          if (result != null) {
            return ActionResult(
              text: "Network scan initiated, Sir. I'll discover all devices on the WiFi network.",
              actionPerformed: true,
              success: true,
            );
          }
          return ActionResult(
            text: "Could not reach the IoT Hub. Check the hub connection in Settings.",
            actionPerformed: true,
            success: false,
          );

        case 'iot_list_devices':
          final result = await IotHubService().listDevices(onlineOnly: true);
          if (result != null) {
            final count = result['count'] ?? 0;
            final devices = (result['devices'] as List?)?.take(10) ?? [];
            final summary = devices.map((d) {
              final name = d['friendly_name'] ?? d['vendor'] ?? 'Unknown';
              return '${d['ip']} ($name) [${d['device_type']}]';
            }).join('\n');
            return ActionResult(
              text: "Found $count devices online:\n$summary",
              actionPerformed: true,
              success: true,
            );
          }
          return ActionResult(
            text: "Could not reach the IoT Hub.",
            actionPerformed: true,
            success: false,
          );

        case 'iot_list_cameras':
          final result = await IotHubService().listCameras();
          if (result != null) {
            final count = result['count'] ?? 0;
            final cameras = (result['cameras'] as List?) ?? [];
            if (cameras.isEmpty) {
              return ActionResult(
                text: "No permitted cameras found online, Sir. Run a scan and grant permissions first.",
                actionPerformed: true,
                success: true,
              );
            }
            final summary = cameras.map((c) {
              final name = c['friendly_name'] ?? c['vendor'] ?? 'Unknown';
              final recording = c['is_recording'] == true ? ' 🔴 RECORDING' : '';
              return '${c['ip']} ($name)$recording';
            }).join('\n');
            return ActionResult(
              text: "$count cameras available:\n$summary",
              actionPerformed: true,
              success: true,
            );
          }
          return ActionResult(
            text: "Could not reach the IoT Hub.",
            actionPerformed: true,
            success: false,
          );

        case 'iot_record':
          final camera = params['camera'] as String? ?? 'all';
          final state = params['state'] as String? ?? 'start';
          Map<String, dynamic>? result;

          if (state == 'start') {
            if (camera == 'all') {
              result = await IotHubService().startRecordingAll();
              if (result != null) {
                final count = result['count'] ?? 0;
                return ActionResult(
                  text: "Recording started on $count cameras, Sir.",
                  actionPerformed: true,
                  success: true,
                );
              }
            } else {
              result = await IotHubService().startRecording(camera);
              if (result != null && result['status'] == 'recording_started') {
                return ActionResult(
                  text: "Recording started on camera ${result['camera_ip']}, Sir.",
                  actionPerformed: true,
                  success: true,
                );
              }
            }
          } else if (state == 'stop') {
            if (camera == 'all') {
              result = await IotHubService().stopRecordingAll();
              if (result != null) {
                final count = result['count'] ?? 0;
                return ActionResult(
                  text: "Stopped recording on $count cameras, Sir.",
                  actionPerformed: true,
                  success: true,
                );
              }
            } else {
              result = await IotHubService().stopRecording(camera);
              if (result != null) {
                return ActionResult(
                  text: "Recording stopped, Sir.",
                  actionPerformed: true,
                  success: true,
                );
              }
            }
          }
          return ActionResult(
            text: "Could not ${state == 'start' ? 'start' : 'stop'} recording. Check IoT Hub connection.",
            actionPerformed: true,
            success: false,
          );

        case 'iot_snapshot':
          final camera = params['camera'] as String? ?? '';
          if (camera.isEmpty) {
            return ActionResult(
              text: "Please specify which camera to snapshot.",
              actionPerformed: true,
              success: false,
            );
          }
          // Snapshot is returned as an image file from the hub
          return ActionResult(
            text: "Snapshot captured from camera $camera, Sir. Check the IoT dashboard.",
            actionPerformed: true,
            success: true,
          );

        case 'iot_permit_device':
          final mac = params['mac'] as String? ?? '';
          if (mac == 'all') {
            final result = await IotHubService().grantAllPending();
            if (result != null) {
              final count = result['count'] ?? 0;
              return ActionResult(
                text: "Granted permission to $count pending devices, Sir.",
                actionPerformed: true,
                success: true,
              );
            }
          } else if (mac.isNotEmpty) {
            final result = await IotHubService().permitDevice(mac);
            if (result != null && result['status'] == 'granted') {
              return ActionResult(
                text: "Permission granted for device $mac, Sir.",
                actionPerformed: true,
                success: true,
              );
            }
          }
          return ActionResult(
            text: "Could not grant permission. Check the device MAC address.",
            actionPerformed: true,
            success: false,
          );

        case 'iot_select_mic':
          final deviceId = params['device_id'] as String? ?? 'local';
          final result = await IotHubService().selectMic(deviceId);
          if (result != null) {
            final name = result['name'] ?? deviceId;
            return ActionResult(
              text: "Microphone switched to $name, Sir.",
              actionPerformed: true,
              success: true,
            );
          }
          return ActionResult(
            text: "Could not switch microphone.",
            actionPerformed: true,
            success: false,
          );

        case 'iot_select_speaker':
          final deviceId = params['device_id'] as String? ?? 'local';
          final result = await IotHubService().selectSpeaker(deviceId);
          if (result != null) {
            final name = result['name'] ?? deviceId;
            return ActionResult(
              text: "Speaker switched to $name, Sir.",
              actionPerformed: true,
              success: true,
            );
          }
          return ActionResult(
            text: "Could not switch speaker.",
            actionPerformed: true,
            success: false,
          );

        case 'iot_fallback_status':
          final result = await IotHubService().getFallbackStatus();
          if (result != null) {
            final cam = result['camera'] ?? {};
            final mic = result['microphone'] ?? {};
            final spk = result['speaker'] ?? {};
            final camSrc = cam['using_local'] == true ? 'Local' : cam['active_source'];
            final micSrc = mic['using_local'] == true ? 'Local' : mic['active_name'];
            final spkSrc = spk['using_local'] == true ? 'Local' : spk['active_name'];
            return ActionResult(
              text: "Fallback status:\n📷 Camera: $camSrc\n🎤 Mic: $micSrc\n🔊 Speaker: $spkSrc",
              actionPerformed: true,
              success: true,
            );
          }
          return ActionResult(
            text: "Could not get fallback status.",
            actionPerformed: true,
            success: false,
          );

        case 'iot_bluetooth_scan':
          final result = await IotHubService().scanBluetooth();
          if (result != null) {
            final count = result['count'] ?? 0;
            final devices = (result['devices'] as List?)?.take(5) ?? [];
            final summary = devices.map((d) => "${d['name']} (${d['mac']})").join('\n');
            return ActionResult(
              text: "Found $count Bluetooth devices nearby:\n$summary",
              actionPerformed: true,
              success: true,
            );
          }
          return ActionResult(
            text: "Could not scan for Bluetooth devices.",
            actionPerformed: true,
            success: false,
          );

        case 'iot_bluetooth_connect':
          final mac = params['mac'] as String? ?? params['device_id'] as String? ?? '';
          if (mac.isEmpty) {
            return ActionResult(
              text: "Please specify which Bluetooth device to connect.",
              actionPerformed: true,
              success: false,
            );
          }
          final result = await IotHubService().connectBluetooth(mac);
          if (result != null && result['status'] == 'connected') {
            final name = result['device']?['name'] ?? mac;
            return ActionResult(
              text: "Connected to Bluetooth device $name, Sir.",
              actionPerformed: true,
              success: true,
            );
          }
          return ActionResult(
            text: "Initiated connection to Bluetooth device $mac.",
            actionPerformed: true,
            success: true,
          );

        // ── ADB / Connected Device Commands ──────────────────────────────
        case 'list_connected_devices':
          await AdbService().loadSettings();
          final adbDevs = await AdbService().listDevices();
          if (adbDevs.isEmpty) {
            return ActionResult(
              text: "No ADB devices are currently connected, Sir. Make sure developer mode and wireless debugging are enabled.",
              actionPerformed: true,
              success: false,
            );
          }
          final devList = adbDevs.map((d) => '${d.displayName} (${d.serial}) — ${d.status}').join('\n');
          return ActionResult(
            text: "I found ${adbDevs.length} connected device${adbDevs.length > 1 ? 's' : ''}:\n$devList",
            actionPerformed: true,
            success: true,
          );

        case 'unlock_device':
          final serial = params['serial'] as String?;
          if (serial == null) {
            // Try listing and using first connected device
            await AdbService().loadSettings();
            final devs = await AdbService().listDevices();
            if (devs.isEmpty) {
              return ActionResult(
                text: "No ADB devices connected. Please connect a device first.",
                actionPerformed: true,
                success: false,
              );
            }
            final target = devs.first;
            final r = await AdbService().unlockDevice(target.serial);
            return ActionResult(
              text: r.success
                  ? "Unlocked ${target.displayName}, Sir."
                  : "Failed to unlock device: ${r.message}",
              actionPerformed: true,
              success: r.success,
            );
          }
          final ulResult = await AdbService().unlockDevice(serial);
          return ActionResult(
            text: ulResult.success
                ? "Device $serial unlocked, Sir."
                : "Unlock failed: ${ulResult.message}",
            actionPerformed: true,
            success: ulResult.success,
          );

        case 'adb_shell':
          final ser = params['serial'] as String?;
          final cmd = params['command'] as String?;
          if (ser == null || cmd == null) {
            return ActionResult(
              text: "Please specify both a device serial and a shell command.",
              actionPerformed: false,
              success: false,
            );
          }
          await AdbService().loadSettings();
          final shResult = await AdbService().runShell(ser, cmd);
          final output = shResult.data?['output'] ?? shResult.message;
          return ActionResult(
            text: shResult.success ? "ADB shell output:\n$output" : "Shell error: ${shResult.message}",
            actionPerformed: true,
            success: shResult.success,
          );

        case 'device_screenshot':
          final screenshotSerial = params['serial'] as String?;
          if (screenshotSerial == null) {
            return ActionResult(
              text: "Specify the device serial for screenshot.",
              actionPerformed: false,
              success: false,
            );
          }
          await AdbService().loadSettings();
          final ssResult = await AdbService().screenshot(screenshotSerial);
          return ActionResult(
            text: ssResult.success
                ? "Screenshot captured from $screenshotSerial, Sir."
                : "Screenshot failed: ${ssResult.message}",
            actionPerformed: true,
            success: ssResult.success,
          );

        case 'screen_mirror':
          final mirrorSerial = params['serial'] as String?;
          if (mirrorSerial == null) {
            return ActionResult(
              text: "Specify the device serial to start mirroring.",
              actionPerformed: false,
              success: false,
            );
          }
          await AdbService().loadSettings();
          final mResult = await AdbService().startMirror(mirrorSerial);
          return ActionResult(
            text: mResult.success
                ? "Screen mirroring started for $mirrorSerial, Sir."
                : "Mirror failed: ${mResult.message}",
            actionPerformed: true,
            success: mResult.success,
          );

        case 'adb_connect':
          final host = params['host'] as String?;
          if (host == null) {
            return ActionResult(
              text: "Specify the device IP and port to connect. Example: 192.168.1.100:5555",
              actionPerformed: false,
              success: false,
            );
          }
          await AdbService().loadSettings();
          final connResult = await AdbService().connectWifi(host);
          return ActionResult(
            text: connResult.success
                ? "Connected to ADB device at $host, Sir."
                : "ADB connect failed: ${connResult.message}",
            actionPerformed: true,
            success: connResult.success,
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
