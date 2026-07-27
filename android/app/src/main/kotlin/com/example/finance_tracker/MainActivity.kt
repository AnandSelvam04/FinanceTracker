package com.example.finance_tracker

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
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
}
