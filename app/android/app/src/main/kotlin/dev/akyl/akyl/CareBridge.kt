package dev.akyl.akyl

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import android.os.SystemClock
import android.speech.tts.TextToSpeech
import android.telephony.SmsManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

/**
 * Забота о человеке, когда приложение закрыто: напоминания (например,
 * о лекарствах) и присмотр за зарядом телефона.
 *
 * Всё держится на AlarmManager: будильник Android срабатывает в закрытом
 * приложении и после перезагрузки (см. [CareBootReceiver]). Сторонних
 * библиотек нет — только Android SDK.
 */
class CareBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.akyl/care"
        private const val LOCATION_REQUEST = 4401
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "schedule" -> {
                val reminder = JSONObject()
                    .put("id", call.argument<Int>("id")!!)
                    .put("text", call.argument<String>("text")!!)
                    .put("at", call.argument<Number>("at")!!.toLong())
                    .put("daily", call.argument<Boolean>("daily") == true)
                Reminders.save(context, reminder)
                Reminders.arm(context, reminder)
                askNotifications()
                result.success(null)
            }
            "cancel" -> {
                Reminders.cancel(context, call.argument<Int>("id")!!)
                result.success(null)
            }
            "list" -> {
                val list = Reminders.all(context).map {
                    mapOf(
                        "id" to it.getInt("id"),
                        "text" to it.getString("text"),
                        "at" to it.getLong("at"),
                        "daily" to it.getBoolean("daily"),
                    )
                }
                result.success(list)
            }
            "setBatteryWatch" -> {
                val numbers = call.argument<List<String>>("numbers") ?: emptyList()
                BatteryWatch.configure(context, numbers)
                result.success(null)
            }
            "batteryWatchEnabled" -> result.success(BatteryWatch.numbers(context).isNotEmpty())
            "requestLocation" -> {
                val granted = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                    PackageManager.PERMISSION_GRANTED
                if (!granted) {
                    ActivityHolder.current?.requestPermissions(arrayOf(
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION,
                    ), LOCATION_REQUEST)
                }
                result.success(granted)
            }
            else -> result.notImplemented()
        }
    }

    private fun askNotifications() {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED) {
            ActivityHolder.current?.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4402)
        }
    }
}

/** Хранилище и будильники напоминаний. */
object Reminders {
    private const val PREFS = "reminders"
    const val CHANNEL = "reminders"

    fun all(context: Context): List<JSONObject> {
        val raw = context.getSharedPreferences(PREFS, 0).getString("list", "[]") ?: "[]"
        val array = JSONArray(raw)
        return (0 until array.length()).map { array.getJSONObject(it) }
    }

    private fun write(context: Context, list: List<JSONObject>) {
        context.getSharedPreferences(PREFS, 0).edit()
            .putString("list", JSONArray(list).toString()).apply()
    }

    fun save(context: Context, reminder: JSONObject) {
        val id = reminder.getInt("id")
        write(context, all(context).filter { it.getInt("id") != id } + reminder)
    }

    fun cancel(context: Context, id: Int) {
        write(context, all(context).filter { it.getInt("id") != id })
        alarms(context).cancel(pending(context, id))
    }

    fun find(context: Context, id: Int) = all(context).firstOrNull { it.getInt("id") == id }

    private fun alarms(context: Context) = context.getSystemService(AlarmManager::class.java)

    private fun pending(context: Context, id: Int): PendingIntent = PendingIntent.getBroadcast(
        context, id,
        Intent(context, ReminderReceiver::class.java).putExtra("id", id),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /** Точный будильник, если Android разрешает; иначе — неточный, но всё равно сработает. */
    fun arm(context: Context, reminder: JSONObject) {
        val at = reminder.getLong("at")
        val intent = pending(context, reminder.getInt("id"))
        val alarms = alarms(context)
        if (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        } else {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        }
    }

    /** После перезагрузки: заново взвести будущие, переставить ежедневные. */
    fun rearmAll(context: Context) {
        val now = System.currentTimeMillis()
        for (reminder in all(context)) {
            if (reminder.getLong("at") < now) {
                if (!reminder.getBoolean("daily")) { cancel(context, reminder.getInt("id")); continue }
                var next = reminder.getLong("at")
                while (next < now) next += 24 * 60 * 60 * 1000L
                reminder.put("at", next)
                save(context, reminder)
            }
            arm(context, reminder)
        }
    }

    fun ensureChannel(context: Context) {
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "Напоминания", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Напоминания помощника: лекарства, звонки, дела"
            })
    }
}

/**
 * Срабатывание напоминания: уведомление со звуком и голос вслух —
 * «Напоминаю: выпить таблетку». Ежедневное переставляется на завтра.
 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", -1)
        val reminder = Reminders.find(context, id) ?: return
        val text = reminder.getString("text")

        Reminders.ensureChannel(context)
        val open = PendingIntent.getActivity(context, id,
            Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val notification = android.app.Notification.Builder(context, Reminders.CHANNEL)
            .setSmallIcon(R.drawable.ic_voice_notification)
            .setContentTitle("Напоминание")
            .setContentText(text)
            .setStyle(android.app.Notification.BigTextStyle().bigText(text))
            .setContentIntent(open)
            .setAutoCancel(true)
            .setCategory(android.app.Notification.CATEGORY_REMINDER)
            .build()
        if (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(
                Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            context.getSystemService(NotificationManager::class.java).notify(10_000 + id, notification)
        }

        if (reminder.getBoolean("daily")) {
            reminder.put("at", reminder.getLong("at") + 24 * 60 * 60 * 1000L)
            Reminders.save(context, reminder)
            Reminders.arm(context, reminder)
        } else {
            Reminders.cancel(context, id)
        }

        speak(context, "Напоминаю: $text")
    }

    /** Голос из закрытого приложения: receiver живёт ещё до 10 секунд. */
    private fun speak(context: Context, text: String) {
        val pending = goAsync()
        var tts: TextToSpeech? = null
        val done = Runnable {
            tts?.shutdown()
            pending.finish()
        }
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        handler.postDelayed(done, 9000)
        tts = TextToSpeech(context.applicationContext) { status ->
            if (status != TextToSpeech.SUCCESS) return@TextToSpeech
            tts?.language = Locale("ru", "RU")
            tts?.setOnUtteranceProgressListener(object : android.speech.tts.UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) {
                    handler.removeCallbacks(done); handler.post(done)
                }
                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    handler.removeCallbacks(done); handler.post(done)
                }
            })
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "reminder")
        }
    }
}

/**
 * Присмотр за телефоном пожилого человека: если заряд опустился ниже 15%,
 * близким уходит SMS — «телефон мамы скоро выключится». Проверка раз в
 * полчаса, не чаще одного SMS за 6 часов.
 */
object BatteryWatch {
    private const val PREFS = "battery_watch"
    private const val THRESHOLD = 15
    private const val QUIET_MS = 6 * 60 * 60 * 1000L

    fun numbers(context: Context): List<String> =
        context.getSharedPreferences(PREFS, 0).getString("numbers", "")!!
            .split(',').filter { it.isNotBlank() }

    fun configure(context: Context, numbers: List<String>) {
        context.getSharedPreferences(PREFS, 0).edit()
            .putString("numbers", numbers.joinToString(",")).apply()
        if (numbers.isEmpty()) cancel(context) else arm(context)
    }

    private fun pending(context: Context) = PendingIntent.getBroadcast(
        context, 7300, Intent(context, BatteryWatchReceiver::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    fun arm(context: Context) {
        if (numbers(context).isEmpty()) return
        context.getSystemService(AlarmManager::class.java).setInexactRepeating(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + AlarmManager.INTERVAL_HALF_HOUR,
            AlarmManager.INTERVAL_HALF_HOUR,
            pending(context))
    }

    private fun cancel(context: Context) =
        context.getSystemService(AlarmManager::class.java).cancel(pending(context))

    fun check(context: Context) {
        val numbers = numbers(context)
        if (numbers.isEmpty()) return
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return
        val level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) * 100 /
            battery.getIntExtra(BatteryManager.EXTRA_SCALE, 100).coerceAtLeast(1)
        val status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
        if (level < 0 || level > THRESHOLD || charging) return

        val prefs = context.getSharedPreferences(PREFS, 0)
        val now = System.currentTimeMillis()
        if (now - prefs.getLong("last", 0) < QUIET_MS) return
        if (context.checkSelfPermission(Manifest.permission.SEND_SMS) !=
            PackageManager.PERMISSION_GRANTED) return

        val sms = if (Build.VERSION.SDK_INT >= 31) context.getSystemService(SmsManager::class.java)
            else @Suppress("DEPRECATION") SmsManager.getDefault()
        val text = "Телефон почти разрядился ($level%) и скоро выключится. " +
            "Если не дозвонитесь — это из-за батареи. (Alym AI)"
        for (number in numbers) runCatching { sms.sendTextMessage(number, null, text, null, null) }
        prefs.edit().putLong("last", now).apply()
    }
}

class BatteryWatchReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = BatteryWatch.check(context)
}

/** После перезагрузки будильники Android стираются — взводим заново. */
class CareBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != "android.intent.action.MY_PACKAGE_REPLACED") return
        Reminders.rearmAll(context)
        BatteryWatch.arm(context)
    }
}
