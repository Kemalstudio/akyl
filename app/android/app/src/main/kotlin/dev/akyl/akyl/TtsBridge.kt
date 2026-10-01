package dev.akyl.akyl

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Голосовой ответ встроенным движком Android.
 *
 * Качество здесь решает не движок, а выбор голоса: в системе обычно стоит
 * несколько русских, и по умолчанию берётся не лучший. Поэтому голос
 * выбирается явно — самый качественный из тех, что не ходят в сеть, —
 * или тот, что человек выбрал в настройках.
 *
 * На время ответа берётся аудиофокус с приглушением: музыка стихает, а не
 * перекрикивает помощника. Начало каждого слова уходит в Dart — анимация
 * говорящего помощника идёт в ритме речи.
 */
class TtsBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.akyl/tts"
        const val EVENTS = "dev.akyl/tts_events"
        private const val UTTERANCE_ID = "akyl"

        /** Медленнее обычного: короткую фразу нужно успеть разобрать. */
        private const val DEFAULT_RATE = 0.94f

        /** Чуть ниже обычного: звучит спокойнее, без «мультяшности». */
        private const val DEFAULT_PITCH = 0.96f
    }

    private var tts: TextToSpeech? = null
    private var ready = false
    private var initialized = false
    private val handler = Handler(Looper.getMainLooper())
    private var pendingSpeech: MethodChannel.Result? = null
    private var utterance = 0
    private val timeout = Runnable { completeSpeech("Озвучка не завершилась вовремя") }
    private var locale: Locale = Locale("ru", "RU")
    private var preferredVoice: String? = null

    private val audio = context.getSystemService(AudioManager::class.java)
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANT)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()
    private val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        .setAudioAttributes(attributes)
        .setOnAudioFocusChangeListener { change ->
            // Входящий звонок или другое приложение забрали звук — замолкаем.
            if (change == AudioManager.AUDIOFOCUS_LOSS ||
                change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) {
                handler.post { stopSpeaking() }
            }
        }
        .build()

    /** Начало слова, конец фразы — для анимации и замера задержки. */
    class Events : EventChannel.StreamHandler {
        var sink: EventChannel.EventSink? = null
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
        override fun onCancel(arguments: Any?) { sink = null }
    }

    val events = Events()

    private fun emit(type: String) = handler.post { events.sink?.success(mapOf("type" to type)) }

    private fun completeSpeech(error: String? = null) {
        handler.removeCallbacks(timeout)
        audio.abandonAudioFocusRequest(focusRequest)
        val pending = pendingSpeech
        pendingSpeech = null
        if (error == null) pending?.success(null) else pending?.error("TTS", error, null)
    }

    /** Фраза, произнесённая до того, как движок успел инициализироваться. */
    private var queued: String? = null

    private var rate = DEFAULT_RATE
    private var pitch = DEFAULT_PITCH

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                val tag = call.argument<String>("locale") ?: "ru_RU"
                rate = (call.argument<Double>("rate") ?: DEFAULT_RATE.toDouble()).toFloat()
                pitch = (call.argument<Double>("pitch") ?: DEFAULT_PITCH.toDouble()).toFloat()
                init(tag)
                result.success(null)
            }

            "speak" -> {
                val text = call.argument<String>("text")
                if (text.isNullOrEmpty()) {
                    result.success(null)
                } else {
                    completeSpeech()
                    utterance++
                    pendingSpeech = result
                    handler.postDelayed(timeout, 20000)
                    speak(text)
                }
            }

            "stop" -> {
                stopSpeaking()
                result.success(null)
            }

            /** Какой голос выбран — показывается в настройках приложения. */
            "voiceName" -> result.success(tts?.voice?.name)

            "voices" -> result.success(
                offlineVoices().map {
                    mapOf("name" to it.name, "quality" to it.quality, "local" to true)
                },
            )

            "setVoice" -> {
                preferredVoice = call.argument<String>("name")
                applyVoice()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun stopSpeaking() {
        tts?.stop()
        queued = null
        completeSpeech()
    }

    private fun init(localeTag: String) {
        if (tts != null) return
        locale = localeTag.split("_").let {
            if (it.size >= 2) Locale(it[0], it[1]) else Locale(it[0])
        }
        tts = TextToSpeech(context) { status ->
            initialized = true
            ready = status == TextToSpeech.SUCCESS
            if (!ready) {
                completeSpeech("Голосовой движок недоступен")
                return@TextToSpeech
            }

            tts?.apply {
                setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(id: String?) { emit("start") }
                    override fun onRangeStart(id: String?, start: Int, end: Int, frame: Int) {
                        emit("word")
                    }
                    override fun onDone(id: String?) { handler.post {
                        emit("done")
                        if (id == "$UTTERANCE_ID-$utterance") completeSpeech()
                    } }
                    @Deprecated("Android callback")
                    override fun onError(id: String?) { handler.post {
                        if (id == "$UTTERANCE_ID-$utterance") completeSpeech("Не удалось произнести ответ")
                    } }
                })
                language = locale
                setSpeechRate(rate)
                setPitch(pitch)
                // Голос ассистента, а не музыка: система сама приглушит
                // под него плеер и направит в нужный выход.
                setAudioAttributes(attributes)
            }
            applyVoice()

            if (ready) queued?.let { speak(it) }
            queued = null
        }
    }

    private fun applyVoice() {
        val engine = tts ?: return
        if (!initialized) return
        val voices = offlineVoices()
        val chosen = voices.firstOrNull { it.name == preferredVoice } ?: voices.maxByOrNull { it.quality }
        if (chosen == null) {
            ready = false
            completeSpeech("Установите русский офлайн-голос в настройках Android")
        } else {
            engine.voice = chosen
            ready = true
        }
    }

    /**
     * Голоса языка ответа без сети. Сетевой голос отбрасывается не ради
     * качества, а ради обещания: ответ не зависит от связи.
     */
    private fun offlineVoices(): List<Voice> {
        val engine = tts ?: return emptyList()
        val voices = try { engine.voices } catch (e: Exception) { null } ?: return emptyList()
        return voices
            .filter { it.locale.language == locale.language }
            .filterNot { it.isNetworkConnectionRequired }
            .filterNot { it.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) }
            .sortedByDescending { it.quality }
    }

    private fun speak(text: String) {
        val engine = tts
        if (initialized && !ready) {
            completeSpeech("Русский офлайн-голос недоступен")
            return
        }
        if (engine == null || !ready) {
            // Первая команда может прийти раньше готовности движка — не теряем её.
            queued = text
            return
        }
        audio.requestAudioFocus(focusRequest)
        if (engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "$UTTERANCE_ID-$utterance") == TextToSpeech.ERROR) {
            completeSpeech("Не удалось произнести ответ")
        }
    }

    fun dispose() {
        completeSpeech()
        tts?.stop()
        tts?.shutdown()
        tts = null
        ready = false
        initialized = false
    }
}
