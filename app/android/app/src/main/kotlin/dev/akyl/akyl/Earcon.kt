package dev.akyl.akyl

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * Короткий мягкий сигнал «слушаю»: две ноты с плавной огибающей, тише
 * системных звуков. Генерируется кодом — без файлов и без резкого щелчка,
 * которым раздражал системный SpeechRecognizer при каждом перезапуске.
 */
object Earcon {
    private const val RATE = 22050

    fun play(kind: String) {
        val notes = when (kind) {
            "done" -> listOf(1318.5 to 70, 987.8 to 90)
            "error" -> listOf(392.0 to 140)
            else -> listOf(880.0 to 70, 1318.5 to 90) // listening: квинта вверх
        }
        val samples = render(notes)
        val track = try {
            AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(RATE)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                )
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(samples.size * 2)
                .build()
        } catch (e: Exception) {
            VoiceLog.w("AUDIO", "сигнал недоступен: ${e.message}")
            return
        }
        track.write(samples, 0, samples.size)
        track.setNotificationMarkerPosition(samples.size)
        track.setPlaybackPositionUpdateListener(object : AudioTrack.OnPlaybackPositionUpdateListener {
            override fun onMarkerReached(t: AudioTrack) { t.release() }
            override fun onPeriodicNotification(t: AudioTrack) {}
        })
        runCatching { track.play() }.onFailure { track.release() }
    }

    private fun render(notes: List<Pair<Double, Int>>): ShortArray {
        val total = notes.sumOf { RATE * it.second / 1000 }
        val out = ShortArray(total)
        var offset = 0
        for ((freq, ms) in notes) {
            val n = RATE * ms / 1000
            for (i in 0 until n) {
                // Огибающая «приподнятый косинус»: без щелчков в начале и конце.
                val env = 0.5 * (1 - cos(2 * PI * i / n))
                val v = sin(2 * PI * freq * i / RATE) * env * 0.16
                out[offset + i] = (v * Short.MAX_VALUE).toInt().toShort()
            }
            offset += n
        }
        return out
    }
}
