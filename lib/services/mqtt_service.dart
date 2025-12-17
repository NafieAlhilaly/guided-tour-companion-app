import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class ReceivedMqttMessage {
  final String topic;
  final String payload;
  final DateTime time;

  ReceivedMqttMessage({
    required this.topic,
    required this.payload,
    DateTime? time,
  }) : time = time ?? DateTime.now();
}

class MqttService {
  MqttService._private();
  static final MqttService instance = MqttService._private();

  MqttServerClient? _client;
  final StreamController<ReceivedMqttMessage> _messagesController =
      StreamController.broadcast();

  Stream<ReceivedMqttMessage> get messages => _messagesController.stream;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect(
    String host, {
    int port = 1883,
    String? clientIdentifier,
  }) async {
    _client = MqttServerClient(
      host,
      clientIdentifier ??
          'flutter_client_${DateTime.now().millisecondsSinceEpoch}',
    );
    _client!.port = port;
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 20;
    _client!.onDisconnected = _onDisconnected;

    try {
      final connMess = MqttConnectMessage()
          .withClientIdentifier(_client!.clientIdentifier)
          .startClean();
      _client!.connectionMessage = connMess;
      await _client!.connect();

      if (_client!.connectionStatus?.state == MqttConnectionState.connected) {
        // listen for incoming messages
        _client!.updates?.listen((event) => _onMessage(event));
      } else {
        final status = _client!.connectionStatus;
        throw Exception(
          'Connection failed: ${status?.state} - ${status?.returnCode}',
        );
      }
    } catch (e) {
      _client?.disconnect();
      rethrow;
    }
  }

  void _onDisconnected() {
    // Optionally notify listeners
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>>? event) {
    if (event == null) return;
    for (var rec in event) {
      final recMess = rec.payload as MqttPublishMessage;
      final message = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );
      _messagesController.add(
        ReceivedMqttMessage(topic: rec.topic, payload: message),
      );
    }
  }

  void subscribe(String topic, {MqttQos qos = MqttQos.atMostOnce}) {
    if (_client == null) return;
    _client!.subscribe(topic, qos);
  }

  void publish(
    String topic,
    String message, {
    MqttQos qos = MqttQos.atMostOnce,
  }) {
    if (_client == null) return;
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    _client!.publishMessage(topic, qos, builder.payload!);
  }

  void disconnect() {
    _client?.disconnect();
    _client = null;
  }

  void dispose() {
    disconnect();
    _messagesController.close();
  }
}
