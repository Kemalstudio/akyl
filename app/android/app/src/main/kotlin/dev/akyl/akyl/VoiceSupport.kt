package dev.akyl.akyl

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.lang.ref.WeakReference

/**
 * Экран приложения, если он сейчас есть. Нужен только для системных
 * диалогов разрешений: всё остальное работает от контекста приложения,
 * потому что голос живёт и без экрана.
 */
object ActivityHolder {
    private var ref: WeakReference<Activity>? = null

    val current: Activity?
        get() = ref?.get()?.takeUnless { it.isFinishing || it.isDestroyed }

    /** Экран виден (между onStart и onStop): Android разрешает открывать другие экраны. */
    @Volatile var visible = false

    fun attach(activity: Activity) {
        ref = WeakReference(activity)
    }

    fun detach(activity: Activity) {
        if (ref?.get() === activity) ref = null
    }
}

/**
 * Журнал голоса в logcat с теми же тегами, что в Dart: [VOICE], [AUDIO]…
 * Текст речи сюда не пишется — только события.
 */
object VoiceLog {
    private const val TAG = "AkylVoice"
    fun i(tag: String, message: String) = Log.i(TAG, "[$tag] $message")
    fun w(tag: String, message: String) = Log.w(TAG, "[$tag] $message")
}

/**
 * Системные события для Dart: блокировка экрана, звонок, заглушённый
 * микрофон, служба. Шлются в главном потоке — туда, где живёт EventSink.
 */
object VoiceEvents : EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun emit(type: String, value: Boolean = false, extra: Map<String, Any?> = emptyMap()) {
        val event = HashMap<String, Any?>(extra).apply {
            put("type", type)
            put("value", value)
        }
        if (Looper.myLooper() == Looper.getMainLooper()) sink?.success(event)
        else main.post { sink?.success(event) }
    }
}

/**
 * Команда из системного жеста помощника. Передаётся внутри процесса и
 * никогда не берётся из параметров чужого Intent.
 */
object VoiceCommandInbox {
    private var pending: String? = null
    private var receivedAt = 0L

    fun put(command: String) {
        pending = command
        receivedAt = SystemClock.elapsedRealtime()
    }

    fun take(): String? {
        val command = pending
        pending = null
        return if (SystemClock.elapsedRealtime() - receivedAt <= 15000) command else null
    }
}
