package com.primeflix.app.media3

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

object Media3Bridge {
    private const val CHANNEL_NAME = "com.primeflix/media3"
    var activePlayer: Media3PlayerActivity? = null

    fun register(activity: Activity, flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playMedia" -> {
                        val url = call.argument<String>("url")?.trim().orEmpty()
                        val title = call.argument<String>("title")?.trim().orEmpty().ifEmpty { "PrimeFlix" }

                        val headersJson = JSONObject()
                        val rawHeaders = call.argument>("headers")
                        rawHeaders?.forEach { (k, v) ->
                            if (k != null && v != null) {
                                headersJson.put(k.toString(), v.toString())
                            }
                        }

                        val serversJson = JSONArray()
                        val rawServers = call.argument<List<*>>("servers")
                        rawServers?.forEach { entry ->
                            if (entry is Map<*, *>) {
                                val sUrl = entry["url"]?.toString()?.trim().orEmpty()
                                if (sUrl.isNotEmpty()) {
                                    val entryHeaders = JSONObject()
                                    val hMap = entry["headers"]
                                    if (hMap is Map<*, *>) {
                                        hMap.forEach { (hk, hv) ->
                                            if (hk != null && hv != null) {
                                                entryHeaders.put(hk.toString(), hv.toString())
                                            }
                                        }
                                    } else if (headersJson.length() > 0) {
                                        val keys = headersJson.keys()
                                        while (keys.hasNext()) {
                                            val hk = keys.next()
                                            entryHeaders.put(hk, headersJson.optString(hk, ""))
                                        }
                                    }

                                    val obj = JSONObject()
                                    obj.put("url", sUrl)
                                    obj.put("title", entry["title"]?.toString() ?: title)
                                    obj.put(
                                        "providerName",
                                        entry["providerName"]?.toString()
                                            ?: entry["server"]?.toString()
                                            ?: "Server"
                                    )
                                    obj.put("quality", entry["quality"]?.toString() ?: "HD")
                                    obj.put("headers", entryHeaders)
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

                        if (serversJson.length() == 0) {
                            val singleObj = JSONObject()
                            singleObj.put("url", resolvedUrl)
                            singleObj.put("title", title)
                            singleObj.put("providerName", "Server")
                            singleObj.put("quality", "HD")
                            singleObj.put("headers", headersJson)
                            serversJson.put(singleObj)
                        }

                        try {
                            val current = activePlayer
                            if (current != null && !current.isFinishing && !current.isDestroyed) {
                                current.updateServersFromBridge(serversJson.toString())
                                result.success(true)
                                return@setMethodCallHandler
                            }

                            val intent = Intent(activity, Media3PlayerActivity::class.java).apply {
                                putExtra("url", resolvedUrl)
                                putExtra("title", title)
                                putExtra("servers_json", serversJson.toString())
                                putExtra("start_index", 0)
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