package com.coinceeper.adl

import android.content.Intent
import android.os.Build
import android.view.WindowManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterFragmentActivity
import org.json.JSONObject
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    /** مطابق TspAgentChannel (Dart) */
    private val tspAgentChannel = "com.coinceeper.app/tsp_agent"
    private var tspNativePathDone = false

    private fun ensureNativeLibPath() {
        if (tspNativePathDone) return
        val p = TspNativeLoader.getTspagentDiskPath()
            ?: File(applicationInfo.nativeLibraryDir, "libtspagent.so").absolutePath
        TspAgentBridge.setNativeLibPath(p)
        tspNativePathDone = true
    }

    override fun onResume() {
        super.onResume()
        TspWebClickHost.setCurrentActivityForWebClick(this)
    }

    override fun onDestroy() {
        TspWebClickHost.setCurrentActivityForWebClick(null)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.coinceeper.app/screen_protection",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    window.setFlags(
                        WindowManager.LayoutParams.FLAG_SECURE,
                        WindowManager.LayoutParams.FLAG_SECURE,
                    )
                    result.success(null)
                }
                "disable" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            tspAgentChannel,
        ).setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            try {
                TspAgentBridge.ensureLoaded(this@MainActivity)
            } catch (e: UnsatisfiedLinkError) {
                result.error(
                    "NATIVE_GONE",
                    "Build agent native libs: scripts/build_gobridge.sh (Go + NDK). ${e.message}",
                    null,
                )
                return@setMethodCallHandler
            } catch (e: Throwable) {
                result.error("NATIVE", e.message, null)
                return@setMethodCallHandler
            }
            try {
                ensureNativeLibPath()
                when (call.method) {
                    "tspVersion" -> result.success(TspAgentBridge.versionString())
                    "tspHealth" -> result.success(TspAgentBridge.healthJson())
                    "tspFingerprint" -> result.success(TspAgentBridge.fingerprint())
                    "tspStartForeground" -> {
                        val i = Intent(this, TspAgentForegroundService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(i)
                        } else {
                            startService(i)
                        }
                        result.success(null)
                    }
                    "tspStopForeground" -> {
                        stopService(Intent(this, TspAgentForegroundService::class.java))
                        result.success(null)
                    }
                    "tspStart" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as? Map<String, Any?>
                        val cfg = args?.get("configPath") as? String
                        if (cfg.isNullOrBlank()) {
                            result.error("ARG", "configPath required", null)
                        } else {
                            val st = args["statePath"] as? String
                            val code = TspAgentBridge.startWithPaths(cfg, st)
                            if (code == 0 || code == -2) {
                                TspAgentRuntimePrefs.setPaths(
                                    this@MainActivity,
                                    configPath = cfg,
                                    statePath = st,
                                )
                            }
                            result.success(code)
                        }
                    }
                    "tspSetStrictMode" -> {
                        val v = (call.arguments as? Number)?.toInt() ?: 0
                        result.success(TspAgentBridge.setStrictMode(v) == 0)
                    }
                    "tspPrepareAttestation" -> {
                        val hint = when (val a = call.arguments) {
                            is Map<*, *> -> (a["nonceHint"] as? String) ?: ""
                            is String -> a
                            else -> ""
                        }
                        TspAttestationProvider.getPlayIntegrityToken(
                            this@MainActivity,
                            hint,
                        ) { token ->
                            val j = JSONObject()
                            j.put("p", "play_integrity")
                            j.put("t", token)
                            TspAgentBridge.setAttestationJSON(j.toString())
                            Handler(Looper.getMainLooper()).post {
                                result.success(true)
                            }
                        }
                    }
                    "tspSetDeviceKey" -> {
                        // Isolated try so a KeyStore failure returns false (not result.error)
                        // which lets the Dart fallback path run instead of crashing.
                        try {
                            val hex = TspSecureKeyProvider.getOrCreatePayloadKeyHex(this@MainActivity)
                            result.success(TspAgentBridge.setPayloadKeyHex(hex) == 0)
                        } catch (e: Throwable) {
                            android.util.Log.w("TspAgent", "device-key setup failed: ${e.message}")
                            result.success(false)
                        }
                    }
                    "tspSetPayloadKeyHex" -> {
                        val hex = (call.arguments as? String)?.trim().orEmpty()
                        if (hex.length != 64) {
                            result.success(false)
                        } else {
                            result.success(TspAgentBridge.setPayloadKeyHex(hex) == 0)
                        }
                    }
                    "tspStop" -> {
                        TspAgentRuntimePrefs.clear(this@MainActivity)
                        TspAgentBridge.stopRuntime()
                        stopService(Intent(this, TspAgentForegroundService::class.java))
                        result.success(null)
                    }
                    "tspIsRunning" -> result.success(TspAgentBridge.isRuntimeRunning())
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                result.error("NATIVE", e.message, null)
            }
        }
    }
}
