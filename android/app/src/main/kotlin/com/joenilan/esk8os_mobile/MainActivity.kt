package com.joenilan.esk8os_mobile

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Lets the app pull its own activity back to the front (e.g. when the
        // floating overlay is tapped). Allowed from the background because we
        // hold SYSTEM_ALERT_WINDOW + a foreground service while recording.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "esk8os/app")
            .setMethodCallHandler { call, result ->
                if (call.method == "bringToFront") {
                    val intent = Intent(this, MainActivity::class.java)
                    intent.addFlags(
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_NEW_TASK
                    )
                    startActivity(intent)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
