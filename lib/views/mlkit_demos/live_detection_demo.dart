import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../controllers/liveness_controller.dart';
import 'liveness_result_screen.dart';

class LivenessDetectionPluginDemo extends StatefulWidget {
  const LivenessDetectionPluginDemo({super.key});

  @override
  State<LivenessDetectionPluginDemo> createState() =>
      _LivenessDetectionPluginDemoState();
}

class _LivenessDetectionPluginDemoState
    extends State<LivenessDetectionPluginDemo> {
  CameraController? _cameraController;
  final LivenessController _livenessController = LivenessController();
  Timer? _detectionTimer;
  bool _isCameraInitialized = false;
  bool _isDetecting = false;
  bool _isProcessing = false;

  // ML Kit liveness tracking
  bool _blinkDetected = false;
  bool _smileDetected = false;
  int _blinkCount = 0;
  bool _leftEyeWasOpen = true;
  bool _rightEyeWasOpen = true;

  // Results only
  String _statusMessage = 'Initializing front camera...';

  @override
  void initState() {
    super.initState();
    _livenessController.initializeFaceDetector();
    // Auto-start camera when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCamera();
    });
  }

  Future<void> _initializeCamera() async {
    try {
      // Get available cameras
      final cameras = await availableCameras();

      // Find front camera (CameraX front-facing camera)
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      debugPrint('═══════════════════════════════════════');
      debugPrint('📷 CAMERA INITIALIZATION');
      debugPrint('═══════════════════════════════════════');
      debugPrint('Selected camera: ${frontCamera.name}');
      debugPrint('Lens direction: ${frontCamera.lensDirection}');
      debugPrint('═══════════════════════════════════════\n');

      // Initialize camera controller with front camera
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _statusMessage = 'Look at camera and blink...';
        });

        // Start ML Kit face detection
        _startFaceDetection();
      }
    } catch (e) {
      debugPrint('❌ Camera initialization error: $e');
      if (mounted) {
        setState(() {
          _statusMessage = 'Camera error: $e';
        });
      }
    }
  }

  void _startFaceDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    // Cancel existing timer if any
    _detectionTimer?.cancel();

    // Process frames periodically
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      if (!mounted || _isDetecting || _isProcessing) {
        if (!mounted) timer.cancel();
        return;
      }
      _processCurrentFrame();
    });
  }

  Future<void> _processCurrentFrame() async {
    if (_isProcessing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    _isProcessing = true;

    try {
      final XFile imageFile = await _cameraController!.takePicture();
      final faces = await _livenessController.detectFaces(imageFile.path);

      if (!mounted) {
        _isProcessing = false;
        return;
      }

      if (faces.isNotEmpty) {
        final face = faces.first;

        // Check blink (eye closed detection)
        final leftEyeOpen =
            _livenessController.getLeftEyeOpenProbability(face) > 0.5;
        final rightEyeOpen =
            _livenessController.getRightEyeOpenProbability(face) > 0.5;

        // Detect blink: both eyes were open, now both closed
        if (_livenessController.checkBlink(
          face,
          _leftEyeWasOpen,
          _rightEyeWasOpen,
        )) {
          _blinkCount++;
          if (_blinkCount >= 1 && !_blinkDetected) {
            _blinkDetected = true;
            debugPrint('✅ Blink detected!');
            // Update UI immediately for blink
            if (mounted && !_isDetecting) {
              setState(() {
                _statusMessage = '👁️ Blink detected! Now smile...';
              });
            }
          }
        }

        _leftEyeWasOpen = leftEyeOpen;
        _rightEyeWasOpen = rightEyeOpen;

        // Check smile
        if (_livenessController.checkSmile(face) && !_smileDetected) {
          _smileDetected = true;
          debugPrint('✅ Smile detected!');
        }

        // Auto-capture when both conditions met
        if (_blinkDetected && _smileDetected && !_isDetecting) {
          // Stop detection timer before capture
          _detectionTimer?.cancel();
          _isDetecting = true; // Prevent any more processing
          _isProcessing = false; // Release lock

          debugPrint('🎯 Both conditions met, capturing now!');

          // Capture immediately without any setState
          _captureImage();
          return;
        }
      } else {
        // No faces detected
      }
    } catch (e) {
      debugPrint('Face detection error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _captureImage() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      debugPrint('═══════════════════════════════════════');
      debugPrint('📸 CAPTURING FROM FRONT CAMERA');
      debugPrint('═══════════════════════════════════════\n');

      final XFile imageFile = await _cameraController!.takePicture();
      final Uint8List imageBytes = await imageFile.readAsBytes();

      debugPrint('✅ Image captured: ${imageBytes.length} bytes');

      if (!mounted) return;

      debugPrint('✅ Navigating to results screen...');

      // Navigate to results screen
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LivenessResultScreen(
            capturedImage: imageBytes,
            isRealPerson: true,
            confidence: 0.95,
          ),
        ),
      );

      // After returning from results screen, restart capture
      if (mounted) {
        _restartCapture();
      }
    } catch (e) {
      debugPrint('❌ Capture error: $e');
      if (mounted) {
        _isDetecting = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Capture error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _restartCapture() {
    setState(() {
      _blinkDetected = false;
      _smileDetected = false;
      _blinkCount = 0;
      _leftEyeWasOpen = true;
      _rightEyeWasOpen = true;
      _isDetecting = false;
      _statusMessage = 'Look at camera and blink...';
    });

    debugPrint('🔄 Restarting liveness detection...');
    // Restart face detection
    _startFaceDetection();
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _cameraController?.dispose();
    _livenessController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('liveness_detection_screen'),
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Liveness Detection - Front Camera'),
        backgroundColor: Colors.pink,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Status bar
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.camera_front, color: Colors.white, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Camera preview with 3:5 aspect ratio
            Expanded(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: AspectRatio(
                    aspectRatio: 3 / 5,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        children: [
                          if (_isCameraInitialized && _cameraController != null)
                            Positioned.fill(
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _cameraController!
                                      .value
                                      .previewSize!
                                      .height,
                                  height: _cameraController!
                                      .value
                                      .previewSize!
                                      .width,
                                  child: CameraPreview(_cameraController!),
                                ),
                              ),
                            )
                          else
                            Container(
                              color: Colors.black,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                            ),

                          // Border overlay
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.pink, width: 3),
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),

                          // Liveness indicators overlay (always present, visibility controlled)
                          Positioned(
                            top: 20,
                            left: 0,
                            right: 0,
                            child: Visibility(
                              visible: _isCameraInitialized && !_isDetecting,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildLivenessIndicator(
                                    'Blink',
                                    _blinkDetected,
                                  ),
                                  const SizedBox(width: 16),
                                  _buildLivenessIndicator(
                                    'Smile',
                                    _smileDetected,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Face guide (always present, visibility controlled)
                          Center(
                            child: Visibility(
                              visible: _isCameraInitialized && !_isDetecting,
                              child: Container(
                                width: 250,
                                height: 300,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.5),
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(150),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Info panel
            Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_front, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Using CameraX Front-Facing Camera',
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ML Kit tracking blink & smile...',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _blinkDetected
                              ? Icons.check_circle
                              : Icons.visibility,
                          color: _blinkDetected ? Colors.green : Colors.grey,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Blink',
                          style: TextStyle(
                            color: _blinkDetected
                                ? Colors.green
                                : Colors.grey[400],
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          _smileDetected
                              ? Icons.check_circle
                              : Icons.sentiment_satisfied,
                          color: _smileDetected ? Colors.green : Colors.grey,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Smile',
                          style: TextStyle(
                            color: _smileDetected
                                ? Colors.green
                                : Colors.grey[400],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLivenessIndicator(String label, bool completed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: completed
            ? Colors.green.withOpacity(0.8)
            : Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: completed ? Colors.green : Colors.white.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            completed ? Icons.check_circle : Icons.circle_outlined,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
