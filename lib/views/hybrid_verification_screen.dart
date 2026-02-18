import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../controllers/gaze_detection_controller.dart';
import '../controllers/antispoofing_controller.dart';
import '../models/gaze_result.dart';
import '../models/antispoofing_result.dart';

class HybridVerificationScreen extends StatefulWidget {
  const HybridVerificationScreen({super.key});

  @override
  State<HybridVerificationScreen> createState() =>
      _HybridVerificationScreenState();
}

class _HybridVerificationScreenState extends State<HybridVerificationScreen>
    with SingleTickerProviderStateMixin {
  // Controllers
  final GazeDetectionController _gazeController = GazeDetectionController();
  final AntispoofingController _antispoofingController =
      AntispoofingController();
  CameraController? _cameraController;
  late List<CameraDescription> _cameras;

  // General state
  bool _isStreaming = false;
  bool _isLoading = false;
  bool _isVerifying = false;
  String _statusMessage = "";

  // Gaze calibration state
  GazeResult? _currentGaze;
  late AnimationController _progressAnimationController;
  Animation<double>? _progressAnimation;
  final List<String> _calibrationSequence = [
    'CENTER',
    'LEFT',
    'RIGHT',
    'UP',
    'DOWN',
  ];
  int _currentTargetIdx = 0;
  bool _isLookingAtTarget = false;
  Timer? _detectionTimer;
  bool _isProcessingGaze = false;
  bool _gazeCalibrationPassed = false;

  // Antispoofing background state
  final List<AntispoofingResult> _antispoofResults = [];
  AntispoofingResult? _finalAntispoofResult;
  bool _antispoofingDone = false;
  int _antispoofFramesCaptured = 0;
  int _gazeFrameCounter = 0;
  final List<List<int>> _antispoofSavedBytes = [];

  // Combined result
  bool? _hybridPassed;

  @override
  void initState() {
    super.initState();

    _progressAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _progressAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _progressAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed && _isLookingAtTarget) {
        _advanceToNextTarget();
      }
    });

    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      // Load both models
      await Future.wait([
        _gazeController.loadModel(),
        _antispoofingController.loadModel(),
      ]);
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
    _progressAnimationController.dispose();
    _cameraController?.dispose();
    _detectionTimer?.cancel();
    _gazeController.dispose();
    super.dispose();
  }

  // ==========================================
  // CAMERA
  // ==========================================

  Future<void> _toggleCamera() async {
    if (_isStreaming) {
      await _stopCamera();
    } else {
      await _startCamera();
    }
  }

  Future<void> _startCamera() async {
    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    _cameraController = CameraController(camera, ResolutionPreset.high);

    try {
      await _cameraController!.initialize();
      setState(() => _isStreaming = true);
    } catch (e) {
      _showError('Error starting camera: $e');
    }
  }

  Future<void> _stopCamera() async {
    _stopVerification();
    await _cameraController?.dispose();
    _cameraController = null;

    setState(() {
      _isStreaming = false;
      _currentGaze = null;
      _statusMessage = "";
    });
  }

  // ==========================================
  // HYBRID VERIFICATION
  // ==========================================

  Future<void> _startVerification() async {
    if (!_isStreaming || _cameraController == null) return;

    setState(() {
      _isVerifying = true;
      _currentTargetIdx = 0;
      _isLookingAtTarget = false;
      _gazeCalibrationPassed = false;
      _antispoofingDone = false;
      _antispoofResults.clear();
      _finalAntispoofResult = null;
      _hybridPassed = null;
      _antispoofFramesCaptured = 0;
      _gazeFrameCounter = 0;
      _antispoofSavedBytes.clear();
      _statusMessage = "Look at: ${_calibrationSequence[_currentTargetIdx]}";
    });

    print('\n🔄 ========================================');
    print('🔄 Starting HYBRID verification');
    print('🔄 Gaze calibration + Antispoofing');
    print('🔄 ========================================');

    // Start gaze detection timer (every 300ms)
    _detectionTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (timer) => _detectGaze(),
    );

    // Antispoofing frames will be captured from gaze detection frames
    // (frame 2 at ~600ms and frame 4 at ~1200ms)
  }

  void _stopVerification() {
    _detectionTimer?.cancel();
    _progressAnimationController.reset();

    setState(() {
      _isVerifying = false;
      _isLookingAtTarget = false;
      _currentTargetIdx = 0;
      _statusMessage = "";
    });

    print('🛑 Hybrid verification stopped');
  }

  // ==========================================
  // GAZE DETECTION & CALIBRATION
  // ==========================================

  Future<void> _detectGaze() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (_isProcessingGaze) return;

    _isProcessingGaze = true;

    try {
      final image = await _cameraController!.takePicture();
      final imageBytes = await image.readAsBytes();
      _gazeFrameCounter++;

      // Save frames for antispoofing at frame 2 (~600ms) and frame 4 (~1200ms)
      if (!_antispoofingDone && _antispoofSavedBytes.length < 2) {
        if (_gazeFrameCounter == 2 || _gazeFrameCounter == 4) {
          _antispoofSavedBytes.add(imageBytes);
          _antispoofFramesCaptured = _antispoofSavedBytes.length;
          print(
            '📸 [Antispoofing] Saved gaze frame $_gazeFrameCounter for liveness (${_antispoofSavedBytes.length}/2)',
          );
          setState(() {});

          // When we have 2 frames, kick off background processing
          if (_antispoofSavedBytes.length == 2) {
            _processAntispoofFrames();
          }
        }
      }

      final result = await _gazeController.predictFromPath(image.path);

      if (result != null) {
        print(
          '👁️ Gaze: ${result.direction} (P: ${result.pitchDegrees.toStringAsFixed(1)}°, Y: ${result.yawDegrees.toStringAsFixed(1)}°)',
        );
        setState(() => _currentGaze = result);

        if (_isVerifying && !_gazeCalibrationPassed) {
          _checkCalibrationProgress(result);
        }
      } else {
        setState(() => _currentGaze = null);
      }
    } catch (e) {
      print('Error detecting gaze: $e');
    } finally {
      _isProcessingGaze = false;
    }
  }

  void _checkCalibrationProgress(GazeResult result) {
    final currentTarget = _calibrationSequence[_currentTargetIdx];
    final isCorrectDirection = result.direction == currentTarget;

    if (isCorrectDirection && !_isLookingAtTarget) {
      _isLookingAtTarget = true;
      _progressAnimationController.reset();
      _progressAnimationController.forward();
      print('👁️ Started looking at $currentTarget');
    } else if (!isCorrectDirection && _isLookingAtTarget) {
      _isLookingAtTarget = false;
      _progressAnimationController.stop();
      _progressAnimationController.reset();
      print('⚠️ Looked away from $currentTarget');
    }

    setState(() {});
  }

  void _advanceToNextTarget() {
    final completedTarget = _calibrationSequence[_currentTargetIdx];
    print('✅ $completedTarget confirmed!');

    _currentTargetIdx++;
    _isLookingAtTarget = false;
    _progressAnimationController.reset();

    if (_currentTargetIdx >= _calibrationSequence.length) {
      // Gaze calibration complete!
      print('\n🎉 GAZE CALIBRATION COMPLETE!');
      _gazeCalibrationPassed = true;
      _detectionTimer?.cancel();

      setState(() {
        _statusMessage = "✅ Gaze verified! Checking liveness...";
      });

      // Check if antispoofing is also done
      _checkBothComplete();
    } else {
      setState(() {
        _statusMessage = "Look at: ${_calibrationSequence[_currentTargetIdx]}";
      });
      print('Next target: ${_calibrationSequence[_currentTargetIdx]}');
    }
  }

  // ==========================================
  // ANTISPOOFING BACKGROUND PROCESSING
  // ==========================================

  Future<void> _processAntispoofFrames() async {
    // Process saved frames in background - doesn't touch camera at all
    try {
      print('🤖 [Antispoofing] Processing 2 saved frames in background...');

      for (int i = 0; i < _antispoofSavedBytes.length; i++) {
        final bytes = _antispoofSavedBytes[i];
        print('🤖 [Antispoofing] Processing frame ${i + 1}...');
        final result = await _antispoofingController.predictFromBytes(
          bytes is List<int> ? Uint8List.fromList(bytes) : bytes as Uint8List,
        );
        _antispoofResults.add(result);
        print(
          '✅ [Antispoofing] Frame ${i + 1}: ${result.isLive ? "LIVE" : "SPOOF"} '
          '(confidence: ${(result.confidence * 100).toStringAsFixed(1)}%)',
        );
      }

      _computeAntispoofResult();
    } catch (e) {
      print('❌ [Antispoofing] Error processing frames: $e');
    }
  }

  void _computeAntispoofResult() {
    final validResults = _antispoofResults
        .where((r) => r.status == 'success')
        .toList();

    if (validResults.isEmpty) {
      _finalAntispoofResult = AntispoofingResult(
        isLive: false,
        liveProb: 0.0,
        spoofProb: 1.0,
        confidence: 0.0,
        status: 'no_face',
      );
    } else {
      final avgLiveProb =
          validResults.map((r) => r.liveProb).reduce((a, b) => a + b) /
          validResults.length;
      final avgSpoofProb =
          validResults.map((r) => r.spoofProb).reduce((a, b) => a + b) /
          validResults.length;
      final avgConfidence =
          validResults.map((r) => r.confidence).reduce((a, b) => a + b) /
          validResults.length;
      final isLive = avgLiveProb > 0.5;

      _finalAntispoofResult = AntispoofingResult(
        isLive: isLive,
        liveProb: avgLiveProb,
        spoofProb: avgSpoofProb,
        confidence: avgConfidence,
        status: 'success',
        faceBbox: validResults.first.faceBbox,
      );
    }

    _antispoofingDone = true;
    print(
      '📊 [Antispoofing] Final: ${_finalAntispoofResult!.isLive ? "LIVE" : "SPOOF"} '
      '(${(_finalAntispoofResult!.confidence * 100).toStringAsFixed(1)}%)',
    );

    _checkBothComplete();
  }

  // ==========================================
  // COMBINE RESULTS
  // ==========================================

  void _checkBothComplete() {
    if (!_gazeCalibrationPassed || !_antispoofingDone) {
      // One is still pending
      if (_gazeCalibrationPassed && !_antispoofingDone) {
        setState(() {
          _statusMessage = "✅ Gaze verified! Waiting for liveness check...";
        });
      }
      return;
    }

    // Both complete - determine final result
    _detectionTimer?.cancel();
    final isLive = _finalAntispoofResult?.isLive ?? false;
    final passed = _gazeCalibrationPassed && isLive;

    print('\n🏁 ========================================');
    print('🏁 HYBRID VERIFICATION COMPLETE');
    print('🏁 Gaze Calibration: ✅ PASSED');
    print('🏁 Antispoofing: ${isLive ? "✅ LIVE" : "❌ SPOOF"}');
    print('🏁 Final Result: ${passed ? "✅ VERIFIED" : "❌ FAILED"}');
    print('🏁 ========================================\n');

    setState(() {
      _isVerifying = false;
      _hybridPassed = passed;
      _statusMessage = passed
          ? "✅ Verification Complete - You are verified!"
          : "❌ Verification Failed - Liveness check did not pass";
    });

    _showResultDialog(passed);
  }

  void _showResultDialog(bool passed) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              passed ? Icons.check_circle : Icons.cancel,
              color: passed ? Colors.green : Colors.red,
              size: 32,
            ),
            const SizedBox(width: 8),
            Text(passed ? 'Verified!' : 'Failed'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDialogRow('Gaze Calibration', _gazeCalibrationPassed),
            const SizedBox(height: 8),
            _buildDialogRow(
              'Liveness Check',
              _finalAntispoofResult?.isLive ?? false,
            ),
            if (_finalAntispoofResult != null &&
                _finalAntispoofResult!.status == 'success') ...[
              const Divider(),
              Text(
                'Live: ${(_finalAntispoofResult!.liveProb * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 14),
              ),
              Text(
                'Spoof: ${(_finalAntispoofResult!.spoofProb * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 14),
              ),
              Text(
                'Confidence: ${(_finalAntispoofResult!.confidence * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 14),
              ),
            ],
            if (_finalAntispoofResult?.status == 'no_face')
              const Text(
                '\n⚠️ No face detected during liveness check',
                style: TextStyle(color: Colors.orange),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _currentTargetIdx = 0;
                _hybridPassed = null;
              });
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogRow(String label, bool passed) {
    return Row(
      children: [
        Icon(
          passed ? Icons.check_circle : Icons.cancel,
          color: passed ? Colors.green : Colors.red,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 16)),
      ],
    );
  }

  void _showError(String message) {
    setState(() {
      _statusMessage = message;
      _isLoading = false;
    });
  }

  // ==========================================
  // UI BUILD
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Hybrid Verification'),
        backgroundColor: Colors.black.withOpacity(0.3),
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Camera preview
          _buildCameraPreview(),

          // Calibration overlay (during verification)
          if (_isVerifying && !_gazeCalibrationPassed)
            _buildCalibrationOverlay(),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    return SizedBox.expand(
      child: Container(
        color: Colors.black,
        child: Center(
          child:
              _isStreaming &&
                  _cameraController != null &&
                  _cameraController!.value.isInitialized
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _cameraController!.value.previewSize!.height,
                          height: _cameraController!.value.previewSize!.width,
                          child: CameraPreview(_cameraController!),
                        ),
                      ),
                    ),
                    // Reference circle
                    CustomPaint(
                      size: const Size(240, 240),
                      painter: _ReferenceCirclePainter(),
                    ),
                  ],
                )
              : const Text(
                  'Camera is off',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
        ),
      ),
    );
  }

  Widget _buildCalibrationOverlay() {
    final size = MediaQuery.of(context).size;
    final currentTarget = _calibrationSequence[_currentTargetIdx];

    return AnimatedBuilder(
      animation: _progressAnimation ?? _progressAnimationController,
      builder: (context, child) {
        return CustomPaint(
          size: size,
          painter: _HybridCalibrationPainter(
            target: currentTarget,
            progress: _progressAnimation?.value ?? 0.0,
            currentGaze: _currentGaze,
            antispoofFramesCaptured: _antispoofFramesCaptured,
          ),
        );
      },
    );
  }

  Widget _buildBottomControls() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.8), Colors.transparent],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoading)
              const CircularProgressIndicator()
            else ...[
              // Status message
              if (_statusMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _hybridPassed == true
                        ? Colors.green.withOpacity(0.2)
                        : _hybridPassed == false
                        ? Colors.red.withOpacity(0.2)
                        : Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _hybridPassed == true
                          ? Colors.green
                          : _hybridPassed == false
                          ? Colors.red
                          : Colors.blue,
                    ),
                  ),
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Antispoofing background progress indicator
              if (_isVerifying)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _antispoofingDone
                            ? Icons.check_circle
                            : Icons.camera_alt,
                        color: _antispoofingDone ? Colors.green : Colors.orange,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _antispoofingDone
                            ? 'Liveness: ${_finalAntispoofResult!.isLive ? "✅ Live" : "❌ Spoof"}'
                            : 'Liveness check: $_antispoofFramesCaptured/2 frames',
                        style: TextStyle(
                          fontSize: 13,
                          color: _antispoofingDone
                              ? (_finalAntispoofResult!.isLive
                                    ? Colors.greenAccent
                                    : Colors.redAccent)
                              : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),

              // Result card
              if (_hybridPassed != null) _buildResultCard(),

              // Control buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isStreaming && !_isVerifying)
                    ElevatedButton.icon(
                      onPressed: _startVerification,
                      icon: const Icon(Icons.verified_user),
                      label: const Text('Start Verification'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    ),
                  if (_isVerifying)
                    ElevatedButton.icon(
                      onPressed: _stopVerification,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _isLoading || _isVerifying
                        ? null
                        : _toggleCamera,
                    icon: Icon(
                      _isStreaming ? Icons.videocam_off : Icons.videocam,
                    ),
                    label: Text(_isStreaming ? 'Stop Camera' : 'Start Camera'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isStreaming ? Colors.red : Colors.blue,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final gazeOk = _gazeCalibrationPassed;
    final livenessOk = _finalAntispoofResult?.isLive ?? false;
    final passed = gazeOk && livenessOk;

    return Card(
      color: (passed ? Colors.green : Colors.red).withOpacity(0.15),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              passed ? '✅ VERIFIED' : '❌ VERIFICATION FAILED',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: passed ? Colors.green : Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            _buildCheckRow(
              'Gaze Calibration',
              gazeOk,
              gazeOk ? 'All 5 directions confirmed' : 'Incomplete',
            ),
            const SizedBox(height: 4),
            _buildCheckRow(
              'Liveness Check',
              livenessOk,
              _finalAntispoofResult?.status == 'no_face'
                  ? 'No face detected'
                  : livenessOk
                  ? 'Live (${(_finalAntispoofResult!.confidence * 100).toStringAsFixed(1)}%)'
                  : 'Spoof detected (${(_finalAntispoofResult!.confidence * 100).toStringAsFixed(1)}%)',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckRow(String label, bool passed, String detail) {
    return Row(
      children: [
        Icon(
          passed ? Icons.check_circle : Icons.cancel,
          color: passed ? Colors.greenAccent : Colors.redAccent,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                detail,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ==========================================
// PAINTERS
// ==========================================

class _ReferenceCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 120, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HybridCalibrationPainter extends CustomPainter {
  final String target;
  final double progress;
  final GazeResult? currentGaze;
  final int antispoofFramesCaptured;

  _HybridCalibrationPainter({
    required this.target,
    required this.progress,
    this.currentGaze,
    required this.antispoofFramesCaptured,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Semi-transparent background
    final bgPaint = Paint()..color = Colors.black.withOpacity(0.3);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final offset = 140.0;

    Color color;
    Offset targetPos;
    String label;

    switch (target) {
      case 'CENTER':
        color = Colors.white;
        targetPos = Offset(centerX, centerY);
        label = 'Look at CENTER';
        break;
      case 'LEFT':
        color = Colors.cyan;
        targetPos = Offset(centerX - offset, centerY);
        label = '⬅️ Look LEFT';
        break;
      case 'RIGHT':
        color = Colors.green;
        targetPos = Offset(centerX + offset, centerY);
        label = 'Look RIGHT ➡️';
        break;
      case 'UP':
        color = Colors.red;
        targetPos = Offset(centerX, centerY - offset);
        label = '⬆️ Look UP';
        break;
      case 'DOWN':
        color = Colors.purple;
        targetPos = Offset(centerX, centerY + offset);
        label = '⬇️ Look DOWN';
        break;
      default:
        return;
    }

    // Draw arrow from center to target
    if (target != 'CENTER') {
      final arrowPaint = Paint()
        ..color = color.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;

      final center = Offset(centerX, centerY);
      final direction = targetPos - center;
      final arrowStart = center + direction * 0.3;
      final arrowEnd = center + direction * 0.7;

      canvas.drawLine(arrowStart, arrowEnd, arrowPaint);

      // Arrowhead
      final arrowHeadPaint = Paint()
        ..color = color.withOpacity(0.8)
        ..style = PaintingStyle.fill;
      _drawArrowHead(canvas, arrowEnd, targetPos, arrowHeadPaint, 20);
    } else {
      // Radiating circles for CENTER
      for (int i = 1; i <= 3; i++) {
        final pulsePaint = Paint()
          ..color = color.withOpacity(0.3 / i)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(targetPos, 40.0 + i * 20, pulsePaint);
      }
    }

    // Draw current gaze direction indicator
    if (currentGaze != null) {
      final gazeColor = currentGaze!.direction == target
          ? Colors.greenAccent
          : Colors.yellowAccent;

      final gazePaint = Paint()
        ..color = gazeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;

      final center = Offset(centerX, centerY);
      Offset gazeDirection;

      switch (currentGaze!.direction) {
        case 'LEFT':
          gazeDirection = Offset(centerX - 150, centerY);
          break;
        case 'RIGHT':
          gazeDirection = Offset(centerX + 150, centerY);
          break;
        case 'UP':
          gazeDirection = Offset(centerX, centerY - 150);
          break;
        case 'DOWN':
          gazeDirection = Offset(centerX, centerY + 150);
          break;
        default:
          gazeDirection = center;
      }

      if (currentGaze!.direction != 'CENTER') {
        canvas.drawLine(center, gazeDirection, gazePaint);
        final gazeDotPaint = Paint()
          ..color = gazeColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(gazeDirection, 12, gazeDotPaint);
        final glowPaint = Paint()
          ..color = gazeColor.withOpacity(0.5)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(gazeDirection, 18, glowPaint);
      } else {
        final gazeDotPaint = Paint()
          ..color = gazeColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, 12, gazeDotPaint);
      }
    } else {
      // No gaze - show warning
      final noGazePainter = TextPainter(
        text: TextSpan(
          text: '⚠️ Detecting face...',
          style: TextStyle(
            color: Colors.orange,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black,
                offset: const Offset(2, 2),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      noGazePainter.layout();
      noGazePainter.paint(
        canvas,
        Offset(centerX - noGazePainter.width / 2, centerY + 150),
      );
    }

    // Draw target dot + ring
    final targetPaint = Paint()..color = color;
    canvas.drawCircle(targetPos, 15, targetPaint);
    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(targetPos, 25, ringPaint);

    // Progress circle
    final progressBgPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    final progressArcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(targetPos, 40, progressBgPaint);
    canvas.drawArc(
      Rect.fromCircle(center: targetPos, radius: 40),
      -pi / 2,
      2 * pi * progress,
      false,
      progressArcPaint,
    );

    // Label text
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black,
              offset: const Offset(3, 3),
              blurRadius: 6,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(centerX - textPainter.width / 2, size.height - 200),
    );

    // Progress percentage
    final percentText = '${(progress * 100).toInt()}%';
    final percentPainter = TextPainter(
      text: TextSpan(
        text: percentText,
        style: TextStyle(
          color: color,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    percentPainter.layout();
    percentPainter.paint(
      canvas,
      Offset(
        targetPos.dx - percentPainter.width / 2,
        targetPos.dy - percentPainter.height / 2,
      ),
    );
  }

  void _drawArrowHead(
    Canvas canvas,
    Offset tip,
    Offset targetPos,
    Paint paint,
    double size,
  ) {
    final direction = targetPos - tip;
    final angle = atan2(direction.dy, direction.dx);

    final leftPoint = Offset(
      tip.dx + size * cos(angle + 2.5),
      tip.dy + size * sin(angle + 2.5),
    );
    final rightPoint = Offset(
      tip.dx + size * cos(angle - 2.5),
      tip.dy + size * sin(angle - 2.5),
    );

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(leftPoint.dx, leftPoint.dy)
      ..lineTo(rightPoint.dx, rightPoint.dy)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HybridCalibrationPainter oldDelegate) {
    return oldDelegate.target != target ||
        oldDelegate.progress != progress ||
        oldDelegate.currentGaze?.direction != currentGaze?.direction ||
        oldDelegate.antispoofFramesCaptured != antispoofFramesCaptured;
  }
}
