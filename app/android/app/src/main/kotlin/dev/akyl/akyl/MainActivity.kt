package dev.akyl.akyl

import android.content.Intent

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var phoneBridge: PhoneBridge? = null
    private var ttsBridge: TtsBridge? = null
    private var handsFreeChannel: MethodChannel? = null
    private var micBridge: MicBridge? = null
    private var micChannel: EventChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        handsFreeChannel = MethodChannel(messenger, HandsFreeBridge.CHANNEL).also {
            it.setMethodCallHandler(HandsFreeBridge(this))
        }

        val phone = PhoneBridge(this).also { phoneBridge = it }
        MethodChannel(messenger, PhoneBridge.CHANNEL).setMethodCallHandler(phone)

        MethodChannel(messenger, ContactsBridge.CHANNEL)
            .setMethodCallHandler(ContactsBridge(this))

        MethodChannel(messenger, DeviceBridge.CHANNEL)
            .setMethodCallHandler(DeviceBridge(this))

        micBridge = MicBridge(this)
        micChannel = EventChannel(messenger, MicBridge.CHANNEL).also {
            it.setStreamHandler(micBridge)
        }

        MethodChannel(messenger, CareBridge.CHANNEL).setMethodCallHandler(CareBridge(this))

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
        micBridge?.stopCapture()
        micChannel?.setStreamHandler(null)
        micBridge = null
        micChannel = null
        handsFreeChannel?.setMethodCallHandler(null)
        handsFreeChannel = null
        ttsBridge?.dispose()
        ttsBridge = null
        phoneBridge?.dispose()
        phoneBridge = null
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handsFreeChannel?.invokeMethod("commandAvailable", null)
    }
}
