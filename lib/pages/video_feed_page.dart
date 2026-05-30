import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/mqtt_service.dart';

class VideoFeedPage extends StatefulWidget {
  const VideoFeedPage({super.key});

  @override
  State<VideoFeedPage> createState() => _VideoFeedPageState();
}

class _VideoFeedPageState extends State<VideoFeedPage> with WidgetsBindingObserver {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  bool _isStreaming = false;
  bool _shouldBeStreaming = false; // Track if the user explicitly started the stream
  bool _isFullScreen = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _remoteRenderer.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle reconnection when the app comes back from screen timeout/background
    if (state == AppLifecycleState.resumed) {
      if (_shouldBeStreaming && !_isStreaming) {
        _startWebRTC();
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Close connection when app is backgrounded to save resources and avoid stale sockets
      if (_isStreaming) {
        _peerConnection?.close();
        _peerConnection = null;
        _remoteRenderer.srcObject = null;
        setState(() => _isStreaming = false);
      }
    }
  }

  @override
  void dispose() {
    _exitFullScreen();
    _stopStream();
    _remoteRenderer.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });

    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      _exitFullScreen();
    }
  }

  void _exitFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  Future<void> _stopStream({bool resetIntent = true}) async {
    if (resetIntent) {
      _shouldBeStreaming = false;
    }

    await _peerConnection?.close();
    _peerConnection = null;
    _remoteRenderer.srcObject = null;
    if (mounted) {
      setState(() => _isStreaming = false);
    }
  }

  Future<void> _startWebRTC() async {
    try {
      // Clean up any existing connection before starting a new one
      await _stopStream(resetIntent: false);

      setState(() {
        _errorMessage = null;
        _isStreaming = true;
        _shouldBeStreaming = true;
      });

      final Map<String, dynamic> configuration = {
        'iceServers': [],
        'sdpSemantics': 'unified-plan',
      };

      _peerConnection = await createPeerConnection(configuration);

      // Listen for the remote stream
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.track.kind == 'video' && event.streams.isNotEmpty) {
          setState(() {
            _remoteRenderer.srcObject = event.streams[0];
          });
        }
      };

      // Use transceivers for Unified Plan (modern WebRTC)
      // This explicitly tells the peer connection we want to receive video
      await _peerConnection!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      // Create offer without legacy constraints
      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Dynamically use host from MqttService
      final String host = MqttService.instance.host;
      final String port = '8080'; // Default bridge port

      // Signaling: POST offer to your Python WebRTC server
      final response = await http.post(
        Uri.parse('http://$host:$port/offer'),
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
    final videoPlayer = Container(
      margin: _isFullScreen ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: _isFullScreen ? BorderRadius.zero : BorderRadius.circular(16),
        border: _isFullScreen ? null : Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: _isFullScreen ? BorderRadius.zero : BorderRadius.circular(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The Video View
            if (_remoteRenderer.srcObject != null)
              RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              ),

            // Dark overlay when not streaming
            if (!_isStreaming || _remoteRenderer.srcObject == null)
              Container(color: Colors.black45),

            // Player Controls Overlay
            if (!_isStreaming)
              IconButton(
                icon: const Icon(Icons.play_circle_fill, size: 80, color: Colors.white70),
                onPressed: _startWebRTC,
              )
            else if (_remoteRenderer.srcObject == null && _errorMessage == null)
              const CircularProgressIndicator(color: Colors.white),

            // Live Badge Overlay
            if (_isStreaming && _remoteRenderer.srcObject != null)
              Positioned(
                top: 16,
                left: 16,
                child: _buildLiveBadge(),
              ),

            // Full Screen Toggle Button Overlay
            if (_isStreaming && _remoteRenderer.srcObject != null)
              Positioned(
                bottom: 16,
                right: 16,
                child: IconButton(
                  icon: Icon(
                    _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    size: 42,
                    color: Colors.white54,
                  ),
                  onPressed: _toggleFullScreen,
                ),
              ),

            // Error Display
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullScreen
          ? null
          : AppBar(
              title: const Text('Drone Live Feed'),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
      body: Center(
        child: _isFullScreen
            ? videoPlayer
            : AspectRatio(
                aspectRatio: 16 / 9,
                child: videoPlayer,
              ),
      ),
    );
  }

  Widget _buildLiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, color: Colors.white, size: 10),
          const SizedBox(width: 6),
          const Text(
            "LIVE",
            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}