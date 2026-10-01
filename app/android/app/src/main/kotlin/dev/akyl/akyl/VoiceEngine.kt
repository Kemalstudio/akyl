package dev.akyl.akyl

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Один движок Flutter на процесс. Раньше Dart жил внутри MainActivity и
 * умирал вместе с экраном — голосовой конвейер, диалог и навыки пропадали,
 * а фоновой службе приходилось открывать приложение ради каждой команды.
 *
 * Теперь движок создаёт тот, кто первым попросил — экран или служба
 * микрофона, — и он переживает закрытие экрана. MainActivity только
 * подключается к нему. Все мосты работают от контекста приложения.
 */
object VoiceEngine {
    private const val ID = "akyl"

    /** Мосты, которым нужен ответ на запрос разрешений из MainActivity. */
    var phone: PhoneBridge? = null
        private set

    fun ensure(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ID)?.let { return it }
        val app = context.applicationContext
        MicHub.init(app)
        // Плагины из pubspec регистрируются автоматически.
        val engine = FlutterEngine(app)
        registerBridges(app, engine)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ID, engine)
        VoiceLog.i("BACKGROUND", "движок Flutter запущен")
        return engine
    }

    private fun registerBridges(app: Context, engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        phone = PhoneBridge(app).also {
            MethodChannel(messenger, PhoneBridge.CHANNEL).setMethodCallHandler(it)
        }
        MethodChannel(messenger, ContactsBridge.CHANNEL).setMethodCallHandler(ContactsBridge(app))
        MethodChannel(messenger, DeviceBridge.CHANNEL).setMethodCallHandler(DeviceBridge(app))
        MethodChannel(messenger, CareBridge.CHANNEL).setMethodCallHandler(CareBridge(app))
        EventChannel(messenger, MicHub.CHANNEL).setStreamHandler(MicHub)
        MethodChannel(messenger, VoiceBridge.CHANNEL).setMethodCallHandler(VoiceBridge(app))
        EventChannel(messenger, VoiceBridge.EVENTS).setStreamHandler(VoiceEvents)
        val tts = TtsBridge(app)
        MethodChannel(messenger, TtsBridge.CHANNEL).setMethodCallHandler(tts)
        EventChannel(messenger, TtsBridge.EVENTS).setStreamHandler(tts.events)
    }
}
