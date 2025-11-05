import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:tor/platform/system_proxy_channel.dart';

export 'package:tor/platform/system_proxy_channel.dart' show ProxyConfigInfo;

enum ProxyType {
  none(0),
  socks5(1),
  httpConnect(2);

  final int value;
  const ProxyType(this.value);
}

/// Proxy authentication credentials
class ProxyAuth {
  final String username;
  final String password;

  const ProxyAuth({
    required this.username,
    required this.password,
  });
}

/// Base class for proxy configuration
abstract class ProxyConfiguration {
  const ProxyConfiguration();

  /// Create a configuration with no proxy (direct connection)
  factory ProxyConfiguration.direct() = DirectProxyConfiguration;

  /// Create a static proxy configuration
  factory ProxyConfiguration.static({
    required String address,
    required int port,
    required ProxyType type,
    ProxyAuth? auth,
  }) = StaticProxyConfiguration;

  /// Create a dynamic proxy configuration with callback
  factory ProxyConfiguration.dynamic(
      ProxyResolveCallback callback,
      ) = DynamicProxyConfiguration;

  /// Create a configuration that uses system proxy settings
  factory ProxyConfiguration.system() = SystemProxyConfiguration;
}

/// Direct connection (no proxy)
class DirectProxyConfiguration extends ProxyConfiguration {
  const DirectProxyConfiguration();
}

/// Static proxy configuration
class StaticProxyConfiguration extends ProxyConfiguration {
  final String address;
  final int port;
  final ProxyType type;
  final ProxyAuth? auth;

  const StaticProxyConfiguration({
    required this.address,
    required this.port,
    required this.type,
    this.auth,
  });

  /// Get the proxy address in "IP:PORT" format
  String get fullAddress => '$address:$port';
}

/// Dynamic proxy configuration with callback
class DynamicProxyConfiguration extends ProxyConfiguration {
  final ProxyResolveCallback callback;

  const DynamicProxyConfiguration(this.callback);
}

/// System proxy configuration (reads OS proxy settings)
class SystemProxyConfiguration extends ProxyConfiguration {
  const SystemProxyConfiguration();
}

typedef ProxyResolveCallback = ProxyInfo? Function(
    String targetAddress,
    int targetPort,
    );

/// Proxy information returned by callback
class ProxyInfo {
  final String address;
  final int port;
  final ProxyType type;
  final ProxyAuth? auth;

  const ProxyInfo({
    required this.address,
    required this.port,
    required this.type,
    this.auth,
  });

  String get fullAddress => '$address:$port';
}

typedef NativeProxyCallback = Bool Function(
    Pointer<Void> context,
    Pointer<Utf8> targetAddr,
    Uint16 targetPort,
    Pointer<Pointer<Utf8>> outProxyAddr,
    Pointer<Uint8> outProxyType,
    );

typedef NativeProxyCallbackDart = bool Function(
    Pointer<Void> context,
    Pointer<Utf8> targetAddr,
    int targetPort,
    Pointer<Pointer<Utf8>> outProxyAddr,
    Pointer<Uint8> outProxyType,
    );

/// Proxy callback manager for FFI
class ProxyCallbackManager {
  static final Map<int, ProxyResolveCallback> _callbacks = {};
  static int _nextId = 0;

  /// Register a Dart callback and return an ID
  static int registerCallback(ProxyResolveCallback callback) {
    final id = _nextId++;
    _callbacks[id] = callback;
    return id;
  }

  /// Unregister a callback
  static void unregisterCallback(int id) {
    _callbacks.remove(id);
  }

  /// Get the native callback function pointer
  static Pointer<NativeFunction<NativeProxyCallback>> getNativeCallback() {
    return Pointer.fromFunction<NativeProxyCallback>(
      _nativeCallbackStatic,
      false,
    );
  }

  /// Native callback handler (static)
  static bool _nativeCallbackStatic(
      Pointer<Void> context,
      Pointer<Utf8> targetAddr,
      int targetPort,
      Pointer<Pointer<Utf8>> outProxyAddr,
      Pointer<Uint8> outProxyType,
      ) {
    try {
      final callbackId = context.address;
      final callback = _callbacks[callbackId];

      if (callback == null) {
        return false; // Use direct connection
      }

      final targetAddressStr = targetAddr.toDartString();
      final proxyInfo = callback(targetAddressStr, targetPort);

      if (proxyInfo == null) {
        return false; // Use direct connection
      }

      // Allocate C string for proxy address (caller will free it)
      final proxyAddrStr = '${proxyInfo.address}:${proxyInfo.port}';
      final proxyAddrUtf8 = proxyAddrStr.toNativeUtf8();
      outProxyAddr.value = proxyAddrUtf8.cast();
      outProxyType.value = proxyInfo.type.value;

      return true; // Use proxy
    } catch (e) {
      debugPrint('Error in proxy callback: $e');
      return false;
    }
  }
}

/// Helper to get system proxy settings
class SystemProxy {
  /// Get current system proxy configuration
  ///
  /// Returns the best available proxy based on priority:
  /// 1. SOCKS5 (best for Tor)
  /// 2. HTTPS
  /// 3. HTTP
  ///
  /// Returns null if no proxy is configured
  static Future<ProxyInfo?> getCurrent() async {
    // Platform-specific implementation
    if (Platform.isAndroid || Platform.isIOS) {
      return await _getMobileProxy();
    } else if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      return await _getDesktopProxy();
    }
    return null;
  }

  /// Get all system proxy configurations (http, https, socks5)
  ///
  /// This method returns all available proxy types, allowing the caller
  /// to choose which one to use based on their specific needs.
  ///
  /// Returns a Map with keys: 'http', 'https', 'socks5'
  /// Each value contains host, port, username, password (empty if not configured)
  static Future<Map<String, ProxyConfigInfo>> getAllProxyConfigs() async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        return await SystemProxyChannel.getSystemProxy();
      } catch (e) {
        debugPrint('Failed to get all proxy configs: $e');
        return {
          'http': ProxyConfigInfo.empty(),
          'https': ProxyConfigInfo.empty(),
          'socks5': ProxyConfigInfo.empty(),
        };
      }
    } else {
      // Desktop platforms - parse from environment variables
      return _getDesktopProxyConfigs();
    }
  }

  /// Asynchronously get mobile proxy settings
  ///
  /// This method uses platform channels to query native iOS/Android APIs.
  /// Returns the best available proxy based on priority (SOCKS5 > HTTPS > HTTP).
  ///
  /// Protocol mapping:
  /// - SOCKS5 proxy → SOCKS5 protocol (native support)
  /// - HTTP/HTTPS proxy → HTTP CONNECT protocol (standard for HTTPS tunneling)
  static Future<ProxyInfo?> _getMobileProxy() async {
    try {
      final allProxies = await SystemProxyChannel.getSystemProxy();

      // Priority: SOCKS5 > HTTPS > HTTP
      final socks5 = allProxies['socks5'];
      if (socks5 != null && socks5.isConfigured) {
        return ProxyInfo(
          address: socks5.host,
          port: socks5.port,
          type: ProxyType.socks5,
          auth: socks5.auth,
        );
      }

      // For HTTP/HTTPS proxies, use HTTP CONNECT protocol
      final https = allProxies['https'];
      if (https != null && https.isConfigured) {
        return ProxyInfo(
          address: https.host,
          port: https.port,
          type: ProxyType.httpConnect,  // Use HTTP CONNECT protocol
          auth: https.auth,
        );
      }

      final http = allProxies['http'];
      if (http != null && http.isConfigured) {
        return ProxyInfo(
          address: http.host,
          port: http.port,
          type: ProxyType.httpConnect,  // Use HTTP CONNECT protocol
          auth: http.auth,
        );
      }

      return null;
    } catch (e) {
      debugPrint('Failed to get mobile proxy: $e');
      return null;
    }
  }

  /// Check if VPN is active on mobile
  static Future<bool> isVpnActive() async {
    try {
      return await SystemProxyChannel.isVpnActive();
    } catch (e) {
      debugPrint('Failed to check VPN status: $e');
      return false;
    }
  }

  static Future<ProxyInfo?> _getDesktopProxy() async {
    // Try to read proxy from environment variables
    // Priority: SOCKS5 > HTTPS > HTTP
    final socksProxy = Platform.environment['SOCKS_PROXY'] ??
        Platform.environment['socks_proxy'];
    final httpsProxy = Platform.environment['HTTPS_PROXY'] ??
        Platform.environment['https_proxy'];
    final httpProxy = Platform.environment['HTTP_PROXY'] ??
        Platform.environment['http_proxy'];

    // Try SOCKS5 first (best for Tor)
    if (socksProxy != null && socksProxy.isNotEmpty) {
      final parsed = _parseProxyUrl(socksProxy);
      if (parsed != null) return parsed;
    }

    // Try HTTPS second
    if (httpsProxy != null && httpsProxy.isNotEmpty) {
      final parsed = _parseProxyUrl(httpsProxy);
      if (parsed != null) return parsed;
    }

    // Try HTTP last
    if (httpProxy != null && httpProxy.isNotEmpty) {
      final parsed = _parseProxyUrl(httpProxy);
      if (parsed != null) return parsed;
    }

    return null;
  }

  /// Get all desktop proxy configurations
  static Map<String, ProxyConfigInfo> _getDesktopProxyConfigs() {
    final socksProxy = Platform.environment['SOCKS_PROXY'] ??
        Platform.environment['socks_proxy'];
    final httpsProxy = Platform.environment['HTTPS_PROXY'] ??
        Platform.environment['https_proxy'];
    final httpProxy = Platform.environment['HTTP_PROXY'] ??
        Platform.environment['http_proxy'];

    return {
      'http': _parseEnvProxyConfig(httpProxy),
      'https': _parseEnvProxyConfig(httpsProxy),
      'socks5': _parseEnvProxyConfig(socksProxy),
    };
  }

  /// Parse environment variable proxy config to ProxyConfigInfo
  static ProxyConfigInfo _parseEnvProxyConfig(String? proxyUrl) {
    if (proxyUrl == null || proxyUrl.isEmpty) {
      return ProxyConfigInfo.empty();
    }

    final parsed = _parseProxyUrl(proxyUrl);
    if (parsed == null) {
      return ProxyConfigInfo.empty();
    }

    return ProxyConfigInfo(
      host: parsed.address,
      port: parsed.port,
      username: parsed.auth?.username ?? '',
      password: parsed.auth?.password ?? '',
    );
  }

  /// Parse proxy URL in format: scheme://[user:pass@]host:port
  static ProxyInfo? _parseProxyUrl(String proxyUrl) {
    try {
      final uri = Uri.parse(proxyUrl);
      final scheme = uri.scheme.toLowerCase();
      ProxyType type;

      if (scheme == 'socks5' || scheme == 'socks') {
        type = ProxyType.socks5;
      } else if (scheme == 'http' || scheme == 'https') {
        type = ProxyType.httpConnect;
      } else {
        return null;
      }

      final host = uri.host;
      if (host.isEmpty) {
        return null;
      }

      final port = uri.port != 0 ? uri.port : (scheme == 'https' ? 443 : 80);

      ProxyAuth? auth;
      if (uri.userInfo.isNotEmpty) {
        final parts = uri.userInfo.split(':');
        if (parts.length == 2) {
          auth = ProxyAuth(username: parts[0], password: parts[1]);
        }
      }

      return ProxyInfo(
        address: host,
        port: port,
        type: type,
        auth: auth,
      );
    } catch (e) {
      debugPrint('Failed to parse proxy URL: $e');
      return null;
    }
  }
}