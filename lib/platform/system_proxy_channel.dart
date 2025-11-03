import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tor/proxy_support.dart';

class SystemProxyChannel {
  static const MethodChannel _channel = MethodChannel('com.oxchat.tor/system_proxy');

  /// Get current system proxy settings from native platform
  ///
  /// Returns:
  /// - Map with all proxy configurations
  ///   {
  ///     'http': {'host': '...', 'port': 8080, 'username': '...', 'password': '...'},
  ///     'https': {'host': '...', 'port': 8080, 'username': '...', 'password': '...'},
  ///     'socks5': {'host': '...', 'port': 1080, 'username': '...', 'password': '...'}
  ///   }
  /// - Empty strings if a type is not configured
  static Future<Map<String, ProxyConfigInfo>> getSystemProxy() async {
    try {
      final Map<dynamic, dynamic> result =
          await _channel.invokeMethod('getSystemProxy') ?? {};

      return {
        'http': _parseProxyConfig(result['http']),
        'https': _parseProxyConfig(result['https']),
        'socks5': _parseProxyConfig(result['socks5']),
      };
    } catch (e) {
      // Platform channel not implemented or error occurred
      debugPrint('Failed to get system proxy from platform: $e');
      return {
        'http': ProxyConfigInfo.empty(),
        'https': ProxyConfigInfo.empty(),
        'socks5': ProxyConfigInfo.empty(),
      };
    }
  }

  /// Parse individual proxy configuration
  static ProxyConfigInfo _parseProxyConfig(dynamic config) {
    if (config == null || config is! Map) {
      return ProxyConfigInfo.empty();
    }

    final String host = (config['host'] as String?) ?? '';
    final int port = (config['port'] as int?) ?? 0;
    final String username = (config['username'] as String?) ?? '';
    final String password = (config['password'] as String?) ?? '';

    return ProxyConfigInfo(
      host: host,
      port: port,
      username: username,
      password: password,
    );
  }

  /// Check if VPN is currently active
  ///
  /// Returns true if VPN is connected, false otherwise
  static Future<bool> isVpnActive() async {
    try {
      final bool? result = await _channel.invokeMethod('isVpnActive');
      return result ?? false;
    } catch (e) {
      debugPrint('Failed to check VPN status: $e');
      return false;
    }
  }
}

/// Proxy configuration info for a specific type
class ProxyConfigInfo {
  final String host;
  final int port;
  final String username;
  final String password;

  const ProxyConfigInfo({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  factory ProxyConfigInfo.empty() {
    return const ProxyConfigInfo(
      host: '',
      port: 0,
      username: '',
      password: '',
    );
  }

  /// Check if this proxy configuration is valid
  bool get isConfigured => host.isNotEmpty && port > 0;

  /// Check if authentication is configured
  bool get hasAuth => username.isNotEmpty && password.isNotEmpty;

  /// Convert to ProxyAuth if configured
  ProxyAuth? get auth {
    return hasAuth ? ProxyAuth(username: username, password: password) : null;
  }
}