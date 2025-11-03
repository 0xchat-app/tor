import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tor/proxy_support.dart';

typedef ProxyChangeCallback = void Function(ProxyInfo? proxy);

/// System proxy monitor with change detection
///
/// Periodically queries the system proxy and invokes a callback only when
/// the proxy configuration changes. This eliminates redundant updates and
/// provides a reactive interface for proxy management.
///
/// Usage:
/// ```dart
/// final monitor = SystemProxyMonitor(
///   onChanged: (proxy) {
///     if (proxy != null) {
///       debugPrint('Proxy changed: ${proxy.address}:${proxy.port}');
///       // Update your proxy configuration
///     } else {
///       debugPrint('Proxy removed');
///       // Clear proxy configuration
///     }
///   },
/// );
///
/// // Start monitoring (polls every 5 seconds)
/// monitor.start();
///
/// // Stop monitoring
/// monitor.stop();
///
/// // Get current cached proxy (synchronous)
/// final current = monitor.current;
/// ```
class SystemProxyMonitor {
  /// Callback invoked when proxy configuration changes
  final ProxyChangeCallback onChanged;

  /// Polling interval (default: 5 seconds)
  final Duration pollInterval;

  ProxyInfo? _current;
  DateTime? _lastUpdateTime;
  Timer? _pollTimer;
  int _pollCount = 0;

  /// Create a new system proxy monitor
  ///
  /// [onChanged] - Callback invoked when proxy changes (required)
  /// [pollInterval] - How often to check for changes (default: 5 seconds)
  SystemProxyMonitor({
    required this.onChanged,
    this.pollInterval = const Duration(seconds: 5),
  });

  /// Get current cached proxy (synchronous)
  ProxyInfo? get current => _current;

  /// Get last update time
  DateTime? get lastUpdateTime => _lastUpdateTime;

  /// Check if monitor is running
  bool get isRunning => _pollTimer != null;

  /// Get poll count (for debugging)
  int get pollCount => _pollCount;

  /// Start monitoring system proxy
  void start() {
    if (_pollTimer != null) {
      debugPrint('[ProxyMonitor] Already running');
      return;
    }

    debugPrint('[ProxyMonitor] Starting (interval: ${pollInterval.inSeconds}s)');

    // Initial check
    _checkForChanges();

    // Periodic checks
    _pollTimer = Timer.periodic(pollInterval, (_) => _checkForChanges());
  }

  /// Stop monitoring
  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    debugPrint('[ProxyMonitor] Stopped (polls: $_pollCount)');
  }

  /// Force an immediate check for changes
  Future<void> checkNow() async {
    await _checkForChanges();
  }

  /// Check for proxy changes and invoke callback if changed
  Future<void> _checkForChanges() async {
    try {
      final newProxy = await SystemProxy.getCurrent();
      _pollCount++;

      // Check if proxy changed
      if (_hasChanged(newProxy, _current)) {
        final oldProxy = _current;
        _current = newProxy;
        _lastUpdateTime = DateTime.now();

        // Log the change
        if (kDebugMode) {
          if (newProxy != null) {
            if (oldProxy != null) {
              debugPrint('[ProxyMonitor] 🔄 Proxy CHANGED: ${oldProxy.address}:${oldProxy.port} → ${newProxy.address}:${newProxy.port}');
            } else {
              debugPrint('[ProxyMonitor] ✅ Proxy DETECTED: ${newProxy.address}:${newProxy.port} (${newProxy.type.name})');
            }
          } else {
            if (oldProxy != null) {
              debugPrint('[ProxyMonitor] ❌ Proxy REMOVED (was: ${oldProxy.address}:${oldProxy.port})');
            }
          }
        }

        // Invoke change callback
        onChanged(newProxy);
      } else {
        // Log periodic status (every 12 checks = 1 minute)
        if (kDebugMode && _pollCount % 12 == 0) {
          if (_current != null) {
            debugPrint('[ProxyMonitor] ✓ No change: ${_current!.address}:${_current!.port} (polls: $_pollCount)');
          } else {
            debugPrint('[ProxyMonitor] ✓ No proxy configured (polls: $_pollCount)');
          }
        }
      }
    } catch (e) {
      debugPrint('[ProxyMonitor] ✗ Check failed: $e');
    }
  }

  /// Check if proxy configuration has changed
  bool _hasChanged(ProxyInfo? newProxy, ProxyInfo? oldProxy) {
    if (newProxy == null && oldProxy == null) return false;
    if (newProxy == null || oldProxy == null) return true;

    return newProxy.address != oldProxy.address ||
        newProxy.port != oldProxy.port ||
        newProxy.type != oldProxy.type;
  }

  /// Get statistics for debugging
  Map<String, dynamic> getStats() {
    return {
      'running': isRunning,
      'polls': _pollCount,
      'current_proxy': _current != null
          ? '${_current!.address}:${_current!.port} (${_current!.type.name})'
          : 'none',
      'last_update': _lastUpdateTime?.toIso8601String() ?? 'never',
    };
  }
}