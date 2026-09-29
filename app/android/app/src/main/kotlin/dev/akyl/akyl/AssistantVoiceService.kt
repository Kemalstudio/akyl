package dev.akyl.akyl

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.os.UserManager
import android.service.voice.VoiceInteractionService
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService

/**
 * Alym AI как системный помощник Android. Выбор делает сам человек в
 * настройках — приложение не меняет помощника скрытно.
 *
 * Роль даёт две вещи, без которых «Макс» не пережил бы перезагрузку:
 * Android сам привязывает этот сервис после загрузки, и ему разрешено
 * запускать microphone-службу из фона. Прослушивание — не здесь, а в
 * VoiceService + MicHub + Dart; раньше тут крутился цикл системного
 * SpeechRecognizer, который щёлкал сигналами и пропускал обращения.
 */
class AssistantVoiceService : VoiceInteractionService() {
    companion object {
        fun isSelected(context: Context) = isActiveService(
            context,
            ComponentName(context, AssistantVoiceService::class.java),
        )
    }

    private var waitingForUnlock = false

    /** До первой разблокировки после загрузки данные приложения зашифрованы. */
    private val unlockReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (!waitingForUnlock) return
            waitingForUnlock = false
            runCatching { unregisterReceiver(this) }
            startListening()
        }
    }

    override fun onReady() {
        super.onReady()
        if (!VoiceBridge.backgroundEnabled(this)) return
        val users = getSystemService(UserManager::class.java)
        if (users.isUserUnlocked) {
            startListening()
        } else {
            waitingForUnlock = true
            val filter = IntentFilter(Intent.ACTION_USER_UNLOCKED)
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(unlockReceiver, filter, RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(unlockReceiver, filter)
            }
        }
    }

    private fun startListening() {
        if (!VoiceBridge.backgroundEnabled(this)) return
        VoiceLog.i("BACKGROUND", "помощник готов — запускаю службу микрофона")
        VoiceService.start(this)
    }

    override fun onDestroy() {
        if (waitingForUnlock) runCatching { unregisterReceiver(unlockReceiver) }
        super.onDestroy()
    }
}

class AssistantSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession = AssistantSession(this)
}

/**
 * Жест помощника (долгое нажатие кнопки, «угол» экрана): открыть Alym AI
 * и сразу слушать команду.
 */
private class AssistantSession(context: Context) : VoiceInteractionSession(context) {
    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        setUiEnabled(false)
        VoiceCommandInbox.put("")
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_VOICE)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        try {
            startVoiceActivity(intent)
        } catch (_: RuntimeException) {
            VoiceCommandInbox.take()
            VoiceLog.w("BACKGROUND", "не удалось открыть помощника")
        }
        hide()
    }
}
