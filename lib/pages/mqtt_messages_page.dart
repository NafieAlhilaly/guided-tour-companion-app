import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../services/mqtt_service.dart';
import 'video_feed_page.dart';
import 'metrics_page.dart';

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
    final topic = "/notification/med_alert";
    final payload = "med_alert";
    if (topic.isEmpty) return;
    MqttService.instance.publish(topic, payload);
    _pubMsgCtrl.clear();
    _showTopSnackBar('Published to $topic');
  }
  void _showTopSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
      ),
    );
  }
  void _disconnect() {
    MqttService.instance.disconnect();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    MqttService.instance.subscribe("/notification/med_alert");
    MqttService.instance.subscribe("/notification/violation_alert");
    MqttService.instance.subscribe("/notification/alert_notification");
    MqttService.instance.subscribe("/companion_drone/telemetry/os_metrics");
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
            // child: Row(
            //   children: [
            //     Expanded(
            //       child: TextField(
            //         controller: _subTopicCtrl,
            //         decoration: const InputDecoration(
            //           labelText: 'Subscribe topic',
            //         ),
            //       ),
            //     ),
            //     const SizedBox(width: 8),
            //     ElevatedButton(
            //       onPressed: _subscribe,
            //       child: const Text('Subscribe'),
            //     ),
            //   ],
            // ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('No messages yet'))
                : ListView.builder(
                    reverse: true,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final m = _messages[index];
                      return ListTile(
                        title: Text(m.topic, style: TextStyle(fontSize: 12)),
                        subtitle: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 15,
                          ),
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(255, 74, 49, 176),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: _buildMessageContent(m),
                        ),
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
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 24) / 2,
                  child: ElevatedButton(
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all(Colors.red),
                      foregroundColor: WidgetStateProperty.all(Colors.white),
                    ),
                    onPressed: _publish,
                    child: const Text('Medical Alert'),
                  ),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 24) / 2,
                  child: ElevatedButton.icon(
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all(Colors.blue),
                      foregroundColor: WidgetStateProperty.all(Colors.white),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const VideoFeedPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.videocam),
                    label: const Text('Video'),
                  ),
                ),
                SizedBox(
                  width: MediaQuery.of(context).size.width - 16,
                  child: ElevatedButton.icon(
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all(Colors.orange),
                      foregroundColor: WidgetStateProperty.all(Colors.white),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MetricsPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.bar_chart),
                    label: const Text('Companion Computer Metrics'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(ReceivedMqttMessage m) {
    if (m.topic == '/notification/alert_notification') {
      try {
        final Map<String, dynamic> data = jsonDecode(m.payload);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data['message'] != null)
              Text(
                data['message'],
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            if (data['image'] != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  base64Decode(data['image']),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Text(
                    'Error loading image',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ],
        );
      } catch (_) {}
    }
    return Text(
      m.payload,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
    );
  }
}
