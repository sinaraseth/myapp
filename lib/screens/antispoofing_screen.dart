import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/antispoofing_service.dart';

class AntispoofingScreen extends StatefulWidget {
  const AntispoofingScreen({super.key});

  @override
  State<AntispoofingScreen> createState() => _AntispoofingScreenState();
}

class _AntispoofingScreenState extends State<AntispoofingScreen> {
  final AntispoofingService _antispoofingService = AntispoofingService();
  CameraController? _cameraController;
  late List<CameraDescription> _cameras;
  
  bool _isStreaming = false;
  bool _isRecording = false;
  bool _isLoading = false;
  int _countdown = 3;
  Timer? _countdownTimer;
  Timer? _recordingTimer;

  AntispoofingResult? _result;
  String _statusMessage = "";

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      await _antispoofingService.loadModel();
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _showError('No cameras available.');
        return;
      }
    } catch (e) {
      _showError('Initialization Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _countdownTimer?.cancel();
    _recordingTimer?.cancel();
    _antispoofingService.dispose();
    super.dispose();
  }

  Future<void> _toggleWebcam() async {
    if (_isStreaming) {
      await _stopWebcam();
    } else {
      await _startWebcam();
    }
  }

  Future<void> _startWebcam() async {
    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front, 
      orElse: () => _cameras.first
    );

    _cameraController = CameraController(camera, ResolutionPreset.high);

    try {
      await _cameraController!.initialize();
      setState(() => _isStreaming = true);
      Future.delayed(const Duration(seconds: 1), _startRecording);
    } catch (e) {
      _showError('Error starting webcam: $e');
    }
  }

  Future<void> _stopWebcam() async {
    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();
    _cameraController = null;
    _countdownTimer?.cancel();
    _recordingTimer?.cancel();
    setState(() {
      _isStreaming = false;
      _isRecording = false;
      _result = null;
      _statusMessage = "";
    });
  }

  void _startRecording() {
    if (!_isStreaming) return;
    setState(() {
      _isRecording = true;
      _countdown = 3;
      _result = null;
       _statusMessage = "";
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
      }
    });

    _recordingTimer = Timer(const Duration(seconds: 3), _stopRecordingAndPredict);
    // Capture frame at 1.5 seconds
    Future.delayed(const Duration(milliseconds: 1500), _captureAndPredict);
  }

  Future<void> _captureAndPredict() async {
    if (!_isRecording || _cameraController == null) return;
    
    try {
      final image = await _cameraController!.takePicture();
      final imageBytes = await image.readAsBytes();
      
      setState(() {
        _isLoading = true;
        _statusMessage = "3s video sent, waiting for recognition...";
      });

      final result = await _antispoofingService.predictFromBytes(imageBytes);
      setState(() => _result = result);

    } catch (e) {
      _showError('Error capturing frame: $e');
    } finally {
       setState(() => _isLoading = false);
    }
  }

  void _stopRecordingAndPredict() {
    setState(() {
      _isRecording = false;
      if (_result == null && !_isLoading) {
        _statusMessage = "Recording finished. Waiting for result...";
      } 
    });
  }

  void _showError(String message) {
    setState(() {
      _statusMessage = message;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Stream | Face Anti-Spoofing Detection')),
      body: Column(
        children: [
          _buildVideoDisplay(),
          _buildControls(),
          if (_isLoading)
             const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          if (_statusMessage.isNotEmpty && !_isLoading)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(_statusMessage, style: const TextStyle(fontSize: 16, color: Colors.blue)),
            ),
          if (_result != null) _buildResultCard(),
        ],
      ),
    );
  }

  Widget _buildVideoDisplay() {
    return Expanded(
      child: Container(
        color: Colors.black,
        child: Center(
          child: _isStreaming && _cameraController != null && _cameraController!.value.isInitialized
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.rotationY(3.14159), // Mirror horizontally
                      child: AspectRatio(
                        aspectRatio: _cameraController!.value.aspectRatio,
                        child: CameraPreview(_cameraController!),
                      ),
                    ),
                    if (_isRecording)
                      Container(
                        color: Colors.black.withOpacity(0.5),
                        child: Text(
                          '$_countdown',
                          style: const TextStyle(fontSize: 96, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                )
              : const Text('Webcam is off', style: TextStyle(color: Colors.white, fontSize: 18)),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: ElevatedButton(
        onPressed: _isLoading || (_isStreaming && _isRecording) ? null : _toggleWebcam,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isStreaming ? Colors.red : Colors.blue,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
        ),
        child: Text(_isStreaming ? 'Stop Webcam' : 'Start Webcam', style: const TextStyle(fontSize: 18)),
      ),
    );
  }
  
  Widget _buildResultCard() {
    if (_result == null) return const SizedBox.shrink();

    final status = _result!.status;
    final isLive = _result!.isLive;
    final cardColor = status == 'no_face' ? Colors.yellow.shade700 : (isLive ? Colors.green : Colors.red);
    final statusText = status == 'no_face' ? '⚠️ No Face Detected' : (isLive ? '✅ LIVE' : '❌ SPOOF');
    
    return Card(
      color: cardColor.withOpacity(0.1),
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              statusText,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cardColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (status != 'no_face') ...[
              _buildResultRow('Live Probability:', _result!.liveProb),
              _buildResultRow('Spoof Probability:', _result!.spoofProb),
              _buildResultRow('Confidence:', _result!.confidence),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text('${(value * 100).toStringAsFixed(2)}%', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
