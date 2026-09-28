package dev.akyl.akyl

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var phoneBridge: PhoneBridge? = null
    private var ttsBridge: TtsBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        val phone = PhoneBridge(this).also { phoneBridge = it }
        MethodChannel(messenger, PhoneBridge.CHANNEL).setMethodCallHandler(phone)

        MethodChannel(messenger, ContactsBridge.CHANNEL)
            .setMethodCallHandler(ContactsBridge(this))

        val tts = TtsBridge(this).also { ttsBridge = it }
        MethodChannel(messenger, TtsBridge.CHANNEL).setMethodCallHandler(tts)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        // Сначала наш мост: если код запроса его, Flutter об этом знать не нужно.
        if (phoneBridge?.onRequestPermissionsResult(requestCode) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        ttsBridge?.dispose()
        ttsBridge = null
        phoneBridge?.dispose()
        phoneBridge = null
        super.onDestroy()
    }
}
