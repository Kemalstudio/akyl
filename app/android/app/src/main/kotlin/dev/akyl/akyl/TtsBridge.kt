package dev.akyl.akyl

import android.content.Context
import android.media.AudioAttributes
import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Голосовой ответ встроенным движком Android (ТЗ, раздел 4: TTS, старт).
 *
 * Качество здесь решает не движок, а выбор голоса: в системе обычно стоит
 * несколько русских, и по умолчанию берётся не лучший. Поэтому голос
 * выбирается явно — самый качественный из тех, что не ходят в сеть.
 *
 * Темп чуть медленнее и тон чуть ниже обычного: ассистент проговаривает
 * короткие фразы вроде «Звоню Маме», и на них стандартная скорость звучит
 * тараторящей.
 */
class TtsBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.akyl/tts"
        private const val UTTERANCE_ID = "akyl"

        /** Медленнее обычного: короткую фразу нужно успеть разобрать. */
        private const val DEFAULT_RATE = 0.94f

        /** Чуть ниже обычного: звучит спокойнее, без «мультяшности». */
        private const val DEFAULT_PITCH = 0.96f
    }

    private var tts: TextToSpeech? = null
    private var ready = false

    /** Фраза, произнесённая до того, как движок успел инициализироваться. */
    private var queued: String? = null

    private var rate = DEFAULT_RATE
    private var pitch = DEFAULT_PITCH

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                val locale = call.argument<String>("locale") ?: "ru_RU"
                rate = (call.argument<Double>("rate") ?: DEFAULT_RATE.toDouble()).toFloat()
                pitch = (call.argument<Double>("pitch") ?: DEFAULT_PITCH.toDouble()).toFloat()
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

            /** Какой голос выбран — показывается в настройках приложения. */
            "voiceName" -> result.success(tts?.voice?.name)

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
            if (!ready) return@TextToSpeech

            tts?.apply {
                language = locale
                setSpeechRate(rate)
                setPitch(pitch)
                // Голос ассистента, а не музыка: система сама приглушит
                // под него плеер и направит в нужный выход.
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANT)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                bestVoiceFor(this, locale)?.let { voice = it }
            }

            queued?.let { speak(it) }
            queued = null
        }
    }

    /**
     * Лучший голос для языка: сначала отсекаются требующие сети, затем
     * выбирается самый высокий заявленный уровень качества.
     *
     * Сетевой голос отбрасывается не ради качества, а ради обещания из ТЗ:
     * приложение работает офлайн, и ответ не должен зависеть от связи.
     */
    private fun bestVoiceFor(engine: TextToSpeech, locale: Locale): Voice? {
        val voices = try {
            engine.voices
        } catch (e: Exception) {
            null
        } ?: return null

        return voices
            .filter { it.locale.language == locale.language }
            .filterNot { it.isNetworkConnectionRequired }
            .filterNot { it.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) }
            .maxByOrNull { it.quality }
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
