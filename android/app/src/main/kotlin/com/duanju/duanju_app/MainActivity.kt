package com.duanju.duanju_app

import io.flutter.embedding.android.FlutterActivity
import android.app.UiModeManager
import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.os.Build
import android.os.Bundle
import android.os.BatteryManager
import android.os.PowerManager
import android.os.SystemClock
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Rect
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.net.ConnectivityManager
import android.net.Uri
import android.util.Rational
import android.view.InputDevice
import android.view.WindowManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var headroomReadAt = 0L
    private var thermalHeadroom: Double? = null
    private var deviceChannel: MethodChannel? = null
    private var televisionMode = false
    private var pipAutoEnterEnabled = false
    private var pipAspectWidth = 16
    private var pipAspectHeight = 9
    private var pipSourceRect: Rect? = null

    @Suppress("DEPRECATION")
    private fun isTelevisionDevice(): Boolean {
        val configuration = resources.configuration
        val mode = (getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager)?.currentModeType
            ?: (configuration.uiMode and Configuration.UI_MODE_TYPE_MASK)
        if (mode == Configuration.UI_MODE_TYPE_TELEVISION ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK_ONLY) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_TELEVISION) ||
            packageManager.hasSystemFeature("amazon.hardware.fire_tv")) {
            return true
        }
        if (mode == Configuration.UI_MODE_TYPE_CAR ||
            mode == Configuration.UI_MODE_TYPE_WATCH ||
            mode == Configuration.UI_MODE_TYPE_VR_HEADSET ||
            configuration.touchscreen != Configuration.TOUCHSCREEN_NOTOUCH ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_SENSOR_ACCELEROMETER) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_AUTOMOTIVE) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_WATCH) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_PC)) {
            return false
        }
        val remoteNavigation = configuration.navigation == Configuration.NAVIGATION_DPAD ||
            InputDevice.getDeviceIds().any { id ->
                val device = InputDevice.getDevice(id)
                device != null && !device.isVirtual && device.supportsSource(InputDevice.SOURCE_DPAD)
            }
        return remoteNavigation || packageManager.hasSystemFeature(PackageManager.FEATURE_LIVE_TV)
    }

    override fun setRequestedOrientation(requestedOrientation: Int) {
        super.setRequestedOrientation(
            if (televisionMode) ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE else requestedOrientation
        )
    }

    private fun isSoftwareCodec(info: MediaCodecInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return info.isSoftwareOnly
        }
        val lower = info.name.lowercase()
        return lower.startsWith("omx.google.") ||
            lower.startsWith("c2.android.") ||
            lower.startsWith("omx.ffmpeg.") ||
            lower.contains(".sw.") ||
            lower.contains("google.")
    }

    private fun pickDecodersForMime(
        codecs: Array<MediaCodecInfo>,
        mimeType: String,
    ): Pair<String?, String?> {
        var hardwareCodec: String? = null
        var softwareCodec: String? = null
        for (info in codecs) {
            if (info.isEncoder) continue
            val supportsMime = info.supportedTypes.any { it.equals(mimeType, ignoreCase = true) }
            if (!supportsMime) continue
            val isHw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                info.isHardwareAccelerated && !isSoftwareCodec(info)
            } else {
                !isSoftwareCodec(info)
            }
            if (isHw) {
                if (hardwareCodec == null) hardwareCodec = info.name
            } else {
                if (softwareCodec == null) softwareCodec = info.name
            }
        }
        return hardwareCodec to softwareCodec
    }

    @Suppress("DEPRECATION")
    private fun currentDisplayRefreshRate(): Double? {
        return runCatching {
            val rate = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display?.refreshRate
            } else {
                windowManager.defaultDisplay?.refreshRate
            }
            rate?.toDouble()?.takeIf { it.isFinite() && it > 0.0 }
        }.getOrNull()
    }

    private fun mediaCodecDiagnostics(): Map<String, Any?> {
        val codecs = runCatching {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
        }.getOrDefault(emptyArray())
        val (hevcHw, hevcSw) = pickDecodersForMime(codecs, "video/hevc")
        val (avcHw, avcSw) = pickDecodersForMime(codecs, "video/avc")
        return mapOf(
            "hardware" to Build.HARDWARE,
            "board" to Build.BOARD,
            "model" to Build.MODEL,
            "sdkInt" to Build.VERSION.SDK_INT,
            "refreshRate" to currentDisplayRefreshRate(),
            "hevcHardware" to hevcHw,
            "hevcSoftware" to hevcSw,
            "avcHardware" to avcHw,
            "avcSoftware" to avcSw,
        )
    }

    private fun playbackPower(): Map<String, Any?> {
        val power = getSystemService(Context.POWER_SERVICE) as? PowerManager
        val activity = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val now = SystemClock.elapsedRealtime()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            (headroomReadAt == 0L || now - headroomReadAt >= 10000L)) {
            headroomReadAt = now
            thermalHeadroom = runCatching {
                power?.getThermalHeadroom(0)?.toDouble()?.takeIf { it.isFinite() }
            }.getOrNull()
        }
        val thermalStatus = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            power?.currentThermalStatus ?: PowerManager.THERMAL_STATUS_NONE
        } else 0
        return mapOf(
            "batterySaver" to (power?.isPowerSaveMode ?: false),
            "onBattery" to ((battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) ?: -1) <= 0),
            "thermalStatus" to thermalStatus,
            "headroom" to thermalHeadroom,
            "lowMemory" to (activity?.isLowRamDevice ?: true),
            "gles" to (activity?.deviceConfigurationInfo?.reqGlEsVersion ?: 0)
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        televisionMode = if (savedInstanceState?.containsKey("duanju.televisionMode") == true) {
            savedInstanceState.getBoolean("duanju.televisionMode")
        } else isTelevisionDevice()
        super.onCreate(savedInstanceState)
        if (televisionMode) {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            // 关键修复：大屏电视芯片（晶晨/联发科/瑞芯微/海思等）的硬件视频合成器 (HWC) 要求窗口保持不透明 (OPAQUE)。
            // 若错误设为 RGBA_8888 会引入透明通道，破坏视频硬件直通图层混合，导致电视端黑屏（有声音无图像）。
            window.setFormat(android.graphics.PixelFormat.OPAQUE)
            val lp = window.attributes
            lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
            window.attributes = lp
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            window.colorMode = ActivityInfo.COLOR_MODE_DEFAULT
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
    }

    override fun onResume() {
        super.onResume()
        if (televisionMode) requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("duanju.televisionMode", televisionMode)
        super.onSaveInstanceState(outState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deviceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "duanju/device")
            .also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "deviceInfo" -> {
                            val version = packageManager.getPackageInfo(packageName, 0).versionName
                            result.success(mapOf("television" to isTelevisionDevice(), "version" to version))
                        }
                        "setTelevisionMode" -> {
                            val enabled = call.argument<Boolean>("enabled")
                            if (enabled == null) {
                                result.error("invalid_display_mode", "缺少电视模式状态", null)
                            } else {
                                val changed = televisionMode != enabled
                                televisionMode = enabled
                                if (enabled || changed) {
                                    requestedOrientation = if (enabled) {
                                        ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                                    } else ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                                }
                                result.success(null)
                            }
                        }
                        "playbackPower" -> result.success(runCatching { playbackPower() }.getOrNull())
                        "systemProxy" -> {
                            val connection = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                            val proxy = connection.defaultProxy
                            val host = proxy?.host.orEmpty()
                            val address = if (host.isNotEmpty() && (proxy?.port ?: 0) > 0) {
                                "http://${if (host.contains(':')) "[$host]" else host}:${proxy!!.port}"
                            } else ""
                            result.success(mapOf(
                                "http" to address,
                                "https" to address,
                                "bypass" to (proxy?.exclusionList?.toList() ?: emptyList<String>()),
                                "pac" to (proxy != null && proxy.pacFileUrl != Uri.EMPTY)
                            ))
                        }
                        "pictureInPictureStatus" -> result.success(pictureInPictureStatus())
                        "updatePictureInPictureConfig" -> {
                            val autoEnter = call.argument<Boolean>("autoEnter") ?: false
                            val width = call.argument<Int>("width") ?: 16
                            val height = call.argument<Int>("height") ?: 9
                            result.success(
                                updatePictureInPictureConfig(
                                    autoEnter = autoEnter,
                                    width = width,
                                    height = height,
                                    left = call.argument<Int>("left"),
                                    top = call.argument<Int>("top"),
                                    right = call.argument<Int>("right"),
                                    bottom = call.argument<Int>("bottom"),
                                )
                            )
                        }
                        "enterPictureInPicture" -> {
                            val width = call.argument<Int>("width") ?: 16
                            val height = call.argument<Int>("height") ?: 9
                            result.success(enterPlayerPictureInPicture(
                                width,
                                height,
                                call.argument<Int>("left"),
                                call.argument<Int>("top"),
                                call.argument<Int>("right"),
                                call.argument<Int>("bottom")
                            ))
                        }
                        "getBrightness" -> {
                            if (televisionMode || isTelevisionDevice()) {
                                result.success(1.0)
                            } else {
                                val lp = window.attributes
                                val current = if (lp.screenBrightness >= 0f) {
                                    lp.screenBrightness.toDouble()
                                } else {
                                    try {
                                        val sys = Settings.System.getInt(
                                            contentResolver,
                                            Settings.System.SCREEN_BRIGHTNESS
                                        )
                                        (sys / 255.0).coerceIn(0.0, 1.0)
                                    } catch (e: Exception) {
                                        0.5
                                    }
                                }
                                result.success(current)
                            }
                        }
                        "setBrightness" -> {
                            if (televisionMode || isTelevisionDevice()) {
                                // 电视机由硬件自身画质引擎管理，忽略亮度覆写以保护电视原生画质与色阶
                                result.success(true)
                            } else {
                                val value = call.argument<Double>("brightness")?.toFloat()
                                if (value != null) {
                                    val lp = window.attributes
                                    lp.screenBrightness = value.coerceIn(0.01f, 1.0f)
                                    window.attributes = lp
                                    result.success(true)
                                } else {
                                    result.error("invalid_arg", "缺少亮度数值", null)
                                }
                            }
                        }
                        "resetBrightness" -> {
                            val lp = window.attributes
                            lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                            window.attributes = lp
                            result.success(true)
                        }
                        "openExternalPlayer" -> {
                            val url = call.argument<String>("url")
                            val title = call.argument<String>("title") ?: "短剧"
                            if (!url.isNullOrEmpty()) {
                                try {
                                    val intent = Intent(Intent.ACTION_VIEW).apply {
                                        setDataAndType(Uri.parse(url), "video/*")
                                        putExtra("title", title)
                                        putExtra("return_result", true)
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    startActivity(intent)
                                    result.success(true)
                                } catch (e: Exception) {
                                    result.error("no_player", "未找到外部播放器: ${e.message}", null)
                                }
                            } else {
                                result.error("invalid_url", "播放地址为空", null)
                            }
                        }
                        "mediaCodecDiagnostics" -> {
                            result.success(mediaCodecDiagnostics())
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    private fun pictureInPictureSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun pictureInPictureStatus(): Map<String, Any> {
        return mapOf(
            "supported" to pictureInPictureSupported(),
            "active" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode)
        )
    }

    private fun parsePipSourceRect(
        left: Int?,
        top: Int?,
        right: Int?,
        bottom: Int?
    ): Rect? {
        if (left == null || top == null || right == null || bottom == null) {
            return null
        }
        if (right <= left || bottom <= top) {
            return null
        }
        return Rect(left, top, right, bottom)
    }

    private fun buildPictureInPictureParams(
        width: Int,
        height: Int,
        sourceRect: Rect?,
        autoEnter: Boolean
    ): PictureInPictureParams {
        val safeWidth = width.coerceIn(1, 10000)
        val safeHeight = height.coerceIn(1, 10000)
        val builder = PictureInPictureParams.Builder()
        builder.setAspectRatio(Rational(safeWidth, safeHeight))
        if (sourceRect != null && sourceRect.width() > 0 && sourceRect.height() > 0) {
            builder.setSourceRectHint(sourceRect)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnter)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun updatePictureInPictureConfig(
        autoEnter: Boolean,
        width: Int,
        height: Int,
        left: Int?,
        top: Int?,
        right: Int?,
        bottom: Int?
    ): Map<String, Any> {
        pipAutoEnterEnabled = autoEnter
        pipAspectWidth = width.coerceIn(1, 10000)
        pipAspectHeight = height.coerceIn(1, 10000)
        pipSourceRect = parsePipSourceRect(left, top, right, bottom)
        if (!pictureInPictureSupported() || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return pictureInPictureStatus()
        }
        runCatching {
            if (!isInPictureInPictureMode) {
                setPictureInPictureParams(
                    buildPictureInPictureParams(
                        width = pipAspectWidth,
                        height = pipAspectHeight,
                        sourceRect = pipSourceRect,
                        autoEnter = pipAutoEnterEnabled,
                    )
                )
            }
        }
        return pictureInPictureStatus()
    }

    private fun enterPlayerPictureInPicture(
        width: Int,
        height: Int,
        left: Int?,
        top: Int?,
        right: Int?,
        bottom: Int?
    ): Map<String, Any> {
        if (!pictureInPictureSupported()) return pictureInPictureStatus()
        pipAutoEnterEnabled = true
        pipAspectWidth = width.coerceIn(1, 10000)
        pipAspectHeight = height.coerceIn(1, 10000)
        val rect = parsePipSourceRect(left, top, right, bottom)
        if (rect != null) {
            pipSourceRect = rect
        }
        return runCatching {
            val params = buildPictureInPictureParams(
                width = pipAspectWidth,
                height = pipAspectHeight,
                sourceRect = pipSourceRect,
                autoEnter = true,
            )
            val entered = enterPictureInPictureMode(params)
            pictureInPictureStatus() + ("requested" to entered)
        }.getOrElse { pictureInPictureStatus() }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S &&
            pipAutoEnterEnabled &&
            !isTelevisionDevice() &&
            pictureInPictureSupported() &&
            !isInPictureInPictureMode
        ) {
            enterPlayerPictureInPicture(
                width = pipAspectWidth,
                height = pipAspectHeight,
                left = pipSourceRect?.left,
                top = pipSourceRect?.top,
                right = pipSourceRect?.right,
                bottom = pipSourceRect?.bottom,
            )
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        deviceChannel?.invokeMethod(
            "pictureInPictureChanged",
            mapOf("active" to isInPictureInPictureMode)
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pipAutoEnterEnabled = false
        deviceChannel?.setMethodCallHandler(null)
        deviceChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
