package dev.akyl.akyl

import android.Manifest
import android.annotation.SuppressLint
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.telephony.PhoneNumberUtils
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.os.BatteryManager
import android.provider.AlarmClock
import android.provider.CallLog
import android.provider.ContactsContract
import android.view.KeyEvent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Телефон, которым ассистент управляет голосом: заряд, будильник, таймер,
 * фонарик, громкость, последнее SMS, недавние звонки, запуск приложений.
 *
 * Каждая ошибка возвращается с текстом, который ассистент скажет вслух.
 */
class DeviceBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.akyl/device"
        private const val PERMISSION_REQUEST = 4301
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "batteryLevel" -> {
                    val manager =
                        context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    val level = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                    if (level in 0..100) result.success(level)
                    else result.error("NO_BATTERY", "Заряд недоступен", null)
                }
                "isCharging" -> result.success(isCharging())
                "setAlarm" -> {
                    val hour = call.argument<Int>("hour")!!
                    val minute = call.argument<Int>("minute")!!
                    result.success(setAlarm(hour, minute))
                }
                "setTimer" -> {
                    start(Intent(AlarmClock.ACTION_SET_TIMER)
                        .putExtra(AlarmClock.EXTRA_LENGTH, call.argument<Int>("seconds")!!)
                        .putExtra(AlarmClock.EXTRA_SKIP_UI, true),
                        "Не нашёл приложение таймера")
                    result.success(null)
                }
                "setTorch" -> {
                    setTorch(call.argument<Boolean>("on") == true)
                    result.success(null)
                }
                "changeVolume" -> {
                    changeVolume(call.argument<String>("change") ?: "up")
                    result.success(null)
                }
                "lastSms" -> {
                    if (!granted(Manifest.permission.READ_SMS)) {
                        throw UserError("Разрешите доступ к SMS и повторите команду")
                    }
                    result.success(lastSms())
                }
                "recentCalls" -> {
                    if (!granted(Manifest.permission.READ_CALL_LOG)) {
                        throw UserError("Разрешите доступ к журналу звонков и повторите команду")
                    }
                    result.success(recentCalls(call.argument<Int>("limit") ?: 3))
                }
                "openApp" -> result.success(openApp(call.argument<String>("query") ?: ""))
                "media" -> {
                    media(call.argument<String>("action") ?: "play")
                    result.success(null)
                }
                "lastCallWith" -> {
                    if (!granted(Manifest.permission.READ_CALL_LOG)) {
                        throw UserError("Разрешите доступ к журналу звонков и повторите команду")
                    }
                    result.success(lastCallWith(call.argument<List<String>>("numbers") ?: emptyList()))
                }
                "location" -> {
                    location(result)
                    return
                }
                else -> result.notImplemented()
            }
        } catch (e: UserError) {
            result.error("DEVICE", e.message, null)
        } catch (e: SecurityException) {
            result.error("DEVICE", "Android не разрешил это действие", null)
        }
    }

    private class UserError(message: String) : Exception(message)

    /**
     * «Часы» — если Android разрешит открыть их экран: приложение видно или
     * Alym AI выбран помощником. Иначе (свёрнуто, телефон на подоконнике)
     * запуск чужого экрана из фона молча блокируется — тогда будильник
     * ставит сам помощник. Возвращает, кто будет звонить: clock | own.
     */
    private fun setAlarm(hour: Int, minute: Int): String {
        if (ActivityHolder.visible || AssistantVoiceService.isSelected(context)) {
            try {
                context.startActivity(
                    Intent(AlarmClock.ACTION_SET_ALARM)
                        .putExtra(AlarmClock.EXTRA_HOUR, hour)
                        .putExtra(AlarmClock.EXTRA_MINUTES, minute)
                        .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                VoiceLog.i("ACTION", "будильник передан в «Часы»")
                return "clock"
            } catch (_: ActivityNotFoundException) {
                // Нет приложения часов — звонить будет помощник.
            }
        }
        AlarmRinger.schedule(context, hour, minute)
        return "own"
    }

    /**
     * Кнопки плеера, как на гарнитуре: Android передаёт их приложению,
     * которое сейчас играет (или играло последним). Разрешений не нужно.
     */
    private fun media(action: String) {
        val code = when (action) {
            "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
            "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            else -> KeyEvent.KEYCODE_MEDIA_PLAY
        }
        val audio = context.getSystemService(AudioManager::class.java)
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
    }

    /** Проверяет разрешение и, если его нет, сразу показывает системный запрос. */
    private fun granted(permission: String): Boolean {
        if (context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) return true
        ActivityHolder.current?.requestPermissions(arrayOf(permission), PERMISSION_REQUEST)
        return false
    }

    private fun start(intent: Intent, notFound: String) {
        try {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: ActivityNotFoundException) {
            throw UserError(notFound)
        }
    }

    private fun isCharging(): Boolean {
        val status = context.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
        )?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: return false

        return status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
    }

    private fun setTorch(on: Boolean) {
        val cameras = context.getSystemService(CameraManager::class.java)
        try {
            val id = cameras.cameraIdList.firstOrNull {
                cameras.getCameraCharacteristics(it)
                    .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            } ?: throw UserError("На телефоне нет фонарика")
            cameras.setTorchMode(id, on)
        } catch (_: CameraAccessException) {
            throw UserError("Фонарик сейчас занят камерой")
        }
    }

    private fun changeVolume(change: String) {
        val audio = context.getSystemService(AudioManager::class.java)
        val stream = AudioManager.STREAM_MUSIC
        val flags = AudioManager.FLAG_SHOW_UI
        when (change) {
            "down" -> audio.adjustStreamVolume(stream, AudioManager.ADJUST_LOWER, flags)
            "mute" -> audio.adjustStreamVolume(stream, AudioManager.ADJUST_MUTE, flags)
            "unmute" -> audio.adjustStreamVolume(stream, AudioManager.ADJUST_UNMUTE, flags)
            "max" -> audio.setStreamVolume(stream, audio.getStreamMaxVolume(stream), flags)
            else -> {
                // Два шага: одного на слух почти не слышно.
                audio.adjustStreamVolume(stream, AudioManager.ADJUST_RAISE, flags)
                audio.adjustStreamVolume(stream, AudioManager.ADJUST_RAISE, 0)
            }
        }
    }

    private fun lastSms(): Map<String, String>? {
        context.contentResolver.query(
            Uri.parse("content://sms/inbox"),
            arrayOf("address", "body"),
            null, null, "date DESC",
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val address = cursor.getString(0) ?: ""
            val body = cursor.getString(1) ?: ""
            return mapOf("from" to contactName(address), "body" to body)
        }
        return null
    }

    private fun recentCalls(limit: Int): List<Map<String, String>> {
        val calls = mutableListOf<Map<String, String>>()
        context.contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            arrayOf(CallLog.Calls.CACHED_NAME, CallLog.Calls.NUMBER, CallLog.Calls.TYPE),
            null, null, "${CallLog.Calls.DATE} DESC",
        )?.use { cursor ->
            while (cursor.moveToNext() && calls.size < limit) {
                val number = cursor.getString(1) ?: ""
                val name = cursor.getString(0)?.takeIf { it.isNotBlank() } ?: contactName(number)
                val type = when (cursor.getInt(2)) {
                    CallLog.Calls.MISSED_TYPE, CallLog.Calls.REJECTED_TYPE -> "missed"
                    CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                    else -> "incoming"
                }
                calls += mapOf("name" to name, "type" to type)
            }
        }
        return calls
    }

    /** Последний звонок с любым из номеров: номера сравниваются без форматирования. */
    private fun lastCallWith(numbers: List<String>): Map<String, Any>? {
        if (numbers.isEmpty()) return null
        context.contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.DATE, CallLog.Calls.TYPE),
            null, null, "${CallLog.Calls.DATE} DESC",
        )?.use { cursor ->
            var scanned = 0
            while (cursor.moveToNext() && scanned++ < 2000) {
                val number = cursor.getString(0) ?: continue
                if (numbers.none { PhoneNumberUtils.compare(it, number) }) continue
                val type = when (cursor.getInt(2)) {
                    CallLog.Calls.MISSED_TYPE, CallLog.Calls.REJECTED_TYPE -> "missed"
                    CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                    else -> "incoming"
                }
                return mapOf("at" to cursor.getLong(1), "type" to type)
            }
        }
        return null
    }

    /**
     * Место для SOS. Сначала свежая точка GPS (до 5 секунд, без интернета),
     * иначе последняя известная из любого источника.
     */
    @SuppressLint("MissingPermission")
    private fun location(result: MethodChannel.Result) {
        val fine = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        val coarse = context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        if (!fine && !coarse) { result.success(null); return }
        val manager = context.getSystemService(LocationManager::class.java)

        fun lastKnown(): Location? = manager.getProviders(true)
            .mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
            .maxByOrNull { it.time }

        fun reply(location: Location?) {
            val best = location ?: lastKnown()
            result.success(best?.let { mapOf("lat" to it.latitude, "lon" to it.longitude) })
        }

        val provider = when {
            fine && manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> null
        }
        if (provider == null || Build.VERSION.SDK_INT < 30) { reply(null); return }

        val handler = Handler(Looper.getMainLooper())
        val cancel = CancellationSignal()
        var answered = false
        val timeout = Runnable {
            if (answered) return@Runnable
            answered = true
            cancel.cancel()
            reply(null)
        }
        handler.postDelayed(timeout, 5000)
        manager.getCurrentLocation(provider, cancel, context.mainExecutor) { location ->
            if (answered) return@getCurrentLocation
            answered = true
            handler.removeCallbacks(timeout)
            reply(location)
        }
    }

    /** Имя из контактов по номеру, иначе сам номер. */
    private fun contactName(number: String): String {
        if (number.isBlank()) return "неизвестного номера"
        if (context.checkSelfPermission(Manifest.permission.READ_CONTACTS) !=
            PackageManager.PERMISSION_GRANTED) return number
        val uri = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
        context.contentResolver.query(
            uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null,
        )?.use { cursor -> if (cursor.moveToFirst()) return cursor.getString(0) ?: number }
        return number
    }

    /**
     * Ищет приложение по названию: сначала точное совпадение подписи, потом
     * вхождение, потом по имени пакета. «камеру» находит «Камера» по основе.
     */
    private fun openApp(query: String): String? {
        val pm = context.packageManager
        val apps = pm.queryIntentActivities(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0,
        ).filter { it.activityInfo.packageName != context.packageName }
        val candidates = query.lowercase().split('|').map { it.trim() }.filter { it.isNotEmpty() }
        for (probe in candidates) {
            val stem = if (probe.length > 4) probe.dropLast(1) else probe
            val match = apps.firstOrNull { it.loadLabel(pm).toString().lowercase() == probe }
                ?: apps.firstOrNull { it.loadLabel(pm).toString().lowercase().contains(probe) }
                ?: apps.firstOrNull { it.activityInfo.packageName.lowercase().contains(probe) }
                ?: apps.firstOrNull { it.loadLabel(pm).toString().lowercase().startsWith(stem) }
                ?: continue
            val launch = pm.getLaunchIntentForPackage(match.activityInfo.packageName) ?: continue
            context.startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return match.loadLabel(pm).toString()
        }
        return null
    }
}
