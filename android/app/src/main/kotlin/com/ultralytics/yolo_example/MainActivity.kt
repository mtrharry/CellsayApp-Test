
package com.ultralytics.yolo_example

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val voiceCommandManager: VoiceCommandManager by lazy {
        VoiceCommandManager(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "voice_commands/methods").setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> voiceCommandManager.initialize(result)
                "start" -> {
                    val locale = call.argument<String>("locale")
                    val listenFor = call.argument<Int>("listenFor")?.toLong() ?: DEFAULT_LISTEN_FOR
                    val pauseFor = call.argument<Int>("pauseFor")?.toLong() ?: DEFAULT_PAUSE_FOR
                    result.success(voiceCommandManager.startListening(locale, listenFor, pauseFor))
                }
                "stop" -> {
                    voiceCommandManager.stopListening()
                    result.success(null)
                }
                "cancel" -> {
                    voiceCommandManager.cancelListening()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "voice_commands/events")
            .setStreamHandler(voiceCommandManager)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        voiceCommandManager.handlePermissionResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        voiceCommandManager.dispose()
        super.onDestroy()
    }

    companion object {
        private const val DEFAULT_LISTEN_FOR = 8000L
        private const val DEFAULT_PAUSE_FOR = 3000L
    }
}
