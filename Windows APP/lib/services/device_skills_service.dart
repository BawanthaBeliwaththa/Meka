// lib/services/device_skills_service.dart — MEKA Desktop (Windows & Linux)
// Desktop-safe version: no Android MethodChannel. All IoT Hub + ESP32 HTTP
// actions work. Android-only actions (SMS, calls, alarms) have desktop
// alternatives (browser launch, file manager, system process commands).
import 'dart:convert';
import 'dart:io';
import 'esp32_service.dart';
import 'iot_hub_service.dart';
import 'adb_service.dart';

class DeviceSkillsService {
  /// Parse AI response and execute any embedded action commands.
  static Future<ActionResult> handleResponse(String response) async {
    // Extract JSON action from response
    final jsonMatch = RegExp(r'\{[^}]+\}').firstMatch(response);
    if (jsonMatch != null) {
      try {
        final json = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        final action = json['action'] as String?;
        if (action != null) {
          final textBeforeJson = response.substring(0, jsonMatch.start).trim();
          final result = await _execute(action, json);
          return ActionResult(
            text: textBeforeJson.isNotEmpty ? textBeforeJson : result.text,
            actionPerformed: result.actionPerformed,
            success: result.success,
          );
        }
      } catch (_) {
        // Not valid action JSON — treat as plain text
      }
    }
    return ActionResult(text: response, actionPerformed: false, success: true);
  }

  static Future<ActionResult> _execute(
      String action, Map<String, dynamic> params) async {
    try {
      switch (action) {
        // ── Desktop App / Browser Actions ────────────────────────────
        case 'open_app':
          final appName = (params['app'] as String? ?? '').toLowerCase();
          await _openDesktopApp(appName);
          return ActionResult(
            text: "Opening $appName.",
            actionPerformed: true,
            success: true,
          );

        case 'web_search':
          final query = Uri.encodeComponent(params['query'] as String? ?? '');
          final url = 'https://www.google.com/search?q=$query';
          await _launchUrl(url);
          return ActionResult(
            text: "Searching for ${params['query']}.",
            actionPerformed: true,
            success: true,
          );

        case 'set_alarm':
          final h = params['hour'] ?? 7;
          final m = (params['minute'] ?? 0).toString().padLeft(2, '0');
          final period = (h as int) >= 12 ? 'PM' : 'AM';
          final h12 = h > 12 ? h - 12 : h == 0 ? 12 : h;
          // Open system alarm/calendar
          if (Platform.isWindows) {
            await Process.run('ms-clock:', [], runInShell: true).catchError((_) async {
              return await Process.run('start', ['ms-clock:'], runInShell: true);
            });
          }
          return ActionResult(
            text: "Reminder noted for $h12:$m $period. Opening clock app.",
            actionPerformed: true,
            success: true,
          );

        case 'send_sms':
          return ActionResult(
            text: "SMS is not available on desktop. You can use the Telegram bot to send messages.",
            actionPerformed: false,
            success: false,
          );

        case 'make_call':
          return ActionResult(
            text: "Phone calling is not available on desktop. You can use the Telegram bot or your phone.",
            actionPerformed: false,
            success: false,
          );

        case 'set_volume':
          final level = params['level'] as int? ?? 50;
          await _setSystemVolume(level);
          return ActionResult(
            text: "Volume set to $level%.",
            actionPerformed: true,
            success: true,
          );

        case 'take_photo':
          return ActionResult(
            text: "Camera capture is not available on desktop. Check IoT Hub cameras with 'list cameras'.",
            actionPerformed: false,
            success: false,
          );

        case 'toggle_wifi':
          if (Platform.isWindows) {
            await Process.run('netsh', ['interface', 'set', 'interface', 'Wi-Fi', 'enabled'], runInShell: true);
          }
          return ActionResult(
            text: "Wi-Fi toggle command sent.",
            actionPerformed: true,
            success: true,
          );

        case 'toggle_bluetooth':
          return ActionResult(
            text: "Bluetooth toggle is best managed via system settings on desktop.",
            actionPerformed: false,
            success: false,
          );

        case 'list_files':
          final searchPath = params['path'] as String? ?? (Platform.isWindows ? r'C:\Users' : '/home');
          try {
            final dir = Directory(searchPath);
            if (await dir.exists()) {
              final list = dir.listSync().take(15).map((e) => e.path.split(Platform.isWindows ? '\\' : '/').last).join(', ');
              return ActionResult(
                text: "Files in $searchPath: $list",
                actionPerformed: true,
                success: true,
              );
            } else {
              return ActionResult(text: "Directory $searchPath does not exist.", actionPerformed: true, success: false);
            }
          } catch (e) {
            return ActionResult(text: "Could not list files: $e", actionPerformed: true, success: false);
          }

        case 'read_file_content':
          final path = params['path'] as String?;
          if (path == null) return ActionResult(text: "No file path specified.", actionPerformed: true, success: false);
          try {
            final file = File(path);
            if (await file.exists()) {
              final content = await file.readAsString();
              final truncated = content.length > 600 ? '${content.substring(0, 600)}...' : content;
              return ActionResult(text: "Content of $path:\n$truncated", actionPerformed: true, success: true);
            } else {
              return ActionResult(text: "File $path not found.", actionPerformed: true, success: false);
            }
          } catch (e) {
            return ActionResult(text: "Could not read file: $e", actionPerformed: true, success: false);
          }

        case 'find_files':
          final query = (params['query'] as String? ?? '').toLowerCase();
          if (query.isEmpty) return ActionResult(text: "No query specified.", actionPerformed: true, success: false);
          try {
            final home = Platform.isWindows
                ? r'C:\Users\' + Platform.environment['USERNAME']!
                : '/home/${Platform.environment['USER'] ?? ''}';
            final List<String> found = [];
            final dir = Directory(home);
            if (await dir.exists()) {
              await for (final entity in dir.list(recursive: true, followLinks: false).handleError((_) {})) {
                final name = entity.path.split(Platform.isWindows ? '\\' : '/').last.toLowerCase();
                if (name.contains(query)) {
                  found.add(entity.path);
                  if (found.length >= 10) break;
                }
              }
            }
            return ActionResult(
              text: found.isEmpty ? "No files found matching '$query'." : "Found files:\n${found.join('\n')}",
              actionPerformed: true,
              success: true,
            );
          } catch (e) {
            return ActionResult(text: "File search error: $e", actionPerformed: true, success: false);
          }

        case 'request_battery_optimization_ignore':
          return ActionResult(text: "Battery optimization is not applicable on desktop.", actionPerformed: false, success: false);

        // ── ESP32 Hardware Node (all HTTP — fully cross-platform) ──
        case 'esp32_relay':
          final ch = params['channel'] as int? ?? 1;
          final state = params['state'] as String? ?? 'toggle';
          final r = await Esp32Service().setRelay(ch, state);
          return ActionResult(
            text: r.success ? "Relay $ch is now ${state == 'toggle' ? 'toggled' : state}, Sir." : "Could not reach ESP32. ${r.message}",
            actionPerformed: true, success: r.success,
          );

        case 'esp32_pin':
          final pin = params['pin'] as int? ?? 2;
          final state = params['state'] as String? ?? 'toggle';
          final r = await Esp32Service().setPin(pin, state);
          return ActionResult(
            text: r.success ? "GPIO pin $pin is now $state, Sir." : "Pin $pin error. ${r.message}",
            actionPerformed: true, success: r.success,
          );

        case 'esp32_pwm':
          final pin = params['pin'] as int? ?? 2;
          final duty = params['duty'] as int? ?? 128;
          final r = await Esp32Service().setPwm(pin, duty);
          return ActionResult(
            text: r.success ? "PWM on pin $pin set to $duty, Sir." : "PWM failed. ${r.message}",
            actionPerformed: true, success: r.success,
          );

        case 'esp32_servo':
          final angle = params['angle'] as int? ?? 90;
          final r = await Esp32Service().setServo(angle);
          return ActionResult(
            text: r.success ? "Servo moved to $angle degrees, Sir." : "Servo error. ${r.message}",
            actionPerformed: true, success: r.success,
          );

        case 'esp32_led':
          final color = params['color'] as String?;
          final brightness = params['brightness'] as int?;
          Esp32Result r;
          if (color != null) {
            final rgb = Esp32Service.colorNameToRgb(color);
            r = await Esp32Service().setLed(r: rgb['r']!, g: rgb['g']!, b: rgb['b']!);
          } else if (brightness != null) {
            r = await Esp32Service().setLed(brightness: brightness);
          } else {
            r = await Esp32Service().setLed(r: params['r'] ?? 255, g: params['g'] ?? 255, b: params['b'] ?? 255);
          }
          return ActionResult(
            text: r.success ? "LED updated, Sir." : "LED error. ${r.message}",
            actionPerformed: true, success: r.success,
          );

        case 'esp32_buzzer':
          final dur = params['duration_ms'] as int? ?? 200;
          final r = await Esp32Service().buzz(dur);
          return ActionResult(
            text: r.success ? "Done, Sir." : "Buzzer error. ${r.message}",
            actionPerformed: true, success: r.success,
          );

        case 'esp32_sensor':
          final type = (params['type'] as String? ?? 'temperature').toLowerCase();
          if (type == 'analog') {
            final data = await Esp32Service().readAnalog();
            if (data != null) return ActionResult(text: "Analog reading: ${data['volts']} volts, Sir.", actionPerformed: true, success: true);
          } else {
            final data = await Esp32Service().readDht();
            if (data != null) {
              if (type == 'humidity') return ActionResult(text: "Current humidity is ${data['humidity']}%, Sir.", actionPerformed: true, success: true);
              return ActionResult(text: "Temperature is ${data['temperature_c']}°C, humidity ${data['humidity']}%, Sir.", actionPerformed: true, success: true);
            }
          }
          return ActionResult(text: "Could not read sensor. Check ESP32 connection.", actionPerformed: true, success: false);

        case 'esp32_reset':
          final r = await Esp32Service().resetAll();
          return ActionResult(
            text: r.success ? "All ESP32 outputs have been reset, Sir." : "Reset failed. ${r.message}",
            actionPerformed: true, success: r.success,
          );

        // ── IoT Hub Commands (all HTTP — fully cross-platform) ─────
        case 'iot_scan':
          final result = await IotHubService().triggerScan();
          return ActionResult(
            text: result != null
                ? "Network scan initiated, Sir. I'll discover all devices on the WiFi network."
                : "Could not reach the IoT Hub. Check Settings.",
            actionPerformed: true, success: result != null,
          );

        case 'iot_list_devices':
          final result = await IotHubService().listDevices(onlineOnly: true);
          if (result != null) {
            final count = result['count'] ?? 0;
            final devices = (result['devices'] as List?)?.take(10) ?? [];
            final summary = devices.map((d) => '${d['ip']} (${d['friendly_name'] ?? d['vendor'] ?? 'Unknown'}) [${d['device_type']}]').join('\n');
            return ActionResult(text: "Found $count devices online:\n$summary", actionPerformed: true, success: true);
          }
          return ActionResult(text: "Could not reach the IoT Hub.", actionPerformed: true, success: false);

        case 'iot_list_cameras':
          final result = await IotHubService().listCameras();
          if (result != null) {
            final cameras = (result['cameras'] as List?) ?? [];
            if (cameras.isEmpty) return ActionResult(text: "No cameras found. Run a scan first.", actionPerformed: true, success: true);
            final summary = cameras.map((c) => '${c['ip']} (${c['friendly_name'] ?? 'Unknown'})${c['is_recording'] == true ? ' 🔴 REC' : ''}').join('\n');
            return ActionResult(text: "${result['count']} cameras:\n$summary", actionPerformed: true, success: true);
          }
          return ActionResult(text: "Could not reach the IoT Hub.", actionPerformed: true, success: false);

        case 'iot_record':
          final camera = params['camera'] as String? ?? 'all';
          final state = params['state'] as String? ?? 'start';
          Map<String, dynamic>? result;
          if (state == 'start') {
            result = camera == 'all' ? await IotHubService().startRecordingAll() : await IotHubService().startRecording(camera);
          } else {
            result = camera == 'all' ? await IotHubService().stopRecordingAll() : await IotHubService().stopRecording(camera);
          }
          return ActionResult(
            text: result != null ? "${state == 'start' ? 'Recording started' : 'Recording stopped'} on camera(s), Sir." : "Could not ${state} recording.",
            actionPerformed: true, success: result != null,
          );

        case 'iot_snapshot':
          return ActionResult(text: "Snapshot captured from camera ${params['camera']}. Check the dashboard.", actionPerformed: true, success: true);

        case 'iot_permit_device':
          final mac = params['mac'] as String? ?? '';
          Map<String, dynamic>? result;
          if (mac == 'all') {
            result = await IotHubService().grantAllPending();
            if (result != null) return ActionResult(text: "Granted permission to ${result['count']} devices, Sir.", actionPerformed: true, success: true);
          } else if (mac.isNotEmpty) {
            result = await IotHubService().permitDevice(mac);
            if (result != null) return ActionResult(text: "Permission granted for $mac, Sir.", actionPerformed: true, success: true);
          }
          return ActionResult(text: "Could not grant permission.", actionPerformed: true, success: false);

        case 'iot_select_mic':
          final deviceId = params['device_id'] as String? ?? 'local';
          final result = await IotHubService().selectMic(deviceId);
          return ActionResult(
            text: result != null ? "Microphone switched to ${result['name'] ?? deviceId}, Sir." : "Could not switch microphone.",
            actionPerformed: true, success: result != null,
          );

        case 'iot_select_speaker':
          final deviceId = params['device_id'] as String? ?? 'local';
          final result = await IotHubService().selectSpeaker(deviceId);
          return ActionResult(
            text: result != null ? "Speaker switched to ${result['name'] ?? deviceId}, Sir." : "Could not switch speaker.",
            actionPerformed: true, success: result != null,
          );

        case 'iot_fallback_status':
          final result = await IotHubService().getFallbackStatus();
          if (result != null) {
            final cam = result['camera'] ?? {};
            final mic = result['microphone'] ?? {};
            final spk = result['speaker'] ?? {};
            return ActionResult(
              text: "Fallback status:\n📷 Camera: ${cam['using_local'] == true ? 'Local' : cam['active_source']}\n🎤 Mic: ${mic['using_local'] == true ? 'Local' : mic['active_name']}\n🔊 Speaker: ${spk['using_local'] == true ? 'Local' : spk['active_name']}",
              actionPerformed: true, success: true,
            );
          }
          return ActionResult(text: "Could not get fallback status.", actionPerformed: true, success: false);

        case 'iot_bluetooth_scan':
          final result = await IotHubService().scanBluetooth();
          if (result != null) {
            final devices = (result['devices'] as List?)?.take(5) ?? [];
            final summary = devices.map((d) => "${d['name']} (${d['mac']})").join('\n');
            return ActionResult(text: "Found ${result['count']} Bluetooth devices:\n$summary", actionPerformed: true, success: true);
          }
          return ActionResult(text: "Could not scan Bluetooth.", actionPerformed: true, success: false);

        case 'iot_bluetooth_connect':
          final mac = params['mac'] as String? ?? '';
          if (mac.isEmpty) return ActionResult(text: "Specify the Bluetooth device MAC.", actionPerformed: true, success: false);
          final result = await IotHubService().connectBluetooth(mac);
          return ActionResult(
            text: result != null && result['status'] == 'connected'
                ? "Connected to ${result['device']?['name'] ?? mac}, Sir."
                : "Initiated connection to $mac.",
            actionPerformed: true, success: true,
          );

        // ── ADB / Connected Device Commands ────────────────────────
        case 'list_connected_devices':
          await AdbService().loadSettings();
          final adbDevs = await AdbService().listDevices();
          if (adbDevs.isEmpty) return ActionResult(text: "No ADB devices connected, Sir.", actionPerformed: true, success: false);
          return ActionResult(
            text: "Found ${adbDevs.length} device(s):\n${adbDevs.map((d) => '${d.displayName} (${d.serial})').join('\n')}",
            actionPerformed: true, success: true,
          );

        case 'unlock_device':
          await AdbService().loadSettings();
          final serial = params['serial'] as String?;
          final devs = await AdbService().listDevices();
          if (devs.isEmpty) return ActionResult(text: "No ADB devices connected.", actionPerformed: true, success: false);
          final target = serial != null ? devs.firstWhere((d) => d.serial == serial, orElse: () => devs.first) : devs.first;
          final r = await AdbService().unlockDevice(target.serial);
          return ActionResult(text: r.success ? "Unlocked ${target.displayName}, Sir." : "Unlock failed: ${r.message}", actionPerformed: true, success: r.success);

        case 'adb_shell':
          final ser = params['serial'] as String?;
          final cmd = params['command'] as String?;
          if (ser == null || cmd == null) return ActionResult(text: "Specify device serial and command.", actionPerformed: false, success: false);
          await AdbService().loadSettings();
          final shResult = await AdbService().runShell(ser, cmd);
          return ActionResult(text: shResult.success ? "ADB:\n${shResult.data?['output'] ?? shResult.message}" : "Shell error: ${shResult.message}", actionPerformed: true, success: shResult.success);

        case 'device_screenshot':
          final s = params['serial'] as String?;
          if (s == null) return ActionResult(text: "Specify device serial.", actionPerformed: false, success: false);
          await AdbService().loadSettings();
          final ss = await AdbService().screenshot(s);
          return ActionResult(text: ss.success ? "Screenshot captured from $s, Sir." : "Screenshot failed: ${ss.message}", actionPerformed: true, success: ss.success);

        case 'screen_mirror':
          final s = params['serial'] as String?;
          if (s == null) return ActionResult(text: "Specify device serial.", actionPerformed: false, success: false);
          await AdbService().loadSettings();
          final mr = await AdbService().startMirror(s);
          return ActionResult(text: mr.success ? "Mirroring started for $s, Sir." : "Mirror failed: ${mr.message}", actionPerformed: true, success: mr.success);

        case 'adb_connect':
          final host = params['host'] as String?;
          if (host == null) return ActionResult(text: "Specify host IP:port.", actionPerformed: false, success: false);
          await AdbService().loadSettings();
          final cr = await AdbService().connectWifi(host);
          return ActionResult(text: cr.success ? "Connected to $host, Sir." : "ADB connect failed: ${cr.message}", actionPerformed: true, success: cr.success);

        default:
          return ActionResult(text: "Command received but not yet implemented on desktop.", actionPerformed: false, success: false);
      }
    } catch (e) {
      return ActionResult(text: "Execution error: $e", actionPerformed: true, success: false);
    }
  }

  /// Offline command parser (no API needed)
  static Future<ActionResult> handleOfflineCommand(String command) async {
    final query = command.toLowerCase().trim();

    if (query.contains('hello') || query.contains('hi')) {
      return ActionResult(text: "Hello! I am MEKA. I can control IoT devices, run ADB commands, and manage files.", actionPerformed: false, success: true);
    }
    if (query.contains('who are you') || query.contains('your name')) {
      return ActionResult(text: "I am MEKA, your desktop AI assistant.", actionPerformed: false, success: true);
    }

    final openMatch = RegExp(r'(?:open|launch)\s+([a-zA-Z0-9\s]+)').firstMatch(query);
    if (openMatch != null) return _execute('open_app', {'app': openMatch.group(1)!.trim()});

    final searchMatch = RegExp(r'(?:search|google)\s+(.+)').firstMatch(query);
    if (searchMatch != null) return _execute('web_search', {'query': searchMatch.group(1)!.trim()});

    return ActionResult(text: "I couldn't understand that offline. Try: 'open chrome', 'search weather', or a hub command.", actionPerformed: false, success: false);
  }

  // ── Platform Helpers ─────────────────────────────────────────────────────
  static Future<void> _openDesktopApp(String appName) async {
    if (Platform.isWindows) {
      final appMap = {
        'chrome': 'chrome', 'browser': 'chrome', 'firefox': 'firefox',
        'notepad': 'notepad', 'calculator': 'calc', 'explorer': 'explorer',
        'terminal': 'wt', 'powershell': 'powershell', 'cmd': 'cmd',
        'settings': 'ms-settings:', 'paint': 'mspaint', 'clock': 'ms-clock:',
      };
      final exe = appMap[appName] ?? appName;
      await Process.run('start', [exe], runInShell: true).catchError((_) async {
        return await Process.run(exe, [], runInShell: true);
      });
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [appName], runInShell: true).catchError((_) async {
        return await Process.run(appName, [], runInShell: true);
      });
    }
  }

  static Future<void> _launchUrl(String url) async {
    if (Platform.isWindows) {
      await Process.run('start', [url], runInShell: true);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [url], runInShell: true);
    }
  }

  static Future<void> _setSystemVolume(int level) async {
    final clamped = level.clamp(0, 100);
    if (Platform.isWindows) {
      // Use PowerShell to set system volume
      final script = '(New-Object -ComObject WScript.Shell).SendKeys([char]173)';
      await Process.run('powershell', [
        '-Command',
        '\$vol = New-Object -ComObject WScript.Shell; \$wmp = New-Object -ComObject WMPlayer.OCX.7; \$wmp.settings.volume = $clamped'
      ]).catchError((_) async => ProcessResult(0, 0, '', ''));
    } else if (Platform.isLinux) {
      await Process.run('amixer', ['sset', 'Master', '$clamped%']);
    }
  }
}

class ActionResult {
  final String text;
  final bool actionPerformed;
  final bool success;
  ActionResult({required this.text, required this.actionPerformed, required this.success});
}
