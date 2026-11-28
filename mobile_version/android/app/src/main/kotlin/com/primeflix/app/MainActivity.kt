package com.primeflix.app

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.primeflix/player"
    private val playerRequestCode = 9001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "playVideo") {
                    val url = call.argument<String>("url") ?: ""
                    val title = call.argument<String>("title") ?: "PrimeFlix"
                    val rawTitle = call.argument<String>("rawTitle") ?: title
                    val tmdbId = call.argument<String>("tmdbId") ?: ""
                    val tmdbKey = call.argument<String>("tmdbKey") ?: ""
                    val gistUrl = call.argument<String>("gistUrl") ?: ""
                    val extraProvidersJson = call.argument<String>("extraProvidersJson") ?: ""
                    val isTv = call.argument<Boolean>("isTv") ?: false
                    val season = call.argument<Int>("season") ?: 1
                    val episode = call.argument<Int>("episode") ?: 1
                    val userAgent = call.argument<String>("userAgent")
                        ?: "VLC/3.0.18 LibVLC/3.0.18 (Linux; Android 13)"
                    val seekSeconds = call.argument<Int>("seekSeconds") ?: 15
                    val sourcesJson = call.argument<String>("sourcesJson") ?: ""
                    val activeIndex = call.argument<Int>("activeIndex") ?: 0
                    val isTvDevice = call.argument<Boolean>("isTvDevice") ?: false

                    if (url.isBlank() && tmdbId.isBlank() && sourcesJson.isBlank()) {
                        try {
                            result.error("INVALID_ARGS", "url, tmdbId, and sourcesJson are all empty", null)
                        } catch (_: Exception) {}
                        return@setMethodCallHandler
                    }

                    try {
                        pendingResult?.success(false)
                    } catch (_: Exception) {}
                    pendingResult = result

                    try {
                        val intent = Intent(this, CinemaPlayerActivity::class.java).apply {
                            putExtra("url", url)
                            putExtra("title", title)
                            putExtra("rawTitle", rawTitle)
                            putExtra("tmdbId", tmdbId)
                            putExtra("tmdbKey", tmdbKey)
                            putExtra("gistUrl", gistUrl)
                            putExtra("extraProvidersJson", extraProvidersJson)
                            putExtra("isTv", isTv)
                            putExtra("season", season)
                            putExtra("episode", episode)
                            putExtra("userAgent", userAgent)
                            putExtra("seekSeconds", seekSeconds)
                            putExtra("sourcesJson", sourcesJson)
                            putExtra("activeIndex", activeIndex)
                            putExtra("isTvDevice", isTvDevice)
                        }
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, playerRequestCode)
                    } catch (e: Exception) {
                        try {
                            pendingResult?.error("LAUNCH_FAILED", e.message, null)
                        } catch (_: Exception) {}
                        pendingResult = null
                    }
                } else {
                    try {
                        result.notImplemented()
                    } catch (_: Exception) {}
                }
            }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == playerRequestCode) {
            try {
                pendingResult?.success(resultCode == Activity.RESULT_OK)
            } catch (_: Exception) {}
            pendingResult = null
        }
    }
}