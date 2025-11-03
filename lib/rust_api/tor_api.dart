// SPDX-FileCopyrightText: 2025 0xChat
//
// SPDX-License-Identifier: MIT

import 'generated/api/tor.dart';
import 'generated/api/types.dart';

/// Dart-side API wrapper for calling Rust Tor functions via FRB
/// 
/// All APIs are now 100% FRB - no FFI callbacks needed!
class TorApi {
  /// Test hello function
  static Future<String> hello() => torHelloFrb();

  /// Start Tor service
  /// 
  /// Parameters:
  /// - [socksPort]: SOCKS proxy port
  /// - [stateDir]: State directory path
  /// - [cacheDir]: Cache directory path
  /// - [useSystemProxy]: Whether to use system proxy (default: true)
  /// 
  /// When useSystemProxy is true, Tor will read proxy from global state.
  /// Use TorApi.setProxy() to update the proxy configuration.
  /// 
  /// Returns the actual port number on success.
  static Future<int> start({
    required int socksPort,
    required String stateDir,
    required String cacheDir,
    bool useSystemProxy = true,
  }) async {
    return await torStartFrb(
      socksPort: socksPort,
      stateDir: stateDir,
      cacheDir: cacheDir,
      useSystemProxy: useSystemProxy,
    );
  }

  /// Update current proxy configuration
  /// 
  /// Pass null to clear proxy (use direct connection).
  /// Pass ProxyInfo to set/update proxy.
  /// 
  /// This can be called while Tor is running to update proxy dynamically.
  /// 
  /// Example:
  /// ```dart
  /// // Set SOCKS5 proxy
  /// TorApi.setProxy(ProxyInfo(
  ///   address: '127.0.0.1',
  ///   port: 1080,
  ///   proxyType: ProxyType.socks5,
  ///   username: null,
  ///   password: null,
  /// ));
  /// 
  /// // Clear proxy (use direct connection)
  /// TorApi.setProxy(null);
  /// ```
  static void setProxy(ProxyInfo? proxy) {
    torSetProxyFrb(proxy: proxy);
  }

  /// Stop Tor service
  static Future<void> stop() => torStopFrb();

  /// Set dormant mode
  static Future<void> setDormant({required bool softMode}) =>
      torSetDormantFrb(softMode: softMode);
}

