package dev.akyl.akyl

import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognitionService
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

/** Recognition endpoint required by the Android assistant role. On-device first, then the system engine. */
class AssistantRecognitionService : RecognitionService() {
    private var engine: SpeechRecognizer? = null
    private var generation = 0
    private var onDevice = true

    override fun onStartListening(recognizerIntent: Intent, callback: Callback) {
        release()
        val token = generation
        // Микрофон нужен чужому распознаванию — наш конвейер уступает.
        VoiceEvents.emit("recognition", true)
        try {
            val created = SpeechEngines.create(this, onDevice)
            if (created == null) {
                callback.error(SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE)
                release()
                return
            }
            engine = created.also { recognizer ->
                recognizer.setRecognitionListener(object : RecognitionListener {
                    private fun send(action: () -> Unit) {
                        if (generation == token) runCatching(action)
                    }
                    override fun onReadyForSpeech(params: Bundle?) = send { callback.readyForSpeech(params ?: Bundle()) }
                    override fun onBeginningOfSpeech() = send { callback.beginningOfSpeech() }
                    override fun onRmsChanged(rmsdB: Float) = send { callback.rmsChanged(rmsdB) }
                    override fun onBufferReceived(buffer: ByteArray?) = send { if (buffer != null) callback.bufferReceived(buffer) }
                    override fun onEndOfSpeech() = send { callback.endOfSpeech() }
                    override fun onPartialResults(partialResults: Bundle?) = send { callback.partialResults(partialResults ?: Bundle()) }
                    override fun onEvent(eventType: Int, params: Bundle?) {}
                    override fun onResults(results: Bundle?) {
                        send { callback.results(results ?: Bundle()) }
                        if (generation == token) release()
                    }
                    override fun onError(error: Int) {
                        // No offline pack: repeat the same request on the system recognizer.
                        if (generation == token && onDevice && SpeechEngines.isLanguageError(error)) {
                            onDevice = false
                            onStartListening(recognizerIntent, callback)
                            return
                        }
                        send { callback.error(error) }
                        if (generation == token) release()
                    }
                })
                recognizer.startListening(Intent(recognizerIntent).apply {
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                })
            }
        } catch (_: RuntimeException) {
            callback.error(SpeechRecognizer.ERROR_CLIENT)
            release()
        }
    }

    override fun onStopListening(callback: Callback) { engine?.stopListening() }
    override fun onCancel(callback: Callback) { release() }
    private fun release() {
        generation++
        engine?.destroy()
        engine = null
        VoiceEvents.emit("recognition", false)
    }
    override fun onDestroy() { release(); super.onDestroy() }
}
