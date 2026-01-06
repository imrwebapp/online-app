package com.mrwebapp.al_quran_mp3

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class AzanBroadcastReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "AzanBroadcastReceiver"
        const val ACTION_PLAY_AZAN = "com.mrwebapp.al_quran_mp3.PLAY_AZAN"
        const val EXTRA_PRAYER_NAME = "prayer_name"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "📡 Broadcast received: ${intent.action}")

        if (intent.action == ACTION_PLAY_AZAN) {
            val prayerName = intent.getStringExtra(EXTRA_PRAYER_NAME) ?: "Azan"
            Log.d(TAG, "🕌 Starting Azan service for $prayerName")

            AzanAudioService.startService(context, prayerName)
}
}
}
