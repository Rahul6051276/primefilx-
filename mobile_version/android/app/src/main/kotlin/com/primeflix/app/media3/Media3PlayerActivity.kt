package com.primeflix.app.media3

import android.app.AlertDialog
import android.content.pm.ActivityInfo
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import org.json.JSONArray
import java.util.Locale

data class ServerEntry(
    val title: String,
    val server: String,
    val url: String,
    val isHindi: Boolean
)

@OptIn(UnstableApi::class)
class Media3PlayerActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_URL = "extra_url"
        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_HEADERS = "extra_headers"
        const val EXTRA_SERVERS_JSON = "extra_servers_json"
    }

    private var player: ExoPlayer? = null
    private lateinit var playerView: PlayerView
    private lateinit var progressBar: ProgressBar
    private lateinit var statusText: TextView
    private lateinit var serversButton: Button

    private var customHeaders: HashMap<String, String> = hashMapOf()
    private val serverList = mutableListOf<ServerEntry>()

    private var resizeModeIndex = 0
    private val resizeModes = listOf(
        AspectRatioFrameLayout.RESIZE_MODE_FIT,
        AspectRatioFrameLayout.RESIZE_MODE_FILL,
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM
    )
    private val resizeLabels = listOf("FIT", "FILL", "ZOOM")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        try {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            hideSystemBars()

            val streamUrl = intent.getStringExtra(EXTRA_URL).orEmpty().trim()
            val title = intent.getStringExtra(EXTRA_TITLE).orEmpty().ifEmpty { "Primeflix" }
            val serversJsonRaw = intent.getStringExtra(EXTRA_SERVERS_JSON).orEmpty()

            @Suppress("UNCHECKED_CAST")
            customHeaders = (intent.getSerializableExtra(EXTRA_HEADERS) as? HashMap<String, String>) ?: hashMapOf()

            parseServers(serversJsonRaw, title, streamUrl)

            val rootLayout = FrameLayout(this).apply {
                setBackgroundColor(Color.BLACK)
            }

            playerView = PlayerView(this).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
                useController = true
                controllerShowTimeoutMs = 4000
                keepScreenOn = true
            }

            progressBar = ProgressBar(this).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER
                )
                visibility = View.VISIBLE
            }

            statusText = TextView(this).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.TOP or Gravity.CENTER_HORIZONTAL
                ).apply {
                    topMargin = 48
                }
                text = title
                setTextColor(Color.WHITE)
                textSize = 14f
                setBackgroundColor(Color.parseColor("#88000000"))
                setPadding(24, 10, 24, 10)
            }

            serversButton = Button(this).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.TOP or Gravity.END
                ).apply {
                    topMargin = 36
                    rightMargin = 36
                }
                text = if (serverList.isNotEmpty()) "SERVERS (${serverList.size})" else "SERVERS"
                setTextColor(Color.WHITE)
                textSize = 12f
                setBackgroundColor(Color.parseColor("#CC0072D2"))
                setOnClickListener { showServersDialog() }
            }

            rootLayout.addView(playerView)
            rootLayout.addView(progressBar)
            rootLayout.addView(statusText)
            rootLayout.addView(serversButton)
            setContentView(rootLayout)

            val initialUrl = if (streamUrl.isNotEmpty()) {
                streamUrl
            } else if (serverList.isNotEmpty()) {
                serverList.first().url
            } else {
                ""
            }

            if (initialUrl.isNotEmpty()) {
                initializePlayer(initialUrl, customHeaders)
            } else {
                progressBar.visibility = View.GONE
                statusText.visibility = View.VISIBLE
                statusText.text = "Stream URL nahi mila — SERVERS button दबाएं"
            }
        } catch (e: Exception) {
            finish()
        }
    }

    private fun parseServers(jsonStr: String, fallbackTitle: String, fallbackUrl: String) {
        serverList.clear()
        if (jsonStr.isNotEmpty()) {
            try {
                val arr = JSONArray(jsonStr)
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    val u = obj.optString("url", "").trim()
                    if (u.isEmpty()) continue
                    val sTitle = obj.optString("title", fallbackTitle).ifEmpty { fallbackTitle }
                    val sName = obj.optString("server", "Server ${i + 1}").ifEmpty { "Server ${i + 1}" }
                    val isHin = obj.optBoolean("isHindi", false)
                    serverList.add(ServerEntry(sTitle, sName, u, isHin))
                }
            } catch (_: Exception) {}
        }
        if (serverList.isEmpty() && fallbackUrl.isNotEmpty()) {
            serverList.add(ServerEntry(fallbackTitle, "Current Server", fallbackUrl, false))
        }
    }

    private fun showServersDialog() {
        try {
            if (serverList.isEmpty()) {
                AlertDialog.Builder(this)
                    .setTitle("Servers")
                    .setMessage("कोई सर्वर लिंक उपलब्ध नहीं है।")
                    .setPositiveButton("OK", null)
                    .show()
                return
            }

            val labels = serverList.mapIndexed { idx, s ->
                val hindiTag = if (s.isHindi) " [HINDI]" else ""
                "${idx + 1}. ${s.server}$hindiTag — ${s.title}\n${s.url}"
            }.toTypedArray()

            AlertDialog.Builder(this)
                .setTitle("Select Server & Link")
                .setItems(labels) { dialog, which ->
                    val chosen = serverList.getOrNull(which) ?: return@setItems
                    dialog.dismiss()
                    statusText.text = "${chosen.server}: ${chosen.title}"
                    statusText.visibility = View.VISIBLE
                    initializePlayer(chosen.url, customHeaders)
                }
                .setNegativeButton("Close", null)
                .show()
        } catch (_: Exception) {}
    }

    private fun initializePlayer(url: String, headers: Map<String, String>) {
        try {
            releasePlayer()
            progressBar.visibility = View.VISIBLE

            val httpFactory = DefaultHttpDataSource.Factory()
                .setUserAgent(
                    headers["User-Agent"]
                        ?: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                )
                .setAllowCrossProtocolRedirects(true)

            val requestHeaders = HashMap(headers).apply {
                remove("User-Agent")
            }
            if (requestHeaders.isNotEmpty()) {
                httpFactory.setDefaultRequestProperties(requestHeaders)
            }

            val mediaSourceFactory = DefaultMediaSourceFactory(this)
                .setDataSourceFactory(httpFactory)

            val exoPlayer = ExoPlayer.Builder(this)
                .setMediaSourceFactory(mediaSourceFactory)
                .build()

            player = exoPlayer
            playerView.player = exoPlayer

            exoPlayer.addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) {
                    when (playbackState) {
                        Player.STATE_BUFFERING -> progressBar.visibility = View.VISIBLE
                        Player.STATE_READY -> {
                            progressBar.visibility = View.GONE
                            statusText.postDelayed({ statusText.visibility = View.GONE }, 2500)
                        }
                        Player.STATE_ENDED, Player.STATE_IDLE -> progressBar.visibility = View.GONE
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    progressBar.visibility = View.GONE
                    statusText.visibility = View.VISIBLE
                    statusText.text = "Playback Error: ${error.errorCodeName}"
                }
            })

            val mediaItem = MediaItem.fromUri(url)
            exoPlayer.setMediaItem(mediaItem)
            exoPlayer.prepare()
            exoPlayer.playWhenReady = true
        } catch (e: Exception) {
            progressBar.visibility = View.GONE
            statusText.visibility = View.VISIBLE
            statusText.text = "Player Error: ${e.localizedMessage ?: "Unable to play"}"
        }
    }

    private fun seekBy(seconds: Long) {
        val currentPlayer = player ?: return
        val target = (currentPlayer.currentPosition + seconds * 1000L)
            .coerceAtLeast(0L)
            .coerceAtMost(currentPlayer.duration.takeIf { it > 0 } ?: Long.MAX_VALUE)
        currentPlayer.seekTo(target)
        showTemporaryBanner("${if (seconds > 0) "+" else ""}${seconds}s")
    }

    private fun cycleScaleMode() {
        resizeModeIndex = (resizeModeIndex + 1) % resizeModes.size
        playerView.resizeMode = resizeModes[resizeModeIndex]
        showTemporaryBanner("Mode: ${resizeLabels[resizeModeIndex]}")
    }

    private fun showTemporaryBanner(msg: String) {
        statusText.text = msg.uppercase(Locale.ROOT)
        statusText.visibility = View.VISIBLE
        statusText.removeCallbacks(hideBannerRunnable)
        statusText.postDelayed(hideBannerRunnable, 1200)
    }

    private val hideBannerRunnable = Runnable {
        statusText.visibility = View.GONE
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val currentPlayer = player
        if (event.action == KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_DPAD_CENTER,
                KeyEvent.KEYCODE_ENTER,
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                    currentPlayer?.let {
                        if (it.isPlaying) it.pause() else it.play()
                    }
                    playerView.showController()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_RIGHT,
                KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> {
                    seekBy(30)
                    playerView.showController()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_LEFT,
                KeyEvent.KEYCODE_MEDIA_REWIND -> {
                    seekBy(-30)
                    playerView.showController()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_UP -> {
                    cycleScaleMode()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_DOWN -> {
                    if (playerView.isControllerFullyVisible) {
                        playerView.hideController()
                    } else {
                        playerView.showController()
                    }
                    return true
                }
                KeyEvent.KEYCODE_BACK -> {
                    finish()
                    return true
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun hideSystemBars() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                controller.hide(WindowInsets.Type.systemBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                )
        }
    }

    private fun releasePlayer() {
        try {
            if (::statusText.isInitialized) {
                statusText.removeCallbacks(hideBannerRunnable)
            }
            player?.release()
            player = null
        } catch (_: Exception) {}
    }

    override fun onStop() {
        super.onStop()
        player?.pause()
    }

    override fun onDestroy() {
        releasePlayer()
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onDestroy()
    }
}