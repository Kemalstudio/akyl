package dev.akyl.akyl

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Экран подключается к движку уровня процесса (VoiceEngine) и не владеет
 * им: закрыли экран — голос, диалог и навыки продолжают работать, если
 * включён фоновый режим.
 */
class MainActivity : FlutterActivity() {

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        VoiceEngine.ensure(context)

    /** Движок переживает экран: его освобождает только гибель процесса. */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        ActivityHolder.attach(this)
        super.onCreate(savedInstanceState)
    }

    override fun onStart() {
        ActivityHolder.attach(this)
        ActivityHolder.visible = true
        super.onStart()
    }

    override fun onStop() {
        ActivityHolder.visible = false
        super.onStop()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        // Сначала наш мост: если код запроса его, Flutter об этом знать не нужно.
        if (VoiceEngine.phone?.onRequestPermissionsResult(requestCode) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Жест помощника при открытом приложении: Dart заберёт команду.
        if (intent.hasCategory(Intent.CATEGORY_VOICE)) VoiceEvents.emit("assist")
    }

    override fun onDestroy() {
        ActivityHolder.detach(this)
        super.onDestroy()
    }
}
