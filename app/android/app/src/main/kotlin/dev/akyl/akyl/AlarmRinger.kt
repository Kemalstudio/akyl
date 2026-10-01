package dev.akyl.akyl

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import java.util.Calendar

/**
 * Будильник, который ставит сам помощник.
 *
 * Обычно «поставь будильник» уходит в приложение «Часы» (AlarmClock.ACTION_SET_ALARM).
 * Но это запуск чужого экрана, и из фона Android 14+ его молча блокирует,
 * если Alym AI не выбран помощником. Тогда будильник ставится здесь:
 * AlarmManager.setAlarmClock — система считает его настоящим будильником
 * (значок в строке состояния, срабатывание в режиме сна), звонок идёт
 * на потоке будильника и повторяется, пока его не выключат.
 */
object AlarmRinger {
    private const val PREFS = "own_alarms"
    private const val CHANNEL = "alarm_clock"
    private const val NOTIFICATION_BASE = 20_000
    const val ACTION_FIRE = "dev.akyl.alarm.FIRE"
    const val ACTION_DISMISS = "dev.akyl.alarm.DISMISS"
    const val ACTION_SNOOZE = "dev.akyl.alarm.SNOOZE"
    private const val SNOOZE_MINUTES = 10

    /** Ближайшее hh:mm — сегодня, если ещё не прошло, иначе завтра. */
    fun nextOccurrence(hour: Int, minute: Int, now: Long = System.currentTimeMillis()): Long {
        val c = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (c.timeInMillis <= now) c.add(Calendar.DAY_OF_YEAR, 1)
        return c.timeInMillis
    }

    fun schedule(context: Context, hour: Int, minute: Int) {
        val id = hour * 60 + minute
        arm(context, id, nextOccurrence(hour, minute))
    }

    private fun arm(context: Context, id: Int, at: Long) {
        context.getSharedPreferences(PREFS, 0).edit().putLong(id.toString(), at).apply()
        val alarms = context.getSystemService(AlarmManager::class.java)
        val fire = firePending(context, id)
        try {
            val show = PendingIntent.getActivity(
                context, id, Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE,
            )
            alarms.setAlarmClock(AlarmManager.AlarmClockInfo(at, show), fire)
        } catch (e: SecurityException) {
            // Нет права на точные будильники — сработает чуть позже, но сработает.
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, fire)
        }
        VoiceLog.i("ACTION", "будильник Alym AI взведён")
    }

    private fun firePending(context: Context, id: Int): PendingIntent = PendingIntent.getBroadcast(
        context, id,
        Intent(context, AlarmRingReceiver::class.java).setAction(ACTION_FIRE).putExtra("id", id),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    fun forget(context: Context, id: Int) {
        context.getSharedPreferences(PREFS, 0).edit().remove(id.toString()).apply()
    }

    /** После перезагрузки AlarmManager всё забывает — взводим заново. */
    fun rearmAll(context: Context) {
        val now = System.currentTimeMillis()
        for ((key, value) in context.getSharedPreferences(PREFS, 0).all) {
            val id = key.toIntOrNull() ?: continue
            val at = value as? Long ?: continue
            if (at > now - 60_000) arm(context, id, maxOf(at, now + 5_000)) else forget(context, id)
        }
    }

    fun ring(context: Context, id: Int) {
        forget(context, id)
        val notifications = context.getSystemService(NotificationManager::class.java)
        notifications.createNotificationChannel(
            NotificationChannel(CHANNEL, "Будильник", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Будильники, которые поставил помощник"
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                        ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                enableVibration(true)
                setBypassDnd(true)
            },
        )
        fun action(kind: String, request: Int) = PendingIntent.getBroadcast(
            context, request,
            Intent(context, AlarmRingReceiver::class.java).setAction(kind).putExtra("id", id),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val open = PendingIntent.getActivity(
            context, id, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        val time = "%02d:%02d".format(id / 60 % 24, id % 60)
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_voice_notification)
            .setContentTitle("Будильник $time")
            .setContentText("Поставил Alym AI")
            .setCategory(Notification.CATEGORY_ALARM)
            .setOngoing(true)
            .setFullScreenIntent(open, true)
            .setDeleteIntent(action(ACTION_DISMISS, id + 1_000_000))
            .addAction(Notification.Action.Builder(null, "Выключить", action(ACTION_DISMISS, id + 1_000_000)).build())
            .addAction(Notification.Action.Builder(null, "Через $SNOOZE_MINUTES минут", action(ACTION_SNOOZE, id + 2_000_000)).build())
            .build()
        // Звук повторяется, пока будильник не выключат.
        notification.flags = notification.flags or Notification.FLAG_INSISTENT
        if (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(
                Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            notifications.notify(NOTIFICATION_BASE + id, notification)
        }
    }

    fun dismiss(context: Context, id: Int) {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_BASE + id)
    }

    fun snooze(context: Context, id: Int) {
        dismiss(context, id)
        arm(context, id, System.currentTimeMillis() + SNOOZE_MINUTES * 60_000L)
    }
}

class AlarmRingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", -1)
        if (id < 0) return
        when (intent.action) {
            AlarmRinger.ACTION_FIRE -> AlarmRinger.ring(context, id)
            AlarmRinger.ACTION_DISMISS -> AlarmRinger.dismiss(context, id)
            AlarmRinger.ACTION_SNOOZE -> AlarmRinger.snooze(context, id)
        }
    }
}
