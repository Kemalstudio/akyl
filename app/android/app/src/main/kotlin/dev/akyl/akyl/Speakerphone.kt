package dev.akyl.akyl

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Включение громкой связи для команды «позвони маме по громкой связи».
 *
 * Включить динамик в момент запуска Intent нельзя: аудиотракт переходит
 * в режим разговора только когда звонок соединился. Поэтому здесь короткий
 * опрос состояния AudioManager, а не один вызов.
 *
 * На Android 12+ setSpeakerphoneOn объявлен устаревшим, и правильный путь —
 * setCommunicationDevice. Реализованы оба.
 */
class Speakerphone(private val context: Context) {

    companion object {
        /** Как часто проверять, что звонок соединился. */
        private const val POLL_INTERVAL_MS = 150L

        /** Сколько всего ждать соединения, прежде чем сдаться. */
        private const val TIMEOUT_MS = 8000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private var pending: Runnable? = null

    /** Отменяет предыдущее ожидание и начинает новое. */
    fun enableWhenCallStarts() {
        cancel()

        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val deadline = System.currentTimeMillis() + TIMEOUT_MS

        val poll = object : Runnable {
            override fun run() {
                if (audio.mode == AudioManager.MODE_IN_CALL ||
                    audio.mode == AudioManager.MODE_IN_COMMUNICATION
                ) {
                    apply(audio)
                    pending = null
                    return
                }
                if (System.currentTimeMillis() >= deadline) {
                    pending = null
                    return
                }
                handler.postDelayed(this, POLL_INTERVAL_MS)
            }
        }

        pending = poll
        handler.postDelayed(poll, POLL_INTERVAL_MS)
    }

    /** Пользователь отменил команду — ждать больше нечего. */
    fun cancel() {
        pending?.let { handler.removeCallbacks(it) }
        pending = null
    }

    @SuppressLint("NewApi")
    private fun apply(audio: AudioManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val speaker = audio.availableCommunicationDevices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
            }
            if (speaker != null && audio.setCommunicationDevice(speaker)) return
            // Устройство не отдалось — падаем на старый путь, он ещё работает.
        }
        @Suppress("DEPRECATION")
        audio.isSpeakerphoneOn = true
    }
}
