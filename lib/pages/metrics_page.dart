import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/mqtt_service.dart';

class MetricData {
  final double cpu;
  final double memory;
  final double disk;
  final DateTime timestamp;

  MetricData({
    required this.cpu,
    required this.memory,
    required this.disk,
    required this.timestamp,
  });

  factory MetricData.fromJson(Map<String, dynamic> json) {
    return MetricData(
      cpu: (json['cpu_utilization'] as num).toDouble(),
      memory: (json['memory_utilization'] as num).toDouble(),
      disk: (json['disk_utilization'] as num).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    );
  }
}

class MetricsPage extends StatefulWidget {
  const MetricsPage({super.key});

  @override
  State<MetricsPage> createState() => _MetricsPageState();
}

class _MetricsPageState extends State<MetricsPage> {
  final List<MetricData> _history = [];
  late StreamSubscription<ReceivedMqttMessage> _subscription;
  final String _topic = "/companion_drone/telemetry/os_metrics";

  @override
  void initState() {
    super.initState();
    MqttService.instance.subscribe(_topic);
    _subscription = MqttService.instance.messages.listen((msg) {
      if (msg.topic == _topic) {
        _processMetrics(msg.payload);
      }
    });
  }

  void _processMetrics(String payload) {
    try {
      final data = MetricData.fromJson(jsonDecode(payload));
      setState(() {
        _history.insert(0, data);
        // Maintain 10-minute window
        final tenMinutesAgo = DateTime.now().subtract(const Duration(minutes: 10));
        _history.removeWhere((m) => m.timestamp.isBefore(tenMinutesAgo));
      });
    } catch (e) {
      debugPrint("Error parsing metrics: $e");
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _history.isNotEmpty ? _history.first : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Companion Metrics'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: current == null
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.orange),
                  SizedBox(height: 20),
                  Text("Waiting for drone telemetry...", 
                    style: TextStyle(color: Colors.white54, fontSize: 16)),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader("Real-time Status"),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: _buildGaugeCard("CPU", current.cpu, Colors.blueAccent)),
                      const SizedBox(width: 15),
                      Expanded(child: _buildGaugeCard("RAM", current.memory, Colors.greenAccent)),
                    ],
                  ),
                  const SizedBox(height: 15),
                  _buildLinearCard("Storage Usage", current.disk, Colors.orangeAccent),
                  const SizedBox(height: 35),
                  _buildHeader("History (10m)"),
                  const SizedBox(height: 15),
                  _buildHistoryTable(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(String text) {
    return Text(text, 
      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold));
  }

  Widget _buildGaugeCard(String label, double percent, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 70, width: 70,
                child: CircularProgressIndicator(
                  value: percent / 100,
                  strokeWidth: 6,
                  backgroundColor: Colors.white10,
                  color: color,
                ),
              ),
              Text("${percent.toInt()}%", 
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildLinearCard(String label, double percent, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white60, fontSize: 14)),
              Text("${percent.toStringAsFixed(1)}%", 
                style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 10,
              backgroundColor: Colors.white10,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTable() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final item = _history[index];
        final time = "${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}:${item.timestamp.second.toString().padLeft(2, '0')}";
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(time, style: const TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'monospace')),
              _historyItem("CPU", item.cpu, Colors.blueAccent),
              _historyItem("RAM", item.memory, Colors.greenAccent),
            ],
          ),
        );
      },
    );
  }

  Widget _historyItem(String label, double value, Color color) {
    return Row(
      children: [
        Text("$label: ", style: const TextStyle(color: Colors.white38, fontSize: 12)),
        Text("${value.toInt()}%", style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}