// SPDX-FileCopyrightText: 2024 Cypher Stack LLC
//
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A SOCKS5 socket.
///
/// A Dart 3 Socket wrapper that implements the SOCKS5 protocol.  Now with SSL!
///
/// Properties:
///  - [proxyHost]: The host of the SOCKS5 proxy server.
///  - [proxyPort]: The port of the SOCKS5 proxy server.
///  - [_socksSocket]: The underlying Socket that connects to the SOCKS5 proxy
///  server.
///  - [_responseController]: A StreamController that listens to the
///  [_socksSocket] and broadcasts the response.
///
/// Methods:
/// - connect: Connects to the SOCKS5 proxy server.
/// - connectTo: Connects to the specified [domain] and [port] through the
/// SOCKS5 proxy server.
/// - write: Converts [object] to a String by invoking [Object.toString] and
/// sends the encoding of the result to the socket.
/// - sendServerFeaturesCommand: Sends the server.features command to the
/// proxy server.
/// - close: Closes the connection to the Tor proxy.
///
/// Usage:
/// ```dart
/// // Instantiate a socks socket at localhost and on the port selected by the
/// // tor service.
/// var socksSocket = await SOCKSSocket.create(
///  proxyHost: InternetAddress.loopbackIPv4.address,
///  proxyPort: tor.port,
///  // sslEnabled: true, // For SSL connections.
///  );
///
/// // Connect to the socks instantiated above.
/// await socksSocket.connect();
///
/// // Connect to bitcoincash.stackwallet.com on port 50001 via socks socket.
/// await socksSocket.connectTo(
/// 'bitcoincash.stackwallet.com', 50001);
///
/// // Send a server features command to the connected socket, see method for
/// // more specific usage example..
/// await socksSocket.sendServerFeaturesCommand();
/// await socksSocket.close();
/// ```
///
/// See also:
/// - SOCKS5 protocol(https://www.ietf.org/rfc/rfc1928.txt)
class SOCKSSocket {
  /// The host of the SOCKS5 proxy server.
  final String proxyHost;

  /// The port of the SOCKS5 proxy server.
  final int proxyPort;

  /// The underlying Socket that connects to the SOCKS5 proxy server.
  late final Socket _socksSocket;

  /// Getter for the underlying Socket that connects to the SOCKS5 proxy server.
  Socket get socket => sslEnabled ? _secureSocksSocket : _socksSocket;

  /// A wrapper around the _socksSocket that enables SSL connections.
  late final Socket _secureSocksSocket;

  /// A StreamController that listens to the _socksSocket and broadcasts.
  final StreamController<List<int>> _responseController =
      StreamController.broadcast();

  /// A StreamController that listens to the _secureSocksSocket and broadcasts.
  final StreamController<List<int>> _secureResponseController =
      StreamController.broadcast();

  /// Getter for the StreamController that listens to the _socksSocket and
  /// broadcasts, or the _secureSocksSocket and broadcasts if SSL is enabled.
  StreamController<List<int>> get responseController =>
      sslEnabled ? _secureResponseController : _responseController;

  /// A StreamSubscription that listens to the _socksSocket or the
  /// _secureSocksSocket if SSL is enabled.
  StreamSubscription<List<int>>? _subscription;

  /// Getter for the StreamSubscription that listens to the _socksSocket or the
  /// _secureSocksSocket if SSL is enabled.
  StreamSubscription<List<int>>? get subscription => _subscription;

  /// Is SSL enabled?
  final bool sslEnabled;

  /// Private constructor.
  SOCKSSocket._(this.proxyHost, this.proxyPort, this.sslEnabled);

  /// Provides a stream of data as `List<int>`.
  Stream<List<int>> get inputStream => sslEnabled
      ? _secureResponseController.stream
      : _responseController.stream;

  /// Provides a StreamSink compatible with `List<int>` for sending data.
  StreamSink<List<int>> get outputStream {
    // Create a simple StreamSink wrapper for _socksSocket and
    // _secureSocksSocket that accepts List<int> and forwards it to write method.
    var sink = StreamController<List<int>>();
    sink.stream.listen((data) {
      if (sslEnabled) {
        _secureSocksSocket.add(data);
      } else {
        _socksSocket.add(data);
      }
    });
    return sink.sink;
  }

  /// Creates a SOCKS5 socket to the specified [proxyHost] and [proxyPort].
  ///
  /// This method is a factory constructor that returns a Future that resolves
  /// to a SOCKSSocket instance.
  ///
  /// Parameters:
  /// - [proxyHost]: The host of the SOCKS5 proxy server.
  /// - [proxyPort]: The port of the SOCKS5 proxy server.
  ///
  /// Returns:
  ///  A Future that resolves to a SOCKSSocket instance.
  static Future<SOCKSSocket> create(
      {required String proxyHost,
      required int proxyPort,
      bool sslEnabled = false}) async {
    // Create a SOCKS socket instance.
    var instance = SOCKSSocket._(proxyHost, proxyPort, sslEnabled);

    // Initialize the SOCKS socket.
    await instance._init();

    // Return the SOCKS socket instance.
    return instance;
  }

  /// Constructor.
  SOCKSSocket(
      {required this.proxyHost,
      required this.proxyPort,
      required this.sslEnabled}) {
    _init();
  }

  /// Initializes the SOCKS socket.
  ///
  /// This method is a private method that is called by the constructor.
  ///
  /// Returns:
  ///   A Future that resolves to void.
  Future<void> _init() async {
    // Connect to the SOCKS proxy server.
    _socksSocket = await Socket.connect(
      proxyHost,
      proxyPort,
    );

    // Listen to the socket.
    _subscription = _socksSocket.listen(
      (data) {
        // Add the data to the response controller.
        _responseController.add(data);
      },
      onError: (e) {
        // Handle errors.
        if (e is Object) {
          _responseController.addError(e);
        }

        // If the error is not an object, send the error as a string.
        _responseController.addError("$e");
        // TODO make sure sending error as string is acceptable.
      },
      onDone: () {
        // Close the response controller when the socket is closed.
        // _responseController.close();
      },
    );
  }

  /// Connects to the SOCKS socket.
  ///
  /// Returns:
  ///  A Future that resolves to void.
  Future<void> connect() async {
    // Greeting and method selection.
    _socksSocket.add([0x05, 0x01, 0x00]);

    // Wait for server response.
    var response = await _responseController.stream.first;

    // Check if the connection was successful.
    if (response[1] != 0x00) {
      throw Exception(
          'socks_socket.connect(): Failed to connect to SOCKS5 proxy.');
    }

    return;
  }

  /// Connects to the specified [domain] and [port] through the SOCKS socket.
  ///
  /// Parameters:
  /// - [domain]: The domain to connect to.
  /// - [port]: The port to connect to.
  ///
  /// Returns:
  ///   A Future that resolves to void.
  Future<void> connectTo(String domain, int port) async {
    // Connect command.
    var request = [
      0x05, // SOCKS version.
      0x01, // Connect command.
      0x00, // Reserved.
      0x03, // Domain name.
      domain.length,
      ...domain.codeUnits,
      (port >> 8) & 0xFF,
      port & 0xFF
    ];


    debugPrint('[SOCKS5] Connecting to $domain:$port via SOCKS proxy at $proxyHost:$proxyPort');

    // Send the connect command to the SOCKS proxy server.
    _socksSocket.add(request);

    // Wait for server response.
    var response = await _responseController.stream.first;


    debugPrint('[SOCKS5] Response: ${response.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    debugPrint('[SOCKS5] Response length: ${response.length}, version: 0x${response[0].toRadixString(16)}, reply: 0x${response[1].toRadixString(16)}');

    // Validate SOCKS5 response
    if (response.length < 2) {
      throw Exception(
          'socks_socket.connectTo(): Invalid SOCKS5 response (too short: ${response.length} bytes)');
    }

    if (response[0] != 0x05) {
      throw Exception(
          'socks_socket.connectTo(): Invalid SOCKS5 version in response: 0x${response[0].toRadixString(16)} (expected 0x05)');
    }

    // Check if the connection was successful.
    if (response[1] != 0x00) {
      final errorCode = response[1];
      final errorMsg = _getSocks5ErrorMessage(errorCode);
      final text = 'socks_socket.connectTo(): Failed to connect to $domain:$port through SOCKS5 proxy. '
          'Error code: 0x${errorCode.toRadixString(16)} ($errorMsg). '
          'Full response: ${response.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}';
      debugPrint('[SOCKS5] Exception: $text');
      throw Exception(
          text);
    }


    debugPrint('[SOCKS5] ✓ Successfully connected to $domain:$port');

    // Upgrade to SSL if needed.
    if (sslEnabled) {
      // Upgrade to SSL.
      _secureSocksSocket = await SecureSocket.secure(
        _socksSocket,
        host: domain,
        // onBadCertificate: (_) => true, // Uncomment this to bypass certificate validation (NOT recommended for production).
      );

      // Listen to the secure socket.
      _subscription = _secureSocksSocket.listen(
        (data) {
          // Add the data to the response controller.
          _secureResponseController.add(data);
        },
        onError: (e) {
          // Handle errors.
          if (e is Object) {
            _secureResponseController.addError(e);
          }

          // If the error is not an object, send the error as a string.
          _secureResponseController.addError("$e");
          // TODO make sure sending error as string is acceptable.
        },
        onDone: () {
          // Close the response controller when the socket is closed.
          _secureResponseController.close();
        },
      );
    }

    return;
  }

  /// Converts [object] to a String by invoking [Object.toString] and
  /// sends the encoding of the result to the socket.
  ///
  /// Parameters:
  /// - [object]: The object to write to the socket.
  ///
  /// Returns:
  ///  A Future that resolves to void.
  void write(Object? object) {
    // Don't write null.
    if (object == null) return;

    // Write the data to the socket.
    List<int> data = utf8.encode(object.toString());
    if (sslEnabled) {
      _secureSocksSocket.add(data);
    } else {
      _socksSocket.add(data);
    }
  }

  /// Closes the connection to the Tor proxy.
  ///
  /// Returns:
  ///  A Future that resolves to void.
  Future<void> close() async {
    // Ensure all data is sent before closing.
    try {
      if (sslEnabled) {
        await _secureSocksSocket.flush();
      }
      await _socksSocket.flush();
    } finally {
      await _subscription?.cancel();
      await _socksSocket.close();
      _responseController.close();
      if (sslEnabled) {
        _secureResponseController.close();
      }
    }
  }

  StreamSubscription<List<int>> listen(
    void Function(List<int> data)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return sslEnabled
        ? _secureResponseController.stream.listen(
            onData,
            onError: onError,
            onDone: onDone,
            cancelOnError: cancelOnError,
          )
        : _responseController.stream.listen(
            onData,
            onError: onError,
            onDone: onDone,
            cancelOnError: cancelOnError,
          );
  }

  /// Get human-readable SOCKS5 error message
  String _getSocks5ErrorMessage(int errorCode) {
    switch (errorCode) {
      case 0x00:
        return 'succeeded';
      case 0x01:
        return 'general SOCKS server failure';
      case 0x02:
        return 'connection not allowed by ruleset';
      case 0x03:
        return 'Network unreachable';
      case 0x04:
        return 'Host unreachable';
      case 0x05:
        return 'Connection refused';
      case 0x06:
        return 'TTL expired';
      case 0x07:
        return 'Command not supported';
      case 0x08:
        return 'Address type not supported';
      default:
        return 'Unknown error';
    }
  }

  /// Sends the server.features command to the proxy server.
  ///
  /// This demos how to send the server.features command.  Use as an example
  /// for sending other commands.
  ///
  /// Returns:
  ///   A Future that resolves to void.
  Future<void> sendServerFeaturesCommand() async {
    // The server.features command.
    const String command =
        '{"jsonrpc":"2.0","id":"0","method":"server.features","params":[]}';

    if (!sslEnabled) {
      // Send the command to the proxy server.
      _socksSocket.writeln(command);

      // Wait for the response from the proxy server.
      var responseData = await _responseController.stream.first;
      if (kDebugMode) {
        debugPrint("responseData: ${utf8.decode(responseData)}");
      }
    } else {
      // Send the command to the proxy server.
      _secureSocksSocket.writeln(command);

      // Wait for the response from the proxy server.
      var responseData = await _secureResponseController.stream.first;
      if (kDebugMode) {
        debugPrint("secure responseData: ${utf8.decode(responseData)}");
      }
    }

    return;
  }
}
