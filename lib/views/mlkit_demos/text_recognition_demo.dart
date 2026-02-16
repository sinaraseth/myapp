import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../controllers/text_recognition_controller.dart';

class TextRecognitionDemo extends StatefulWidget {
  const TextRecognitionDemo({super.key});

  @override
  State<TextRecognitionDemo> createState() => _TextRecognitionDemoState();
}

class _TextRecognitionDemoState extends State<TextRecognitionDemo> {
  CameraController? _cameraController;
  late List<CameraDescription> _cameras;
  bool _isProcessing = false;
  String _recognizedText = '';
  bool _isCameraActive = false;

  final TextRecognitionController _textRecognitionController =
      TextRecognitionController();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      final camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      setState(() {});
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  Future<void> _captureAndRecognize() async {
    if (_isProcessing || _cameraController == null) return;

    setState(() {
      _isProcessing = true;
      _recognizedText = 'Processing...';
    });

    try {
      final image = await _cameraController!.takePicture();
      final recognizedText = await _textRecognitionController.recognizeText(
        File(image.path),
      );

      if (mounted) {
        setState(() {
          _recognizedText = recognizedText;
        });
      }

      // Clean up the temporary file
      await File(image.path).delete();
    } catch (e) {
      print('Error recognizing text: $e');
      setState(() {
        _recognizedText = 'Error: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _toggleCamera() {
    setState(() {
      _isCameraActive = !_isCameraActive;
      if (!_isCameraActive) {
        _recognizedText = '';
      }
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textRecognitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Text Recognition Demo'),
        backgroundColor: Colors.black.withOpacity(0.3),
        elevation: 0,
      ),
      body: Container(
        color: Colors.black,
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: _buildCameraPreview(),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_recognizedText.isNotEmpty) _buildTextDisplay(),
                    _buildControls(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return SizedBox.expand(
      child: Container(
        color: Colors.black,
        child: _isCameraActive
            ? CameraPreview(_cameraController!)
            : const Center(
                child: Text(
                  'Camera Off\n\nTap "Start Camera" to begin',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton.icon(
            onPressed: _toggleCamera,
            icon: Icon(_isCameraActive ? Icons.videocam_off : Icons.videocam),
            label: Text(_isCameraActive ? 'Stop Camera' : 'Start Camera'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isCameraActive ? Colors.red : Colors.green,
            ),
          ),
          ElevatedButton.icon(
            onPressed: _isCameraActive && !_isProcessing
                ? _captureAndRecognize
                : null,
            icon: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.camera_alt),
            label: const Text('Capture & Recognize'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextDisplay() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recognized Text:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _recognizedText,
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
