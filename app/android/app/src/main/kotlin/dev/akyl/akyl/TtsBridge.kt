package dev.akyl.akyl

import android.content.Context
import android.speech.tts.TextToSpeech
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Голосовой ответ встроенным движком Android (ТЗ, раздел 4: TTS, старт).
 * Ничего не весит и работает офлайн, если в системе установлен русский голос.
 * Piper ru_RU заменит это в v1.0 — на стороне Dart интерфейс тот же.
 */
class TtsBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.akyl/tts"
        private const val UTTERANCE_ID = "akyl"
    }

    private var tts: TextToSpeech? = null
    private var ready = false

    /** Фраза, произнесённая до того, как движок успел инициализироваться. */
    private var queued: String? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                val locale = call.argument<String>("locale") ?: "ru_RU"
                init(locale)
                result.success(null)
            }

            "speak" -> {
                val text = call.argument<String>("text")
                if (text.isNullOrEmpty()) {
                    result.success(null)
                } else {
                    speak(text)
                    result.success(null)
                }
            }

            "stop" -> {
                tts?.stop()
                queued = null
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun init(localeTag: String) {
        if (tts != null) return
        val locale = localeTag.split("_").let {
            if (it.size >= 2) Locale(it[0], it[1]) else Locale(it[0])
        }
        tts = TextToSpeech(context) { status ->
            ready = status == TextToSpeech.SUCCESS
            if (ready) {
                tts?.language = locale
                queued?.let { speak(it) }
                queued = null
            }
        }
    }

    private fun speak(text: String) {
        val engine = tts
        if (engine == null || !ready) {
            // Первая команда может прийти раньше готовности движка — не теряем её.
            queued = text
            return
        }
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, UTTERANCE_ID)
    }

    fun dispose() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        ready = false
    }
}
