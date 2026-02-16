import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class LivenessDetectionDemo extends StatefulWidget {
  const LivenessDetectionDemo({super.key});

  @override
  State<LivenessDetectionDemo> createState() => _LivenessDetectionDemoState();
}

class _LivenessDetectionDemoState extends State<LivenessDetectionDemo> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isDetecting = false;

  // Detection state
  String _statusMessage = 'Position your face in the frame';
  DetectionPhase _currentPhase = DetectionPhase.idle;
  double _progress = 0.0;
  int _blinkCount = 0;
  bool _smileDetected = false;

  // Results
  Uint8List? _capturedImage;
  List<String> _completedChecks = [];

  // Configurable thresholds
  int _blinkThreshold = 3;
  double _smileThreshold = 0.7;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('❌ Camera initialization error: $e');
      if (mounted) {
        setState(() {
          _statusMessage = 'Camera error: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _startLivenessDetection() async {
    if (_isDetecting) return;

    setState(() {
      _isDetecting = true;
      _currentPhase = DetectionPhase.preparing;
      _statusMessage = 'Preparing camera...';
      _progress = 0.0;
      _blinkCount = 0;
      _smileDetected = false;
      _completedChecks.clear();
      _capturedImage = null;
    });

    try {
      // Phase 1: Detecting face
      await _updatePhase(
        DetectionPhase.detectingFace,
        'Looking for face...',
        0.1,
      );
      await Future.delayed(const Duration(seconds: 1));

      // Phase 2: Face detected
      await _updatePhase(
        DetectionPhase.faceDetected,
        'Face detected! Hold steady...',
        0.2,
      );
      await Future.delayed(const Duration(seconds: 1));

      // Phase 3: Blink detection
      await _updatePhase(
        DetectionPhase.waitingBlink,
        'Please blink $_blinkThreshold times',
        0.3,
      );

      for (int i = 0; i < _blinkThreshold; i++) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted || !_isDetecting) return;

        setState(() {
          _blinkCount = i + 1;
          _progress = 0.3 + (0.3 * (_blinkCount / _blinkThreshold));
          _statusMessage = 'Blink detected! ($_blinkCount/$_blinkThreshold)';
        });
      }

      _completedChecks.add('Blink detection ✓');

      // Phase 4: Smile detection
      await _updatePhase(
        DetectionPhase.waitingSmile,
        'Great! Now please smile 😊',
        0.65,
      );
      await Future.delayed(const Duration(milliseconds: 1500));

      setState(() {
        _smileDetected = true;
        _progress = 0.75;
        _statusMessage = 'Smile detected! ✓';
      });

      _completedChecks.add('Smile detection ✓');

      // ✅ Phase 5: Capture screenshot from preview (no plugin)
      await _updatePhase(DetectionPhase.capturing, 'Capturing image...', 0.85);
      await _captureFromPreview();
      await Future.delayed(const Duration(milliseconds: 500));

      _completedChecks.add('Image captured ✓');

      // ✅ Phase 6: Analyze (simulated)
      await _updatePhase(
        DetectionPhase.analyzing,
        'Analyzing for spoofing...',
        0.90,
      );
      await Future.delayed(const Duration(milliseconds: 800));

      _completedChecks.add('Anti-spoofing analysis ✓');

      // ✅ Generate result (simulated liveness check)
      final result = await _verifyLiveness();

      if (!mounted) return;

      setState(() {
        _progress = 1.0;
      });

      // Phase 7: Show result
      if (result.isLive) {
        await _updatePhase(
          DetectionPhase.success,
          '✅ REAL PERSON DETECTED',
          1.0,
        );
        _completedChecks.add('All checks passed ✓');
      } else {
        await _updatePhase(DetectionPhase.failed, '⚠️ SPOOF DETECTED', 1.0);
      }

      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _showResultDialog(result);
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Detection error: $e');
      debugPrint('❌ Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _currentPhase = DetectionPhase.failed;
          _statusMessage = '❌ Error occurred';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDetecting = false;
        });
      }
    }
  }

  // ✅ Capture image from camera preview
  Future<void> _captureFromPreview() async {
    try {
      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        debugPrint('⚠️ Camera not ready for capture');
        return;
      }

      final XFile image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();

      setState(() {
        _capturedImage = bytes;
      });

      debugPrint('✅ Image captured from preview: ${bytes.length} bytes');
    } catch (e) {
      debugPrint('❌ Failed to capture from preview: $e');
    }
  }

  Future<void> _updatePhase(
    DetectionPhase phase,
    String message,
    double progress,
  ) async {
    if (!mounted) return;
    setState(() {
      _currentPhase = phase;
      _statusMessage = message;
      _progress = progress;
    });
  }

  // ✅ Simulated liveness verification
  Future<LivenessResult> _verifyLiveness() async {
    await Future.delayed(const Duration(milliseconds: 800));

    // Simulated analysis based on completed checks
    final hasAllChecks = _blinkCount >= _blinkThreshold && _smileDetected;

    if (!hasAllChecks) {
      return LivenessResult(
        isLive: false,
        confidence: 0.45,
        reason: 'Incomplete liveness checks',
      );
    }

    // Simulate anti-spoofing detection
    // In production, this would use ML models
    final random = DateTime.now().millisecond;
    final isReal = random % 10 < 9; // 90% success rate for demo

    if (isReal) {
      return LivenessResult(
        isLive: true,
        confidence: 0.88 + (random % 12) / 100, // 88-99%
        reason:
            'All anti-spoofing checks passed:\n'
            '• Natural blink patterns detected\n'
            '• Genuine smile movements\n'
            '• No screen/print artifacts\n'
            '• Depth variation confirmed',
      );
    } else {
      return LivenessResult(
        isLive: false,
        confidence: 0.45 + (random % 30) / 100, // 45-75%
        reason:
            'Possible spoofing detected:\n'
            '• Static image patterns found\n'
            '• Suspicious motion characteristics\n'
            '• Screen reflection detected',
      );
    }
  }

  void _showResultDialog(LivenessResult result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 700),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: result.isLive ? Colors.green : Colors.red,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      result.isLive ? Icons.verified_user : Icons.warning,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        result.isLive
                            ? 'Verification Successful'
                            : 'Verification Failed',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Result emoji
                      Text(
                        result.isLive ? '✅' : '⚠️',
                        style: const TextStyle(fontSize: 60),
                      ),
                      const SizedBox(height: 16),

                      // Result text
                      Text(
                        result.isLive ? 'REAL PERSON' : 'SPOOF DETECTED',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: result.isLive ? Colors.green : Colors.red,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Confidence
                      Text(
                        'Confidence: ${(result.confidence * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Captured image
                      if (_capturedImage != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _capturedImage!,
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Reason
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: result.isLive
                              ? Colors.green.withOpacity(0.1)
                              : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: result.isLive
                                ? Colors.green.withOpacity(0.3)
                                : Colors.red.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result.isLive ? '✅ Analysis:' : '⚠️ Detection:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: result.isLive
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              result.reason,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Completed checks
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Completed Checks:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ..._completedChecks.map(
                              (check) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      size: 16,
                                      color: Colors.green,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        check,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          setState(() {
                            _currentPhase = DetectionPhase.idle;
                          });
                        },
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _startLivenessDetection();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.pink,
                        ),
                        child: const Text('Try Again'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _stopDetection() {
    setState(() {
      _isDetecting = false;
      _currentPhase = DetectionPhase.idle;
      _statusMessage = 'Position your face in the frame';
    });
  }

  Color _getPhaseColor() {
    switch (_currentPhase) {
      case DetectionPhase.idle:
        return Colors.grey;
      case DetectionPhase.preparing:
      case DetectionPhase.detectingFace:
        return Colors.blue;
      case DetectionPhase.faceDetected:
      case DetectionPhase.waitingBlink:
      case DetectionPhase.waitingSmile:
        return Colors.orange;
      case DetectionPhase.capturing:
      case DetectionPhase.analyzing:
        return Colors.purple;
      case DetectionPhase.success:
        return Colors.green;
      case DetectionPhase.failed:
        return Colors.red;
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Liveness Detection'),
        backgroundColor: Colors.pink,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top status card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getPhaseColor(),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        _isDetecting
                            ? Icons.face_retouching_natural
                            : Icons.face,
                        color: Colors.white,
                        size: 28,
                      ),
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

                  if (_isDetecting) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Progress: ${(_progress * 100).toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        if (_blinkCount > 0)
                          Text(
                            'Blinks: $_blinkCount/$_blinkThreshold',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Camera preview with 3:4 aspect ratio
            Expanded(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        children: [
                          // Camera preview
                          if (_isCameraInitialized && _cameraController != null)
                            Positioned.fill(
                              child: CameraPreview(_cameraController!),
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

                          // Idle overlay
                          if (!_isDetecting &&
                              _currentPhase == DetectionPhase.idle)
                            Positioned.fill(
                              child: Container(
                                color: Colors.black.withOpacity(0.4),
                                child: const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.face,
                                        size: 80,
                                        color: Colors.white,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'Ready to start',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                          // Face guide
                          if (_isDetecting)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: FaceGuidePainter(
                                  color: _getPhaseColor(),
                                  progress: _progress,
                                ),
                              ),
                            ),

                          // Real-time indicators
                          if (_isDetecting) ...[
                            // Blink indicator
                            if (_currentPhase == DetectionPhase.waitingBlink)
                              Positioned(
                                left: 16,
                                top: 100,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    children: [
                                      const Icon(
                                        Icons.remove_red_eye,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$_blinkCount/$_blinkThreshold',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // Smile indicator
                            if (_currentPhase == DetectionPhase.waitingSmile)
                              Positioned(
                                right: 16,
                                top: 100,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        _smileDetected
                                            ? Icons.sentiment_satisfied_alt
                                            : Icons.sentiment_neutral,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _smileDetected ? 'Done!' : 'Smile',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom controls
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  if (!_isDetecting) ...[
                    ElevatedButton.icon(
                      onPressed: _isCameraInitialized
                          ? _startLivenessDetection
                          : null,
                      icon: const Icon(Icons.play_arrow, size: 28),
                      label: const Text(
                        'Start Liveness Check',
                        style: TextStyle(fontSize: 18),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pink,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    OutlinedButton.icon(
                      onPressed: () => _showSettingsDialog(),
                      icon: const Icon(Icons.settings),
                      label: const Text('Detection Settings'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ] else ...[
                    OutlinedButton.icon(
                      onPressed: _stopDetection,
                      icon: const Icon(Icons.stop),
                      label: const Text(
                        'Cancel Detection',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.red),
                        backgroundColor: Colors.red.withOpacity(0.2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detection Settings'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Blinks Required: $_blinkThreshold'),
                Slider(
                  value: _blinkThreshold.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '$_blinkThreshold',
                  onChanged: (value) {
                    setDialogState(() {
                      _blinkThreshold = value.toInt();
                    });
                  },
                ),
                const SizedBox(height: 16),
                Text('Smile Threshold: ${(_smileThreshold * 100).toInt()}%'),
                Slider(
                  value: _smileThreshold,
                  min: 0.3,
                  max: 1.0,
                  divisions: 7,
                  onChanged: (value) {
                    setDialogState(() {
                      _smileThreshold = value;
                    });
                  },
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _blinkThreshold = 3;
                _smileThreshold = 0.7;
              });
              Navigator.pop(context);
            },
            child: const Text('Reset'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {});
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class FaceGuidePainter extends CustomPainter {
  final Color color;
  final double progress;

  FaceGuidePainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.30;

    final outerPaint = Paint()
      ..color = color.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    canvas.drawCircle(center, radius, outerPaint);

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius + 15),
      -3.14159 / 2,
      2 * 3.14159 * progress,
      false,
      progressPaint,
    );

    final cornerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    const cornerLength = 25.0;

    canvas.drawLine(
      center + Offset(-radius - 10, -radius - 10),
      center + Offset(-radius - 10 + cornerLength, -radius - 10),
      cornerPaint,
    );
    canvas.drawLine(
      center + Offset(-radius - 10, -radius - 10),
      center + Offset(-radius - 10, -radius - 10 + cornerLength),
      cornerPaint,
    );
    canvas.drawLine(
      center + Offset(radius + 10, -radius - 10),
      center + Offset(radius + 10 - cornerLength, -radius - 10),
      cornerPaint,
    );
    canvas.drawLine(
      center + Offset(radius + 10, -radius - 10),
      center + Offset(radius + 10, -radius - 10 + cornerLength),
      cornerPaint,
    );
    canvas.drawLine(
      center + Offset(-radius - 10, radius + 10),
      center + Offset(-radius - 10 + cornerLength, radius + 10),
      cornerPaint,
    );
    canvas.drawLine(
      center + Offset(-radius - 10, radius + 10),
      center + Offset(-radius - 10, radius + 10 - cornerLength),
      cornerPaint,
    );
    canvas.drawLine(
      center + Offset(radius + 10, radius + 10),
      center + Offset(radius + 10 - cornerLength, radius + 10),
      cornerPaint,
    );
    canvas.drawLine(
      center + Offset(radius + 10, radius + 10),
      center + Offset(radius + 10, radius + 10 - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(FaceGuidePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

enum DetectionPhase {
  idle,
  preparing,
  detectingFace,
  faceDetected,
  waitingBlink,
  waitingSmile,
  capturing,
  analyzing,
  success,
  failed,
}

class LivenessResult {
  final bool isLive;
  final double confidence;
  final String reason;

  LivenessResult({
    required this.isLive,
    required this.confidence,
    required this.reason,
  });
}
