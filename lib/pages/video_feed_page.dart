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
  RTCDataChannel? _dataChannel;
  double? _currentLatencyMs;
  bool _isFullScreen = false;
  bool _showDebugLogs = false;
  String? _errorMessage;
  final List<String> _debugLogs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _remoteRenderer.initialize();
  }

  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String().split('T').last.substring(0, 8);
    setState(() {
      _debugLogs.insert(0, '[$timestamp] $message');
      if (_debugLogs.length > 50) _debugLogs.removeLast();
    });
    print(message);
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
    _dataChannel?.close();
    _dataChannel = null;
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
    _dataChannel?.close(); // Close data channel when stream stops
    _dataChannel = null;
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
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'}, // Added STUN for better discovery
        ],
        'sdpSemantics': 'unified-plan',
      };

      _log("Creating PeerConnection...");
      _peerConnection = await createPeerConnection(configuration);

      _peerConnection!.onIceGatheringState = (state) {
        _log("ICE Gathering State: ${state.toString().split('.').last}");
      };

      _peerConnection!.onIceConnectionState = (state) {
        _log("ICE Connection State: ${state.toString().split('.').last}");
      };

      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.track.kind == 'video' && event.streams.isNotEmpty) {
          setState(() {
            _remoteRenderer.srcObject = event.streams[0];
          });
          _log("SUCCESS: Remote video track received");
        }
      };

      _peerConnection!.onDataChannel = _handleDataChannel;

      // IMPORTANT: Create a data channel before generating the offer.
      // This ensures the SDP offer includes the 'm=application' section for SCTP.
      // Without this, the server cannot initiate the 'latency-tracer' channel.
      await _peerConnection!.createDataChannel('capability-check', RTCDataChannelInit());

      _log("Adding Video Transceiver...");
      await _peerConnection!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      _log("Creating Offer...");
      RTCSessionDescription offer = await _peerConnection!.createOffer();
      
      _log("Setting Local Description...");
      await _peerConnection!.setLocalDescription(offer);

      // Dynamically use host from MqttService
      final String host = MqttService.instance.host;
      final String port = '8080'; // Default bridge port

      _log("POSTing offer to http://$host:$port/offer");
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
        _log("Answer received, setting remote description...");
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(data['sdp'], data['type']),
        );
        _log("Handshake complete. Waiting for stream/data...");
      } else {
        throw Exception('Server Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _log("FATAL ERROR: $e");
      setState(() {
        _errorMessage = "WebRTC Error: $e";
        _isStreaming = false;
      });
    }
  }

  void _handleDataChannel(RTCDataChannel channel) {
    _log('!!! Data Channel Callback Triggered: ${channel.label}'); // Crucial new log
    _log('Received remote data channel: ${channel.label}');
    if (channel.label == 'latency-tracer') {
      setState(() {
        _dataChannel = channel;
      });

      _dataChannel!.onMessage = (RTCDataChannelMessage message) {
        if (!message.isBinary) {
          _processLatencyMessage(message.text);
        }
      };

      _dataChannel!.onDataChannelState = (state) {
        _log('Latency Data Channel State: $state');
        if (mounted) setState(() {}); // Refresh UI on state change
        
        if (state == RTCDataChannelState.RTCDataChannelClosed || state == RTCDataChannelState.RTCDataChannelClosing) {
          setState(() {
            _currentLatencyMs = null; // Clear latency when channel closes
          });
        }
      };
    }
  }

  void _processLatencyMessage(String messageText) {
    try {
      final Map<String, dynamic> data = jsonDecode(messageText);
      final dynamic ts = data['ts'];
      if (ts == null || ts is! num) {
        _log('Latency message error: missing "ts" key');
        return;
      }
      final int sourceTsNs = ts.toInt(); 
      final int nowNs = DateTime.now().microsecondsSinceEpoch * 1000; // Current device time in nanoseconds
      final double totalLatencyMs = (nowNs - sourceTsNs) / 1000000.0; // Convert ns to ms
      setState(() {
        _currentLatencyMs = totalLatencyMs;
      });
    } catch (e) {
      _log('Error processing latency: $e');
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

            // Live Badge Overlay (Initial Position)
            if (_isStreaming && _remoteRenderer.srcObject != null)
              Positioned(
                top: 16,
                left: 16,
                child: _buildLiveBadge(),
              ),
              if (_isStreaming && _remoteRenderer.srcObject != null)
              Positioned(
                top: 16,
                right: 16,
                child: _buildLatencyBadge(),
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
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: videoPlayer,
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(height: 16),
                  _showDebugLogs ? Expanded(child: _buildDebugPanel()) : _buildDebugPanel(),
                ],
              ),
      ),
    );
  }

  Widget _buildLiveBadge() {
    if (!_isStreaming || _remoteRenderer.srcObject == null) return const SizedBox.shrink();
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

  Widget _buildLatencyBadge() {
    if (!_isStreaming) return const SizedBox.shrink();

    String latencyText = "--- ms";
    Color badgeColor = Colors.blue;

    if (_currentLatencyMs != null) {
      latencyText = "${_currentLatencyMs!.toStringAsFixed(1)} ms";
    } else if (_dataChannel == null) {
      latencyText = (_peerConnection != null && _peerConnection!.iceConnectionState == RTCIceConnectionState.RTCIceConnectionStateConnected)
          ? "Server not creating Data Channel?"
          : "Waiting for Data Channel...";
    } else if (_dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      latencyText = "Channel: ${_dataChannel!.state.toString().split('.').last}";
      badgeColor = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.speed, color: Colors.white, size: 10),
          const SizedBox(width: 6),
          Text(
            latencyText,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => setState(() => _showDebugLogs = !_showDebugLogs),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showDebugLogs ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                      color: Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text("Debug Logs", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _debugLogs.clear()),
                child: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
              ),
            ],
          ),
          if (_showDebugLogs) ...[
            const Divider(color: Colors.white10),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _debugLogs.length,
                itemBuilder: (context, index) => Text(
                  _debugLogs[index],
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}