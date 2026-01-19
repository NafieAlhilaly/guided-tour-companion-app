import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/mqtt_service.dart';

class VideoStreamPage extends StatefulWidget {
  const VideoStreamPage({super.key});

  @override
  State<VideoStreamPage> createState() => _VideoStreamPageState();
}

class _VideoStreamPageState extends State<VideoStreamPage> {
  final TextEditingController _topicController = TextEditingController(
    text: 'camera/image',
  );
  
  Uint8List? _imageData;
  bool _isStreaming = false;
  StreamSubscription<ReceivedMqttMessage>? _mqttSubscription;
  String _statusMessage = 'Not connected';
  int _frameCount = 0;
  DateTime? _lastFrameTime;
  double _fps = 0.0;
  int _width = 0;
  int _height = 0;
  
  @override
  void dispose() {
    _stopStream();
    _topicController.dispose();
    super.dispose();
  }

  void _startStream() {
    if (_isStreaming) return;
    
    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      _showError('Please enter a topic');
      return;
    }

    setState(() {
      _isStreaming = true;
      _statusMessage = 'Subscribing to $topic...';
      _frameCount = 0;
      _lastFrameTime = null;
      _fps = 0.0;
    });

    // Subscribe to MQTT topic
    MqttService.instance.subscribe(topic);
    
    // Listen for messages on this topic
    _mqttSubscription = MqttService.instance.messages.listen((msg) {
      if (msg.topic == topic) {
        _processImageMessage(msg.payload);
      }
    });
  }

  void _stopStream() {
    _mqttSubscription?.cancel();
    _mqttSubscription = null;
    
    final topic = _topicController.text.trim();
    if (topic.isNotEmpty) {
      // Note: We're not unsubscribing to avoid affecting other listeners
      // MqttService.instance.unsubscribe(topic);
    }
    
    setState(() {
      _isStreaming = false;
      _statusMessage = 'Disconnected';
      _fps = 0.0;
    });
  }

  void _processImageMessage(String payload) {
    try {
      // Parse JSON message
      final jsonData = json.decode(payload) as Map<String, dynamic>;
      
      // Extract base64 image
      final base64Image = jsonData['image'] as String?;
      if (base64Image == null || base64Image.isEmpty) {
        _showError('No image data in message');
        return;
      }

      // Decode base64 to bytes
      final imageBytes = base64.decode(base64Image);
      
      // Calculate FPS
      final now = DateTime.now();
      if (_lastFrameTime != null) {
        final timeDiff = now.difference(_lastFrameTime!).inMilliseconds;
        if (timeDiff > 0) {
          _fps = 1000.0 / timeDiff;
        }
      }
      _lastFrameTime = now;
      _frameCount++;

      setState(() {
        _imageData = imageBytes;
        _width = jsonData['width'] as int? ?? 0;
        _height = jsonData['height'] as int? ?? 0;
        _statusMessage = 'Streaming • ${_width}x$_height • ${_fps.toStringAsFixed(1)} FPS';
      });
    } catch (e) {
      _showError('Error parsing message: ${e.toString()}');
    }
  }

  void _showError(String message) {
    if (mounted) {
      setState(() {
        _statusMessage = 'Error: $message';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Stream'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isStreaming)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, color: Colors.white, size: 8),
                      const SizedBox(width: 6),
                      Text(
                        'LIVE',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _topicController,
                      decoration: const InputDecoration(
                        labelText: 'MQTT Topic',
                        hintText: 'camera/image',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.topic),
                      ),
                      enabled: !_isStreaming,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isStreaming ? null : _startStream,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Start Stream'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              disabledBackgroundColor: Colors.grey,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: !_isStreaming ? null : _stopStream,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop Stream'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              disabledBackgroundColor: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isStreaming 
                            ? Colors.green.withOpacity(0.1)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isStreaming ? Icons.check_circle : Icons.circle_outlined,
                            size: 16,
                            color: _isStreaming ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _statusMessage,
                              style: TextStyle(
                                color: _isStreaming ? Colors.green[800] : Colors.grey[700],
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isStreaming && _frameCount > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Frames received: $_frameCount',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                elevation: 2,
                clipBehavior: Clip.antiAlias,
                child: _imageData != null
                    ? Image.memory(
                        _imageData!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                                const SizedBox(height: 8),
                                Text('Error loading image', style: TextStyle(color: Colors.grey[600])),
                              ],
                            ),
                          );
                        },
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.videocam_off,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No video feed',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                'Enter an MQTT topic and press "Start Stream" to begin receiving video data.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(16),
                              margin: const EdgeInsets.symmetric(horizontal: 32),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.withOpacity(0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Expected Format',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue[900],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '{\n  "image": "<base64_jpeg>",\n  "timestamp": 1704200000.123,\n  "width": 960,\n  "height": 540,\n  "frame_id": "camera_link",\n  "encoding": "jpeg"\n}',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
