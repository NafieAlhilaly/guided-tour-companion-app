import 'dart:async';

import 'package:flutter/material.dart';
import '../services/mqtt_service.dart';

class MqttMessagesPage extends StatefulWidget {
  const MqttMessagesPage({super.key});

  @override
  State<MqttMessagesPage> createState() => _MqttMessagesPageState();
}

class _MqttMessagesPageState extends State<MqttMessagesPage> {
  final List<ReceivedMqttMessage> _messages = [];
  late final StreamSubscription<ReceivedMqttMessage> _sub;

  final _subTopicCtrl = TextEditingController(text: '#');
  final _pubTopicCtrl = TextEditingController(text: 'test/topic');
  final _pubMsgCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sub = MqttService.instance.messages.listen((msg) {
      setState(() {
        _messages.insert(0, msg);
      });
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _subTopicCtrl.dispose();
    _pubTopicCtrl.dispose();
    _pubMsgCtrl.dispose();
    super.dispose();
  }

  void _subscribe() {
    final topic = _subTopicCtrl.text.trim();
    if (topic.isEmpty) return;
    MqttService.instance.subscribe(topic);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Subscribed to $topic')));
  }

  void _publish() {
    final topic = _pubTopicCtrl.text.trim();
    final payload = _pubMsgCtrl.text;
    if (topic.isEmpty) return;
    MqttService.instance.publish(topic, payload);
    _pubMsgCtrl.clear();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Published to $topic')));
  }

  void _disconnect() {
    MqttService.instance.disconnect();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    MqttService.instance.subscribe("/notification/med_alert");
    MqttService.instance.subscribe("/notification/violation_alert");
    return Scaffold(
      appBar: AppBar(
        title: const Text('MQTT Messages'),
        actions: [
          IconButton(
            tooltip: 'Disconnect',
            icon: const Icon(Icons.link_off),
            onPressed: _disconnect,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subTopicCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Subscribe topic',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _subscribe,
                  child: const Text('Subscribe'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('No messages yet'))
                : ListView.builder(
                    reverse: false,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final m = _messages[index];
                      return ListTile(
                        title: Text(m.topic),
                        subtitle: Text(m.payload),
                        trailing: Text(
                          '${m.time.hour}:${m.time.minute.toString().padLeft(2, '0')}',
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pubTopicCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Publish topic',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pubMsgCtrl,
                        decoration: const InputDecoration(labelText: 'Message'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _publish,
                      child: const Text('Send'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
