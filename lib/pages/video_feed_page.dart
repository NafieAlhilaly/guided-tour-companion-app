import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart';

class VideoFeedPage extends StatefulWidget {
  const VideoFeedPage({super.key});

  @override
  State<VideoFeedPage> createState() => _VideoFeedPageState();
}

class _VideoFeedPageState extends State<VideoFeedPage> {
  final TextEditingController _hostController = TextEditingController(text: 'localhost');
  final TextEditingController _portController = TextEditingController(text: '8080');
  
  RTCPeerConnection? _peerConnection;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isStreaming = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _remoteRenderer.initialize();
  }

  @override
  void dispose() {
    _stopStream();
    _remoteRenderer.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _stopStream() async {
    await _peerConnection?.close();
    _peerConnection = null;
    if (mounted) {
      setState(() => _isStreaming = false);
    }
  }

  Future<void> _startWebRTC() async {
    try {
      setState(() {
        _errorMessage = null;
        _isStreaming = true;
      });

      final Map<String, dynamic> configuration = {
        'iceServers': []
      };

      _peerConnection = await createPeerConnection(configuration);

      // Listen for the remote stream
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.track.kind == 'video') {
          _remoteRenderer.srcObject = event.streams[0];
        }
      };

      // Create offer to receive video only
      RTCSessionDescription offer = await _peerConnection!.createOffer({
        'offerToReceiveVideo': 1,
        'offerToReceiveAudio': 0,
      });
      await _peerConnection!.setLocalDescription(offer);

      // Signaling: POST offer to your Python WebRTC server
      final response = await http.post(
        Uri.parse('http://${_hostController.text}:${_portController.text}/offer'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sdp': offer.sdp,
          'type': offer.type,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(data['sdp'], data['type']),
        );
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = "WebRTC Error: $e";
        _isStreaming = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebRTC Video Stream')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    TextField(controller: _hostController, decoration: const InputDecoration(labelText: 'Server Host')),
                    TextField(controller: _portController, decoration: const InputDecoration(labelText: 'Server Port')),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _isStreaming ? _stopStream : _startWebRTC,
                      style: ElevatedButton.styleFrom(backgroundColor: _isStreaming ? Colors.red : null),
                      child: Text(_isStreaming ? 'Stop Stream' : 'Start Stream'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              height: 300,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _errorMessage != null
                  ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.white)))
                  : _isStreaming
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
                        )
                      : const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.videocam_off, color: Colors.white54, size: 48),
                              SizedBox(height: 8),
                              Text('Stream Offline', style: TextStyle(color: Colors.white54)),
                            ],
                          ),
                        ),
            ),
            const SizedBox(height: 10),
            if (_isStreaming)
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Receiving frames...', style: TextStyle(fontStyle: FontStyle.italic)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}