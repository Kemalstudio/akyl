package dev.akyl.akyl

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioRecordingConfiguration
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AudioEffect
import android.media.audiofx.NoiseSuppressor
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Единственный владелец микрофона в процессе: 16 кГц, моно, 16 бит,
 * кусками по 32 мс (окно Silero VAD). Подписка Dart открывает запись,
 * отписка закрывает. Второй подписчик не создаёт второй AudioRecord —
 * прежняя запись сначала полностью останавливается.
 *
 * Источник VOICE_RECOGNITION: Android не накладывает на него обработку для
 * звонков, которая портит распознавание. Если человек включил подавление
 * эха — VOICE_COMMUNICATION с AcousticEchoCanceler: тогда ответ помощника
 * из динамика не слышен в микрофоне и перебивать можно просто речью.
 */
object MicHub : EventChannel.StreamHandler {
    const val CHANNEL = "dev.akyl/mic"
    private const val SAMPLE_RATE = 16000
    private const val CHUNK_BYTES = 1024 // 512 отсчётов = одно окно VAD

    private val main = Handler(Looper.getMainLooper())
    private lateinit var context: Context

    @Volatile private var running = false
    private var recorder: AudioRecord? = null
    private var thread: Thread? = null
    private val effects = mutableListOf<AudioEffect>()
    private var recordingCallback: AudioManager.AudioRecordingCallback? = null

    // Для экрана настроек и отладки.
    var open = false
        private set
    var silenced = false
        private set
    var aecActive = false
        private set
    var nsActive = false
        private set
    var source = ""
        private set

    fun init(context: Context) {
        this.context = context.applicationContext
    }

    val aecAvailable: Boolean get() = AcousticEchoCanceler.isAvailable()

    @SuppressLint("MissingPermission")
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        if (!stopCapture()) {
            events.error("MIC", "Предыдущая запись ещё закрывается", null)
            return
        }
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED) {
            events.error("PERMISSION", "Нет разрешения на микрофон", null)
            return
        }
        val args = arguments as? Map<*, *>
        val wantAec = args?.get("aec") == true
        val wantNs = args?.get("ns") == true
        val audioSource = if (wantAec) MediaRecorder.AudioSource.VOICE_COMMUNICATION
            else MediaRecorder.AudioSource.VOICE_RECOGNITION

        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val capture = try {
            AudioRecord(
                audioSource,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                maxOf(minBuffer, CHUNK_BYTES * 8),
            )
        } catch (e: IllegalArgumentException) {
            events.error("MIC", "Микрофон не поддерживает 16 кГц", null)
            return
        } catch (e: SecurityException) {
            events.error("PERMISSION", "Доступ к микрофону отозван", null)
            return
        }
        if (capture.state != AudioRecord.STATE_INITIALIZED) {
            capture.release()
            events.error("MIC", "Микрофон занят другим приложением", null)
            return
        }
        attachEffects(capture.audioSessionId, wantAec, wantNs)
        source = if (wantAec) "VOICE_COMMUNICATION" else "VOICE_RECOGNITION"
        watchSilencing(capture)

        running = true
        open = true
        recorder = capture
        VoiceLog.i("AUDIO", "запись открыта: $source, AEC=$aecActive, NS=$nsActive")
        thread = Thread({
            try {
                capture.startRecording()
                if (capture.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                    main.post { if (running && recorder === capture)
                        events.error("MIC", "Микрофон занят другим приложением", null) }
                    return@Thread
                }
                val buffer = ByteArray(CHUNK_BYTES)
                while (running) {
                    val read = capture.read(buffer, 0, buffer.size)
                    if (read < 0) {
                        // ERROR_DEAD_OBJECT: сменился маршрут (Bluetooth), сервер
                        // аудио перезапустился. Dart переоткроет запись.
                        main.post { if (running && recorder === capture)
                            events.error("MIC", "Микрофон перестал передавать звук ($read)", null) }
                        break
                    }
                    if (read == 0) continue
                    val chunk = buffer.copyOf(read)
                    main.post { if (running && recorder === capture) events.success(chunk) }
                }
            } catch (e: IllegalStateException) {
                main.post { if (running && recorder === capture)
                    events.error("MIC", "Микрофон остановился", null) }
            } catch (e: SecurityException) {
                main.post { if (running && recorder === capture)
                    events.error("PERMISSION", "Доступ к микрофону отозван", null) }
            } finally {
                runCatching { capture.stop() }
                capture.release()
                main.post {
                    if (recorder === capture) {
                        running = false
                        recorder = null
                        thread = null
                        open = false
                        releaseEffects()
                    }
                }
            }
        }, "akyl-mic").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    override fun onCancel(arguments: Any?) {
        stopCapture()
    }

    /** true — запись освобождена и можно открывать новую. */
    fun stopCapture(): Boolean {
        running = false
        val capture = recorder
        recorder = null
        runCatching { capture?.stop() }
        val oldThread = thread
        if (oldThread != null && oldThread !== Thread.currentThread()) {
            runCatching { oldThread.join(500) }
        }
        thread = if (oldThread?.isAlive == true) oldThread else null
        releaseEffects()
        unwatchSilencing()
        if (open) VoiceLog.i("AUDIO", "запись закрыта")
        open = false
        return oldThread?.isAlive != true
    }

    private fun attachEffects(session: Int, aec: Boolean, ns: Boolean) {
        releaseEffects()
        if (aec && AcousticEchoCanceler.isAvailable()) {
            AcousticEchoCanceler.create(session)?.let {
                it.enabled = true
                effects.add(it)
                aecActive = it.enabled
            }
        }
        if (ns && NoiseSuppressor.isAvailable()) {
            NoiseSuppressor.create(session)?.let {
                it.enabled = true
                effects.add(it)
                nsActive = it.enabled
            }
        }
    }

    private fun releaseEffects() {
        effects.forEach { runCatching { it.release() } }
        effects.clear()
        aecActive = false
        nsActive = false
    }

    /**
     * Android заглушает запись (отдаёт нули), когда микрофон забирает
     * звонок или приложение с приоритетом. Без этого сигнала помощник
     * молча «глох» бы — теперь Dart показывает причину.
     */
    private fun watchSilencing(capture: AudioRecord) {
        unwatchSilencing()
        val audio = context.getSystemService(AudioManager::class.java)
        val session = capture.audioSessionId
        val callback = object : AudioManager.AudioRecordingCallback() {
            override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>) {
                val ours = configs.firstOrNull { it.clientAudioSessionId == session } ?: return
                val now = ours.isClientSilenced
                if (now != silenced) {
                    silenced = now
                    VoiceLog.i("AUDIO", if (now) "запись заглушена системой" else "запись снова слышна")
                    VoiceEvents.emit("silenced", now)
                }
            }
        }
        audio.registerAudioRecordingCallback(callback, main)
        recordingCallback = callback
    }

    private fun unwatchSilencing() {
        val callback = recordingCallback ?: return
        recordingCallback = null
        runCatching {
            context.getSystemService(AudioManager::class.java).unregisterAudioRecordingCallback(callback)
        }
        if (silenced) {
            silenced = false
            VoiceEvents.emit("silenced", false)
        }
    }
}
