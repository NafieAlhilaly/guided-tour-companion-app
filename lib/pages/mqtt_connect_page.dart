import 'package:flutter/material.dart';
import '../services/mqtt_service.dart';
import 'mqtt_messages_page.dart';

class MqttConnectPage extends StatefulWidget {
  const MqttConnectPage({super.key});

  @override
  State<MqttConnectPage> createState() => _MqttConnectPageState();
}

class _MqttConnectPageState extends State<MqttConnectPage> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '1883');
  bool _loading = false;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 1883;
    if (host.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter the host')));
      return;
    }

    setState(() => _loading = true);
    try {
      await MqttService.instance.connect(host, port: port);
      if (mounted) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const MqttMessagesPage()));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Connect failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MQTT Connect')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Host (e.g. broker.hivemq.com)',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Port (default 1883)',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _connect,
                    child: const Text('Connect'),
                  ),
          ],
        ),
      ),
    );
  }
}
