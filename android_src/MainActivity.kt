package com.example.meka

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.provider.AlarmClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle
import java.util.Calendar

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.meka.assistant/device"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openApp" -> {
                    val appName = call.argument<String>("app") ?: ""
                    openApp(appName, result)
                }
                "setAlarm" -> {
                    val hour = call.argument<Int>("hour") ?: 0
                    val minute = call.argument<Int>("minute") ?: 0
                    val label = call.argument<String>("label") ?: "Meka Alarm"
                    setAlarm(hour, minute, label, result)
                }
                "sendSms" -> {
                    val to = call.argument<String>("to") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    sendSms(to, message, result)
                }
                "makeCall" -> {
                    val to = call.argument<String>("to") ?: ""
                    makeCall(to, result)
                }
                "setVolume" -> {
                    val level = call.argument<Int>("level") ?: 50
                    setVolume(level, result)
                }
                "webSearch" -> {
                    val query = call.argument<String>("query") ?: ""
                    webSearch(query, result)
                }
                "takePhoto" -> {
                    takePhoto(result)
                }
                "toggleWifi" -> {
                    openWifiSettings(result)
                }
                "toggleBluetooth" -> {
                    openBluetoothSettings(result)
                }
                "openSettings" -> {
                    openSystemSettings(result)
                }
                "ignoreBatteryOptimizations" -> {
                    ignoreBatteryOptimizations(result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openApp(appName: String, result: MethodChannel.Result) {
        try {
            val pm = packageManager
            val packages = mapOf(
                "youtube" to "com.google.android.youtube",
                "whatsapp" to "com.whatsapp",
                "maps" to "com.google.android.apps.maps",
                "google maps" to "com.google.android.apps.maps",
                "camera" to "com.android.camera2",
                "chrome" to "com.android.chrome",
                "gmail" to "com.google.android.gm",
                "spotify" to "com.spotify.music",
                "netflix" to "com.netflix.mediaclient",
                "facebook" to "com.facebook.katana",
                "instagram" to "com.instagram.android",
                "twitter" to "com.twitter.android",
                "tiktok" to "com.zhiliaoapp.musically",
                "telegram" to "org.telegram.messenger",
                "calculator" to "com.google.android.calculator",
                "clock" to "com.google.android.deskclock",
                "calendar" to "com.google.android.calendar",
                "photos" to "com.google.android.apps.photos",
                "files" to "com.google.android.apps.nbu.files",
                "settings" to "com.android.settings",
                "play store" to "com.android.vending",
                "messages" to "com.google.android.apps.messaging",
                "phone" to "com.google.android.dialer",
                "contacts" to "com.google.android.contacts",
            )

            val lower = appName.lowercase()
            val pkg = packages.entries.firstOrNull { lower.contains(it.key) }?.value

            if (pkg != null) {
                val intent = pm.getLaunchIntentForPackage(pkg)
                if (intent != null) {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                    return
                }
            }

            // Fallback: search Play Store
            val intent = Intent(Intent.ACTION_VIEW,
                Uri.parse("market://search?q=$appName")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("OPEN_APP_ERROR", e.message, null)
        }
    }

    private fun setAlarm(hour: Int, minute: Int, label: String, result: MethodChannel.Result) {
        try {
            val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(AlarmClock.EXTRA_HOUR, hour)
                putExtra(AlarmClock.EXTRA_MINUTES, minute)
                putExtra(AlarmClock.EXTRA_MESSAGE, label)
                putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("ALARM_ERROR", e.message, null)
        }
    }

    private fun sendSms(to: String, message: String, result: MethodChannel.Result) {
        try {
            val intent = Intent(Intent.ACTION_SENDTO).apply {
                data = Uri.parse("smsto:$to")
                putExtra("sms_body", message)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("SMS_ERROR", e.message, null)
        }
    }

    private fun makeCall(to: String, result: MethodChannel.Result) {
        try {
            val intent = Intent(Intent.ACTION_DIAL).apply {
                data = Uri.parse("tel:$to")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("CALL_ERROR", e.message, null)
        }
    }

    private fun setVolume(level: Int, result: MethodChannel.Result) {
        try {
            val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val vol = (level * max / 100)
            audio.setStreamVolume(AudioManager.STREAM_MUSIC, vol, 0)
            result.success(true)
        } catch (e: Exception) {
            result.error("VOLUME_ERROR", e.message, null)
        }
    }

    private fun webSearch(query: String, result: MethodChannel.Result) {
        try {
            val intent = Intent(Intent.ACTION_VIEW,
                Uri.parse("https://www.google.com/search?q=${Uri.encode(query)}")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("SEARCH_ERROR", e.message, null)
        }
    }

    private fun takePhoto(result: MethodChannel.Result) {
        try {
            val intent = Intent("android.media.action.IMAGE_CAPTURE").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("CAMERA_ERROR", e.message, null)
        }
    }

    private fun openWifiSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_WIFI_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("WIFI_ERROR", e.message, null)
        }
    }

    private fun openBluetoothSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("BLUETOOTH_ERROR", e.message, null)
        }
    }

    private fun openSystemSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("SETTINGS_ERROR", e.message, null)
        }
    }

    private fun ignoreBatteryOptimizations(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                result.success(true)
            } else {
                result.success(false)
            }
        } catch (e: Exception) {
            result.error("BATTERY_ERROR", e.message, null)
        }
    }
}
