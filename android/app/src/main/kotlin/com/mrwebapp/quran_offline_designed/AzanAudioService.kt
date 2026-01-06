package com.mrwebapp.al_quran_mp3

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.*
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlin.jvm.Volatile

class AzanAudioService : Service() {

    private val tag = "AzanAudioService"

    companion object {
        const val CHANNEL_ID = "azan_native_playback"
        const val CHANNEL_NAME = "Azan Playback"
        const val NOTIFICATION_ID = 2101

        const val ACTION_START = "com.mrwebapp.al_quran_mp3.action.START"
        const val ACTION_STOP = "com.mrwebapp.al_quran_mp3.action.STOP"
        const val EXTRA_PRAYER = "extra_prayer"

        private const val REQUEST_CODE_STOP = 100
        private const val REQUEST_CODE_CONTENT = 101

        fun startService(context: Context, prayerName: String) {
            val intent = Intent(context, AzanAudioService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_PRAYER, prayerName)
            }
            Log.d("AzanAudioService", "startService() requested for $prayerName (sdk=${Build.VERSION.SDK_INT})")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            val intent = Intent(context, AzanAudioService::class.java).apply { action = ACTION_STOP }
            try {
                Log.d("AzanAudioService", "stopService() requested")
                context.startService(intent)
            } catch (e: Exception) {
                Log.e("AzanAudioService", "stopService() failed", e)
            }
        }
    }

    private var mediaPlayer: MediaPlayer? = null
    private var currentPrayer: String = "Azan"
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    @Volatile private var isShuttingDown = false
    @Volatile private var hasPostedForegroundNotification = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        log("Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                log("onStartCommand: ACTION_STOP received")
                shutdownService("Stop action received")
                return START_NOT_STICKY
            }

            ACTION_START -> {
                log("onStartCommand: ACTION_START received")
                val prayer = intent.getStringExtra(EXTRA_PRAYER)
                if (!prayer.isNullOrEmpty()) currentPrayer = prayer

                startForegroundServiceProperly()
                acquireWakeLock()
                startAzanForcePlayback()
                return START_STICKY
            }

            else -> {
                log("onStartCommand: restart with null action")
                startForegroundServiceProperly()
                acquireWakeLock()
                startAzanForcePlayback()
                return START_STICKY
            }
        }
    }

    private fun startForegroundServiceProperly() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                buildNotification(currentPrayer),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, buildNotification(currentPrayer))
        }
        hasPostedForegroundNotification = true
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        log("Service destroyed")
        stopAzanPlayback()
        releaseWakeLock()
        releaseAudioFocus()
        stopForegroundNotification()
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "AzanAudioService::WakeLock"
            ).apply { acquire(10 * 60 * 1000L) }
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
            wakeLock = null
        }
    }

    private fun requestAudioFocus(force: Boolean = false): Boolean {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val focusListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
                log("Audio focus changed: $focusChange")
            }

            audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setOnAudioFocusChangeListener(focusListener)
                .build()

            val result = audioManager.requestAudioFocus(audioFocusRequest!!)
            log("Audio focus request result: $result")
            return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED || force
        } else {
            val result = audioManager.requestAudioFocus(
                null,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
            )
            log("Audio focus request result: $result")
            return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED || force
        }
    }

    private fun releaseAudioFocus() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it); audioFocusRequest = null }
        } else {
            audioManager.abandonAudioFocus(null)
        }
    }

    /** Force playback: ignores focus denial */
    private fun startAzanForcePlayback() {
        stopAzanPlayback()

        if (!requestAudioFocus(force = true)) {
            log("Audio focus denied but forcing playback")
        }

        try {
            val player = MediaPlayer()
            val afd = resources.openRawResourceFd(R.raw.azan) ?: run {
                updateNotification("Error: Could not load audio file")
                player.release()
                shutdownService("Audio resource missing")
                return
            }
            player.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            afd.close()

            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )

            player.setOnCompletionListener { shutdownService("Playback completed") }
            player.setOnErrorListener { _, what, extra ->
                log("MediaPlayer error $what,$extra")
                shutdownService("Playback error")
                true
            }

            player.isLooping = false
            player.setVolume(1.0f, 1.0f)
            player.prepare()
            mediaPlayer = player
            mediaPlayer!!.start()
            updateNotification("Azan is playing (force)")
            log("MediaPlayer started with force-play")
        } catch (e: Exception) {
            updateNotification("Error: ${e.message}")
            log("Unexpected error: ${e.message}")
            shutdownService("Unexpected error")
        }
    }

    private fun stopAzanPlayback() {
        mediaPlayer?.let { player ->
            try { if (player.isPlaying) player.stop() } catch (e: Exception) {}
            try { player.reset() } catch (e: Exception) {}
            try { player.release() } catch (e: Exception) {}
        }
        mediaPlayer = null
    }

    private fun updateNotification(statusText: String) {
        val notification = buildNotification(currentPrayer, statusText)
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun buildNotification(prayerName: String, statusText: String = "Azan is playing"): Notification {
        val stopIntent = Intent(this, AzanAudioService::class.java).apply { action = ACTION_STOP }
        val stopFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT
        val stopPendingIntent = PendingIntent.getService(this, REQUEST_CODE_STOP, stopIntent, stopFlags)

        val contentIntent = packageManager.getLaunchIntentForPackage(packageName)?.let { launchIntent ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                PendingIntent.getActivity(this, REQUEST_CODE_CONTENT, launchIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            else PendingIntent.getActivity(this, REQUEST_CODE_CONTENT, launchIntent, PendingIntent.FLAG_UPDATE_CURRENT)
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("🕌 $prayerName Time")
            .setContentText(statusText)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(contentIntent)
            .setShowWhen(false)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(NotificationCompat.Action.Builder(android.R.drawable.ic_media_pause, "Stop", stopPendingIntent).build())
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Plays Azan audio even when the app is closed."
                setSound(null, null)
                enableLights(false)
                enableVibration(true)
                setShowBadge(true)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun shutdownService(reason: String) {
        if (isShuttingDown) return
        isShuttingDown = true
        log("shutdownService: $reason")
        stopAzanPlayback()
        releaseWakeLock()
        releaseAudioFocus()
        stopForegroundNotification()
        stopSelf()
    }

    private fun stopForegroundNotification() {
        if (!hasPostedForegroundNotification) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE)
        else @Suppress("DEPRECATION") stopForeground(true)
        hasPostedForegroundNotification = false
    }

    private fun log(message: String) = Log.d(tag, message)
}
