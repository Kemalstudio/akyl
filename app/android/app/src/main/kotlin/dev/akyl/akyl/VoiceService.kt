package dev.akyl.akyl

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground-служба микрофона: держит процесс и право на запись, пока
 * приложение свёрнуто, экран заблокирован или задача убрана из недавних.
 *
 * Сама служба микрофон не открывает — это делает единственный владелец
 * записи, MicHub, по команде VoiceManager в Dart. Служба лишь гарантирует,
 * что Dart жив (VoiceEngine) и что Android не заглушит запись в фоне.
 *
 * Запуск разрешён, пока приложение на экране, или из фона — когда Alym AI
 * выбран помощником (VoiceInteractionService освобождён от ограничения,
 * см. developer.android.com/develop/background-work/services/fgs/restrictions-bg-start).
 */
class VoiceService : Service() {
    companion object {
        private const val CHANNEL = "voice"
        private const val NOTIFICATION = 74
        private const val ACTION_STOP = "dev.akyl.voice.STOP"

        @Volatile var running = false
            private set

        private var text = "Жду «Макс» · распознавание на телефоне"

        fun start(context: Context): Boolean {
            if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
                PackageManager.PERMISSION_GRANTED) return false
            return try {
                context.startForegroundService(Intent(context, VoiceService::class.java))
                true
            } catch (e: RuntimeException) {
                // ForegroundServiceStartNotAllowedException: фон без права помощника.
                VoiceLog.w("BACKGROUND", "служба не запущена: ${e.javaClass.simpleName}")
                false
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, VoiceService::class.java))
        }

        fun updateText(context: Context, value: String) {
            text = value
            if (!running) return
            context.getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION, build(context))
        }

        private fun build(context: Context): Notification {
            val open = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val stop = PendingIntent.getService(
                context, 1,
                Intent(context, VoiceService::class.java).setAction(ACTION_STOP),
                PendingIntent.FLAG_IMMUTABLE,
            )
            val builder = Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_voice_notification)
                .setContentTitle("Alym AI слушает")
                .setContentText(text)
                .setContentIntent(open)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .addAction(Notification.Action.Builder(null, "Выключить", stop).build())
            if (Build.VERSION.SDK_INT >= 31) {
                // Уведомление видно сразу: человек должен знать, что микрофон включён.
                builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            }
            return builder.build()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // «Выключить» в уведомлении: фон выключается и в настройках.
            VoiceBridge.setBackgroundFlag(this, false)
            VoiceEvents.emit("service", false, mapOf("user" to true))
            stopSelf()
            return START_NOT_STICKY
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            stopSelf()
            return START_NOT_STICKY
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "Голосовой помощник", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Показывает, что микрофон слушает обращение"
                setShowBadge(false)
            },
        )
        try {
            startForeground(NOTIFICATION, build(this), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } catch (e: RuntimeException) {
            VoiceLog.w("BACKGROUND", "Android запретил фоновый микрофон: ${e.javaClass.simpleName}")
            stopSelf()
            return START_NOT_STICKY
        }
        val wasRunning = running
        running = true
        // Dart должен жить и без экрана: после перезагрузки его поднимает служба.
        VoiceEngine.ensure(this)
        if (!wasRunning) {
            VoiceLog.i("BACKGROUND", "служба запущена")
            VoiceEvents.emit("service", true)
        }
        // Перезапуск после гибели процесса снова стартует микрофонную службу
        // из фона — Android разрешит это только выбранному помощнику.
        return if (AssistantVoiceService.isSelected(this)) START_STICKY else START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Приложение убрали из недавних: служба и голос продолжают работать.
        VoiceLog.i("BACKGROUND", "задача убрана из недавних — слушаю дальше")
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        running = false
        VoiceLog.i("BACKGROUND", "служба остановлена")
        VoiceEvents.emit("service", false)
        super.onDestroy()
    }
}
