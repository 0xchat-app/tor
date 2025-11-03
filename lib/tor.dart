// SPDX-FileCopyrightText: 2022 Foundation Devices Inc.
// SPDX-FileCopyrightText: 2024 Foundation Devices Inc.
//
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tor/dart_api/bridge_generated.dart/bridge.dart' as frb;
import 'package:tor/dart_api/bridge_generated.dart/frb_generated.dart';
import 'package:tor/dart_api/tor_api.dart';
import 'package:tor/system_proxy_monitor.dart';
import 'package:tor/proxy_support.dart' as proxy_support;

class CouldntBootstrapDirectory implements Exception {
  String? rustError;

  CouldntBootstrapDirectory({this.rustError});
}

class NotSupportedPlatform implements Exception {
  NotSupportedPlatform(String s);
}

class ClientNotActive implements Exception {}

class Tor {
  static const String libName = "tor";
  static bool _frbInitialized = false;

  /// Flag to indicate that Tor client and proxy have started. Traffic is routed through the proxy only if it is also [enabled].
  bool get started => _started;

  /// Getter for the started flag.
  bool _started = false;

  /// Flag to indicate that Tor is currently starting (prevents concurrent starts).
  bool _starting = false;

  /// Flag to indicate that traffic should flow through the proxy.
  bool _enabled = false;

  /// Getter for the enabled flag.
  bool get enabled => _enabled;

  /// Flag to indicate that a Tor circuit is thought to have been established
  /// (true means that Tor has bootstrapped).
  bool get bootstrapped => _bootstrapped;

  /// Getter for the bootstrapped flag.
  bool _bootstrapped = false;

  /// A stream of Tor events.
  ///
  /// This stream broadcast just the port for now (-1 if circuit not established or proxy not enabled)
  final StreamController events = StreamController.broadcast();

  /// Getter for the proxy port.
  ///
  /// Returns -1 if Tor is not enabled or if the circuit is not established.
  ///
  /// Returns the proxy port if Tor is enabled and the circuit is established.
  ///
  /// This is the port that should be used for all requests.
  int get port {
    if (!_enabled) {
      return -1;
    }
    return _proxyPort;
  }

  /// The proxy port.
  int _proxyPort = -1;

  /// System proxy monitor
  SystemProxyMonitor? _proxyMonitor;

  /// Singleton instance of the Tor class.
  static final Tor _instance = Tor._internal();

  /// Getter for the singleton instance of the Tor class.
  static Tor get instance => _instance;

  /// Initialize the Tor ffi lib instance if it hasn't already been set. Nothing
  /// changes if _tor is already been set.
  ///
  /// Returns a Future that completes when the Tor service has started.
  ///
  /// Throws an exception if the Tor service fails to start.
  static Future<Tor> init({bool enabled = true}) async {
    if (!_frbInitialized) {
      await RustLib.init();
      _frbInitialized = true;
      debugPrint('✓ FRB initialized');
    }
    var singleton = Tor._instance;
    singleton._enabled = enabled;
    return singleton;
  }

  /// Private constructor for the Tor class.
  Tor._internal() {
    debugPrint("Instance of Tor created!");
  }

  /// Start the Tor service.
  Future<void> enable() async {
    _enabled = true;
    if (!started && !_starting) {
      _starting = true;
      try {
        await start();
      } finally {
        _starting = false;
      }
    }
    broadcastState();
  }

  void broadcastState() {
    events.add(port);
  }

  Future<int> _getRandomUnusedPort({List<int> excluded = const []}) async {
    var random = Random.secure();
    int potentialPort = 0;

    retry:
    while (potentialPort <= 0 || excluded.contains(potentialPort)) {
      potentialPort = random.nextInt(65535);
      try {
        var socket = await ServerSocket.bind("0.0.0.0", potentialPort);
        socket.close();
        return potentialPort;
      } catch (_) {
        continue retry;
      }
    }

    return -1;
  }

  /// Start the Tor service.
  ///
  /// Parameters:
  /// - [useSystemProxy]: Whether to use system proxy (default: true)
  /// - [canRetryWithError]: Whether to retry on certain errors (default: true)
  ///
  /// When useSystemProxy is true:
  /// - System proxy is queried every 5 seconds
  /// - Dart calls TorApi.setProxy() to update Rust-side proxy state
  /// - Rust reads from this state for EACH network connection
  /// - Automatically adapts to proxy changes
  /// - Supports SOCKS5 and HTTP CONNECT proxies
  /// - Falls back to direct connection if no proxy is configured
  ///
  /// When useSystemProxy is false:
  /// - All connections use direct connection (no proxy)
  /// - Faster startup and lower overhead
  /// - Use for testing or when proxy is explicitly not wanted
  ///
  /// Throws an exception if the Tor service fails to start.
  Future<void> start({
    bool useSystemProxy = true,
    bool canRetryWithError = true,
  }) async {
    // Prevent concurrent starts
    if (_started || _starting) {
      return;
    }

    _starting = true;

    // Set the state and cache directories.
    final Directory appSupportDir = await getApplicationSupportDirectory();
    final stateDir = await Directory('${appSupportDir.path}/tor_state').create();
    final cacheDir = await Directory('${appSupportDir.path}/tor_cache').create();

    try {
      // Generate a random port.
      int newPort = await _getRandomUnusedPort();

      // Setup system proxy monitor if enabled
      if (useSystemProxy) {
        _startProxyMonitor();

        debugPrint('🔄 Tor: Starting with system proxy support');
        debugPrint('🔄 Tor: Proxy changes will be detected automatically');
      } else {
        debugPrint('🔄 Tor: Starting in direct connection mode (no proxy)');
      }

      // Call Rust start function via FRB
      final actualPort = await TorApi.start(
        socksPort: newPort,
        stateDir: stateDir.path,
        cacheDir: cacheDir.path,
        useSystemProxy: useSystemProxy,
      );

      // Set the started flag.
      _started = true;
      _bootstrapped = true;

      if (useSystemProxy) {
        debugPrint('✓ Tor: Client started with system proxy support (FRB)');
        debugPrint('✓ Tor: SOCKS proxy listening on port $actualPort');
        debugPrint('✓ Tor: Monitoring system proxy changes');

        // Display initial proxy status
        final stats = _proxyMonitor?.getStats();
        debugPrint('📊 Proxy monitor stats: $stats');
      } else {
        debugPrint('✓ Tor: Client started in direct mode (no proxy)');
        debugPrint('✓ Tor: SOCKS proxy listening on port $actualPort');
      }

      // Set the proxy port.
      _proxyPort = actualPort;
      broadcastState();
    } catch (e) {
      debugPrint('❌ Tor: Failed to start - $e');

      if (e.toString().contains('Error setting up the guard manager')) {
        await Future.wait([
          stateDir.delete(recursive: true),
          cacheDir.delete(recursive: true),
        ]);

        if (canRetryWithError) {
          debugPrint('🔄 Tor: Retrying after cleaning state directories');
          await start(useSystemProxy: useSystemProxy, canRetryWithError: false);
        }
      } else {
        rethrow;
      }
    } finally {
      _starting = false;
    }
  }

  /// Start system proxy monitor
  void _startProxyMonitor() {
    // Stop existing monitor if any
    _proxyMonitor?.stop();

    // Create monitor with callback
    _proxyMonitor = SystemProxyMonitor(
      onChanged: _onProxyChanged,
      pollInterval: const Duration(seconds: 5),
    );

    // Start monitoring
    _proxyMonitor!.start();
  }

  /// Callback invoked when system proxy changes
  void _onProxyChanged(proxy_support.ProxyInfo? proxy) {
    if (proxy != null) {
      // Convert from proxy_support.ProxyInfo to FRB ProxyInfo
      final frbProxyInfo = frb.ProxyInfo(
        address: proxy.address,
        port: proxy.port,
        proxyType: proxy.type.name == 'socks5'
            ? frb.ProxyType.socks5
            : frb.ProxyType.httpConnect,
        username: null,
        password: null,
      );

      debugPrint('[Tor] 🔄 Proxy changed, updating Rust: ${proxy.address}:${proxy.port} (${proxy.type.name})');

      TorApi.setProxy(frbProxyInfo);

      debugPrint('[Tor] ✅ Rust proxy updated');
    } else {
      debugPrint('[Tor] 🔄 Proxy removed, clearing Rust proxy');

      // Clear proxy (use direct connection)
      TorApi.setProxy(null);

      debugPrint('[Tor] ✅ Rust proxy cleared (direct connection)');
    }
  }

  /// Bootstrap the Tor service.
  ///
  /// This will bootstrap the Tor service and establish a Tor circuit.  This
  /// function should only be called after the Tor service has been started.
  ///
  /// This function will block until the Tor service has bootstrapped.
  ///
  /// Throws an exception if the Tor service fails to bootstrap.
  ///
  /// Returns void.
  void bootstrap() {
    // Bootstrap is handled internally by create_bootstrapped() in Rust
    // No separate bootstrap call needed for FRB version
    debugPrint('✓ Tor: Bootstrap called (handled internally)');
  }

  /// Prevent traffic flowing through the proxy
  void disable() {
    _enabled = false;
    broadcastState();
  }

  /// Stops the proxy
  Future<void> stop() async {
    // Stop proxy monitor
    _proxyMonitor?.stop();
    _proxyMonitor = null;

    await TorApi.stop();
    _started = false;
    _bootstrapped = false;
    _proxyPort = -1;
    broadcastState();
  }

  Future<void> setClientDormant(bool dormant) async {
    if (!started || !bootstrapped) {
      throw ClientNotActive();
    }

    await TorApi.setDormant(softMode: dormant);
  }
}