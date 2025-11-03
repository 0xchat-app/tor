package com.oxchat.tor

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.ProxyInfo
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class SystemProxyPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.oxchat.tor/system_proxy")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getSystemProxy" -> {
                val proxyInfo = getSystemProxy()
                result.success(proxyInfo)
            }
            "isVpnActive" -> {
                val isVpnActive = isVpnActive()
                result.success(isVpnActive)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    /**
     * Get system proxy settings
     *
     * Returns a Map with all proxy configurations (http, https, socks5)
     * Each type returns its host and port, or empty string if not configured
     */
    private fun getSystemProxy(): Map<String, Any> {
        val result = mutableMapOf<String, Any>()

        // Initialize empty configurations for all types
        var httpConfig = mutableMapOf<String, Any>(
            "host" to "",
            "port" to 0,
            "username" to "",
            "password" to ""
        )
        var httpsConfig = mutableMapOf<String, Any>(
            "host" to "",
            "port" to 0,
            "username" to "",
            "password" to ""
        )
        var socks5Config = mutableMapOf<String, Any>(
            "host" to "",
            "port" to 0,
            "username" to "",
            "password" to ""
        )

        try {
            // Method 1: Try to get proxy from system properties
            val httpProxyHost = System.getProperty("http.proxyHost")
            val httpProxyPort = System.getProperty("http.proxyPort")

            if (!httpProxyHost.isNullOrEmpty() && !httpProxyPort.isNullOrEmpty()) {
                httpConfig["host"] = httpProxyHost
                httpConfig["port"] = httpProxyPort.toInt()

                // Check for HTTP proxy auth (rare on Android)
                System.getProperty("http.proxyUser")?.let { httpConfig["username"] = it }
                System.getProperty("http.proxyPassword")?.let { httpConfig["password"] = it }
            }

            // HTTPS proxy (usually same as HTTP on Android)
            val httpsProxyHost = System.getProperty("https.proxyHost") ?: httpProxyHost
            val httpsProxyPort = System.getProperty("https.proxyPort") ?: httpProxyPort

            if (!httpsProxyHost.isNullOrEmpty() && !httpsProxyPort.isNullOrEmpty()) {
                httpsConfig["host"] = httpsProxyHost
                httpsConfig["port"] = httpsProxyPort.toInt()

                System.getProperty("https.proxyUser")?.let { httpsConfig["username"] = it }
                System.getProperty("https.proxyPassword")?.let { httpsConfig["password"] = it }
            }

            // SOCKS proxy
            val socksProxyHost = System.getProperty("socksProxyHost")
            val socksProxyPort = System.getProperty("socksProxyPort")

            if (!socksProxyHost.isNullOrEmpty() && !socksProxyPort.isNullOrEmpty()) {
                socks5Config["host"] = socksProxyHost
                socks5Config["port"] = socksProxyPort.toInt()

                System.getProperty("socksProxyUser")?.let { socks5Config["username"] = it }
                System.getProperty("socksProxyPassword")?.let { socks5Config["password"] = it }
            }

            // Method 2: Check environment variables (override if set)
            val envSocksProxy = System.getenv("SOCKS_PROXY") ?: System.getenv("socks_proxy")
            if (!envSocksProxy.isNullOrEmpty()) {
                parseProxyUrl(envSocksProxy)?.let { parsed ->
                    socks5Config["host"] = parsed["host"] ?: ""
                    socks5Config["port"] = parsed["port"] ?: 0
                    socks5Config["username"] = parsed["username"] ?: ""
                    socks5Config["password"] = parsed["password"] ?: ""
                }
            }

            val envHttpProxy = System.getenv("HTTP_PROXY") ?: System.getenv("http_proxy")
            if (!envHttpProxy.isNullOrEmpty()) {
                parseProxyUrl(envHttpProxy)?.let { parsed ->
                    httpConfig["host"] = parsed["host"] ?: ""
                    httpConfig["port"] = parsed["port"] ?: 0
                    httpConfig["username"] = parsed["username"] ?: ""
                    httpConfig["password"] = parsed["password"] ?: ""
                }
            }

            val envHttpsProxy = System.getenv("HTTPS_PROXY") ?: System.getenv("https_proxy")
            if (!envHttpsProxy.isNullOrEmpty()) {
                parseProxyUrl(envHttpsProxy)?.let { parsed ->
                    httpsConfig["host"] = parsed["host"] ?: ""
                    httpsConfig["port"] = parsed["port"] ?: 0
                    httpsConfig["username"] = parsed["username"] ?: ""
                    httpsConfig["password"] = parsed["password"] ?: ""
                }
            }

        } catch (e: Exception) {
            android.util.Log.e("SystemProxyPlugin", "Failed to get system proxy", e)
        }

        // Build final result with all proxy types
        result["http"] = httpConfig
        result["https"] = httpsConfig
        result["socks5"] = socks5Config

        return result
    }

    private fun isVpnActive(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                val activeNetwork = connectivityManager?.activeNetwork

                if (activeNetwork != null) {
                    val capabilities = connectivityManager.getNetworkCapabilities(activeNetwork)
                    capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ?: false
                } else {
                    false
                }
            } else {
                false
            }
        } catch (e: Exception) {
            android.util.Log.e("SystemProxyPlugin", "Failed to check VPN status", e)
            false
        }
    }

    /**
     * Parse proxy URL in format: scheme://[user:pass@]host:port
     */
    private fun parseProxyUrl(url: String): Map<String, Any>? {
        try {
            val uri = java.net.URI(url)
            val host = uri.host ?: return null
            val scheme = uri.scheme?.toLowerCase()

            val port = if (uri.port > 0) uri.port else when (scheme) {
                "https" -> 443
                "http" -> 80
                "socks5", "socks" -> 1080
                else -> 1080
            }

            val result = mutableMapOf<String, Any>(
                "host" to host,
                "port" to port,
                "username" to "",
                "password" to ""
            )

            // Parse authentication
            val userInfo = uri.userInfo
            if (!userInfo.isNullOrEmpty()) {
                val parts = userInfo.split(":")
                if (parts.size == 2) {
                    result["username"] = parts[0]
                    result["password"] = parts[1]
                }
            }

            return result
        } catch (e: Exception) {
            android.util.Log.e("SystemProxyPlugin", "Failed to parse proxy URL: $url", e)
            return null
        }
    }
}