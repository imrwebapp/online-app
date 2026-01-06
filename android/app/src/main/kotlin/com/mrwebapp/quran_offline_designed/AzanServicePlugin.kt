package com.mrwebapp.al_quran_mp3

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AzanServicePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "AzanServicePlugin"
        private const val CHANNEL = "com.mrwebapp.al_quran_mp3/azan_service"
    }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        Log.d(TAG, "✅ Plugin attached")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startAzanService" -> {
                val prayerName = call.argument<String>("prayerName") ?: "Azan"
                Log.d(TAG, "startAzanService() prayer=$prayerName")
                AzanAudioService.startService(context, prayerName)
                result.success(null)
            }
            "stopAzanService" -> {
                Log.d(TAG, "stopAzanService()")
                AzanAudioService.stopService(context)
                result.success(null)
            }
            "scheduleAzanAlarm" -> {
                val prayerName = call.argument<String>("prayerName") ?: "Azan"
                val timeMillis = call.argument<Long>("timeMillis")
                val alarmId = call.argument<Int>("alarmId") ?: 999
                
                if (timeMillis != null) {
                    scheduleAlarm(prayerName, timeMillis, alarmId)
                    result.success(true)
                } else {
                    result.error("INVALID_TIME", "timeMillis is required", null)
                }
            }
            "cancelAzanAlarm" -> {
                val alarmId = call.argument<Int>("alarmId") ?: 999
                cancelAlarm(alarmId)
                result.success(true)
            }
            else -> {
                Log.w(TAG, "Unknown method ${call.method}")
                result.notImplemented()
            }
        }
    }

    private fun scheduleAlarm(prayerName: String, timeMillis: Long, alarmId: Int) {
        Log.d(TAG, "📅 Scheduling native alarm for $prayerName at $timeMillis (ID: $alarmId)")
        
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        
        // Create intent for BroadcastReceiver
        val intent = Intent(context, AzanBroadcastReceiver::class.java).apply {
            action = AzanBroadcastReceiver.ACTION_PLAY_AZAN
            putExtra(AzanBroadcastReceiver.EXTRA_PRAYER_NAME, prayerName)
        }
        
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            alarmId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or 
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )
        
        // Schedule exact alarm
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                timeMillis,
                pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                timeMillis,
                pendingIntent
            )
        }
        
        Log.d(TAG, "✅ Native alarm scheduled for $prayerName")
    }

    private fun cancelAlarm(alarmId: Int) {
        Log.d(TAG, "🗑️ Cancelling alarm ID: $alarmId")
        
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        
        val intent = Intent(context, AzanBroadcastReceiver::class.java).apply {
            action = AzanBroadcastReceiver.ACTION_PLAY_AZAN
        }
        
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            alarmId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or 
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )
        
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
        
        Log.d(TAG, "✅ Alarm cancelled")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        Log.d(TAG, "Detached from engine")
    }
}