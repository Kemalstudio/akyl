package dev.akyl.akyl

import android.Manifest
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Системная сторона голоса для VoiceManager (Dart): служба микрофона,
 * блокировка экрана, звонки, сигналы, выбор помощника.
 */
class VoiceBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.akyl/voice"
        const val EVENTS = "dev.akyl/voice_events"
        private const val PREFS = "hands_free"
        private const val KEY_BACKGROUND = "enabled"

        /** Фон включён — его читает AssistantVoiceService после перезагрузки. */
        fun backgroundEnabled(context: Context) =
            context.getSharedPreferences(PREFS, 0).getBoolean(KEY_BACKGROUND, false)

        fun setBackgroundFlag(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREFS, 0).edit().putBoolean(KEY_BACKGROUND, enabled).apply()
        }

        fun locked(context: Context): Boolean =
            context.getSystemService(KeyguardManager::class.java).isKeyguardLocked

        fun inCall(context: Context): Boolean {
            val mode = context.getSystemService(AudioManager::class.java).mode
            return mode == AudioManager.MODE_IN_CALL ||
                mode == AudioManager.MODE_IN_COMMUNICATION ||
                mode == AudioManager.MODE_RINGTONE
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private var lastLocked: Boolean? = null
    private var lastCall: Boolean? = null

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            // Экран выключили — это ещё не блокировка: Android запирает не сразу.
            main.postDelayed({ reportLock() }, if (intent.action == Intent.ACTION_SCREEN_OFF) 1500 else 0)
        }
    }

    private var modeListener: Any? = null
    private val callPoll = object : Runnable {
        override fun run() {
            reportCall()
            main.postDelayed(this, 2000)
        }
    }

    init {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(screenReceiver, filter)
        }
        watchCalls()
    }

    /** Звонок забирает микрофон — голос должен уступить и вернуться после. */
    private fun watchCalls() {
        val audio = context.getSystemService(AudioManager::class.java)
        if (Build.VERSION.SDK_INT >= 31) {
            val listener = AudioManager.OnModeChangedListener { reportCall() }
            audio.addOnModeChangedListener(context.mainExecutor, listener)
            modeListener = listener
        } else {
            main.postDelayed(callPoll, 2000)
        }
    }

    private fun reportLock() {
        val now = locked(context)
        if (now == lastLocked) return
        lastLocked = now
        VoiceEvents.emit("lock", now)
    }

    private fun reportCall() {
        val now = inCall(context)
        if (now == lastCall) return
        lastCall = now
        VoiceLog.i("AUDIO", if (now) "идёт звонок" else "звонок окончен")
        VoiceEvents.emit("call", now)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> {
                val power = context.getSystemService(PowerManager::class.java)
                val notifications = context.getSystemService(NotificationManager::class.java)
                result.success(mapOf(
                    "serviceRunning" to VoiceService.running,
                    "assistantSelected" to AssistantVoiceService.isSelected(context),
                    "locked" to locked(context),
                    "callActive" to inCall(context),
                    "micSilenced" to MicHub.silenced,
                    "ignoringBatteryOptimizations" to power.isIgnoringBatteryOptimizations(context.packageName),
                    "aecAvailable" to MicHub.aecAvailable,
                    "aecActive" to MicHub.aecActive,
                    "nsActive" to MicHub.nsActive,
                    "audioSource" to MicHub.source,
                    "notificationsAllowed" to notifications.areNotificationsEnabled(),
                ))
            }
            "startService" -> {
                askNotifications()
                result.success(VoiceService.start(context))
            }
            "stopService" -> {
                VoiceService.stop(context)
                result.success(null)
            }
            "updateNotification" -> {
                VoiceService.updateText(context, call.argument<String>("text") ?: "")
                result.success(null)
            }
            "setBackgroundEnabled" -> {
                setBackgroundFlag(context, call.argument<Boolean>("enabled") == true)
                result.success(null)
            }
            "playCue" -> {
                Earcon.play(call.argument<String>("cue") ?: "listening")
                result.success(null)
            }
            "selectAssistant" -> {
                open(Intent(Settings.ACTION_VOICE_INPUT_SETTINGS), result)
            }
            "openBatterySettings" -> {
                open(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS), result)
            }
            "takeCommand" -> result.success(VoiceCommandInbox.take())
            else -> result.notImplemented()
        }
    }

    private fun open(intent: Intent, result: MethodChannel.Result) {
        try {
            val activity = ActivityHolder.current
            if (activity != null) activity.startActivity(intent)
            else context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            result.success(null)
        } catch (_: RuntimeException) {
            result.error("SETTINGS", "Не удалось открыть настройки", null)
        }
    }

    /** Без разрешения уведомление службы не видно — а человек должен знать. */
    private fun askNotifications() {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED) {
            ActivityHolder.current?.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4203)
        }
    }
}
