package com.example.finance_tracker

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity, not FlutterActivity: the app-lock prompt
// (local_auth's BiometricPrompt) can only be shown from a FragmentActivity.
// With a plain FlutterActivity every unlock attempt failed at once, leaving
// the lock screen's Unlock button doing nothing.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // FLAG_SECURE keeps balances and transaction lists out of the
        // recents/app-switcher thumbnail and blocks screenshots and screen
        // recording. Without it the optional biometric lock is easy to work
        // around: the last screen viewed stays visible in the task switcher,
        // and there is little point locking the app if its contents are
        // readable from outside it.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Registers the plugins; must stay first.
        super.configureFlutterEngine(flutterEngine)
        // Settings > Match my wallpaper: hands the wallpaper's accent colour
        // (Material You, Android 12+) to SettingsProvider, which seeds the
        // app's theme from it. Null on older Android, where there is none.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "wallpaperAccent") {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        // Tone 600 of the accent: deep enough for the white
                        // text of the app bar it colours.
                        result.success(getColor(android.R.color.system_accent1_600))
                    } else {
                        result.success(null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private companion object {
        // Matched by the channel name in lib/providers/settings_provider.dart.
        const val SYSTEM_CHANNEL = "finance_tracker/system"
    }
}
