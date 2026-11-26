package com.primeflix.app.media3

import android.app.AlertDialog
import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.AudioManager
import android.media.audiofx.LoudnessEnhancer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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
import android.widget.TextView
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.abs

data class NativeServerItem(
    val url: String,
    val title: String,
    val providerName: String,
    val quality: String,
    val headers: Map<String, String>
)

private data class TrackChoice(
    val label: String,
    val onSelect: () -> Unit
)

@OptIn(UnstableApi::class)
class Media3PlayerActivity : AppCompatActivity() {

    private val primeBlue = Color.parseColor("#00A8E1")
    private val activeRed = Color.parseColor("#E50914")
    private val darkCard = Color.parseColor("#1A242F")
    private val panelBg = Color.parseColor("#F00B1622")

    private lateinit var rootLayout: FrameLayout
    private lateinit var playerView: PlayerView
    private lateinit var mobileTopBar: LinearLayout
    private lateinit var serversBtn: Button
    private lateinit var mobileAudioBtn: Button
    private lateinit var spinner: ProgressBar

    private lateinit var tvHintBar: LinearLayout
    private lateinit var tvStatusBanner: TextView
    private lateinit var tvMenuPanel: LinearLayout
    private lateinit var tvTabsRow: LinearLayout
    private lateinit var tvListContainer: LinearLayout
    private lateinit var tvCloseBtn: Button

    private lateinit var swipeHud: LinearLayout
    private lateinit var swipeHudLabel: TextView
    private lateinit var swipeHudBar: ProgressBar
    private lateinit var swipeHudPct: TextView

    private var exoPlayer: ExoPlayer? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var audioManager: AudioManager? = null

    private var isTvDevice = false
    private var tvMenuOpen = false
    private var tvSelectedTab = 0 // 0: Sources, 1: Picture & Size, 2: Audio, 3: Subtitles
    private var tvSizeMode = 0 // 0: Fit, 1: Fill / Stretch, 2: Zoom

    private val servers = mutableListOf<NativeServerItem>()
    private var activeIndex = -1

    private var currentBrightness = 0.6f
    private var currentVolumePct = 100f
    private var dragLeft = false
    private var dragRight = false
    private var dragStartY = 0f
    private var dragStartVal = 0f

    private val handler = Handler(Looper.getMainLooper())
    private val hideHudTask = Runnable { swipeHud.visibility = View.GONE }
    private val hideTvStatusTask = Runnable { tvStatusBanner.visibility = View.GONE }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Media3Bridge.activePlayer = this
        isTvDevice = detectTvDevice()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        val maxVol = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC)?.coerceAtLeast(1) ?: 15
        val curVol = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: maxVol
        currentVolumePct = ((curVol.toFloat() / maxVol.toFloat()) * 100f).coerceIn(0f, 200f)

        hideSystemUi()
        buildUi(intent.getStringExtra("title") ?: "PrimeFlix")
        initExoPlayer()

        val serversJson = intent.getStringExtra("servers_json") ?: "[]"
        val startIdx = intent.getIntExtra("start_index", 0)
        loadServersJson(serversJson, startIdx)
    }

    private fun detectTvDevice(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        if (uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) {
            return true
        }
        if (packageManager.hasSystemFeature("android.software.leanback")) {
            return true
        }
        val smallestWidthDp = resources.configuration.smallestScreenWidthDp
        return smallestWidthDp >= 600
    }

    private fun hideSystemUi() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let { ctrl ->
                ctrl.hide(WindowInsets.Type.systemBars())
                ctrl.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                    View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        }
    }

    private fun buildUi(title: String) {
        rootLayout = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        playerView = PlayerView(this).apply {
            useController = !isTvDevice
            controllerShowTimeoutMs = 4500
            setShutterBackgroundColor(Color.BLACK)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        rootLayout.addView(playerView)

        if (!isTvDevice) {
            val swipeView = View(this).apply {
                layoutParams = FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
                setOnTouchListener { v, event -> onSwipeTouch(v, event) }
            }
            rootLayout.addView(swipeView)
        }

        // Mobile Top Bar (Servers + Audio Track button)
        mobileTopBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            visibility = if (isTvDevice) View.GONE else View.VISIBLE
            setBackgroundColor(Color.parseColor("#99000000"))
            setPadding(dp(14), dp(8), dp(14), dp(8))
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        }

        val backBtn = Button(this).apply {
            text = "< Back"
            setTextColor(Color.WHITE)
            textSize = 12f
            isAllCaps = false
            background = makePill(darkCard, Color.WHITE)
            setPadding(dp(12), dp(6), dp(12), dp(6))
            setOnClickListener { finish() }
        }

        val titleTv = TextView(this).apply {
            text = title
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
            setPadding(dp(12), 0, dp(12), 0)
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }

        serversBtn = Button(this).apply {
            text = "Servers (0)"
            setTextColor(Color.WHITE)
            textSize = 12f
            isAllCaps = false
            background = makePill(darkCard, primeBlue)
            setPadding(dp(12), dp(6), dp(12), dp(6))
            setOnClickListener { showMobileServersDialog() }
        }

        mobileAudioBtn = Button(this).apply {
            text = "Audio"
            setTextColor(Color.WHITE)
            textSize = 12f
            isAllCaps = false
            background = makePill(darkCard, primeBlue)
            setPadding(dp(12), dp(6), dp(12), dp(6))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { leftMargin = dp(8) }
            setOnClickListener { showMobileAudioDialog() }
        }

        mobileTopBar.addView(backBtn)
        mobileTopBar.addView(titleTv)
        mobileTopBar.addView(serversBtn)
        mobileTopBar.addView(mobileAudioBtn)
        rootLayout.addView(mobileTopBar)

        // TV Status Toast Banner (Top-Left)
        tvStatusBanner = TextView(this).apply {
            visibility = View.GONE
            setTextColor(Color.WHITE)
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            background = makePill(Color.parseColor("#E0101A24"), primeBlue)
            setPadding(dp(16), dp(8), dp(16), dp(8))
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.START
            ).apply {
                topMargin = dp(18)
                leftMargin = dp(20)
            }
        }
        rootLayout.addView(tvStatusBanner)

        // TV Bottom Remote Shortcut Strip
        tvHintBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            visibility = if (isTvDevice) View.VISIBLE else View.GONE
            setBackgroundColor(Color.parseColor("#B3000000"))
            setPadding(dp(20), dp(8), dp(20), dp(8))
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
            )
        }
        val hintText = TextView(this).apply {
            text = "OK: Play/Pause   •   ◀ / ▶: ±10s   •   ▲ UP: Size / Stretch   •   ▼ DOWN: Sources / Audio / Subtitles"
            setTextColor(Color.WHITE)
            textSize = 12f
            maxLines = 1
        }
        tvHintBar.addView(hintText)
        rootLayout.addView(tvHintBar)

        // TV Bottom Menu Panel (Sources, Picture & Size, Audio, Subtitles)
        tvMenuPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            background = makePanelDrawable(panelBg, primeBlue)
            setPadding(dp(18), dp(14), dp(18), dp(14))
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(270),
                Gravity.BOTTOM
            ).apply {
                leftMargin = dp(18)
                rightMargin = dp(18)
                bottomMargin = dp(14)
            }
        }

        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        tvTabsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }

        tvCloseBtn = Button(this).apply {
            text = "✕ Close"
            setTextColor(Color.WHITE)
            textSize = 12f
            isAllCaps = false
            isFocusable = true
            isFocusableInTouchMode = true
            background = makePill(darkCard, Color.WHITE)
            setPadding(dp(14), dp(6), dp(14), dp(6))
            bindTvFocus(this, darkCard)
            setOnClickListener { setTvMenuOpen(false) }
        }

        headerRow.addView(tvTabsRow)
        headerRow.addView(tvCloseBtn)
        tvMenuPanel.addView(headerRow)

        val scrollView = ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f
            ).apply { topMargin = dp(10) }
        }
        tvListContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        scrollView.addView(tvListContainer)
        tvMenuPanel.addView(scrollView)
        rootLayout.addView(tvMenuPanel)

        spinner = ProgressBar(this).apply {
            indeterminateDrawable.setTint(primeBlue)
            layoutParams = FrameLayout.LayoutParams(dp(52), dp(52), Gravity.CENTER)
        }
        rootLayout.addView(spinner)

        // Mobile Swipe HUD
        swipeHud = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            visibility = View.GONE
            background = makePill(Color.parseColor("#E6060B10"), primeBlue)
            setPadding(dp(16), dp(10), dp(16), dp(10))
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        }
        swipeHudLabel = TextView(this).apply {
            setTextColor(primeBlue)
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
        }
        swipeHudBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            layoutParams = LinearLayout.LayoutParams(dp(110), dp(10)).apply {
                leftMargin = dp(10)
                rightMargin = dp(10)
            }
        }
        swipeHudPct = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
        }
        swipeHud.addView(swipeHudLabel)
        swipeHud.addView(swipeHudBar)
        swipeHud.addView(swipeHudPct)
        rootLayout.addView(swipeHud)

        setContentView(rootLayout)
    }

    private fun initExoPlayer() {
        val exo = ExoPlayer.Builder(this).build()
        exoPlayer = exo
        playerView.player = exo

        try {
            val sid = exo.audioSessionId
            if (sid != C.AUDIO_SESSION_ID_UNSET) {
                loudnessEnhancer = LoudnessEnhancer(sid).apply { enabled = false }
            }
        } catch (_: Throwable) {
        }

        exo.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                spinner.visibility =
                    if (playbackState == Player.STATE_BUFFERING) View.VISIBLE else View.GONE
                if (playbackState == Player.STATE_READY) {
                    applyVolume(currentVolumePct, showHud = false)
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                spinner.visibility = View.GONE
                if (activeIndex + 1 < servers.size) {
                    playServerAt(activeIndex + 1)
                }
            }
        })
    }

    fun updateServersFromBridge(serversJson: String) {
        runOnUiThread {
            val hadNone = servers.isEmpty()
            appendJsonServers(serversJson)
            serversBtn.text = "Servers (${servers.size})"
            if (hadNone && servers.isNotEmpty()) {
                playServerAt(0)
            }
            if (tvMenuOpen && tvSelectedTab == 0) {
                renderTvMenuContent()
            }
        }
    }

    private fun loadServersJson(serversJson: String, startIndex: Int) {
        appendJsonServers(serversJson)
        serversBtn.text = "Servers (${servers.size})"
        if (servers.isNotEmpty()) {
            playServerAt(startIndex.coerceIn(0, servers.size - 1))
        } else {
            spinner.visibility = View.GONE
        }
    }

    private fun appendJsonServers(serversJson: String) {
        try {
            val arr = JSONArray(serversJson)
            val seen = servers.map { it.url }.toHashSet()
            for (i in 0 until arr.length()) {
                val obj: JSONObject = arr.optJSONObject(i) ?: continue
                val url = obj.optString("url", "").trim()
                if (url.isEmpty() || seen.contains(url)) continue

                val headersMap = mutableMapOf<String, String>()
                val hObj = obj.optJSONObject("headers")
                if (hObj != null) {
                    val keys = hObj.keys()
                    while (keys.hasNext()) {
                        val k = keys.next()
                        headersMap[k] = hObj.optString(k, "")
                    }
                }

                servers.add(
                    NativeServerItem(
                        url = url,
                        title = obj.optString("title", ""),
                        providerName = obj.optString("providerName", "Server"),
                        quality = obj.optString("quality", "HD"),
                        headers = headersMap
                    )
                )
                seen.add(url)
            }
        } catch (_: Throwable) {
        }
    }

    private fun playServerAt(index: Int) {
        if (index !in servers.indices) return
        activeIndex = index
        val item = servers[index]
        spinner.visibility = View.VISIBLE
        if (isTvDevice) {
            showTvStatus("Playing [${item.quality}] ${item.providerName}")
        }

        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
        if (item.headers.isNotEmpty()) {
            httpFactory.setDefaultRequestProperties(item.headers)
        }

        val mediaSourceFactory = DefaultMediaSourceFactory(this)
            .setDataSourceFactory(httpFactory)

        exoPlayer?.apply {
            setMediaSource(mediaSourceFactory.createMediaSource(MediaItem.fromUri(Uri.parse(item.url))))
            prepare()
            playWhenReady = true
        }
    }

    private fun cyclePictureSize(): String {
        tvSizeMode = (tvSizeMode + 1) % 3
        val label = when (tvSizeMode) {
            1 -> {
                playerView.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FILL
                "Picture Size: Stretch (Fill)"
            }
            2 -> {
                playerView.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                "Picture Size: Zoom"
            }
            else -> {
                playerView.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                "Picture Size: Fit"
            }
        }
        showTvStatus(label)
        return label
    }

    private fun showTvStatus(msg: String) {
        handler.removeCallbacks(hideTvStatusTask)
        tvStatusBanner.text = msg
        tvStatusBanner.visibility = View.VISIBLE
        handler.postDelayed(hideTvStatusTask, 2200)
    }

    private fun setTvMenuOpen(open: Boolean) {
        tvMenuOpen = open
        tvMenuPanel.visibility = if (open) View.VISIBLE else View.GONE
        tvHintBar.visibility = if (open || !isTvDevice) View.GONE else View.VISIBLE
        if (open) {
            renderTvMenuContent()
            tvTabsRow.getChildAt(tvSelectedTab)?.requestFocus()
        }
    }

    private fun renderTvMenuContent() {
        val exo = exoPlayer ?: return
        val tracks = exo.currentTracks
        val audioCount = countTracks(tracks, C.TRACK_TYPE_AUDIO)
        val subCount = countTracks(tracks, C.TRACK_TYPE_TEXT)

        val tabTitles = listOf(
            "Sources (${servers.size})",
            "Picture & Size",
            "Audio ($audioCount)",
            "Subtitles ($subCount)"
        )

        tvTabsRow.removeAllViews()
        tabTitles.forEachIndexed { idx, tabLabel ->
            val selected = idx == tvSelectedTab
            val tabBtn = Button(this).apply {
                text = tabLabel
                setTextColor(Color.WHITE)
                textSize = 12f
                isAllCaps = false
                isFocusable = true
                isFocusableInTouchMode = true
                background = makePill(if (selected) activeRed else darkCard, if (selected) Color.WHITE else primeBlue)
                setPadding(dp(14), dp(6), dp(14), dp(6))
                bindTvFocus(this, if (selected) activeRed else darkCard)
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { rightMargin = dp(8) }
                setOnClickListener {
                    tvSelectedTab = idx
                    renderTvMenuContent()
                }
            }
            tvTabsRow.addView(tabBtn)
        }

        tvListContainer.removeAllViews()
        when (tvSelectedTab) {
            0 -> renderSourcesTab()
            1 -> renderPictureSizeTab()
            2 -> renderAudioTab(exo, tracks)
            3 -> renderSubtitlesTab(exo, tracks)
        }
    }

    private fun renderSourcesTab() {
        if (servers.isEmpty()) {
            tvListContainer.addView(makeTvInfoText("No servers available yet."))
            return
        }
        servers.forEachIndexed { idx, s ->
            val active = idx == activeIndex
            val itemBtn = makeTvOptionRow(
                title = "[${s.quality}] ${s.providerName}",
                subtitle = if (s.title.isNotBlank()) s.title else s.url,
                isSelected = active
            ) {
                playServerAt(idx)
                setTvMenuOpen(false)
            }
            tvListContainer.addView(itemBtn)
        }
    }

    private fun renderPictureSizeTab() {
        val modes = listOf(
            0 to ("Fit (Original Aspect Ratio)" to "Black bars ke saath poora frame"),
            1 to ("Stretch / Fill Screen" to "Poori TV screen par stretch karke bharna"),
            2 to ("Zoom / Crop" to "Screen bharne ke hisaab se zoom karna")
        )
        for ((mode, pair) in modes) {
            val row = makeTvOptionRow(
                title = pair.first,
                subtitle = pair.second,
                isSelected = tvSizeMode == mode
            ) {
                tvSizeMode = mode
                playerView.resizeMode = when (mode) {
                    1 -> AspectRatioFrameLayout.RESIZE_MODE_FILL
                    2 -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                    else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
                }
                showTvStatus("Picture Size: ${pair.first}")
                setTvMenuOpen(false)
            }
            tvListContainer.addView(row)
        }
    }

    private fun renderAudioTab(exo: ExoPlayer, tracks: Tracks) {
        val choices = collectTrackChoices(exo, tracks, C.TRACK_TYPE_AUDIO, includeOff = false)
        if (choices.isEmpty()) {
            tvListContainer.addView(makeTvInfoText("Stream mein extra audio track nahi mila (Default audio chal raha hai)."))
            return
        }
        for (choice in choices) {
            val row = makeTvOptionRow(
                title = choice.label,
                subtitle = "Select audio language / track",
                isSelected = false
            ) {
                choice.onSelect()
                showTvStatus(choice.label)
                setTvMenuOpen(false)
            }
            tvListContainer.addView(row)
        }
    }

    private fun renderSubtitlesTab(exo: ExoPlayer, tracks: Tracks) {
        val choices = collectTrackChoices(exo, tracks, C.TRACK_TYPE_TEXT, includeOff = true)
        for (choice in choices) {
            val row = makeTvOptionRow(
                title = choice.label,
                subtitle = "Subtitle track option",
                isSelected = false
            ) {
                choice.onSelect()
                showTvStatus(choice.label)
                setTvMenuOpen(false)
            }
            tvListContainer.addView(row)
        }
    }

    private fun collectTrackChoices(
        exo: ExoPlayer,
        tracks: Tracks,
        trackType: Int,
        includeOff: Boolean
    ): List<TrackChoice> {
        val list = mutableListOf<TrackChoice>()
        var idx = 1
        for (group in tracks.groups) {
            if (group.type == trackType && group.mediaTrackGroup.length > 0) {
                val fmt = group.mediaTrackGroup.getFormat(0)
                val lang = fmt.language?.uppercase() ?: "TRACK $idx"
                val label = fmt.label ?: lang
                val prefix = if (trackType == C.TRACK_TYPE_AUDIO) "Audio" else "Subtitle"
                list.add(
                    TrackChoice("$prefix #$idx: $label ($lang)") {
                        exo.trackSelectionParameters = exo.trackSelectionParameters
                            .buildUpon()
                            .setTrackTypeDisabled(trackType, false)
                            .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, 0))
                            .build()
                    }
                )
                idx++
            }
        }
        if (includeOff) {
            list.add(
                TrackChoice("Subtitles: Off") {
                    exo.trackSelectionParameters = exo.trackSelectionParameters
                        .buildUpon()
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                        .build()
                }
            )
        }
        return list
    }

    private fun countTracks(tracks: Tracks, trackType: Int): Int {
        var total = 0
        for (group in tracks.groups) {
            if (group.type == trackType && group.mediaTrackGroup.length > 0) {
                total++
            }
        }
        return total
    }

    private fun showMobileServersDialog() {
        if (servers.isEmpty()) return
        val labels = servers.mapIndexed { idx, s ->
            val active = if (idx == activeIndex) " [Active]" else ""
            "[${s.quality}] ${s.providerName}$active"
        }.toTypedArray()

        AlertDialog.Builder(this)
            .setTitle("Select Server (${servers.size})")
            .setSingleChoiceItems(labels, activeIndex.coerceAtLeast(0)) { dlg, which ->
                dlg.dismiss()
                playServerAt(which)
            }
            .show()
    }

    private fun showMobileAudioDialog() {
        val exo = exoPlayer ?: return
        val choices = collectTrackChoices(exo, exo.currentTracks, C.TRACK_TYPE_AUDIO, includeOff = false)
        if (choices.isEmpty()) {
            AlertDialog.Builder(this)
                .setTitle("Audio Track")
                .setMessage("No multiple audio tracks found in this stream.")
                .setPositiveButton("OK", null)
                .show()
            return
        }
        val names = choices.map { it.label }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("Select Audio Track")
            .setItems(names) { dlg, which ->
                choices[which].onSelect()
                dlg.dismiss()
            }
            .show()
    }

    private fun togglePlayPause() {
        val exo = exoPlayer ?: return
        if (exo.isPlaying) {
            exo.pause()
            if (isTvDevice) showTvStatus("Paused")
        } else {
            exo.play()
            if (isTvDevice) showTvStatus("Playing")
        }
    }

    private fun seekRelative(deltaMs: Long) {
        val exo = exoPlayer ?: return
        val dur = exo.duration
        val target = (exo.currentPosition + deltaMs).coerceAtLeast(0L)
        val clamped = if (dur > 0L) target.coerceAtMost(dur) else target
        exo.seekTo(clamped)
        if (isTvDevice) {
            val sec = (deltaMs / 1000L)
            showTvStatus(if (sec >= 0) "Forward +${sec}s" else "Rewind ${sec}s")
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (isTvDevice && event.action == KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_BACK,
                KeyEvent.KEYCODE_ESCAPE -> {
                    if (tvMenuOpen) {
                        setTvMenuOpen(false)
                        return true
                    }
                }

                KeyEvent.KEYCODE_DPAD_DOWN -> {
                    if (!tvMenuOpen) {
                        setTvMenuOpen(true)
                        return true
                    }
                }

                KeyEvent.KEYCODE_DPAD_UP -> {
                    if (!tvMenuOpen) {
                        cyclePictureSize()
                        return true
                    }
                }

                KeyEvent.KEYCODE_DPAD_CENTER,
                KeyEvent.KEYCODE_ENTER,
                KeyEvent.KEYCODE_SPACE,
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                    if (!tvMenuOpen) {
                        togglePlayPause()
                        return true
                    }
                }

                KeyEvent.KEYCODE_DPAD_RIGHT,
                KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> {
                    if (!tvMenuOpen) {
                        seekRelative(10_000L)
                        return true
                    }
                }

                KeyEvent.KEYCODE_DPAD_LEFT,
                KeyEvent.KEYCODE_MEDIA_REWIND -> {
                    if (!tvMenuOpen) {
                        seekRelative(-10_000L)
                        return true
                    }
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun onSwipeTouch(view: View, event: MotionEvent): Boolean {
        val w = view.width.takeIf { it > 0 } ?: 1080
        val h = view.height.takeIf { it > 0 } ?: 720

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                dragStartY = event.y
                if (event.x < w / 2f) {
                    dragLeft = true
                    dragRight = false
                    dragStartVal = currentBrightness
                } else {
                    dragRight = true
                    dragLeft = false
                    dragStartVal = currentVolumePct
                }
                return true
            }

            MotionEvent.ACTION_MOVE -> {
                val dy = dragStartY - event.y
                if (abs(dy) < dp(12)) return true
                val ratio = dy / (h * 0.6f)
                if (dragLeft) {
                    val next = (dragStartVal + ratio).coerceIn(0.05f, 1.0f)
                    currentBrightness = next
                    val attrs = window.attributes
                    attrs.screenBrightness = next
                    window.attributes = attrs
                    val pct = (next * 100f).toInt()
                    showHud("BR", pct, 100, primeBlue, "$pct%")
                } else if (dragRight) {
                    val next = (dragStartVal + (ratio * 200f)).coerceIn(0f, 200f)
                    applyVolume(next, showHud = true)
                }
                return true
            }

            MotionEvent.ACTION_UP -> {
                val moved = abs(dragStartY - event.y)
                dragLeft = false
                dragRight = false
                handler.removeCallbacks(hideHudTask)
                handler.postDelayed(hideHudTask, 750)
                if (moved < dp(12)) {
                    if (playerView.isControllerFullyVisible) {
                        playerView.hideController()
                    } else {
                        playerView.showController()
                    }
                }
                return true
            }
        }
        return false
    }

    private fun applyVolume(pct: Float, showHud: Boolean) {
        currentVolumePct = pct.coerceIn(0f, 200f)
        val mgr = audioManager ?: return
        val maxVol = mgr.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val sysTarget = ((currentVolumePct.coerceAtMost(100f) / 100f) * maxVol)
            .toInt()
            .coerceIn(0, maxVol)
        mgr.setStreamVolume(AudioManager.STREAM_MUSIC, sysTarget, 0)

        try {
            if (currentVolumePct > 100f) {
                val gainMb = (((currentVolumePct - 100f) / 100f) * 2000f)
                    .toInt()
                    .coerceIn(0, 2500)
                loudnessEnhancer?.setTargetGain(gainMb)
                loudnessEnhancer?.enabled = gainMb > 0
            } else {
                loudnessEnhancer?.enabled = false
            }
        } catch (_: Throwable) {
        }

        if (showHud) {
            val isBoost = currentVolumePct > 100f
            val col = if (isBoost) Color.parseColor("#FF9800") else primeBlue
            val lbl = if (currentVolumePct <= 0f) "MUTE" else "VOL"
            showHud(lbl, currentVolumePct.toInt(), 200, col, "${currentVolumePct.toInt()}%")
        }
    }

    private fun showHud(label: String, valInt: Int, maxInt: Int, color: Int, text: String) {
        handler.removeCallbacks(hideHudTask)
        swipeHudLabel.text = label
        swipeHudLabel.setTextColor(color)
        swipeHudBar.max = maxInt
        swipeHudBar.progress = valInt.coerceIn(0, maxInt)
        swipeHudBar.progressDrawable.setTint(color)
        swipeHudPct.text = text
        swipeHudPct.setTextColor(color)
        swipeHud.visibility = View.VISIBLE
    }

    private fun makeTvOptionRow(
        title: String,
        subtitle: String,
        isSelected: Boolean,
        onClick: () -> Unit
    ): LinearLayout {
        val baseColor = if (isSelected) activeRed else darkCard
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            isFocusable = true
            isFocusableInTouchMode = true
            background = makeRowDrawable(baseColor, if (isSelected) Color.WHITE else Color.parseColor("#33FFFFFF"))
            setPadding(dp(14), dp(8), dp(14), dp(8))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(8) }

            val tView = TextView(this@Media3PlayerActivity).apply {
                text = if (isSelected) "✓ $title" else title
                setTextColor(Color.WHITE)
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
            }
            val sView = TextView(this@Media3PlayerActivity).apply {
                text = subtitle
                setTextColor(Color.parseColor("#CCCCCC"))
                textSize = 11f
                maxLines = 1
            }
            addView(tView)
            addView(sView)

            setOnFocusChangeListener { v, focused ->
                val bg = v.background
                if (bg is GradientDrawable) {
                    bg.setStroke(dp(if (focused) 3 else 1), if (focused) Color.WHITE else primeBlue)
                    bg.setColor(if (focused) primeBlue else baseColor)
                }
            }
            setOnClickListener { onClick() }
        }
    }

    private fun makeTvInfoText(msg: String): TextView {
        return TextView(this).apply {
            text = msg
            setTextColor(Color.WHITE)
            textSize = 13f
            setPadding(dp(8), dp(8), dp(8), dp(8))
        }
    }

    private fun bindTvFocus(view: View, normalColor: Int) {
        view.setOnFocusChangeListener { v, focused ->
            val bg = v.background
            if (bg is GradientDrawable) {
                bg.setStroke(dp(if (focused) 3 else 1), if (focused) Color.WHITE else primeBlue)
                bg.setColor(if (focused) primeBlue else normalColor)
            }
        }
    }

    private fun makePill(fill: Int, stroke: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(18).toFloat()
            setColor(fill)
            setStroke(dp(1), stroke)
        }
    }

    private fun makeRowDrawable(fill: Int, stroke: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(10).toFloat()
            setColor(fill)
            setStroke(dp(1), stroke)
        }
    }

    private fun makePanelDrawable(fill: Int, stroke: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(16).toFloat()
            setColor(fill)
            setStroke(dp(2), stroke)
        }
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        handler.removeCallbacks(hideHudTask)
        handler.removeCallbacks(hideTvStatusTask)
        if (Media3Bridge.activePlayer === this) {
            Media3Bridge.activePlayer = null
        }
        try {
            loudnessEnhancer?.release()
        } catch (_: Throwable) {
        }
        exoPlayer?.release()
        exoPlayer = null
        super.onDestroy()
    }
}