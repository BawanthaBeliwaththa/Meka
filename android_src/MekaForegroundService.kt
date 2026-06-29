package com.example.meka

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class MekaForegroundService : Service() {
    private val CHANNEL_ID = "MekaForegroundServiceChannel"

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        
        // Use system default icon or voice icon
        val icon = android.R.drawable.ic_btn_speak_now
        
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Meka Personal Intelligence")
            .setContentText("Always active. Listening for 'Hey Meka'...")
            .setSmallIcon(icon)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
            
        startForeground(1, notification)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Meka Service Channel",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }
}
