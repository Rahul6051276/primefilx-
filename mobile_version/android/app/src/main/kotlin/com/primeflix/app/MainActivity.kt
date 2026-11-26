package com.primeflix.app

import android.os.Bundle
import com.primeflix.app.media3.Media3Bridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        try {
            Media3Bridge.register(this, flutterEngine)
        } catch (_: Exception) {
        }
    }
}