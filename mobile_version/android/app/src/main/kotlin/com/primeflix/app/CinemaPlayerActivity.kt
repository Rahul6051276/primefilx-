package com.primeflix.app

import android.app.Activity
import android.app.AlertDialog
import android.app.UiModeManager
import android.content.Context
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.media.AudioManager
import android.media.audiofx.LoudnessEnhancer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.JsonReader
import android.util.JsonToken
import android.util.TypedValue
import android.view.GestureDetector
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Collections
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.max

@OptIn(UnstableApi::class)
class CinemaPlayerActivity : Activity() {

    private data class StreamSourceItem(
        val server: String,
        val title: String,
        val url: String,
        val isHindi: Boolean,
        val isMultiAudio: Boolean = false,
        val headers: Map<String, String> = emptyMap(),
        val stalkerEndpoint: String = "",
        val stalkerCmd: String = "",
        val stalkerMediaType: String = "vod",
        val stalkerEpisode: Int = 0,
        val stalkerItemId: String = "",
        val stalkerPortalRaw: String = "",
        val stalkerMac: String = "",
        val stalkerDev1: String = "",
        val stalkerDev2: String = ""
    )

    private var player: ExoPlayer? = null
    private var httpDataSourceFactory: DefaultHttpDataSource.Factory? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private lateinit var trackSelector: DefaultTrackSelector
    private lateinit var playerView: PlayerView
    private lateinit var currentMediaItem: MediaItem

    private lateinit var hudContainer: FrameLayout
    private lateinit var centerBar: LinearLayout
    private lateinit var actionsRow: LinearLayout
    private lateinit var unlockBtn: Button
    private lateinit var loadingSpinner: ProgressBar
    private lateinit var connectingCard: LinearLayout
    private lateinit var connectingText: TextView
    private lateinit var feedbackBadge: TextView
    private lateinit var titleView: TextView
    private lateinit var infoBadgeView: TextView
    private lateinit var playPauseBtn: Button
    private lateinit var boostBtn: Button
    private lateinit var aspectBtn: Button
    private lateinit var speedBtn: Button
    private lateinit var pictureBtn: Button
    private lateinit var sourcesBtn: Button
    private lateinit var lockBtn: Button
    private lateinit var backBtn: Button
    private lateinit var tvHintView: TextView
    private lateinit var timeCurrentView: TextView
    private lateinit var timeTotalView: TextView
    private lateinit var seekBar: SeekBar
    private lateinit var seekBarRow: LinearLayout
    private lateinit var errorOverlay: LinearLayout
    private lateinit var errorMessageView: TextView

    private lateinit var sourcesOverlay: FrameLayout
    private lateinit var sourcesListContainer: LinearLayout
    private val streamSources = mutableListOf<StreamSourceItem>()
    private var activeSourceIndex = 0
    private var currentActiveUrl = ""
    private var currentUserAgent = "PrimeFlix/1.0"
    private var currentMovieTitle = "PrimeFlix"
    private var currentSearchTitle = "PrimeFlix"
    private var currentPreset = PicturePreset.JUST_PLAYER

    @Volatile private var activeStalkerSource: StreamSourceItem? = null
    @Volatile private var cachedStalkerPlayUrl: String = ""
    @Volatile private var cachedStalkerUrlTimeMs: Long = 0L

    private val primeBlueHex = "#00A8E1"
    private val primeBlueLightHex = "#38BDF8"

    private val handler = Handler(Looper.getMainLooper())
    private var hudVisible = true
    private var isScreenLocked = false
    private var isSeekingFromUser = false
    private var isShaderAttached = false
    private var isTvDevice = false
    private var seekStepSec = 15
    private var seekStepMs = 15_000L
    private var pendingResumePositionMs = 0L
    private var retriedCurrentSourceCount = 0
    private var userManuallyPickedSource = false
    @Volatile private var isActivityDestroyed = false
    @Volatile private var isResolvingAllSources = false

    private val boostLevels = intArrayOf(100, 135, 170, 200)
    private var boostIndex = 0
    private var currentBoostPercent = 100

    private val resizeModes = intArrayOf(
        AspectRatioFrameLayout.RESIZE_MODE_FIT,
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM,
        AspectRatioFrameLayout.RESIZE_MODE_FILL
    )
    private val resizeLabels = arrayOf("Fit", "Crop / Zoom", "Fill")
    private var resizeIndex = 0

    private val speeds = floatArrayOf(0.75f, 1.0f, 1.25f, 1.5f, 2.0f)
    private var speedIndex = 1

    private val prefs by lazy {
        getSharedPreferences("primeflix_player_prefs", Context.MODE_PRIVATE)
    }

    private val hideHudRunnable = Runnable { setHudVisible(false) }
    private val hideUnlockRunnable = Runnable { unlockBtn.visibility = View.GONE }
    private val hideFeedbackRunnable = Runnable { feedbackBadge.visibility = View.GONE }
    private val progressRunnable = object : Runnable {
        override fun run() {
            if (!isSafeUi()) return
            updateProgressUi()
            handler.postDelayed(this, 500)
        }
    }

    private fun isSafeUi(): Boolean = !isActivityDestroyed && !isFinishing && !isDestroyed

    private fun detectAndroidTv(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        val isTvMode = uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
        val hasLeanback = packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        val hasTouch = packageManager.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
        return isTvMode || (hasLeanback && !hasTouch) || intent.getBooleanExtra("isTvDevice", false)
    }

    private fun finishPlayerCleanly() {
        isActivityDestroyed = true
        handler.removeCallbacksAndMessages(null)
        releaseLoudnessEnhancer()
        try {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        } catch (_: Throwable) {}
        try {
            playerView.player = null
            player?.stop()
            player?.release()
            player = null
        } catch (_: Throwable) {}
        setResult(Activity.RESULT_OK)
        finish()
    }

    private fun applyCameraCutoutFullScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        try {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        } catch (_: Throwable) {}

        isTvDevice = detectAndroidTv()

        window.setBackgroundDrawable(ColorDrawable(Color.BLACK))
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        applyCameraCutoutFullScreen()

        seekStepSec = intent.getIntExtra("seekSeconds", 15).coerceIn(5, 60)
        seekStepMs = seekStepSec * 1000L

        currentPreset = if (isTvDevice) {
            PicturePreset.JUST_PLAYER
        } else {
            val savedName = prefs.getString("picture_preset_pure_hw", PicturePreset.JUST_PLAYER.name)
            PicturePreset.values().firstOrNull { it.name == savedName }
                ?: PicturePreset.JUST_PLAYER
        }
        CinemaPictureEngineState.currentPreset = currentPreset

        val savedBoost = prefs.getInt("audio_boost_percent", 100).coerceIn(100, 200)
        currentBoostPercent = savedBoost
        boostIndex = boostLevels.indexOfFirst { it >= savedBoost }.let { if (it < 0) 0 else it }

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        playerView = PlayerView(this).apply {
            useController = false
            setBackgroundColor(Color.BLACK)
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }
        root.addView(playerView)

        playerView.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            if (!isSafeUi()) return@addOnLayoutChangeListener
            syncZoomScaleOnly(resizeModes[resizeIndex])
        }
        applyResizeModeToPlayer(resizeModes[resizeIndex])

        parseIncomingSources()
        buildGestureAndHudLayers(root)
        buildSourcesSidePanel(root)
        configureDeviceSpecificHud()
        setContentView(root)
        enableImmersiveFullscreen()

        val rawUrl = intent.getStringExtra("url")?.trim().orEmpty()
        currentMovieTitle = intent.getStringExtra("title")?.trim().orEmpty().ifEmpty { "PrimeFlix" }
        currentSearchTitle = intent.getStringExtra("rawTitle")?.trim().orEmpty()
            .ifEmpty { currentMovieTitle.substringBefore(" • S").trim() }
        currentUserAgent = intent.getStringExtra("userAgent")?.trim().orEmpty().ifEmpty { "PrimeFlix/1.0" }
        val tmdbId = intent.getStringExtra("tmdbId")?.trim().orEmpty()
        val tmdbKey = intent.getStringExtra("tmdbKey")?.trim().orEmpty()
        val customGistUrl = intent.getStringExtra("gistUrl")?.trim().orEmpty()
        val extraProvidersJson = intent.getStringExtra("extraProvidersJson")?.trim().orEmpty()
        val isTv = intent.getBooleanExtra("isTv", false)
        val season = intent.getIntExtra("season", 1)
        val episode = intent.getIntExtra("episode", 1)

        titleView.text = currentMovieTitle
        pictureBtn.text = if (currentPreset == PicturePreset.JUST_PLAYER) "HW Original" else currentPreset.displayName
        sourcesBtn.text = "Sources (${streamSources.size})"
        updateBoostButtonUi()

        if (streamSources.isNotEmpty()) {
            activeSourceIndex = activeSourceIndex.coerceIn(0, streamSources.size - 1)
            val firstSrc = streamSources[activeSourceIndex]
            currentActiveUrl = firstSrc.url
            setConnectingState(false)
            loadingSpinner.visibility = View.VISIBLE
            resolveAndStartSource(firstSrc, isInitial = true)
            scheduleHideHud()
        } else if (rawUrl.isNotEmpty()) {
            streamSources.add(
                StreamSourceItem(
                    server = "Live Broadcast",
                    title = currentMovieTitle,
                    url = rawUrl,
                    isHindi = isExplicitHindi(currentMovieTitle)
                )
            )
            sourcesBtn.text = "Sources (1)"
            currentActiveUrl = rawUrl
            setConnectingState(false)
            loadingSpinner.visibility = View.VISIBLE
            initExoPlayer(rawUrl, currentMovieTitle, currentUserAgent, currentPreset)
            scheduleHideHud()
        } else if (tmdbId.isNotEmpty()) {
            loadingSpinner.visibility = View.GONE
            setConnectingState(true)
            resolveStreamsInsidePlayer(
                tmdbId = tmdbId,
                tmdbKey = tmdbKey,
                customGistUrl = customGistUrl,
                extraProvidersJson = extraProvidersJson,
                movieTitle = currentSearchTitle,
                isTv = isTv,
                season = season,
                episode = episode
            )
        } else {
            showError("Stream URL खाली है।")
        }
    }

    private fun performStalkerHandshake(
        rawPortal: String,
        mac: String,
        dev1: String,
        dev2: String
    ): Pair<String, Map<String, String>>? {
        if (rawPortal.isEmpty() || mac.isEmpty()) return null
        var portal = rawPortal.trim()
        if (!portal.startsWith("http://") && !portal.startsWith("https://")) {
            portal = "http://$portal"
        }
        val base = portal.trimEnd('/')
        val referer = if (base.endsWith("/c")) "$base/" else "$base/c/"

        val endpoints = mutableListOf<String>()
        if (base.endsWith(".php")) {
            endpoints.add(base)
        } else if (base.endsWith("/c")) {
            val root = base.substring(0, base.length - 2)
            endpoints.add("$root/portal.php")
            endpoints.add("$root/server/load.php")
            endpoints.add("$root/stalker_portal/server/load.php")
        } else {
            endpoints.add("$base/portal.php")
            endpoints.add("$base/server/load.php")
            endpoints.add("$base/stalker_portal/server/load.php")
        }

        val cleanMac = mac.trim().uppercase(Locale.ROOT)
        val cookieParts = mutableListOf(
            "mac=${URLEncoder.encode(cleanMac, "UTF-8")}",
            "stb_lang=en",
            "timezone=Asia%2FKolkata"
        )
        if (dev1.isNotEmpty()) cookieParts.add("device_id=${URLEncoder.encode(dev1, "UTF-8")}")
        if (dev2.isNotEmpty()) cookieParts.add("device_id2=${URLEncoder.encode(dev2, "UTF-8")}")
        val cookieStr = cookieParts.joinToString("; ")
        val magUa = "Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3"

        for (ep in endpoints) {
            val hsStr = httpGetWithHeaders(
                "$ep?type=stb&action=handshake&token=&prehash=&JsHttpRequest=1-xml",
                9000,
                mapOf(
                    "User-Agent" to magUa,
                    "X-User-Agent" to "Model: MAG250; Link: WiFi",
                    "Referer" to referer,
                    "Cookie" to cookieStr
                )
            )
            if (hsStr.contains("{")) {
                try {
                    val cleanJson = hsStr.substring(hsStr.indexOf('{'))
                    val tok = JSONObject(cleanJson).optJSONObject("js")?.optString("token", "").orEmpty()
                    if (tok.isNotEmpty()) {
                        val authHeaders = mapOf(
                            "User-Agent" to magUa,
                            "X-User-Agent" to "Model: MAG250; Link: WiFi",
                            "Referer" to referer,
                            "Cookie" to cookieStr,
                            "Authorization" to "Bearer $tok"
                        )
                        httpGetWithHeaders(
                            "$ep?type=stb&action=get_profile&hd=1&device_id=${URLEncoder.encode(dev1, "UTF-8")}&device_id2=${URLEncoder.encode(dev2, "UTF-8")}&JsHttpRequest=1-xml",
                            6000,
                            authHeaders
                        )
                        return Pair(ep, authHeaders)
                    }
                } catch (_: Throwable) {}
            }
        }
        return null
    }

    private fun fetchVodCmdByMovieId(
        endpoint: String,
        headers: Map<String, String>,
        movieId: String
    ): String {
        if (movieId.isEmpty()) return ""
        try {
            val resStr = httpGetWithHeaders(
                "$endpoint?type=vod&action=get_ordered_list&movie_id=${URLEncoder.encode(movieId, "UTF-8")}&p=1&JsHttpRequest=1-xml",
                10_000,
                headers
            )
            if (resStr.contains("{")) {
                val js = JSONObject(resStr.substring(resStr.indexOf('{'))).opt("js")
                val arr = if (js is JSONObject) js.optJSONArray("data") else if (js is JSONArray) js else null
                if (arr != null && arr.length() > 0) {
                    val first = arr.optJSONObject(0)
                    val c = first?.optString("cmd", "")?.trim().orEmpty()
                    if (c.isNotEmpty()) return c
                }
            }
        } catch (_: Throwable) {}
        return ""
    }

    private fun callStalkerCreateLink(
        endpoint: String,
        headers: Map<String, String>,
        mediaType: String,
        rawCmd: String,
        episode: Int
    ): String {
        var cleanCmd = rawCmd.trim()
        if (cleanCmd.startsWith("ffmpeg ")) {
            cleanCmd = cleanCmd.substring(7).trim()
        }
        if (cleanCmd.startsWith("http://") || cleanCmd.startsWith("https://")) {
            return cleanCmd
        }
        var conn: HttpURLConnection? = null
        return try {
            val encodedCmd = URLEncoder.encode(cleanCmd, "UTF-8")
            val epParam = if (episode > 0) "&series=$episode" else ""
            val reqUrl = "$endpoint?type=$mediaType&action=create_link&cmd=$encodedCmd$epParam&JsHttpRequest=1-xml"
            conn = (URL(reqUrl).openConnection() as HttpURLConnection).apply {
                connectTimeout = 10_000
                readTimeout = 10_000
                requestMethod = "GET"
                headers.forEach { (k, v) -> setRequestProperty(k, v) }
            }
            if (conn.responseCode in 200..299) {
                val body = conn.inputStream.bufferedReader().use { it.readText() }.trim()
                val jsonStart = body.indexOf('{')
                val cleanJson = if (jsonStart > 0) body.substring(jsonStart) else body
                val jsObj = JSONObject(cleanJson).optJSONObject("js")
                var playCmd = jsObj?.optString("cmd", "")?.trim().orEmpty()
                if (playCmd.startsWith("ffmpeg ")) {
                    playCmd = playCmd.substring(7).trim()
                }
                if (playCmd.startsWith("http://") || playCmd.startsWith("https://")) {
                    playCmd
                } else {
                    ""
                }
            } else {
                ""
            }
        } catch (_: Throwable) {
            ""
        } finally {
            try { conn?.disconnect() } catch (_: Throwable) {}
        }
    }

    private fun resolveFreshStalkerUrl(src: StreamSourceItem): Pair<String, Map<String, String>> {
        if (src.stalkerEndpoint.isEmpty()) {
            return Pair(src.url, src.headers)
        }

        var cmdToUse = src.stalkerCmd.trim()
        if (cmdToUse.isEmpty() && src.stalkerItemId.isNotEmpty() && src.stalkerMediaType == "vod") {
            cmdToUse = fetchVodCmdByMovieId(src.stalkerEndpoint, src.headers, src.stalkerItemId)
        }

        if (cmdToUse.isNotEmpty()) {
            val firstTry = callStalkerCreateLink(
                src.stalkerEndpoint,
                src.headers,
                src.stalkerMediaType,
                cmdToUse,
                src.stalkerEpisode
            )
            if (firstTry.isNotEmpty()) {
                return Pair(firstTry, src.headers)
            }
        }

        try { Thread.sleep(250) } catch (_: Throwable) {}
        val portalRaw = src.stalkerPortalRaw.ifEmpty { src.stalkerEndpoint }
        val freshAuth = performStalkerHandshake(
            portalRaw,
            src.stalkerMac,
            src.stalkerDev1,
            src.stalkerDev2
        )
        if (freshAuth != null) {
            if (src.stalkerItemId.isNotEmpty() && src.stalkerMediaType == "vod") {
                val freshVodCmd = fetchVodCmdByMovieId(freshAuth.first, freshAuth.second, src.stalkerItemId)
                if (freshVodCmd.isNotEmpty()) {
                    cmdToUse = freshVodCmd
                }
            }
            if (cmdToUse.isNotEmpty()) {
                val secondTry = callStalkerCreateLink(
                    freshAuth.first,
                    freshAuth.second,
                    src.stalkerMediaType,
                    cmdToUse,
                    src.stalkerEpisode
                )
                if (secondTry.isNotEmpty()) {
                    return Pair(secondTry, freshAuth.second)
                }
            }
        }
        return Pair("", src.headers)
    }

    private fun resolveAndStartSource(
        src: StreamSourceItem,
        isInitial: Boolean,
        resumePosMs: Long = 0L
    ) {
        if (src.stalkerEndpoint.isNotEmpty() && (src.stalkerCmd.isNotEmpty() || src.stalkerItemId.isNotEmpty())) {
            activeStalkerSource = src
            cachedStalkerPlayUrl = ""
            cachedStalkerUrlTimeMs = 0L

            thread(start = true) {
                val (freshUrl, freshHeaders) = resolveFreshStalkerUrl(src)
                handler.post {
                    if (!isSafeUi()) return@post
                    if (freshUrl.isEmpty()) {
                        loadingSpinner.visibility = View.GONE
                        pendingResumePositionMs = 0L
                        if (!userManuallyPickedSource && activeSourceIndex + 1 < streamSources.size) {
                            retriedCurrentSourceCount = 0
                            switchToStreamSource(activeSourceIndex + 1)
                        } else {
                            showError("Selected stream (${src.title}) unavailable on server. Try Retry or Switch Source.")
                        }
                    } else {
                        val updatedSrc = src.copy(headers = freshHeaders)
                        if (activeSourceIndex in streamSources.indices) {
                            streamSources[activeSourceIndex] = updatedSrc
                        }
                        activeStalkerSource = updatedSrc
                        cachedStalkerPlayUrl = freshUrl
                        cachedStalkerUrlTimeMs = System.currentTimeMillis()

                        if (isInitial || player == null) {
                            initExoPlayer(
                                freshUrl,
                                currentMovieTitle,
                                currentUserAgent,
                                currentPreset,
                                freshHeaders,
                                resumePosMs
                            )
                        } else {
                            playResolvedUrlOnExistingPlayer(freshUrl, updatedSrc, freshHeaders, resumePosMs)
                        }
                    }
                }
            }
        } else {
            activeStalkerSource = null
            cachedStalkerPlayUrl = ""
            if (isInitial || player == null) {
                initExoPlayer(src.url, currentMovieTitle, currentUserAgent, currentPreset, src.headers, resumePosMs)
            } else {
                playResolvedUrlOnExistingPlayer(src.url, src, src.headers, resumePosMs)
            }
        }
    }

    private fun playResolvedUrlOnExistingPlayer(
        resolvedUrl: String,
        selected: StreamSourceItem,
        headersToUse: Map<String, String> = selected.headers,
        resumePosMs: Long = 0L
    ) {
        val exo = player ?: return
        applyHeadersToHttpFactory(headersToUse)

        val lower = resolvedUrl.lowercase(Locale.ROOT)
        val itemBuilder = MediaItem.Builder()
            .setUri(Uri.parse(resolvedUrl))
            .setMediaMetadata(MediaMetadata.Builder().setTitle(currentMovieTitle).build())
        when {
            lower.contains(".m3u8") -> itemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
            lower.contains(".mpd") -> itemBuilder.setMimeType(MimeTypes.APPLICATION_MPD)
        }
        currentMediaItem = itemBuilder.build()

        exo.stop()
        if (resumePosMs > 0L) {
            exo.setMediaItem(currentMediaItem, resumePosMs)
        } else {
            exo.setMediaItem(currentMediaItem)
        }
        exo.prepare()
        exo.playWhenReady = true
        if (resumePosMs <= 0L) {
            showFeedback("Playing: ${selected.title}")
        }
    }

    private fun configureDeviceSpecificHud() {
        if (isTvDevice) {
            centerBar.visibility = View.GONE
            actionsRow.visibility = View.GONE
            backBtn.visibility = View.GONE
            sourcesBtn.visibility = View.GONE
            pictureBtn.visibility = View.GONE
            lockBtn.visibility = View.GONE
            tvHintView.visibility = View.VISIBLE
            seekBar.isFocusable = false
        } else {
            centerBar.visibility = View.VISIBLE
            actionsRow.visibility = View.VISIBLE
            backBtn.visibility = View.VISIBLE
            sourcesBtn.visibility = View.VISIBLE
            pictureBtn.visibility = View.VISIBLE
            lockBtn.visibility = View.VISIBLE
            tvHintView.visibility = View.GONE
        }
    }

    private fun parseIncomingSources() {
        try {
            val rawJson = intent.getStringExtra("sourcesJson")?.trim().orEmpty()
            if (rawJson.startsWith("[")) {
                val arr = JSONArray(rawJson)
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    val sUrl = obj.optString("url", "").trim()
                    if (sUrl.isNotEmpty()) {
                        val srv = obj.optString("server", "Server")
                        val ttl = obj.optString("title", currentMovieTitle)
                        val hin = obj.optBoolean("isHindi", isExplicitHindi("$srv $ttl"))
                        val multi = obj.optBoolean("isMultiAudio", isIndianMultiAudioServer("$srv $ttl"))
                        val hdrMap = mutableMapOf<String, String>()
                        val hdrObj = obj.optJSONObject("headers")
                        if (hdrObj != null) {
                            val keys = hdrObj.keys()
                            while (keys.hasNext()) {
                                val k = keys.next()
                                val v = hdrObj.optString(k, "")
                                if (v.isNotEmpty()) hdrMap[k] = v
                            }
                        }
                        streamSources.add(
                            StreamSourceItem(
                                server = srv,
                                title = ttl,
                                url = sUrl,
                                isHindi = hin,
                                isMultiAudio = multi,
                                headers = hdrMap,
                                stalkerEndpoint = obj.optString("stalkerEndpoint", ""),
                                stalkerCmd = obj.optString("stalkerCmd", ""),
                                stalkerMediaType = obj.optString("stalkerMediaType", "vod"),
                                stalkerEpisode = obj.optInt("stalkerEpisode", 0)
                            )
                        )
                    }
                }
            }
            activeSourceIndex = intent.getIntExtra("activeIndex", 0)
        } catch (_: Throwable) {}
    }

    private fun applyHeadersToHttpFactory(headers: Map<String, String>) {
        val factory = httpDataSourceFactory ?: return
        val ua = headers["User-Agent"]
            ?: headers["user-agent"]
            ?: currentUserAgent
        factory.setUserAgent(ua)
        val filtered = headers.filterKeys { !it.equals("User-Agent", ignoreCase = true) }
        factory.setDefaultRequestProperties(filtered)
    }

    private fun setConnectingState(connecting: Boolean) {
        connectingCard.visibility = if (connecting) View.VISIBLE else View.GONE
        centerBar.visibility = if (connecting || isTvDevice) View.GONE else View.VISIBLE
    }

    private fun attachLoudnessEnhancer(audioSessionId: Int) {
        if (audioSessionId <= 0 || audioSessionId == C.AUDIO_SESSION_ID_UNSET) return
        releaseLoudnessEnhancer()
        try {
            loudnessEnhancer = LoudnessEnhancer(audioSessionId)
            applyAudioBoostPercent(currentBoostPercent, showToast = false)
        } catch (_: Throwable) {
            loudnessEnhancer = null
        }
    }

    private fun releaseLoudnessEnhancer() {
        try {
            loudnessEnhancer?.enabled = false
            loudnessEnhancer?.release()
        } catch (_: Throwable) {}
        loudnessEnhancer = null
    }

    private fun applyAudioBoostPercent(percent: Int, showToast: Boolean = true) {
        val clamped = percent.coerceIn(100, 200)
        currentBoostPercent = clamped
        prefs.edit().putInt("audio_boost_percent", clamped).apply()
        updateBoostButtonUi()

        val exo = player
        if (exo != null && loudnessEnhancer == null) {
            val sid = exo.audioSessionId
            if (sid > 0 && sid != C.AUDIO_SESSION_ID_UNSET) {
                try {
                    loudnessEnhancer = LoudnessEnhancer(sid)
                } catch (_: Throwable) {}
            }
        }

        try {
            val enhancer = loudnessEnhancer
            if (enhancer != null) {
                if (clamped <= 100) {
                    enhancer.setTargetGain(0)
                    enhancer.enabled = false
                } else {
                    val gainMb = ((clamped - 100) * 15).coerceIn(0, 1500)
                    enhancer.setTargetGain(gainMb)
                    enhancer.enabled = true
                }
            }
        } catch (_: Throwable) {}

        if (showToast) {
            showFeedback(
                if (clamped > 100) "🔊 Audio Boost: $clamped%" else "🔊 Audio: 100% (Normal)"
            )
        }
    }

    private fun cycleAudioBoost() {
        boostIndex = (boostIndex + 1) % boostLevels.size
        applyAudioBoostPercent(boostLevels[boostIndex], showToast = true)
        scheduleHideHud()
    }

    private fun updateBoostButtonUi() {
        if (!::boostBtn.isInitialized) return
        boostBtn.text = if (currentBoostPercent > 100) {
            "🔊 $currentBoostPercent% BOOST"
        } else {
            "🔊 100%"
        }
        boostBtn.setTextColor(
            if (currentBoostPercent > 100) Color.parseColor(primeBlueLightHex) else Color.WHITE
        )
    }

    private fun searchStalkerProvider(
        prov: JSONObject,
        provName: String,
        movieTitle: String,
        cleanTarget: String,
        isTv: Boolean,
        season: Int,
        episode: Int,
        found: MutableList<StreamSourceItem>,
        onPartialReady: () -> Unit
    ) {
        val rawPortal = prov.optString("portal_url", prov.optString("url", prov.optString("host", ""))).trim()
        val mac = prov.optString("mac", "").trim().uppercase(Locale.ROOT)
        val dev1 = prov.optString("device_id1", prov.optString("device_id", "")).trim()
        val dev2 = prov.optString("device_id2", "").trim()

        val auth = performStalkerHandshake(rawPortal, mac, dev1, dev2) ?: return
        val activeEndpoint = auth.first
        val authHeaders = auth.second

        val mediaType = if (isTv) "series" else "vod"
        val queries = mutableListOf(movieTitle.trim())
        if (movieTitle.contains(":")) {
            queries.add(movieTitle.substringBefore(":").trim())
        }

        val collected = mutableListOf<StreamSourceItem>()

        for (q in queries) {
            if (q.isEmpty() || collected.isNotEmpty()) continue
            val encodedQ = URLEncoder.encode(q, "UTF-8")

            for (page in 1..3) {
                if (!isSafeUi()) break
                val sUrl = "$activeEndpoint?type=$mediaType&action=get_ordered_list&search=$encodedQ&p=$page&JsHttpRequest=1-xml"
                val resStr = httpGetWithHeaders(sUrl, 12_000, authHeaders)
                if (!resStr.contains("{")) break

                var dataArr: JSONArray? = null
                try {
                    val cleanJson = resStr.substring(resStr.indexOf('{'))
                    val js = JSONObject(cleanJson).opt("js")
                    dataArr = when (js) {
                        is JSONObject -> js.optJSONArray("data")
                        is JSONArray -> js
                        else -> null
                    }
                } catch (_: Throwable) {}

                if (dataArr == null || dataArr.length() == 0) break

                for (i in 0 until dataArr.length()) {
                    if (!isSafeUi()) break
                    val item = dataArr.optJSONObject(i) ?: continue
                    val itemName = item.optString("name", item.optString("o_name", ""))
                    val sClean = cleanText(itemName)
                    val matched = sClean.length >= 3 && cleanTarget.length >= 3 && (
                        sClean == cleanTarget ||
                        sClean.contains(cleanTarget) ||
                        (sClean.length > 4 && cleanTarget.contains(sClean))
                    )
                    if (!matched) continue

                    var cmd = item.optString("cmd", "").trim()
                    val itemId = item.optString("id", "").trim()
                    if (isTv && itemId.isNotEmpty()) {
                        val epCmd = findStalkerEpisodeCmd(activeEndpoint, authHeaders, itemId, season, episode)
                        if (epCmd.isNotEmpty()) cmd = epCmd
                    }
                    if (cmd.isEmpty() && itemId.isEmpty()) continue

                    val epVal = if (isTv) episode else 0
                    val placeholderUrl = "$activeEndpoint?stalker_item=$itemId&ep=$epVal&p=$page&i=$i"
                    collected.add(
                        StreamSourceItem(
                            server = provName.ifBlank { "Stalker Portal" },
                            title = if (isTv) "$itemName • S${season}E${episode}" else itemName,
                            url = placeholderUrl,
                            isHindi = isExplicitHindi("$provName $itemName"),
                            isMultiAudio = false,
                            headers = authHeaders,
                            stalkerEndpoint = activeEndpoint,
                            stalkerCmd = cmd,
                            stalkerMediaType = mediaType,
                            stalkerEpisode = epVal,
                            stalkerItemId = itemId,
                            stalkerPortalRaw = rawPortal,
                            stalkerMac = mac,
                            stalkerDev1 = dev1,
                            stalkerDev2 = dev2
                        )
                    )
                }
            }
        }

        if (collected.isNotEmpty()) {
            collected.sortByDescending { if (it.isHindi) 1 else 0 }
            found.addAll(collected.take(15))
            onPartialReady()
        }
    }

    private fun findStalkerEpisodeCmd(
        endpoint: String,
        headers: Map<String, String>,
        seriesId: String,
        season: Int,
        episode: Int
    ): String {
        try {
            val sStr = httpGetWithHeaders(
                "$endpoint?type=series&action=get_ordered_list&movie_id=${URLEncoder.encode(seriesId, "UTF-8")}&p=1&JsHttpRequest=1-xml",
                10_000,
                headers
            )
            if (!sStr.contains("{")) return ""
            val js = JSONObject(sStr.substring(sStr.indexOf('{'))).opt("js")
            val seasons = if (js is JSONObject) js.optJSONArray("data") else if (js is JSONArray) js else null
            if (seasons == null) return ""

            for (i in 0 until seasons.length()) {
                val sObj = seasons.optJSONObject(i) ?: continue
                val sName = sObj.optString("name", "").lowercase(Locale.ROOT)
                val sNum = sObj.optInt("season_number", -1).takeIf { it > 0 }
                    ?: Regex("\\d+").find(sName)?.value?.toIntOrNull()
                if (sNum == season || seasons.length() == 1) {
                    val seasonId = sObj.optString("id", "")
                    val sCmd = sObj.optString("cmd", "")
                    if (seasonId.isNotEmpty()) {
                        val epStr = httpGetWithHeaders(
                            "$endpoint?type=series&action=get_ordered_list&movie_id=${URLEncoder.encode(seriesId, "UTF-8")}&season_id=${URLEncoder.encode(seasonId, "UTF-8")}&p=1&JsHttpRequest=1-xml",
                            10_000,
                            headers
                        )
                        if (epStr.contains("{")) {
                            val epJs = JSONObject(epStr.substring(epStr.indexOf('{'))).opt("js")
                            val eps = if (epJs is JSONObject) epJs.optJSONArray("data") else if (epJs is JSONArray) epJs else null
                            if (eps != null) {
                                for (j in 0 until eps.length()) {
                                    val epObj = eps.optJSONObject(j) ?: continue
                                    val eNum = epObj.optInt("episode_number", -1).takeIf { it > 0 }
                                        ?: Regex("\\d+").find(epObj.optString("name", ""))?.value?.toIntOrNull()
                                    if (eNum == episode) {
                                        val epCmd = epObj.optString("cmd", "").trim()
                                        if (epCmd.isNotEmpty()) return epCmd
                                    }
                                }
                            }
                        }
                    }
                    if (sCmd.isNotEmpty()) return sCmd
                }
            }
        } catch (_: Throwable) {}
        return ""
    }

    private fun resolveStreamsInsidePlayer(
        tmdbId: String,
        tmdbKey: String,
        customGistUrl: String,
        extraProvidersJson: String,
        movieTitle: String,
        isTv: Boolean,
        season: Int,
        episode: Int
    ) {
        isResolvingAllSources = true
        thread(start = true) {
            val found = Collections.synchronizedList(mutableListOf<StreamSourceItem>())
            val playbackStarted = AtomicBoolean(false)
            val cleanTarget = cleanText(movieTitle)
            var imdbId = ""

            fun syncSourcesToUi(isFinal: Boolean = false) {
                val snapshot = synchronized(found) {
                    found.distinctBy { it.url }.toMutableList()
                }
                snapshot.sortWith(
                    compareByDescending<StreamSourceItem> { sourcePriorityScore(it) }
                        .thenByDescending { qualityScore(it.title) }
                )
                if (snapshot.size > 60) {
                    snapshot.subList(60, snapshot.size).clear()
                }

                handler.post {
                    if (!isSafeUi()) return@post
                    streamSources.clear()
                    streamSources.addAll(snapshot)

                    if (currentActiveUrl.isNotEmpty()) {
                        val idx = streamSources.indexOfFirst { it.url == currentActiveUrl }
                        if (idx >= 0) activeSourceIndex = idx
                    }

                    sourcesBtn.text = if (isFinal) {
                        "Sources (${streamSources.size})"
                    } else {
                        "Sources (${streamSources.size}+)"
                    }

                    if (sourcesOverlay.visibility == View.VISIBLE) {
                        refreshSourcesListUi()
                    }

                    if (streamSources.isNotEmpty() && playbackStarted.compareAndSet(false, true)) {
                        activeSourceIndex = 0
                        retriedCurrentSourceCount = 0
                        userManuallyPickedSource = false
                        currentActiveUrl = streamSources[0].url
                        setConnectingState(false)
                        loadingSpinner.visibility = View.VISIBLE
                        resolveAndStartSource(streamSources[0], isInitial = true)
                        if (!isTvDevice) {
                            playPauseBtn.requestFocus()
                        }
                        scheduleHideHud()
                    }
                }
            }

            if (tmdbKey.isNotEmpty()) {
                try {
                    val extType = if (isTv) "tv" else "movie"
                    val extStr = httpGet(
                        "https://api.themoviedb.org/3/$extType/$tmdbId/external_ids?api_key=$tmdbKey",
                        6000
                    )
                    if (extStr.isNotEmpty()) {
                        imdbId = JSONObject(extStr).optString("imdb_id", "")
                    }
                } catch (_: Throwable) {}
            }

            val providers = mutableListOf<JSONObject>()

            if (extraProvidersJson.startsWith("[")) {
                try {
                    val extraArr = JSONArray(extraProvidersJson)
                    for (i in 0 until extraArr.length()) {
                        providers.add(extraArr.getJSONObject(i))
                    }
                } catch (_: Throwable) {}
            }

            if (customGistUrl.isNotEmpty()) {
                try {
                    val sep = if (customGistUrl.contains("?")) "&" else "?"
                    val gistUrl = "$customGistUrl${sep}t=${System.currentTimeMillis()}"
                    val gistStr = httpGet(gistUrl, 10_000)
                    if (gistStr.isNotEmpty()) {
                        val trimmed = gistStr.trim()
                        val arr = if (trimmed.startsWith("[")) {
                            JSONArray(trimmed)
                        } else {
                            val obj = JSONObject(trimmed)
                            obj.optJSONArray("active_providers")
                                ?: obj.optJSONArray("providers")
                                ?: JSONArray()
                        }
                        for (i in 0 until arr.length()) {
                            providers.add(arr.getJSONObject(i))
                        }
                    }
                } catch (_: Throwable) {}
            }

            val latch = CountDownLatch(providers.size)

            for (prov in providers) {
                thread(start = true) {
                    try {
                        if (!isSafeUi()) return@thread
                        val type = prov.optString("type", "").lowercase(Locale.ROOT)
                        val provName = prov.optString("name", "Server")

                        if (type == "stalker") {
                            searchStalkerProvider(
                                prov = prov,
                                provName = provName,
                                movieTitle = movieTitle,
                                cleanTarget = cleanTarget,
                                isTv = isTv,
                                season = season,
                                episode = episode,
                                found = found,
                                onPartialReady = { syncSourcesToUi(isFinal = false) }
                            )
                        } else if (type == "xtream") {
                            var host = prov.optString("xc_host", prov.optString("host", prov.optString("url", ""))).trimEnd('/')
                            if (host.isNotEmpty() && !host.startsWith("http://") && !host.startsWith("https://")) {
                                host = "http://$host"
                            }
                            val user = prov.optString("xc_username", prov.optString("username", ""))
                            val pass = prov.optString("xc_password", prov.optString("password", ""))

                            if (host.isNotEmpty() && user.isNotEmpty() && pass.isNotEmpty()) {
                                if (isTv) {
                                    val cands = streamSearchXtreamList(
                                        apiUrl = "$host/player_api.php?username=$user&password=$pass&action=get_series",
                                        tmdbId = tmdbId,
                                        cleanTarget = cleanTarget,
                                        idKey = "series_id"
                                    )
                                    cands.sortByDescending { if (it.isHindi) 1 else 0 }
                                    for (bestSeries in cands) {
                                        if (!isSafeUi()) break
                                        val infoStr = httpGet(
                                            "$host/player_api.php?username=$user&password=$pass&action=get_series_info&series_id=${bestSeries.id}",
                                            15_000,
                                            userAgent = "IPTVSmartersPro"
                                        )
                                        if (infoStr.startsWith("{")) {
                                            val epMap = JSONObject(infoStr).optJSONObject("episodes")
                                            val epArr = epMap?.optJSONArray("$season")
                                            if (epArr != null) {
                                                for (j in 0 until epArr.length()) {
                                                    val epObj = epArr.getJSONObject(j)
                                                    if (epObj.optInt("episode_num", -1) == episode) {
                                                        val eid = epObj.optString("id", "")
                                                        val ext = epObj.optString("container_extension", "mp4").ifBlank { "mp4" }
                                                        found.add(
                                                            StreamSourceItem(
                                                                server = provName.ifBlank { "IPTV Server" },
                                                                title = if (bestSeries.isHindi) "$movieTitle (Hindi) S$season:E$episode" else "$movieTitle S$season:E$episode",
                                                                url = "$host/series/$user/$pass/$eid.$ext",
                                                                isHindi = bestSeries.isHindi,
                                                                isMultiAudio = false,
                                                                headers = mapOf("User-Agent" to "IPTVSmartersPro")
                                                            )
                                                        )
                                                        syncSourcesToUi(isFinal = false)
                                                        break
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    val cands = streamSearchXtreamList(
                                        apiUrl = "$host/player_api.php?username=$user&password=$pass&action=get_vod_streams",
                                        tmdbId = tmdbId,
                                        cleanTarget = cleanTarget,
                                        idKey = "stream_id"
                                    )
                                    cands.sortByDescending { if (it.isHindi) 1 else 0 }
                                    for (bestMovie in cands) {
                                        found.add(
                                            StreamSourceItem(
                                                server = provName.ifBlank { "IPTV Server" },
                                                title = bestMovie.name.ifBlank { movieTitle },
                                                url = "$host/movie/$user/$pass/${bestMovie.id}.${bestMovie.ext}",
                                                isHindi = bestMovie.isHindi,
                                                isMultiAudio = false,
                                                headers = mapOf("User-Agent" to "IPTVSmartersPro")
                                            )
                                        )
                                    }
                                    if (cands.isNotEmpty()) syncSourcesToUi(isFinal = false)
                                }
                            }
                        } else if (type == "stremio" && imdbId.isNotEmpty()) {
                            val base = prov.optString("url", "").replace("/manifest.json", "")
                            val streamPath = if (isTv) {
                                "$base/stream/series/$imdbId:$season:$episode.json"
                            } else {
                                "$base/stream/movie/$imdbId.json"
                            }
                            val sStr = httpGet(streamPath, 12_000)
                            if (sStr.startsWith("{")) {
                                val entries = JSONObject(sStr).optJSONArray("streams")
                                if (entries != null) {
                                    var addedAny = false
                                    for (i in 0 until entries.length()) {
                                        val sObj = entries.getJSONObject(i)
                                        val sUrl = sObj.optString("url", "").trim()
                                        if (sUrl.isEmpty()) continue
                                        val namePart = sObj.optString("name", "")
                                        val titlePart = sObj.optString("title", "")
                                        val combined = "$namePart $titlePart".trim()
                                        val low = combined.lowercase(Locale.ROOT)
                                        if (low.contains("donation") || low.contains("discord") || low.contains("telegram")) continue

                                        val displayTitle = titlePart.ifBlank { namePart }.ifBlank { "$movieTitle HD" }
                                        val explicitHindi = isExplicitHindi("$provName $combined")
                                        val multiHindi = isIndianMultiAudioServer("$provName $combined")

                                        found.add(
                                            StreamSourceItem(
                                                server = provName.ifBlank { "HDHub4u" },
                                                title = displayTitle,
                                                url = sUrl,
                                                isHindi = explicitHindi || multiHindi,
                                                isMultiAudio = multiHindi && !explicitHindi
                                            )
                                        )
                                        addedAny = true
                                    }
                                    if (addedAny) syncSourcesToUi(isFinal = false)
                                }
                            }
                        }
                    } catch (_: Throwable) {
                    } finally {
                        latch.countDown()
                    }
                }
            }

            try {
                latch.await(30, TimeUnit.SECONDS)
            } catch (_: Throwable) {}

            isResolvingAllSources = false
            syncSourcesToUi(isFinal = true)

            handler.post {
                if (!isSafeUi()) return@post
                if (streamSources.isEmpty()) {
                    setConnectingState(false)
                    showError("No stream sources found for this title.")
                }
            }
        }
    }

    private data class XtreamCandidate(
        val id: String,
        val name: String,
        val ext: String,
        val isHindi: Boolean
    )

    private fun streamSearchXtreamList(
        apiUrl: String,
        tmdbId: String,
        cleanTarget: String,
        idKey: String
    ): MutableList<XtreamCandidate> {
        val matches = mutableListOf<XtreamCandidate>()
        var conn: HttpURLConnection? = null
        try {
            conn = (URL(apiUrl).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15_000
                readTimeout = 35_000
                requestMethod = "GET"
                setRequestProperty("User-Agent", "IPTVSmartersPro")
            }
            if (conn.responseCode !in 200..299) return matches

            JsonReader(InputStreamReader(conn.inputStream, "UTF-8")).use { reader ->
                reader.isLenient = true
                if (reader.peek() != JsonToken.BEGIN_ARRAY) return matches
                reader.beginArray()
                while (reader.hasNext()) {
                    if (!isSafeUi()) break
                    if (reader.peek() != JsonToken.BEGIN_OBJECT) {
                        reader.skipValue()
                        continue
                    }
                    var itemId = ""
                    var itemName = ""
                    var itemCat = ""
                    var itemTmdb = ""
                    var itemExt = "mp4"

                    reader.beginObject()
                    while (reader.hasNext()) {
                        val key = reader.nextName()
                        if (reader.peek() == JsonToken.NULL) {
                            reader.nextNull()
                            continue
                        }
                        when (key) {
                            idKey -> itemId = readScalarAsString(reader)
                            "name" -> itemName = readScalarAsString(reader)
                            "category_name" -> itemCat = readScalarAsString(reader)
                            "tmdb_id", "tmdb" -> itemTmdb = readScalarAsString(reader)
                            "container_extension" -> {
                                val v = readScalarAsString(reader)
                                if (v.isNotBlank()) itemExt = v
                            }
                            else -> reader.skipValue()
                        }
                    }
                    reader.endObject()

                    if (itemId.isNotEmpty()) {
                        val sClean = cleanText(itemName)
                        val tmdbMatch = itemTmdb.isNotEmpty() && itemTmdb == tmdbId
                        val titleMatch = sClean.length >= 3 && cleanTarget.length >= 3 && (
                            sClean == cleanTarget ||
                            (cleanTarget.length >= 4 && sClean.contains(cleanTarget))
                        )
                        if (tmdbMatch || titleMatch) {
                            matches.add(
                                XtreamCandidate(
                                    id = itemId,
                                    name = itemName,
                                    ext = itemExt,
                                    isHindi = isExplicitHindi("$itemName $itemCat")
                                )
                            )
                        }
                    }
                }
            }
        } catch (_: Throwable) {
        } finally {
            try { conn?.disconnect() } catch (_: Throwable) {}
        }
        return matches
    }

    private fun readScalarAsString(reader: JsonReader): String {
        return when (reader.peek()) {
            JsonToken.STRING -> reader.nextString()
            JsonToken.NUMBER -> reader.nextString()
            JsonToken.BOOLEAN -> reader.nextBoolean().toString()
            else -> {
                reader.skipValue()
                ""
            }
        }
    }

    private fun isIptvSource(item: StreamSourceItem): Boolean {
        val urlLow = item.url.lowercase(Locale.ROOT)
        return urlLow.contains("/movie/") || urlLow.contains("/series/") ||
            item.stalkerCmd.isNotEmpty() || item.stalkerItemId.isNotEmpty() ||
            item.server.contains("stalker", true) || item.server.contains("portal", true) ||
            item.server.contains("livebox", true) || item.server.contains("iptv", true) ||
            item.server.contains("tv", true) || item.server.contains("ott", true)
    }

    private fun sourcePriorityScore(item: StreamSourceItem): Int {
        val isIptv = isIptvSource(item)
        return when {
            isIptv && item.isHindi -> 110
            isIptv -> 95
            item.isHindi && !item.isMultiAudio -> 85
            item.isMultiAudio -> 75
            else -> 20
        }
    }

    private fun qualityScore(title: String): Int {
        val low = title.lowercase(Locale.ROOT)
        return when {
            low.contains("1080") -> 4
            low.contains("720") -> 3
            low.contains("2160") || low.contains("4k") -> 2
            else -> 1
        }
    }

    private fun httpGet(urlStr: String, timeoutMs: Int, userAgent: String = "Mozilla/5.0"): String {
        return httpGetWithHeaders(urlStr, timeoutMs, mapOf("User-Agent" to userAgent))
    }

    private fun httpGetWithHeaders(urlStr: String, timeoutMs: Int, headers: Map<String, String>): String {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                connectTimeout = timeoutMs
                readTimeout = timeoutMs
                requestMethod = "GET"
                headers.forEach { (k, v) -> setRequestProperty(k, v) }
            }
            if (conn.responseCode in 200..299) {
                conn.inputStream.bufferedReader().use { it.readText() }
            } else {
                ""
            }
        } catch (_: Throwable) {
            ""
        } finally {
            try { conn?.disconnect() } catch (_: Throwable) {}
        }
    }

    private fun isExplicitHindi(text: String): Boolean {
        val low = text.lowercase(Locale.ROOT)
        return low.contains("hindi") || low.contains("dual") ||
            low.contains("multi") || low.contains("dubbed") ||
            low.contains("(hin)") || low.contains("[hin]") ||
            low.contains(" hin ") || low.startsWith("in ") || low.contains("in |") || low.contains("in -")
    }

    private fun isIndianMultiAudioServer(text: String): Boolean {
        val low = text.lowercase(Locale.ROOT)
        return low.contains("penguplay") || low.contains("4khdhub") ||
            low.contains("hdhub4u") || low.contains("vegamovies") ||
            low.contains("moviesmod") || low.contains("uhdmovies") ||
            low.contains("bollyflix") || low.contains("desiremovies")
    }

    private fun cleanText(text: String): String =
        text.lowercase(Locale.ROOT)
            .replace(Regex("\\(\\d{4}\\)"), "")
            .replace(Regex("[^a-z0-9]"), "")
            .trim()

    private fun findAspectFrameLayout(view: View): AspectRatioFrameLayout? {
        if (view is AspectRatioFrameLayout) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val found = findAspectFrameLayout(view.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }

    private fun resetViewTransform(view: View?) {
        if (view == null) return
        view.scaleX = 1f
        view.scaleY = 1f
        view.translationX = 0f
        view.translationY = 0f
    }

    private fun applyCameraEdgeZoomToSurface(targetView: View?, mode: Int) {
        if (targetView == null) return

        if (mode == AspectRatioFrameLayout.RESIZE_MODE_FIT) {
            resetViewTransform(targetView)
            return
        }

        val screenW = resources.displayMetrics.widthPixels.toFloat()
        val screenH = resources.displayMetrics.heightPixels.toFloat()
        val vw = targetView.width.toFloat()
        val vh = targetView.height.toFloat()

        if (screenW <= 0f || screenH <= 0f || vw <= 0f || vh <= 0f) {
            resetViewTransform(targetView)
            return
        }

        targetView.pivotX = vw / 2f
        targetView.pivotY = vh / 2f
        targetView.translationX = 0f
        targetView.translationY = 0f

        if (mode == AspectRatioFrameLayout.RESIZE_MODE_FILL) {
            targetView.scaleX = (screenW / vw).coerceAtLeast(1f)
            targetView.scaleY = (screenH / vh).coerceAtLeast(1f)
        } else {
            val coverScale = max(1f, max(screenW / vw, screenH / vh))
            targetView.scaleX = coverScale
            targetView.scaleY = coverScale
        }
    }

    private fun syncZoomScaleOnly(mode: Int) {
        if (!::playerView.isInitialized) return
        val aspectFrame = findAspectFrameLayout(playerView)
        val surface = playerView.videoSurfaceView

        if (mode == AspectRatioFrameLayout.RESIZE_MODE_FIT) {
            resetViewTransform(aspectFrame)
            resetViewTransform(surface)
            return
        }

        if (surface != null && surface.width > 0 && surface.height > 0) {
            resetViewTransform(aspectFrame)
            applyCameraEdgeZoomToSurface(surface, mode)
        } else {
            resetViewTransform(surface)
            applyCameraEdgeZoomToSurface(aspectFrame, mode)
        }
    }

    private fun applyResizeModeToPlayer(mode: Int) {
        if (!::playerView.isInitialized) return
        applyCameraCutoutFullScreen()
        playerView.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        playerView.resizeMode = mode

        val aspectFrame = findAspectFrameLayout(playerView)
        val surface = playerView.videoSurfaceView

        if (mode == AspectRatioFrameLayout.RESIZE_MODE_FIT) {
            resetViewTransform(aspectFrame)
            resetViewTransform(surface)
        }

        aspectFrame?.let { frame ->
            frame.layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            )
            frame.resizeMode = mode
            frame.requestLayout()
            frame.invalidate()
        }
        playerView.requestLayout()
        playerView.invalidate()

        playerView.post {
            if (!isSafeUi()) return@post
            syncZoomScaleOnly(mode)
        }
    }

    private fun buildGestureAndHudLayers(root: FrameLayout) {
        val gestureLayer = View(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }
        if (!isTvDevice) {
            setupTouchGestures(gestureLayer)
        }
        root.addView(gestureLayer)

        loadingSpinner = ProgressBar(this).apply {
            indeterminateTintList = ColorStateList.valueOf(Color.parseColor(primeBlueHex))
            layoutParams = FrameLayout.LayoutParams(dp(52), dp(52), Gravity.CENTER)
            visibility = View.GONE
        }
        root.addView(loadingSpinner)

        connectingCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            minimumWidth = dp(260)
            setPadding(dp(32), dp(24), dp(32), dp(24))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#F00C111B"))
                cornerRadius = dp(16).toFloat()
                setStroke(dp(1), Color.parseColor("#9900A8E1"))
            }
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        }
        val cardSpinner = ProgressBar(this).apply {
            indeterminateTintList = ColorStateList.valueOf(Color.parseColor(primeBlueHex))
            layoutParams = LinearLayout.LayoutParams(dp(40), dp(40))
        }
        connectingText = TextView(this).apply {
            text = "Auto-connecting best stream..."
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, dp(14), 0, 0)
        }
        connectingCard.addView(cardSpinner)
        connectingCard.addView(connectingText)
        root.addView(connectingCard)

        feedbackBadge = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dp(18), dp(10), dp(18), dp(10))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#CC0C111B"))
                cornerRadius = dp(24).toFloat()
                setStroke(dp(1), Color.parseColor("#8800A8E1"))
            }
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER_HORIZONTAL or Gravity.TOP
            ).apply {
                topMargin = dp(36)
            }
        }
        root.addView(feedbackBadge)

        hudContainer = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        val topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(18), dp(16), dp(18), dp(22))
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.parseColor("#DD000000"), Color.TRANSPARENT)
            )
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        }

        backBtn = createHudButton("← Back") { finishPlayerCleanly() }
        titleView = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            setPadding(dp(12), 0, dp(10), 0)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        infoBadgeView = TextView(this).apply {
            text = "HW"
            setTextColor(Color.parseColor(primeBlueLightHex))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dp(8), dp(4), dp(8), dp(4))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#3300A8E1"))
                cornerRadius = dp(6).toFloat()
            }
            visibility = View.GONE
        }
        sourcesBtn = createHudButton("Sources (0)") { openSourcesPanel() }.apply {
            background = createSourcesPill()
        }
        pictureBtn = createHudButton("HW Original") { showPicturePresetDialog() }
        lockBtn = createHudButton("🔒 Lock") { lockScreen() }

        topBar.addView(backBtn)
        topBar.addView(titleView)
        topBar.addView(infoBadgeView)
        topBar.addView(spacer(dp(8)))
        topBar.addView(sourcesBtn)
        topBar.addView(spacer(dp(8)))
        topBar.addView(pictureBtn)
        topBar.addView(spacer(dp(8)))
        topBar.addView(lockBtn)
        hudContainer.addView(topBar)

        centerBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        }
        val rwBtn = createHudButton("↺ ${seekStepSec}s", big = true) { seekBy(-seekStepMs) }
        playPauseBtn = createHudButton("❚❚", big = true) { togglePlayPause() }
        val fwBtn = createHudButton("${seekStepSec}s ↻", big = true) { seekBy(seekStepMs) }
        centerBar.addView(rwBtn)
        centerBar.addView(spacer(dp(20)))
        centerBar.addView(playPauseBtn)
        centerBar.addView(spacer(dp(20)))
        centerBar.addView(fwBtn)
        hudContainer.addView(centerBar)

        val bottomPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(22), dp(20), dp(14))
            background = GradientDrawable(
                GradientDrawable.Orientation.BOTTOM_TOP,
                intArrayOf(Color.parseColor("#E6000000"), Color.TRANSPARENT)
            )
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
            )
        }

        seekBarRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(6), dp(10), dp(6))
            background = GradientDrawable().apply {
                setColor(Color.TRANSPARENT)
                cornerRadius = dp(10).toFloat()
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        timeCurrentView = TextView(this).apply {
            text = "00:00"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
        }
        seekBar = SeekBar(this).apply {
            max = 1000
            keyProgressIncrement = 15
            isFocusable = !isTvDevice
            isFocusableInTouchMode = false
            progressTintList = ColorStateList.valueOf(Color.parseColor(primeBlueHex))
            thumbTintList = ColorStateList.valueOf(Color.parseColor(primeBlueHex))
            secondaryProgressTintList = ColorStateList.valueOf(Color.parseColor("#6600A8E1"))
            progressBackgroundTintList = ColorStateList.valueOf(Color.parseColor("#4DFFFFFF"))
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                leftMargin = dp(14)
                rightMargin = dp(14)
            }
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(sb: SeekBar?, progress: Int, fromUser: Boolean) {
                    if (fromUser) {
                        val dur = player?.duration ?: 0L
                        if (dur > 0) {
                            timeCurrentView.text = formatTime((dur * progress) / 1000L)
                        }
                    }
                }

                override fun onStartTrackingTouch(sb: SeekBar?) {
                    isSeekingFromUser = true
                    handler.removeCallbacks(hideHudRunnable)
                }

                override fun onStopTrackingTouch(sb: SeekBar?) {
                    isSeekingFromUser = false
                    val dur = player?.duration ?: 0L
                    if (dur > 0 && sb != null) {
                        val targetPos = (dur * sb.progress) / 1000L
                        pendingResumePositionMs = targetPos
                        player?.seekTo(targetPos)
                    }
                    scheduleHideHud()
                }
            })
        }
        timeTotalView = TextView(this).apply {
            text = "00:00"
            setTextColor(Color.parseColor("#CCFFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
        }
        seekBarRow.addView(timeCurrentView)
        seekBarRow.addView(seekBar)
        seekBarRow.addView(timeTotalView)

        tvHintView = TextView(this).apply {
            text = "◀ -${seekStepSec}s   |   OK Play/Pause   |   +${seekStepSec}s ▶   |   ▲ Screen Size   |   ▼ Sources & Audio"
            setTextColor(Color.parseColor("#CBD5E1"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
            gravity = Gravity.CENTER
            setPadding(0, dp(6), 0, dp(2))
            visibility = View.GONE
        }

        actionsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, dp(10), 0, 0)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        boostBtn = createHudButton("🔊 100%") { cycleAudioBoost() }
        val audioBtn = createHudButton("Audio Track") { showAudioDialog() }
        val subQualBtn = createHudButton("Sub / Quality") { showSubAndQualityDialog() }
        aspectBtn = createHudButton("Fit") { cycleAspectRatio() }
        speedBtn = createHudButton("1.0x") { cyclePlaybackSpeed() }

        actionsRow.addView(boostBtn)
        actionsRow.addView(spacer(dp(8)))
        actionsRow.addView(audioBtn)
        actionsRow.addView(spacer(dp(8)))
        actionsRow.addView(subQualBtn)
        actionsRow.addView(spacer(dp(8)))
        actionsRow.addView(aspectBtn)
        actionsRow.addView(spacer(dp(8)))
        actionsRow.addView(speedBtn)

        bottomPanel.addView(seekBarRow)
        bottomPanel.addView(tvHintView)
        bottomPanel.addView(actionsRow)
        hudContainer.addView(bottomPanel)

        root.addView(hudContainer)

        unlockBtn = createHudButton("🔓 Unlock Screen", big = true) { unlockScreen() }.apply {
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            ).apply {
                bottomMargin = dp(32)
            }
        }
        root.addView(unlockBtn)

        errorOverlay = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#E6000000"))
            setPadding(dp(24), dp(24), dp(24), dp(24))
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }
        errorMessageView = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            gravity = Gravity.CENTER
        }
        val retryBtn = createHudButton("Retry") {
            errorOverlay.visibility = View.GONE
            loadingSpinner.visibility = View.VISIBLE
            retriedCurrentSourceCount = 0
            if (activeSourceIndex in streamSources.indices) {
                resolveAndStartSource(
                    streamSources[activeSourceIndex],
                    isInitial = false,
                    resumePosMs = pendingResumePositionMs
                )
            } else {
                player?.prepare()
                player?.playWhenReady = true
            }
        }
        val switchSrcErrBtn = createHudButton("Switch Source") {
            errorOverlay.visibility = View.GONE
            openSourcesPanel()
        }
        val closeBtn = createHudButton("Close") { finishPlayerCleanly() }
        val errBtns = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, dp(16), 0, 0)
            addView(retryBtn)
            addView(spacer(dp(12)))
            addView(switchSrcErrBtn)
            addView(spacer(dp(12)))
            addView(closeBtn)
        }
        errorOverlay.addView(errorMessageView)
        errorOverlay.addView(errBtns)
        root.addView(errorOverlay)
    }

    private fun buildSourcesSidePanel(root: FrameLayout) {
        sourcesOverlay = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#B3000000"))
            visibility = View.GONE
            isClickable = true
            isFocusable = false
            setOnClickListener { closeSourcesPanel() }
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        val drawerWidth = (resources.displayMetrics.widthPixels * 0.48f)
            .toInt()
            .coerceIn(dp(320), dp(450))

        val drawer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#F50C111B"))
            setPadding(dp(18), dp(18), dp(18), dp(16))
            isClickable = true
            isFocusable = false
            layoutParams = FrameLayout.LayoutParams(
                drawerWidth,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.END
            )
        }

        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        val topLeftAudioBtn = Button(this).apply {
            text = "🔊 Audio"
            isAllCaps = false
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            typeface = Typeface.DEFAULT_BOLD
            minWidth = 0
            minHeight = 0
            isFocusable = true
            isFocusableInTouchMode = false
            setPadding(dp(12), dp(6), dp(12), dp(6))
            background = createFocusablePill()
            setOnClickListener {
                closeSourcesPanel()
                showAudioDialog()
            }
            setOnKeyListener { _, keyCode, event ->
                if (event.action == KeyEvent.ACTION_DOWN &&
                    (keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER)
                ) {
                    closeSourcesPanel()
                    showAudioDialog()
                    true
                } else {
                    false
                }
            }
        }

        val headerTexts = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), 0, dp(8), 0)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }

        val headerTitle = TextView(this).apply {
            text = "Select Stream Source"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16.5f)
            typeface = Typeface.DEFAULT_BOLD
        }
        val headerSub = TextView(this).apply {
            text = "IPTV VOD & Hindi servers listed on top"
            setTextColor(Color.parseColor(primeBlueLightHex))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
            setPadding(0, dp(2), 0, 0)
        }
        headerTexts.addView(headerTitle)
        headerTexts.addView(headerSub)

        val closeDrawerBtn = Button(this).apply {
            text = "✕"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            minWidth = 0
            minHeight = 0
            isFocusable = true
            isFocusableInTouchMode = false
            setPadding(dp(12), dp(6), dp(12), dp(6))
            background = createFocusablePill()
            setOnClickListener { closeSourcesPanel() }
        }

        headerRow.addView(topLeftAudioBtn)
        headerRow.addView(headerTexts)
        headerRow.addView(closeDrawerBtn)
        drawer.addView(headerRow)

        val scrollView = ScrollView(this).apply {
            setPadding(0, dp(14), 0, 0)
            isFocusable = false
            descendantFocusability = ViewGroup.FOCUS_AFTER_DESCENDANTS
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        }

        sourcesListContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            isFocusable = false
            descendantFocusability = ViewGroup.FOCUS_AFTER_DESCENDANTS
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        scrollView.addView(sourcesListContainer)
        drawer.addView(scrollView)
        sourcesOverlay.addView(drawer)
        root.addView(sourcesOverlay)
    }

    private fun openSourcesPanel() {
        if (!isSafeUi()) return
        handler.removeCallbacks(hideHudRunnable)
        refreshSourcesListUi()
        sourcesOverlay.visibility = View.VISIBLE
        sourcesListContainer.post {
            if (!isSafeUi()) return@post
            val offset = if (isResolvingAllSources) 1 else 0
            val targetIdx = (activeSourceIndex + offset).coerceIn(0, (sourcesListContainer.childCount - 1).coerceAtLeast(0))
            if (sourcesListContainer.childCount > 0) {
                sourcesListContainer.getChildAt(targetIdx)?.requestFocus()
            }
        }
    }

    private fun closeSourcesPanel() {
        if (!isSafeUi()) return
        sourcesOverlay.visibility = View.GONE
        if (!isTvDevice) {
            sourcesBtn.requestFocus()
        }
        scheduleHideHud()
    }

    private fun createSourceCardBackground(isSelected: Boolean, isHindi: Boolean): StateListDrawable {
        val focused = GradientDrawable().apply {
            setColor(Color.parseColor("#0C4A6E"))
            cornerRadius = dp(10).toFloat()
            setStroke(dp(3), Color.WHITE)
        }
        val normal = GradientDrawable().apply {
            setColor(
                when {
                    isSelected -> Color.parseColor("#0F2942")
                    isHindi -> Color.parseColor("#132238")
                    else -> Color.parseColor("#131722")
                }
            )
            cornerRadius = dp(10).toFloat()
            setStroke(
                dp(if (isSelected || isHindi) 2 else 1),
                when {
                    isSelected -> Color.parseColor(primeBlueHex)
                    isHindi -> Color.parseColor("#8800A8E1")
                    else -> Color.parseColor("#2A3142")
                }
            )
        }
        return StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_focused), focused)
            addState(intArrayOf(android.R.attr.state_pressed), focused)
            addState(intArrayOf(), normal)
        }
    }

    private fun refreshSourcesListUi() {
        sourcesListContainer.removeAllViews()

        if (streamSources.isEmpty()) {
            val emptyTxt = TextView(this).apply {
                text = "Searching servers... please wait"
                setTextColor(Color.parseColor("#99FFFFFF"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                setPadding(dp(8), dp(24), dp(8), dp(8))
            }
            sourcesListContainer.addView(emptyTxt)
            return
        }

        if (isResolvingAllSources) {
            val scanningBanner = TextView(this).apply {
                text = "⏳ Scanning IPTV & Cloud servers (${streamSources.size} loaded)..."
                setTextColor(Color.parseColor(primeBlueLightHex))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
                typeface = Typeface.DEFAULT_BOLD
                setPadding(dp(4), 0, dp(4), dp(10))
            }
            sourcesListContainer.addView(scanningBanner)
        }

        streamSources.forEachIndexed { index, src ->
            val isSelected = index == activeSourceIndex
            val iptvFlag = isIptvSource(src)

            val card = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                isFocusable = true
                isFocusableInTouchMode = false
                isClickable = true
                setPadding(dp(14), dp(12), dp(14), dp(12))
                background = createSourceCardBackground(isSelected, src.isHindi || iptvFlag)
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    bottomMargin = dp(10)
                }
                setOnClickListener {
                    retriedCurrentSourceCount = 0
                    pendingResumePositionMs = 0L
                    userManuallyPickedSource = true
                    switchToStreamSource(index)
                }
                setOnKeyListener { _, keyCode, event ->
                    if (event.action == KeyEvent.ACTION_DOWN &&
                        (keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER)
                    ) {
                        retriedCurrentSourceCount = 0
                        pendingResumePositionMs = 0L
                        userManuallyPickedSource = true
                        switchToStreamSource(index)
                        true
                    } else {
                        false
                    }
                }
            }

            val leftCol = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            }

            val badgesRow = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }

            val serverBadge = makeTagBadge(
                text = src.server,
                bgHex = if (iptvFlag) "#0284C7" else primeBlueHex,
                fgHex = "#FFFFFF"
            )
            badgesRow.addView(serverBadge)

            if (src.isHindi) {
                badgesRow.addView(spacer(dp(6)))
                badgesRow.addView(
                    makeTagBadge(
                        text = if (src.isMultiAudio) "★ HINDI / MULTI" else "★ HINDI",
                        bgHex = primeBlueLightHex,
                        fgHex = "#06101C"
                    )
                )
            }

            val qTag = extractQualityTag(src.title)
            if (qTag.isNotEmpty()) {
                badgesRow.addView(spacer(dp(6)))
                badgesRow.addView(makeTagBadge(qTag, "#0C4A6E", "#BAE6FD"))
            }

            val titleTxt = TextView(this).apply {
                text = if (src.isHindi && !src.title.contains("hindi", true)) {
                    "${src.title} • Hindi"
                } else {
                    src.title
                }
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f)
                typeface = Typeface.DEFAULT_BOLD
                maxLines = 2
                ellipsize = TextUtils.TruncateAt.END
                setPadding(0, dp(7), dp(8), dp(3))
            }

            val subTxt = TextView(this).apply {
                text = "${src.server} • ${
                    when {
                        iptvFlag -> "IPTV DIRECT VOD"
                        src.isMultiAudio -> "MULTI-AUDIO (HINDI + ENG)"
                        src.isHindi -> "HINDI DUBBED / AUDIO"
                        else -> "ORIGINAL HD"
                    }
                }"
                setTextColor(if (src.isHindi || iptvFlag) Color.parseColor(primeBlueLightHex) else Color.parseColor("#8E96A4"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            }

            leftCol.addView(badgesRow)
            leftCol.addView(titleTxt)
            leftCol.addView(subTxt)

            val rightIcon = TextView(this).apply {
                text = if (isSelected) "✓" else "▶"
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                typeface = Typeface.DEFAULT_BOLD
                layoutParams = LinearLayout.LayoutParams(dp(26), dp(26))
                if (isSelected) {
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.OVAL
                        setColor(Color.parseColor(primeBlueHex))
                    }
                }
            }

            card.addView(leftCol)
            card.addView(rightIcon)
            sourcesListContainer.addView(card)
        }
    }

    private fun makeTagBadge(text: String, bgHex: String, fgHex: String): TextView {
        return TextView(this).apply {
            this.text = text
            setTextColor(Color.parseColor(fgHex))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dp(7), dp(2), dp(7), dp(2))
            background = GradientDrawable().apply {
                setColor(Color.parseColor(bgHex))
                cornerRadius = dp(4).toFloat()
            }
        }
    }

    private fun extractQualityTag(title: String): String {
        val low = title.lowercase(Locale.ROOT)
        return when {
            low.contains("1080") -> "1080p FHD"
            low.contains("720") -> "720p HD"
            low.contains("2160") || low.contains("4k") -> "4K UHD"
            low.contains("480") -> "480p"
            else -> "HD"
        }
    }

    private fun switchToStreamSource(index: Int, resumePosMs: Long = 0L) {
        if (!isSafeUi() || index !in streamSources.indices) return
        activeSourceIndex = index
        val selected = streamSources[index]
        currentActiveUrl = selected.url

        closeSourcesPanel()
        loadingSpinner.visibility = View.VISIBLE
        errorOverlay.visibility = View.GONE

        resolveAndStartSource(selected, isInitial = false, resumePosMs = resumePosMs)
    }

    private fun createSourcesPill(): StateListDrawable {
        val focused = GradientDrawable().apply {
            setColor(Color.parseColor("#0C4A6E"))
            cornerRadius = dp(18).toFloat()
            setStroke(dp(3), Color.WHITE)
        }
        val normal = GradientDrawable().apply {
            setColor(Color.parseColor(primeBlueHex))
            cornerRadius = dp(18).toFloat()
            setStroke(dp(1), Color.parseColor("#88FFFFFF"))
        }
        return StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_focused), focused)
            addState(intArrayOf(android.R.attr.state_pressed), focused)
            addState(intArrayOf(), normal)
        }
    }

    private fun lockScreen() {
        if (isTvDevice) return
        isScreenLocked = true
        setHudVisible(false)
        showUnlockPillTemporarily()
        showFeedback("Screen Locked")
    }

    private fun unlockScreen() {
        isScreenLocked = false
        handler.removeCallbacks(hideUnlockRunnable)
        unlockBtn.visibility = View.GONE
        setHudVisible(true)
        showFeedback("Screen Unlocked")
    }

    private fun showUnlockPillTemporarily() {
        unlockBtn.visibility = View.VISIBLE
        unlockBtn.requestFocus()
        handler.removeCallbacks(hideUnlockRunnable)
        handler.postDelayed(hideUnlockRunnable, 2800)
    }

    private fun initExoPlayer(
        url: String,
        title: String,
        userAgent: String,
        preset: PicturePreset,
        headers: Map<String, String> = emptyMap(),
        resumePosMs: Long = 0L
    ) {
        if (!isSafeUi()) return
        trackSelector = DefaultTrackSelector(this).apply {
            setParameters(
                buildUponParameters()
                    .setMaxVideoSize(1920, 1080)
                    .setForceHighestSupportedBitrate(true)
                    .setPreferredAudioLanguages("hi", "hin", "en")
                    .setMaxAudioChannelCount(2)
                    .setAllowVideoMixedMimeTypeAdaptiveness(true)
                    .setAllowAudioMixedMimeTypeAdaptiveness(true)
                    .setTunnelingEnabled(false)
            )
        }

        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(20_000)
            .setUserAgent(userAgent)
        httpDataSourceFactory = httpFactory
        applyHeadersToHttpFactory(headers)

        // Har seek (Range request) par Stalker ka naya single-use play_token auto-resolve hoga
        val resolvingFactory = ResolvingDataSource.Factory(httpFactory) { dataSpec ->
            val stSrc = activeStalkerSource
            if (stSrc != null && (stSrc.stalkerCmd.isNotEmpty() || stSrc.stalkerItemId.isNotEmpty())) {
                val now = System.currentTimeMillis()
                val isSeekRange = dataSpec.position > 0L
                val isFreshCache = cachedStalkerPlayUrl.isNotEmpty() && (now - cachedStalkerUrlTimeMs) < 1800L
                val resolved = if (!isSeekRange && isFreshCache) {
                    cachedStalkerPlayUrl
                } else {
                    val (freshUrl, freshHdrs) = resolveFreshStalkerUrl(stSrc)
                    if (freshUrl.isEmpty()) {
                        throw IOException("Stalker play_token renewal failed")
                    }
                    cachedStalkerPlayUrl = freshUrl
                    cachedStalkerUrlTimeMs = System.currentTimeMillis()
                    applyHeadersToHttpFactory(freshHdrs)
                    freshUrl
                }
                dataSpec.withUri(Uri.parse(resolved))
            } else {
                dataSpec
            }
        }

        val dataSourceFactory = DefaultDataSource.Factory(this, resolvingFactory)

        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(15_000, 50_000, 1_500, 3_000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        val renderersFactory = DefaultRenderersFactory(this)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
            .setEnableDecoderFallback(true)

        val exo = ExoPlayer.Builder(this, renderersFactory)
            .setTrackSelector(trackSelector)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory))
            .setLoadControl(loadControl)
            .build()

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
            .build()
        exo.setAudioAttributes(audioAttributes, true)

        if (!isTvDevice && preset.useShader) {
            exo.setVideoEffects(listOf(CinemaPictureEffect()))
            isShaderAttached = true
        } else {
            isShaderAttached = false
        }

        val lower = url.lowercase(Locale.ROOT)
        val itemBuilder = MediaItem.Builder()
            .setUri(Uri.parse(url))
            .setMediaMetadata(MediaMetadata.Builder().setTitle(title).build())
        when {
            lower.contains(".m3u8") -> itemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
            lower.contains(".mpd") -> itemBuilder.setMimeType(MimeTypes.APPLICATION_MPD)
        }
        currentMediaItem = itemBuilder.build()

        exo.addListener(object : Player.Listener {
            override fun onAudioSessionIdChanged(audioSessionId: Int) {
                if (!isSafeUi()) return
                attachLoudnessEnhancer(audioSessionId)
            }

            override fun onPlaybackStateChanged(state: Int) {
                if (!isSafeUi()) return
                loadingSpinner.visibility = if (state == Player.STATE_BUFFERING) View.VISIBLE else View.GONE
                if (state == Player.STATE_READY) {
                    retriedCurrentSourceCount = 0
                    pendingResumePositionMs = 0L
                    applyResizeModeToPlayer(resizeModes[resizeIndex])
                    if (loudnessEnhancer == null) {
                        attachLoudnessEnhancer(exo.audioSessionId)
                    }
                } else if (state == Player.STATE_ENDED && exo.duration <= 0L) {
                    if (!userManuallyPickedSource && activeSourceIndex + 1 < streamSources.size) {
                        retriedCurrentSourceCount = 0
                        switchToStreamSource(activeSourceIndex + 1)
                    } else {
                        showError("Stream empty or expired. Try Retry or Switch Source.")
                    }
                }
                updatePlayPauseLabel()
                updateProgressUi()
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (!isSafeUi()) return
                updatePlayPauseLabel()
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (!isSafeUi()) return
                applyResizeModeToPlayer(resizeModes[resizeIndex])
                updateInfoBadge()
            }

            override fun onTracksChanged(tracks: Tracks) {
                if (!isSafeUi()) return
                updateInfoBadge()
            }

            override fun onPlayerError(error: PlaybackException) {
                if (!isSafeUi()) return
                loadingSpinner.visibility = View.GONE
                val currentSrc = streamSources.getOrNull(activeSourceIndex)
                val resumePos = pendingResumePositionMs.takeIf { it > 0L }
                    ?: exo.currentPosition.coerceAtLeast(0L)

                if (currentSrc != null && currentSrc.stalkerEndpoint.isNotEmpty() && retriedCurrentSourceCount < 2) {
                    retriedCurrentSourceCount++
                    pendingResumePositionMs = resumePos
                    loadingSpinner.visibility = View.VISIBLE
                    resolveAndStartSource(currentSrc, isInitial = false, resumePosMs = resumePos)
                    return
                }

                retriedCurrentSourceCount = 0
                pendingResumePositionMs = 0L
                if (!userManuallyPickedSource && activeSourceIndex + 1 < streamSources.size) {
                    switchToStreamSource(activeSourceIndex + 1)
                } else {
                    showError("Playback Error: ${error.localizedMessage ?: error.errorCodeName}")
                }
            }
        })

        playerView.player = exo
        applyResizeModeToPlayer(resizeModes[resizeIndex])
        if (resumePosMs > 0L) {
            exo.setMediaItem(currentMediaItem, resumePosMs)
        } else {
            exo.setMediaItem(currentMediaItem)
        }
        exo.prepare()
        exo.playWhenReady = true
        player = exo
        attachLoudnessEnhancer(exo.audioSessionId)
        handler.post(progressRunnable)
    }

    private fun applyPicturePreset(preset: PicturePreset) {
        if (!isSafeUi()) return
        val effectivePreset = if (isTvDevice) PicturePreset.JUST_PLAYER else preset
        CinemaPictureEngineState.currentPreset = effectivePreset
        if (!isTvDevice) {
            prefs.edit().putString("picture_preset_pure_hw", effectivePreset.name).apply()
        }
        pictureBtn.text = if (effectivePreset == PicturePreset.JUST_PLAYER) "HW Original" else effectivePreset.displayName

        val exo = player ?: return
        val needsShader = !isTvDevice && effectivePreset.useShader
        if (needsShader != isShaderAttached) {
            val pos = exo.currentPosition.coerceAtLeast(0L)
            val wasPlaying = exo.playWhenReady
            exo.stop()
            exo.setVideoEffects(if (needsShader) listOf(CinemaPictureEffect()) else emptyList())
            isShaderAttached = needsShader
            exo.setMediaItem(currentMediaItem, pos)
            exo.prepare()
            exo.playWhenReady = wasPlaying
        }
        showFeedback(effectivePreset.displayName)
    }

    private fun showPicturePresetDialog() {
        if (!isSafeUi() || isTvDevice) return
        handler.removeCallbacks(hideHudRunnable)
        val presets = PicturePreset.values()
        val labels = presets.map { "${it.displayName}\n${it.tagline}" }.toTypedArray()
        val checked = presets.indexOf(CinemaPictureEngineState.currentPreset).coerceAtLeast(0)

        try {
            AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle("Picture Mode")
                .setSingleChoiceItems(labels, checked) { dialog, which ->
                    applyPicturePreset(presets[which])
                    dialog.dismiss()
                    scheduleHideHud()
                }
                .setOnCancelListener { scheduleHideHud() }
                .show()
        } catch (_: Throwable) {}
    }

    private fun showAudioDialog() {
        if (!isSafeUi()) return
        val exo = player ?: return
        handler.removeCallbacks(hideHudRunnable)
        val tracks = exo.currentTracks

        val labels = mutableListOf<String>()
        val actions = mutableListOf<() -> Unit>()
        var checkedIndex = 0

        labels.add("Auto (Hindi Priority)")
        actions.add {
            exo.trackSelectionParameters = exo.trackSelectionParameters.buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
                .setPreferredAudioLanguages("hi", "hin", "en")
                .build()
            showFeedback("Audio: Auto (Hindi Priority)")
        }

        tracks.groups.forEach { group ->
            if (group.type == C.TRACK_TYPE_AUDIO) {
                for (i in 0 until group.length) {
                    val fmt = group.getTrackFormat(i)
                    val supported = group.isTrackSupported(i)
                    val selected = group.isTrackSelected(i)
                    val ch = when (fmt.channelCount) {
                        1 -> "Mono"
                        2 -> "Stereo"
                        6 -> "5.1"
                        8 -> "7.1"
                        else -> if (fmt.channelCount > 0) "${fmt.channelCount}ch" else ""
                    }
                    val codec = fmt.sampleMimeType?.substringAfter("/")?.uppercase(Locale.ROOT) ?: ""
                    val titlePart = formatTrackName(fmt, "Audio Track ${labels.size}")
                    val meta = listOf(ch, codec).filter { it.isNotBlank() }.joinToString(" ")
                    val suffix = if (!supported) " [Device Unsupported]" else ""
                    val fullLabel = if (meta.isNotBlank()) "$titlePart ($meta)$suffix" else "$titlePart$suffix"

                    if (selected) checkedIndex = labels.size
                    labels.add(fullLabel)
                    actions.add {
                        if (!supported) {
                            showFeedback("Audio format unsupported by device")
                        } else {
                            val builder = exo.trackSelectionParameters.buildUpon()
                                .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                                .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i))
                            if (!fmt.language.isNullOrBlank()) {
                                builder.setPreferredAudioLanguage(fmt.language)
                            }
                            exo.trackSelectionParameters = builder.build()
                            showFeedback("Audio: $titlePart")
                        }
                    }
                }
            }
        }

        if (labels.size == 1) {
            labels.add("Single audio stream only")
            actions.add { }
        }

        try {
            AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle("Audio Track")
                .setSingleChoiceItems(labels.toTypedArray(), checkedIndex) { dialog, which ->
                    actions[which].invoke()
                    dialog.dismiss()
                    scheduleHideHud()
                }
                .setNegativeButton("Close") { dialog, _ ->
                    dialog.dismiss()
                    scheduleHideHud()
                }
                .setOnCancelListener { scheduleHideHud() }
                .show()
        } catch (_: Throwable) {}
    }

    private fun showSubAndQualityDialog() {
        if (!isSafeUi()) return
        val exo = player ?: return
        handler.removeCallbacks(hideHudRunnable)
        val tracks = exo.currentTracks

        val items = mutableListOf<String>()
        val actions = mutableListOf<() -> Unit>()

        items.add("Subtitles: Off")
        actions.add {
            exo.trackSelectionParameters = exo.trackSelectionParameters.buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                .build()
            showFeedback("Subtitles Off")
        }
        tracks.groups.forEach { group ->
            if (group.type == C.TRACK_TYPE_TEXT) {
                for (i in 0 until group.length) {
                    if (group.isTrackSupported(i)) {
                        val fmt = group.getTrackFormat(i)
                        val selected = if (group.isTrackSelected(i)) "✓ " else ""
                        val name = formatTrackName(fmt, "Subtitle ${i + 1}")
                        items.add("${selected}Subtitle: $name")
                        actions.add {
                            exo.trackSelectionParameters = exo.trackSelectionParameters.buildUpon()
                                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                                .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i))
                                .build()
                            showFeedback("Subtitle: $name")
                        }
                    }
                }
            }
        }

        items.add("Video Quality: Auto (1080p Max)")
        actions.add {
            exo.trackSelectionParameters = exo.trackSelectionParameters.buildUpon()
                .clearOverridesOfType(C.TRACK_TYPE_VIDEO)
                .setMaxVideoSize(1920, 1080)
                .build()
            showFeedback("Quality: Auto (1080p Max)")
        }
        tracks.groups.forEach { group ->
            if (group.type == C.TRACK_TYPE_VIDEO) {
                for (i in 0 until group.length) {
                    if (group.isTrackSupported(i)) {
                        val fmt = group.getTrackFormat(i)
                        val selected = if (group.isTrackSelected(i)) "✓ " else ""
                        val res = if (fmt.height > 0) "${fmt.width}x${fmt.height}" else "Video ${i + 1}"
                        items.add("${selected}Quality: $res")
                        actions.add {
                            exo.trackSelectionParameters = exo.trackSelectionParameters.buildUpon()
                                .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i))
                                .build()
                            showFeedback("Quality: $res")
                        }
                    }
                }
            }
        }

        try {
            AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle("Subtitles & Video Quality")
                .setItems(items.toTypedArray()) { _, which ->
                    actions[which].invoke()
                    scheduleHideHud()
                }
                .setOnCancelListener { scheduleHideHud() }
                .show()
        } catch (_: Throwable) {}
    }

    private fun formatTrackName(fmt: Format, fallback: String): String {
        val lang = fmt.language
            ?.takeIf { it.isNotBlank() && it != "und" }
            ?.let { Locale(it).displayLanguage }
            ?.takeIf { it.isNotBlank() }
        return listOfNotNull(fmt.label, lang).distinct().joinToString(" • ").ifBlank { fallback }
    }

    private fun setupTouchGestures(view: View) {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)

        var startX = 0f
        var startY = 0f
        var draggingVertical = false
        var startEffectiveVol = 100
        var startBrightness = 0.5f

        val detector = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                if (isScreenLocked) {
                    showUnlockPillTemporarily()
                } else {
                    setHudVisible(!hudVisible)
                }
                return true
            }

            override fun onDoubleTap(e: MotionEvent): Boolean {
                if (isScreenLocked) {
                    showUnlockPillTemporarily()
                    return true
                }
                if (e.x < view.width / 2f) {
                    seekBy(-seekStepMs)
                } else {
                    seekBy(seekStepMs)
                }
                return true
            }
        })

        view.setOnTouchListener { v, event ->
            detector.onTouchEvent(event)
            if (isScreenLocked) return@setOnTouchListener true

            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.x
                    startY = event.y
                    draggingVertical = false
                    val sysPercent = (audioManager.getStreamVolume(AudioManager.STREAM_MUSIC) * 100) / maxVol
                    startEffectiveVol = if (sysPercent >= 100) currentBoostPercent else sysPercent
                    val curB = window.attributes.screenBrightness
                    startBrightness = if (curB < 0f) 0.5f else curB
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.x - startX
                    val dy = startY - event.y
                    if (!draggingVertical && abs(dy) > dp(18) && abs(dy) > abs(dx)) {
                        draggingVertical = true
                    }
                    if (draggingVertical && v.height > 0) {
                        val deltaRatio = dy / (v.height * 0.65f)
                        if (startX < v.width / 2f) {
                            val newB = (startBrightness + deltaRatio).coerceIn(0.05f, 1.0f)
                            val lp = window.attributes
                            lp.screenBrightness = newB
                            window.attributes = lp
                            showFeedback("Brightness ${(newB * 100).toInt()}%")
                        } else {
                            val targetPercent = (startEffectiveVol + (deltaRatio * 200f).toInt()).coerceIn(0, 200)
                            if (targetPercent <= 100) {
                                val sysStep = ((targetPercent * maxVol) / 100).coerceIn(0, maxVol)
                                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, sysStep, 0)
                                applyAudioBoostPercent(100, showToast = false)
                                showFeedback("Volume $targetPercent%")
                            } else {
                                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxVol, 0)
                                applyAudioBoostPercent(targetPercent, showToast = false)
                                showFeedback("🔊 Volume Boost $targetPercent%")
                            }
                        }
                    }
                }
            }
            true
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (sourcesOverlay.visibility == View.VISIBLE) {
            if (keyCode == KeyEvent.KEYCODE_BACK) {
                closeSourcesPanel()
                return true
            }
            return super.onKeyDown(keyCode, event)
        }

        if (isTvDevice) {
            return when (keyCode) {
                KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                    togglePlayPause()
                    setHudVisible(true)
                    true
                }
                KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> {
                    setHudVisible(true)
                    seekBy(seekStepMs)
                    true
                }
                KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_MEDIA_REWIND -> {
                    setHudVisible(true)
                    seekBy(-seekStepMs)
                    true
                }
                KeyEvent.KEYCODE_DPAD_DOWN -> {
                    openSourcesPanel()
                    true
                }
                KeyEvent.KEYCODE_DPAD_UP -> {
                    cycleAspectRatio()
                    true
                }
                KeyEvent.KEYCODE_BACK -> {
                    if (hudVisible) {
                        setHudVisible(false)
                        true
                    } else {
                        finishPlayerCleanly()
                        true
                    }
                }
                else -> super.onKeyDown(keyCode, event)
            }
        }

        if (isScreenLocked) {
            if (keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER) {
                if (unlockBtn.visibility == View.VISIBLE) {
                    unlockScreen()
                    return true
                }
            }
            showUnlockPillTemporarily()
            return true
        }

        return when (keyCode) {
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                if (!hudVisible) {
                    togglePlayPause()
                    setHudVisible(true)
                    true
                } else {
                    scheduleHideHud()
                    super.onKeyDown(keyCode, event)
                }
            }
            KeyEvent.KEYCODE_DPAD_LEFT -> {
                if (!hudVisible || currentFocus == seekBar) {
                    seekBy(-seekStepMs)
                    true
                } else {
                    scheduleHideHud()
                    super.onKeyDown(keyCode, event)
                }
            }
            KeyEvent.KEYCODE_DPAD_RIGHT -> {
                if (!hudVisible || currentFocus == seekBar) {
                    seekBy(seekStepMs)
                    true
                } else {
                    scheduleHideHud()
                    super.onKeyDown(keyCode, event)
                }
            }
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN -> {
                if (!hudVisible) {
                    setHudVisible(true)
                    seekBar.requestFocus()
                    true
                } else {
                    scheduleHideHud()
                    super.onKeyDown(keyCode, event)
                }
            }
            KeyEvent.KEYCODE_BACK -> {
                if (hudVisible) {
                    setHudVisible(false)
                    true
                } else {
                    finishPlayerCleanly()
                    true
                }
            }
            else -> super.onKeyDown(keyCode, event)
        }
    }

    private fun togglePlayPause() {
        val exo = player ?: return
        if (exo.isPlaying) {
            exo.pause()
            showFeedback("❚❚ Paused")
        } else {
            exo.play()
            showFeedback("▶ Playing")
        }
        updatePlayPauseLabel()
        scheduleHideHud()
    }

    private fun seekBy(deltaMs: Long) {
        val exo = player ?: return
        val dur = exo.duration.takeIf { it > 0 } ?: Long.MAX_VALUE
        val target = (exo.currentPosition + deltaMs).coerceIn(0L, dur)
        pendingResumePositionMs = target
        exo.seekTo(target)
        val timeLabel = formatTime(target)
        showFeedback(if (deltaMs < 0) "↺ -${seekStepSec}s  ($timeLabel)" else "+${seekStepSec}s ↻  ($timeLabel)")
        updateProgressUi()
        if (hudVisible) scheduleHideHud()
    }

    private fun cycleAspectRatio() {
        resizeIndex = (resizeIndex + 1) % resizeModes.size
        val mode = resizeModes[resizeIndex]
        applyResizeModeToPlayer(mode)
        aspectBtn.text = resizeLabels[resizeIndex]
        showFeedback("Screen Size: ${resizeLabels[resizeIndex]}")
        scheduleHideHud()
    }

    private fun cyclePlaybackSpeed() {
        speedIndex = (speedIndex + 1) % speeds.size
        val speed = speeds[speedIndex]
        player?.setPlaybackSpeed(speed)
        speedBtn.text = "${speed}x"
        showFeedback("Speed ${speed}x")
        scheduleHideHud()
    }

    private fun updateInfoBadge() {
        val vf = player?.videoFormat ?: return
        val resTag = when {
            vf.height >= 2160 -> "4K"
            vf.height >= 1440 -> "2K"
            vf.height >= 1080 -> "1080p"
            vf.height >= 720 -> "720p"
            vf.height > 0 -> "${vf.height}p"
            else -> ""
        }
        val hdrTag = when (vf.colorInfo?.colorTransfer) {
            C.COLOR_TRANSFER_ST2084 -> " • HDR10"
            C.COLOR_TRANSFER_HLG -> " • HLG"
            else -> ""
        }
        val badge = "$resTag$hdrTag".trim()
        if (badge.isNotEmpty()) {
            infoBadgeView.text = badge
            infoBadgeView.visibility = View.VISIBLE
        }
    }

    private fun updatePlayPauseLabel() {
        playPauseBtn.text = if (player?.isPlaying == true) "❚❚" else "▶"
    }

    private fun updateProgressUi() {
        val exo = player ?: return
        val dur = exo.duration
        val pos = exo.currentPosition.coerceAtLeast(0L)
        if (!isSeekingFromUser && dur > 0) {
            timeCurrentView.text = formatTime(pos)
            timeTotalView.text = formatTime(dur)
            seekBar.progress = ((pos * 1000L) / dur).toInt().coerceIn(0, 1000)
        }
    }

    private fun setHudVisible(visible: Boolean) {
        if (!isSafeUi()) return
        hudVisible = visible
        hudContainer.visibility = if (visible) View.VISIBLE else View.GONE
        handler.removeCallbacks(hideHudRunnable)
        if (visible && !isScreenLocked) scheduleHideHud()
    }

    private fun scheduleHideHud() {
        handler.removeCallbacks(hideHudRunnable)
        if (!isScreenLocked && isSafeUi()) {
            handler.postDelayed(hideHudRunnable, if (isTvDevice) 3500 else 4500)
        }
    }

    private fun showFeedback(msg: String) {
        if (!isSafeUi()) return
        feedbackBadge.text = msg
        feedbackBadge.visibility = View.VISIBLE
        handler.removeCallbacks(hideFeedbackRunnable)
        handler.postDelayed(hideFeedbackRunnable, 1200)
    }

    private fun showError(msg: String) {
        if (!isSafeUi()) return
        errorMessageView.text = msg
        errorOverlay.visibility = View.VISIBLE
    }

    private fun createHudButton(label: String, big: Boolean = false, onClick: () -> Unit): Button {
        return Button(this).apply {
            text = label
            isAllCaps = false
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, if (big) 15f else 12f)
            typeface = Typeface.DEFAULT_BOLD
            isFocusable = true
            isFocusableInTouchMode = false
            minWidth = 0
            minHeight = 0
            setPadding(dp(if (big) 18 else 12), dp(if (big) 11 else 7), dp(if (big) 18 else 12), dp(if (big) 11 else 7))
            background = createFocusablePill()
            setOnClickListener { onClick() }
        }
    }

    private fun createFocusablePill(): StateListDrawable {
        val focused = GradientDrawable().apply {
            setColor(Color.parseColor(primeBlueHex))
            cornerRadius = dp(18).toFloat()
            setStroke(dp(2), Color.WHITE)
        }
        val normal = GradientDrawable().apply {
            setColor(Color.parseColor("#880C111B"))
            cornerRadius = dp(18).toFloat()
            setStroke(dp(1), Color.parseColor("#4400A8E1"))
        }
        return StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_focused), focused)
            addState(intArrayOf(android.R.attr.state_pressed), focused)
            addState(intArrayOf(), normal)
        }
    }

    private fun spacer(widthPx: Int): View = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(widthPx, 1)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun formatTime(ms: Long): String {
        val totalSec = (ms / 1000L).coerceAtLeast(0L)
        val h = totalSec / 3600
        val m = (totalSec % 3600) / 60
        val s = totalSec % 60
        return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s)
        else String.format(Locale.US, "%02d:%02d", m, s)
    }

    private fun enableImmersiveFullscreen() {
        applyCameraCutoutFullScreen()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                )
        }
    }

    override fun onPause() {
        super.onPause()
        try { player?.pause() } catch (_: Throwable) {}
    }

    override fun onDestroy() {
        isActivityDestroyed = true
        handler.removeCallbacksAndMessages(null)
        releaseLoudnessEnhancer()
        try {
            playerView.player = null
            player?.stop()
            player?.release()
            player = null
        } catch (_: Throwable) {}
        super.onDestroy()
    }
}