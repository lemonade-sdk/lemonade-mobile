import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lemonade_mobile/models/discovered_server.dart';

class BeaconListenerService {
  /// Default UDP port to listen on. Must match the port used by
  /// the Lemonade server's NetworkBeacon::startBroadcasting() call.
  static const int defaultPort = 8000;

  RawDatagramSocket? _socket;
  Timer? _pollTimer;
  bool _isListening = false;
  final int _port;
  int _packetCount = 0;

  final _discoveredController = StreamController<DiscoveredServer>.broadcast();
  Stream<DiscoveredServer> get onServerDiscovered =>
      _discoveredController.stream;

  bool get isListening => _isListening;

  BeaconListenerService({int port = defaultPort}) : _port = port;

  Future<void> startListening() async {
    if (_isListening) return;

    try {
      debugPrint('BeaconListener: Binding UDP socket to 0.0.0.0:$_port');
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _port,
        reuseAddress: true,
      );
      _socket!.broadcastEnabled = true;
      _isListening = true;
      _packetCount = 0;
      debugPrint('BeaconListener: Listening on 0.0.0.0:$_port (polling mode)');

      // Poll the socket every second for incoming datagrams
      _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _pollSocket();
      });
    } catch (e) {
      debugPrint('BeaconListener: Failed to bind socket: $e');
      _isListening = false;
      rethrow;
    }
  }

  void _pollSocket() {
    final socket = _socket;
    if (socket == null) return;

    try {
      final datagram = socket.receive();
      if (datagram == null) return;
      _packetCount++;
      debugPrint(
          'BeaconListener: Packet #$_packetCount - ${datagram.data.length} bytes from ${datagram.address.address}:${datagram.port}');
      _handleDatagram(datagram);
    } catch (e) {
      debugPrint('BeaconListener: Error receiving datagram: $e');
    }
  }

  /// Extract the port from a URL string (e.g. "http://10.0.0.1:8000" -> "8000").
  String? _extractPort(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.hasPort) return uri.port.toString();
    } catch (_) {}
    return null;
  }

  /// Build the server URL from the UDP packet's source IP and the port
  /// advertised in the beacon's url field.
  String _buildUrl(String sourceIp, String beaconUrl) {
    final port = _extractPort(beaconUrl);
    if (port != null) {
      return 'http://$sourceIp:$port';
    }
    return 'http://$sourceIp';
  }

  void _handleDatagram(Datagram datagram) {
    try {
      final data = utf8.decode(datagram.data);
      final json = jsonDecode(data) as Map<String, dynamic>;

      // Only accept lemonade service beacons
      if (json['service'] != 'lemonade') return;

      final sourceIp = datagram.address.address;
      final beaconUrl = json['url'] as String? ?? '';
      final resolvedUrl = _buildUrl(sourceIp, beaconUrl);

      final server = DiscoveredServer(
        hostname: json['hostname'] ?? 'Unknown',
        url: resolvedUrl,
        lastSeen: DateTime.now(),
        address: sourceIp,
      );

      debugPrint(
          'BeaconListener: Discovered "${server.hostname}" at $resolvedUrl');
      _discoveredController.add(server);
    } catch (e) {
      debugPrint('BeaconListener: Failed to parse packet: $e');
    }
  }

  void stopListening() {
    _isListening = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _socket?.close();
    _socket = null;
  }

  void dispose() {
    stopListening();
    _discoveredController.close();
  }
}