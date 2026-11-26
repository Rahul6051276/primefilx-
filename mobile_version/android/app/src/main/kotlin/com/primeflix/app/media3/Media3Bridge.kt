package com.primeflix.app.media3

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

object Media3Bridge {
    private const val CHANNEL_NAME = "com.primeflix/media3"

    fun register(activity: Activity, flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playMedia" -> {
                        val url = (call.argument<String>("url"))?.trim() ?: ""
                        val title = (call.argument<String>("title"))?.trim().orEmpty().ifEmpty { "Primeflix" }
                        val rawHeaders = call.argument>("headers")
                        val headers = HashMap<String, String>()
                        rawHeaders?.forEach { (k, v) ->
                            if (k != null && v != null) {
                                headers[k.toString()] = v.toString()
                            }
                        }

                        val rawServers = call.argument<List<*>>("servers")
                        val serversJson = JSONArray()
                        rawServers?.forEach { entry ->
                            if (entry is Map<*, *>) {
                                val obj = JSONObject()
                                val sUrl = entry["url"]?.toString()?.trim().orEmpty()
                                if (sUrl.isNotEmpty()) {
                                    obj.put("title", entry["title"]?.toString() ?: title)
                                    obj.put("server", entry["server"]?.toString() ?: "Server")
                                    obj.put("url", sUrl)
                                    obj.put("isHindi", entry["isHindi"] == true)
                                    serversJson.put(obj)
                                }
                            }
                        }

                        val resolvedUrl = if (url.isNotEmpty()) {
                            url
                        } else if (serversJson.length() > 0) {
                            serversJson.optJSONObject(0)?.optString("url", "") ?: ""
                        } else {
                            ""
                        }

                        if (resolvedUrl.isEmpty()) {
                            result.error("INVALID_URL", "Stream URL is empty", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val intent = Intent(activity, Media3PlayerActivity::class.java).apply {
                                putExtra(Media3PlayerActivity.EXTRA_URL, resolvedUrl)
                                putExtra(Media3PlayerActivity.EXTRA_TITLE, title)
                                putExtra(Media3PlayerActivity.EXTRA_HEADERS, headers)
                                putExtra(Media3PlayerActivity.EXTRA_SERVERS_JSON, serversJson.toString())
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