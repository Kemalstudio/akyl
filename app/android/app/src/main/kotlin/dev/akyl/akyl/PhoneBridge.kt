package dev.akyl.akyl

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telephony.SmsManager
import android.telecom.TelecomManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Звонок и SMS. Единственное место, где приложение говорит с телефонией —
 * вся логика решений остаётся в Dart (ТЗ, раздел 5).
 */
class PhoneBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.akyl/phone"
        private const val PERMISSION_REQUEST_CODE = 4201

        private val REQUIRED = arrayOf(
            Manifest.permission.CALL_PHONE,
            Manifest.permission.SEND_SMS,
            Manifest.permission.READ_CONTACTS,
            // Распознавание речи (ТЗ, FR-2). Спрашивается вместе с остальными,
            // чтобы человек прошёл один диалог, а не четыре подряд.
            Manifest.permission.RECORD_AUDIO,
        )
    }

    /** Ответ Flutter, ожидающий результата системного диалога разрешений. */
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val speakerphone = Speakerphone(activity)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermissions" -> result.success(hasAllPermissions())

            "requestPermissions" -> requestPermissions(result)

            "call" -> {
                val number = call.argument<String>("number")
                val speaker = call.argument<Boolean>("speaker") ?: false
                if (number.isNullOrBlank()) {
                    result.error("BAD_ARGS", "Номер не передан", null)
                } else {
                    placeCall(number, speaker, result)
                }
            }

            "sendSms" -> {
                val number = call.argument<String>("number")
                val text = call.argument<String>("text")
                if (number.isNullOrBlank() || text == null) {
                    result.error("BAD_ARGS", "Нужны number и text", null)
                } else {
                    sendSms(number, text, result)
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun hasAllPermissions(): Boolean = REQUIRED.all {
        ContextCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (hasAllPermissions()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("BUSY", "Запрос разрешений уже идёт", null)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(activity, REQUIRED, PERMISSION_REQUEST_CODE)
    }

    /** Экран уходит — ожидание соединения больше не нужно. */
    fun dispose() = speakerphone.cancel()

    /** Вызывается из MainActivity: системный диалог закрылся. */
    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        pendingPermissionResult?.success(hasAllPermissions())
        pendingPermissionResult = null
        return true
    }

    /**
     * ACTION_CALL, а не ACTION_DIAL: звонок начинается сразу, без экрана набора.
     * Без этого бюджет в 1 секунду из ТЗ теряет смысл — пользователю всё равно
     * пришлось бы достать телефон и нажать кнопку.
     */
    private fun placeCall(number: String, speaker: Boolean, result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.CALL_PHONE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            result.error("NO_PERMISSION", "Нет разрешения CALL_PHONE", null)
            return
        }
        try {
            val intent = Intent(Intent.ACTION_CALL, Uri.fromParts("tel", number, null)).apply {
                putExtra(TelecomManager.EXTRA_START_CALL_WITH_SPEAKERPHONE, speaker)
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            // Динамик включается, когда звонок соединится, — не сейчас.
            if (speaker) speakerphone.enableWhenCallStarts()
            result.success(null)
        } catch (e: Exception) {
            speakerphone.cancel()
            result.error("CALL_FAILED", e.message, null)
        }
    }

    private fun sendSms(number: String, text: String, result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.SEND_SMS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            result.error("NO_PERMISSION", "Нет разрешения SEND_SMS", null)
            return
        }
        try {
            val manager = smsManager()
            // Длинное сообщение телефония не отправит одним куском.
            val parts = manager.divideMessage(text)
            if (parts.size == 1) {
                manager.sendTextMessage(number, null, text, null, null)
            } else {
                manager.sendMultipartTextMessage(number, null, parts, null, null)
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("SMS_FAILED", e.message, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun smsManager(): SmsManager =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            activity.getSystemService(SmsManager::class.java)
        } else {
            SmsManager.getDefault()
        }
}
