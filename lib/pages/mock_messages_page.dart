import 'dart:async';
import 'package:flutter/material.dart';
import 'mock_video_stream_page.dart';

class MockMessage {
  final String topic;
  final String payload;
  final DateTime time;

  MockMessage({
    required this.topic,
    required this.payload,
    required this.time,
  });
}

class MockMessagesPage extends StatefulWidget {
  const MockMessagesPage({super.key});

  @override
  State<MockMessagesPage> createState() => _MockMessagesPageState();
}

class _MockMessagesPageState extends State<MockMessagesPage> {
  final List<MockMessage> _messages = [];
  Timer? _autoMessageTimer;
  int _messageCounter = 0;

  final List<String> _mockPayloads = [
    "Violent movement detected in Zone 3",
    "Violation of safety protocol in Area 5",
    "Unauthorized access attempt detected",
    "Fall detected in Room 12",
    "Restricted area breach detected",
  ];

  final List<String> _mockTopics = [
    '/notification/status',
    '/notification/alert',
    '/notification/system',
    '/notification/sensor',
  ];

  @override
  void initState() {
    super.initState();
    _startAutoMessages();
  }

  @override
  void dispose() {
    _autoMessageTimer?.cancel();
    super.dispose();
  }

  void _startAutoMessages() {
    // Add a new message every 5 seconds
    _autoMessageTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _addAutoMessage();
    });
  }

  void _addAutoMessage() {
    setState(() {
      final topic = _mockTopics[_messageCounter % _mockTopics.length];
      final payload = _mockPayloads[_messageCounter % _mockPayloads.length];
      
      _messages.insert(
        0,
        MockMessage(
          topic: topic,
          payload: payload,
          time: DateTime.now(),
        ),
      );
      _messageCounter++;
    });
  }

  void _addMedicalSupplyMessage() {
    setState(() {
      _messages.insert(
        0,
        MockMessage(
          topic: '/notification/med_alert',
          payload: 'Medical supply request - Urgent',
          time: DateTime.now(),
        ),
      );
    });
    _showTopSnackBar('Medical supply alert sent');
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

  void _clearMessages() {
    setState(() {
      _messages.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            tooltip: 'Clear Messages',
            icon: const Icon(Icons.clear_all),
            onPressed: _clearMessages,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12.0),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mock mode: New messages auto-generate for demonstration purposes.',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.message_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Messages will appear automatically',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final m = _messages[index];
                      final isMedicalAlert = m.topic.contains('med_alert');
                      
                      return ListTile(
                        leading: Icon(
                          isMedicalAlert 
                              ? Icons.medical_services 
                              : Icons.message,
                          color: isMedicalAlert ? Colors.red : Colors.blue,
                        ),
                        title: Text(
                          m.topic,
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 15,
                          ),
                          decoration: BoxDecoration(
                            color: isMedicalAlert 
                                ? Colors.red.shade700 
                                : const Color.fromARGB(255, 74, 49, 176),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Text(
                            m.payload,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        trailing: Text(
                          '${m.time.hour}:${m.time.minute.toString().padLeft(2, '0')}:${m.time.second.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all(Colors.red),
                      foregroundColor: WidgetStateProperty.all(Colors.white),
                      padding: WidgetStateProperty.all(
                        const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    onPressed: _addMedicalSupplyMessage,
                    icon: const Icon(Icons.medical_services),
                    label: const Text('Medical Supply'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all(Colors.blue),
                      foregroundColor: WidgetStateProperty.all(Colors.white),
                      padding: WidgetStateProperty.all(
                        const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MockVideoStreamPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.videocam),
                    label: const Text('Video Stream'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
