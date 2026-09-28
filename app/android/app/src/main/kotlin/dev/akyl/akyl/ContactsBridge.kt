package dev.akyl.akyl

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.ContactsContract
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Чтение адресной книги. Отдаёт плоский список — индекс для поиска строится
 * в Dart (ТЗ, FR-5), чтобы правила падежей и транслитерации тестировались
 * без телефона.
 */
class ContactsBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "dev.akyl/contacts"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadAll" -> {
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS)
                    != PackageManager.PERMISSION_GRANTED
                ) {
                    result.error("NO_PERMISSION", "Нет разрешения READ_CONTACTS", null)
                    return
                }
                try {
                    result.success(loadAll())
                } catch (e: Exception) {
                    result.error("CONTACTS_FAILED", e.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun loadAll(): List<Map<String, Any?>> {
        // Один запрос по таблице телефонов: контакт с несколькими номерами
        // приходит несколькими строками и склеивается по CONTACT_ID.
        val projection = arrayOf(
            ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME_PRIMARY,
            ContactsContract.CommonDataKinds.Phone.NUMBER,
            ContactsContract.CommonDataKinds.Phone.TYPE,
            ContactsContract.CommonDataKinds.Phone.LABEL,
        )

        val byId = LinkedHashMap<String, MutableMap<String, Any?>>()

        context.contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            projection,
            null,
            null,
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME_PRIMARY + " ASC",
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(projection[0])
            val nameIdx = cursor.getColumnIndexOrThrow(projection[1])
            val numberIdx = cursor.getColumnIndexOrThrow(projection[2])
            val typeIdx = cursor.getColumnIndexOrThrow(projection[3])
            val labelIdx = cursor.getColumnIndexOrThrow(projection[4])

            while (cursor.moveToNext()) {
                val id = cursor.getString(idIdx) ?: continue
                val name = cursor.getString(nameIdx) ?: continue
                val number = cursor.getString(numberIdx) ?: continue

                val entry = byId.getOrPut(id) {
                    mutableMapOf(
                        "id" to id,
                        "displayName" to name,
                        "phones" to mutableListOf<Map<String, Any?>>(),
                    )
                }

                @Suppress("UNCHECKED_CAST")
                val phones = entry["phones"] as MutableList<Map<String, Any?>>
                phones.add(
                    mapOf(
                        "number" to number,
                        "type" to phoneTypeName(cursor.getInt(typeIdx)),
                        "label" to cursor.getString(labelIdx),
                    )
                )
            }
        }

        return byId.values.toList()
    }

    /** ContactsContract.TYPE_* -> имена PhoneType из Dart. */
    private fun phoneTypeName(type: Int): String = when (type) {
        ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE -> "mobile"
        ContactsContract.CommonDataKinds.Phone.TYPE_WORK,
        ContactsContract.CommonDataKinds.Phone.TYPE_WORK_MOBILE -> "work"
        ContactsContract.CommonDataKinds.Phone.TYPE_HOME -> "home"
        else -> "other"
    }
}
