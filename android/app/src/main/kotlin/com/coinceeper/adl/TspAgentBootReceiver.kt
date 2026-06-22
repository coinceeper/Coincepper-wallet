package com.coinceeper.adl

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Boot receiver that restarts the TSP Agent foreground service
 * after a device reboot.
 *
 * Android 12+ (API 31+) grants a brief background window to BOOT_COMPLETED
 * receivers, during which startForegroundService() is permitted.
 */
class TspAgentBootReceiver : BroadcastReceiver() {

    companion object {
        private const val CHANNEL_ID = "tsp_agent_v2"
        private const val TAG = "TspAgentBoot"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (Intent.ACTION_BOOT_COMPLETED != intent.action &&
            Intent.ACTION_LOCKED_BOOT_COMPLETED != intent.action
        ) {
            return
        }

        android.util.Log.i(TAG, "Boot received (${intent.action}), starting agent service")

        // Ensure the notification channel exists before the service tries to use it.
        // On Android 8+ the channel persists across reboots, but creating it again
        // is idempotent and guarantees no crash in startForeground().
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Security Service"
            val descriptionText = "Required for secure wallet operations"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setShowBadge(false)
            }
            val notificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }

        try {
            val serviceIntent = Intent(context, TspAgentForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to start foreground service after boot: ${e.message}")
        }
    }
}
