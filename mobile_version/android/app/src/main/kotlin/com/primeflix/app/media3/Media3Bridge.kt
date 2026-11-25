package com.primeflix.app.media3

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object Media3Bridge {
    private const val CHANNEL_NAME = "com.primeflix/media3"

    fun register(activity: Activity, flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playMedia" -> {
                        val url = call.argument<String>("url")?.trim() ?: ""
                        val title = call.argument<String>("title") ?: "Primeflix"
                        @Suppress("UNCHECKED_CAST")
                        val headers = call.argument>("headers") ?: emptyMap()

                        if (url.isEmpty()) {
                            result.error("INVALID_URL", "Stream URL is empty", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val intent = Intent(activity, Media3PlayerActivity::class.java).apply {
                                putExtra(Media3PlayerActivity.EXTRA_URL, url)
                                putExtra(Media3PlayerActivity.EXTRA_TITLE, title)
                                putExtra(Media3PlayerActivity.EXTRA_HEADERS, HashMap(headers))
                            }
                            activity.startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("LAUNCH_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
