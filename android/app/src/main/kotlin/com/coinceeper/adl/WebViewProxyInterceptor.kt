package com.coinceeper.adl

import android.util.Log
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.URL
import java.util.concurrent.ConcurrentHashMap

/**
 * WebViewProxyInterceptor v1 — Intercept and route WebView requests through proxy.
 *
 * == Why This Class Exists ==
 *
 * Android WebView (Chromium) does NOT respect `ProxySelector.setDefault()`.
 * The only way to proxy WebView traffic on Android is:
 *   1. [THIS] `WebViewClient.shouldInterceptRequest()` — intercept every request
 *      and re-issue it through the proxy, returning the proxied response.
 *   2. `VpnService` — create a local VPN (requires system permission, high overhead).
 *   3. `ProxyController` (API 29+) — system proxy, but requires system app privilege.
 *
 * == Architecture ==
 *
 *   ┌─────────────┐     ┌──────────────────┐     ┌───────────────┐
 *   │   WebView   │────▶│ shouldIntercept  │────▶│  ProxyClient  │
 *   │   (Chromium)│     │  Request()       │     │  (HttpURLConn)│
 *   └─────────────┘     └──────────────────┘     └───────┬───────┘
 *                                                         │
 *                                                   ┌─────▼───────┐
 *                                                   │  Proxy/Host │
 *                                                   │  (remote)   │
 *                                                   └─────────────┘
 *
 * == Dual-Mode Design ==
 *
 * - **Mode 1 (No Proxy / Direct):** proxyUrl is empty → returns null from
 *   shouldInterceptRequest, letting WebView use the device's real IP.
 *   This is the DEFAULT and RECOMMENDED mode for real Android devices,
 *   because each device already has a unique mobile carrier IP (Tier 1).
 *
 * - **Mode 2 (Proxy):** proxyUrl is set → intercepts GET/HEAD requests
 *   and re-issues them through the configured HTTP/SOCKS proxy.
 *   POST/PUT/OPTIONS requests with body are NOT intercepted (they pass
 *   through WebView's native stack) to avoid breaking complex interactions.
 *
 * == Request Header Enhancement ==
 *
 * In BOTH modes, the interceptor CAN modify outgoing request headers:
 *   - Accept-Language: per-device randomisation
 *   - User-Agent: already set by WebView settings
 *   - Custom headers for analytics tracking
 *
 * == Limitations ==
 *
 * - `shouldInterceptRequest()` cannot intercept POST/PUT bodies
 *   (Android platform limitation — the body is consumed by Chromium).
 * - WebSocket connections bypass the interceptor entirely.
 * - Each intercepted request creates a new TCP connection (no connection
 *   pooling across requests).
 *
 * For most ad network traffic (banner/image/script/css loads), the
 * interceptor covers 95%+ of requests. POST requests (form submissions,
 * tracking pixels) go through the device's real IP, which is fine since
 * those are typically lightweight.
 */
object WebViewProxyInterceptor {
    private const val TAG = "WebViewProxy"

    // ── Configuration (set per-session from run() config) ─────────
    @Volatile
    private var proxyUrl: String = ""

    @Volatile
    private var proxyEnabled: Boolean = false

    @Volatile
    private var proxyHost: String = ""

    @Volatile
    private var proxyPort: Int = 0

    @Volatile
    private var proxyType: Proxy.Type = Proxy.Type.HTTP

    // ── Accept-Language (GEO fingerprinting) ──────────────────────
    @Volatile
    private var acceptLanguage: String = "en-US,en;q=0.9,fa;q=0.8"

    // ── Bypass / Always-Direct Domains ────────────────────────────
    // Some requests MUST go direct (not through proxy) to avoid breaking
    // ad network SDKs, tracking pixels, or CDN resources.
    private val directBypassDomains = setOf(
        "localhost",
        "127.0.0.1",
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16",
    )

    // URLs that should never be proxied (monitoring, CDN, etc.)
    private val directBypassUrlPatterns = listOf(
        Regex(".*\\.google\\.(com|adservices)\\/.*", RegexOption.IGNORE_CASE),
        Regex(".*\\.doubleclick\\.net\\/.*", RegexOption.IGNORE_CASE),
        Regex(".*\\.googlesyndication\\.com\\/.*", RegexOption.IGNORE_CASE),
        Regex(".*\\/gtm\\.js.*", RegexOption.IGNORE_CASE),
        Regex(".*\\/analytics\\.js.*", RegexOption.IGNORE_CASE),
        Regex(".*\\/beacon\\/.*", RegexOption.IGNORE_CASE),
        Regex(".*wss?:\\/\\/.*", RegexOption.IGNORE_CASE),          // WebSocket
        Regex("about:.*", RegexOption.IGNORE_CASE),
    )

    // ── Analytics ─────────────────────────────────────────────────
    private val interceptedCount = ConcurrentHashMap<String, Long>()
    private var totalIntercepted: Long = 0
    private var totalProxied: Long = 0
    private var totalDirect: Long = 0
    private var totalErrors: Long = 0

    /**
     * Reset and configure the proxy interceptor for a new session.
     *
     * @param url       The proxy URL (e.g. "http://proxy.example.com:8080",
     *                  "socks5://proxy.example.com:1080"). Empty = direct mode.
     * @param acceptLang Accept-Language header value for GEO fingerprinting.
     */
    fun configure(url: String, acceptLang: String = "") {
        proxyUrl = url
        if (acceptLang.isNotBlank()) {
            acceptLanguage = acceptLang
        }
        if (url.isBlank()) {
            proxyEnabled = false
            proxyHost = ""
            proxyPort = 0
            Log.i(TAG, "Proxy DISABLED — using device's real IP (recommended for mobile devices)")
            return
        }
        try {
            val uri = java.net.URI(url)
            proxyHost = uri.host ?: ""
            proxyPort = uri.port
            val isSocks = url.startsWith("socks4") || url.startsWith("socks5") || url.startsWith("socks")
            proxyType = if (isSocks) Proxy.Type.SOCKS else Proxy.Type.HTTP
            proxyEnabled = proxyHost.isNotBlank() && proxyPort > 0
            Log.i(TAG, "Proxy ENABLED: $proxyType://$proxyHost:$proxyPort")
        } catch (e: Exception) {
            proxyEnabled = false
            Log.w(TAG, "Invalid proxy URL '$url', falling back to direct: ${e.message}")
        }
    }

    /**
     * Get the current proxy configuration as a JSON string (for logging/metrics).
     */
    fun getConfig(): String {
        return """{"enabled":$proxyEnabled,"url":"${proxyUrl.replace("\"", "\\\"")}","host":"$proxyHost","port":$proxyPort,"type":"$proxyType","accept_language":"$acceptLanguage"}"""
    }

    /**
     * Main interceptor method — called from WebViewClient.shouldInterceptRequest().
     *
     * @param request The WebResourceRequest from WebView
     * @return WebResourceResponse if proxied, null for direct (WebView handles it)
     */
    fun intercept(request: WebResourceRequest?): WebResourceResponse? {
        if (request == null) return null

        val urlStr = request.url?.toString() ?: return null
        val method = request.method

        // ── Track analytics ──────────────────────────────────────
        totalIntercepted++
        interceptedCount.merge(urlStr, 1L) { a, b -> a + b }

        // ── Decide: proxy or direct? ─────────────────────────────
        if (shouldBypass(urlStr)) {
            totalDirect++
            return null  // Direct — WebView handles it natively
        }

        if (!proxyEnabled) {
            totalDirect++
            return null  // No proxy configured — use device's real IP
        }

        // ── Only proxy GET/HEAD requests ─────────────────────────
        // POST/PUT/DELETE/PATCH requests with body cannot be easily
        // replayed through shouldInterceptRequest, so we let them pass
        // through WebView's native stack.
        val methodUpper = method.uppercase()
        if (methodUpper != "GET" && methodUpper != "HEAD") {
            totalDirect++
            return null
        }

        // ── Proxy the request through configured proxy ───────────
        return proxyRequest(urlStr, request.requestHeaders)
    }

    /**
     * Decide whether a URL should bypass the proxy and go direct.
     */
    private fun shouldBypass(url: String): Boolean {
        // Bypass known direct domains
        try {
            val host = java.net.URI(url).host ?: return true
            if (host in directBypassDomains) return true

            // Private IP ranges
            if (host.matches(Regex("^10\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$"))) return true
            if (host.matches(Regex("^172\\.(1[6-9]|2\\d|3[01])\\.\\d{1,3}\\.\\d{1,3}$"))) return true
            if (host.matches(Regex("^192\\.168\\.\\d{1,3}\\.\\d{1,3}$"))) return true
            if (host.matches(Regex("^127\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$"))) return true
        } catch (_: Exception) {
            return true
        }

        // Bypass known URL patterns
        for (pattern in directBypassUrlPatterns) {
            if (pattern.matches(url)) return true
        }

        return false
    }

    /**
     * Execute a request through the configured proxy and return the response.
     *
     * This creates a fresh HttpURLConnection through the proxy, copies
     * request headers, reads the response, and wraps it in WebResourceResponse.
     */
    private fun proxyRequest(
        urlStr: String,
        requestHeaders: Map<String, String>?
    ): WebResourceResponse? {
        try {
            val proxy = Proxy(proxyType, InetSocketAddress(proxyHost, proxyPort))
            val conn = URL(urlStr).openConnection(proxy) as HttpURLConnection

            @Suppress("DEPRECATION")
            conn.connectTimeout = 15000  // 15s connect timeout
            conn.readTimeout = 30000     // 30s read timeout
            conn.instanceFollowRedirects = true

            // ── Copy request headers ────────────────────────────
            if (requestHeaders != null) {
                for ((key, value) in requestHeaders) {
                    if (!key.equals("host", ignoreCase = true) &&
                        !key.equals("content-length", ignoreCase = true)) {
                        conn.setRequestProperty(key, value)
                    }
                }
            }

            // ── Inject Accept-Language for GEO fingerprinting ───
            conn.setRequestProperty("Accept-Language", acceptLanguage)

            // ── Execute ─────────────────────────────────────────
            conn.connect()

            val responseCode = conn.responseCode
            val responseMessage = conn.responseMessage ?: ""

            // ── Read response body ──────────────────────────────
            val bodyStream: InputStream? = if (responseCode in 200..399) {
                conn.inputStream
            } else {
                conn.errorStream
            }

            // ── Read response headers ───────────────────────────
            val responseHeaders = mutableMapOf<String, String>()
            var headerIdx = 0
            while (true) {
                val key = conn.getHeaderFieldKey(headerIdx) ?: break
                val value = conn.getHeaderField(headerIdx) ?: ""
                if (key.isNotBlank()) {
                    responseHeaders[key] = value
                }
                headerIdx++
            }

            // ── Determine MIME type and encoding ────────────────
            val contentType = conn.contentType ?: "text/html"
            val contentEncoding = conn.contentEncoding ?: "utf-8"
            val mimeType = contentType.split(";").firstOrNull() ?: "text/html"
            val encoding = contentType.split(";")
                .map { it.trim() }
                .firstOrNull { it.startsWith("charset=", ignoreCase = true) }
                ?.substringAfter("charset=")
                ?.trim() ?: contentEncoding

            totalProxied++
            Log.d(TAG, "Proxied: $responseCode ${urlStr.take(80)}")

            return WebResourceResponse(
                mimeType,
                encoding,
                responseCode,
                responseMessage,
                responseHeaders,
                bodyStream
            )
        } catch (e: Exception) {
            totalErrors++
            Log.w(TAG, "Proxy request failed for ${urlStr.take(80)}: ${e.message}")
            return null  // Fallback to direct
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Analytics & Metrics
    // ═══════════════════════════════════════════════════════════════

    /**
     * Get interceptor metrics as a JSON string.
     */
    fun getMetrics(): String {
        val sb = StringBuilder()
        sb.append("{")
        sb.append("\"total_intercepted\":$totalIntercepted,")
        sb.append("\"total_proxied\":$totalProxied,")
        sb.append("\"total_direct\":$totalDirect,")
        sb.append("\"total_errors\":$totalErrors,")
        sb.append("\"proxy_enabled\":$proxyEnabled,")
        sb.append("\"proxy_url\":\"${proxyUrl.replace("\"", "\\\"")}\",")
        sb.append("\"accept_language\":\"$acceptLanguage\"")
        sb.append("}")
        return sb.toString()
    }

    /**
     * Reset all counters (for fresh session start).
     */
    fun resetMetrics() {
        totalIntercepted = 0
        totalProxied = 0
        totalDirect = 0
        totalErrors = 0
        interceptedCount.clear()
    }
}
