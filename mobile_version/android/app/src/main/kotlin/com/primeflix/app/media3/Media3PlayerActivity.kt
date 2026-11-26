package com.primeflix.app.media3

import android.app.AlertDialog
import android.content.Context
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
import android.widget.TextView
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
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

@OptIn(UnstableApi::class)
class Media3PlayerActivity : AppCompatActivity() {

    private val primeBlue = Color.parseColor("#00A8E1")
    private val darkCard = Color.parseColor("#1A242F")

    private lateinit var rootLayout: FrameLayout
    private lateinit var playerView: PlayerView
    private lateinit var serversBtn: Button
    private lateinit var spinner: ProgressBar
    private lateinit var swipeHud: LinearLayout
    private lateinit var swipeHudLabel: TextView
    private lateinit var swipeHudBar: ProgressBar
    private lateinit var swipeHudPct: TextView

    private var exoPlayer: ExoPlayer? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var audioManager: AudioManager? = null

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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Media3Bridge.activePlayer = this
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

        // Media3 ka built-in PlayerView: TV D-pad remote, seek bar, play/pause aur tracks sab out-of-the-box kaam karte hain
        playerView = PlayerView(this).apply {
            useController = true
            controllerShowTimeoutMs = 4500
            setShutterBackgroundColor(Color.BLACK)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        rootLayout.addView(playerView)

        // Left = Brightness, Right = Volume (0% - 200% Boost) swipe layer
        val swipeView = View(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setOnTouchListener { v, event ->
                onSwipeTouch(v, event)
            }
        }
        rootLayout.addView(swipeView)

        // Top Bar: Back + Title + Servers button
        val topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
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
            isFocusable = true
            isFocusableInTouchMode = true
            background = makePill(darkCard, Color.WHITE)
            setPadding(dp(12), dp(6), dp(12), dp(6))
            bindFocus(this, darkCard)
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
            isFocusable = true
            isFocusableInTouchMode = true
            background = makePill(darkCard, primeBlue)
            setPadding(dp(14), dp(6), dp(14), dp(6))
            bindFocus(this, darkCard)
            setOnClickListener { showServersDialog() }
        }

        topBar.addView(backBtn)
        topBar.addView(titleTv)
        topBar.addView(serversBtn)
        rootLayout.addView(topBar)

        spinner = ProgressBar(this).apply {
            indeterminateDrawable.setTint(primeBlue)
            layoutParams = FrameLayout.LayoutParams(dp(52), dp(52), Gravity.CENTER)
        }
        rootLayout.addView(spinner)

        // Brightness / Volume (200% Boost) HUD
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

    private fun showServersDialog() {
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
                playerView.showController()
            }
            .show()
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

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_DPAD_UP -> {
                    if (!playerView.isControllerFullyVisible) {
                        playerView.showController()
                        serversBtn.requestFocus()
                        return true
                    }
                }
                KeyEvent.KEYCODE_DPAD_DOWN,
                KeyEvent.KEYCODE_DPAD_LEFT,
                KeyEvent.KEYCODE_DPAD_RIGHT,
                KeyEvent.KEYCODE_DPAD_CENTER,
                KeyEvent.KEYCODE_ENTER -> {
                    if (!playerView.isControllerFullyVisible) {
                        playerView.showController()
                    }
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun bindFocus(view: View, normalColor: Int) {
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

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        handler.removeCallbacks(hideHudTask)
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
