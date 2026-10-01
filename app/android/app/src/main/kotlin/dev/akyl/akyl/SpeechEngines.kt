package dev.akyl.akyl

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.speech.RecognitionService
import android.speech.SpeechRecognizer

/**
 * Chooses a speech engine: the on-device one first, otherwise the system
 * recognizer (usually Google's). Without an offline Russian pack the phone
 * would not hear anything at all, so the fallback is deliberate.
 *
 * The fallback must never be our own [AssistantRecognitionService]: while
 * Alym AI is the selected assistant Android may make it the default
 * recognizer, and it would forward the request back into itself.
 */
object SpeechEngines {
    fun onDeviceAvailable(context: Context): Boolean =
        Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(context)

    /** A recognition service from another package, preferring the user's default. */
    fun fallbackComponent(context: Context): ComponentName? {
        val own = context.packageName
        Settings.Secure.getString(context.contentResolver, "voice_recognition_service")
            ?.let(ComponentName::unflattenFromString)
            ?.takeIf { it.packageName != own }
            ?.let { return it }
        val services = context.packageManager.queryIntentServices(
            Intent(RecognitionService.SERVICE_INTERFACE), 0)
        val others = services.mapNotNull { it.serviceInfo }.filter { it.packageName != own }
        val preferred = others.firstOrNull { it.packageName == "com.google.android.tts" }
            ?: others.firstOrNull { it.packageName == "com.google.android.googlequicksearchbox" }
            ?: others.firstOrNull()
        return preferred?.let { ComponentName(it.packageName, it.name) }
    }

    fun anyAvailable(context: Context): Boolean =
        onDeviceAvailable(context) || fallbackComponent(context) != null

    /** [preferOnDevice] false forces the fallback, e.g. after a language error. */
    fun create(context: Context, preferOnDevice: Boolean): SpeechRecognizer? {
        if (preferOnDevice && Build.VERSION.SDK_INT >= 31 &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
            return SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        }
        val component = fallbackComponent(context) ?: return null
        return SpeechRecognizer.createSpeechRecognizer(context, component)
    }

    fun isLanguageError(error: Int): Boolean =
        error == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ||
            error == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE
}
