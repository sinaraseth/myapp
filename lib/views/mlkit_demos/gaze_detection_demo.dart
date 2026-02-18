import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../controllers/gaze_detection_controller.dart';
import '../../models/gaze_result.dart';

class GazeDetectionDemo extends StatefulWidget {
  const GazeDetectionDemo({super.key});

  @override
  State<GazeDetectionDemo> createState() => _GazeDetectionDemoState();
}

class _GazeDetectionDemoState extends State<GazeDetectionDemo>
    with SingleTickerProviderStateMixin {
  final GazeDetectionController _gazeController = GazeDetectionController();
  CameraController? _cameraController;
  late List<CameraDescription> _cameras;

  bool _isStreaming = false;
  bool _isLoading = false;
  bool _isCalibrating = false;

  GazeResult? _currentGaze;
  String _statusMessage = "";

  // Animation for progress circle
  late AnimationController _progressAnimationController;
  Animation<double>? _progressAnimation;

  // Calibration variables
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

  @override
  void initState() {
    super.initState();

    // Initialize animation controller for progress circle
    _progressAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000), // 1 seconds for full cycle
      vsync: this,
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _progressAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // Listen for animation completion
    _progressAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed && _isLookingAtTarget) {
        // Animation completed while looking at target - advance to next
        _advanceToNextTarget();
      }
    });

    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      await _gazeController.loadModel();
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
    _detectionTimer?.cancel();
    await _cameraController?.dispose();
    _cameraController = null;

    setState(() {
      _isStreaming = false;
      _isCalibrating = false;
      _currentGaze = null;
      _statusMessage = "";
    });
  }

  Future<void> _startCalibration() async {
    if (!_isStreaming || _cameraController == null) return;

    setState(() {
      _isCalibrating = true;
      _currentTargetIdx = 0;
      _statusMessage = "Look at: ${_calibrationSequence[_currentTargetIdx]}";
    });

    print('\n🎯 Starting gaze calibration...');
    print('Target: ${_calibrationSequence[_currentTargetIdx]}');

    // Start periodic detection - increased interval for 448x448 processing
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 300), (
      timer,
    ) {
      _detectGaze();
    });
  }

  void _stopCalibration() {
    _detectionTimer?.cancel();
    setState(() {
      _isCalibrating = false;
      _currentTargetIdx = 0;
      _statusMessage = "";
    });
    print('🛑 Calibration stopped');
  }

  Future<void> _detectGaze() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    // Prevent concurrent gaze detection calls
    if (_isProcessingGaze) {
      print('⏳ Still processing previous gaze detection...');
      return;
    }

    _isProcessingGaze = true;

    try {
      final image = await _cameraController!.takePicture();

      // Use file path directly for better face detection
      final result = await _gazeController.predictFromPath(image.path);

      if (result != null) {
        print(
          '👁️ Gaze detected: ${result.direction} (Pitch: ${result.pitchDegrees.toStringAsFixed(1)}°, Yaw: ${result.yawDegrees.toStringAsFixed(1)}°)',
        );
        setState(() => _currentGaze = result);

        if (_isCalibrating) {
          _checkCalibrationProgress(result);
        }
      } else {
        print('⚠️ No gaze detected');
        setState(() {
          _currentGaze = null;
        });
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
      // Just started looking at target - begin animation
      _isLookingAtTarget = true;
      _progressAnimationController.reset();
      _progressAnimationController.forward();
      print('👁️ Started looking at $currentTarget');
    } else if (!isCorrectDirection && _isLookingAtTarget) {
      // Looked away - pause and reset animation
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
      // Calibration complete!
      print('\n🎉 CALIBRATION COMPLETE! YOU ARE HUMAN!');
      _detectionTimer?.cancel();
      setState(() {
        _isCalibrating = false;
        _statusMessage = "✅ Calibration Complete! You are verified as human!";
      });

      // Show success dialog
      _showSuccessDialog();
    } else {
      setState(() {
        _statusMessage = "Look at: ${_calibrationSequence[_currentTargetIdx]}";
      });
      print('Next target: ${_calibrationSequence[_currentTargetIdx]}');
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 32),
            SizedBox(width: 8),
            Text('Success!'),
          ],
        ),
        content: const Text(
          'Calibration complete!\nYou are verified as human! ✅',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _currentTargetIdx = 0;
                _statusMessage = "";
              });
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Gaze Direction Detection'),
        backgroundColor: Colors.black.withOpacity(0.3),
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Camera preview
          _buildCameraPreview(),

          // Calibration overlay
          if (_isCalibrating) _buildCalibrationOverlay(),

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
                    // Center reference circle
                    CustomPaint(
                      size: const Size(240, 240),
                      painter: ReferenceCirclePainter(),
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
          painter: CalibrationTargetPainter(
            target: currentTarget,
            progress: _progressAnimation?.value ?? 0.0,
            currentGaze: _currentGaze,
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
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Gaze info card
              if (_currentGaze != null && !_isCalibrating)
                Card(
                  color: _getDirectionColor(
                    _currentGaze!.direction,
                  ).withOpacity(0.2),
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text(
                          '👁️ ${_currentGaze!.direction}',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: _getDirectionColor(_currentGaze!.direction),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Pitch: ${_currentGaze!.pitchDegrees.toStringAsFixed(1)}° | '
                          'Yaw: ${_currentGaze!.yawDegrees.toStringAsFixed(1)}°',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Control buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isStreaming && !_isCalibrating)
                    ElevatedButton.icon(
                      onPressed: _startCalibration,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Calibration'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    ),
                  if (_isCalibrating)
                    ElevatedButton.icon(
                      onPressed: _stopCalibration,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop Calibration'),
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
                    onPressed: _isLoading ? null : _toggleCamera,
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

  Color _getDirectionColor(String direction) {
    switch (direction) {
      case 'CENTER':
        return Colors.white;
      case 'RIGHT':
        return Colors.green;
      case 'LEFT':
        return Colors.cyan;
      case 'UP':
        return Colors.red;
      case 'DOWN':
        return Colors.purple;
      default:
        return Colors.white;
    }
  }
}

// Custom painter for reference circle
class ReferenceCirclePainter extends CustomPainter {
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

// Custom painter for calibration targets
class CalibrationTargetPainter extends CustomPainter {
  final String target;
  final double progress;
  final GazeResult? currentGaze;

  CalibrationTargetPainter({
    required this.target,
    required this.progress,
    this.currentGaze,
  });

  @override
  void paint(Canvas canvas, Size size) {
    print(
      '🎨 Painting calibration overlay - Target: $target, Progress: ${(progress * 100).toInt()}%, HasGaze: ${currentGaze != null}',
    );

    // Draw semi-transparent background
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

    // Draw arrow from center to target (guide arrow)
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

      // Draw main arrow line
      canvas.drawLine(arrowStart, arrowEnd, arrowPaint);

      // Draw arrowhead
      final arrowHeadPaint = Paint()
        ..color = color.withOpacity(0.8)
        ..style = PaintingStyle.fill;

      _drawArrowHead(canvas, arrowEnd, targetPos, arrowHeadPaint, 20);
    } else {
      // For CENTER, draw radiating circles for visual feedback
      final pulsePaint1 = Paint()
        ..color = color.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      final pulsePaint2 = Paint()
        ..color = color.withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      final pulsePaint3 = Paint()
        ..color = color.withOpacity(0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(targetPos, 60, pulsePaint1);
      canvas.drawCircle(targetPos, 80, pulsePaint2);
      canvas.drawCircle(targetPos, 100, pulsePaint3);
    }

    // Draw current gaze direction indicator (where user is looking)
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

      // Draw gaze line
      if (currentGaze!.direction != 'CENTER') {
        canvas.drawLine(center, gazeDirection, gazePaint);

        // Draw small circle at gaze endpoint
        final gazeDotPaint = Paint()
          ..color = gazeColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(gazeDirection, 12, gazeDotPaint);

        // Draw glow effect around dot
        final glowPaint = Paint()
          ..color = gazeColor.withOpacity(0.5)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(gazeDirection, 18, glowPaint);
      } else {
        // For CENTER gaze, draw a filled circle at center
        final gazeDotPaint = Paint()
          ..color = gazeColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, 12, gazeDotPaint);
      }
    } else {
      // No gaze detected - show warning text
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

    // Draw target
    final targetPaint = Paint()..color = color;
    canvas.drawCircle(targetPos, 15, targetPaint);

    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(targetPos, 25, ringPaint);

    // Draw progress circle
    final progressPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;

    final progressArcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(targetPos, 40, progressPaint);
    canvas.drawArc(
      Rect.fromCircle(center: targetPos, radius: 40),
      -3.14159 / 2,
      2 * 3.14159 * progress,
      false,
      progressArcPaint,
    );

    // Draw label - always below center for better visibility
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

    // Draw progress percentage
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
    // Calculate arrow direction
    final direction = targetPos - tip;
    final angle = atan2(direction.dy, direction.dx);

    // Arrow head points
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
  bool shouldRepaint(CalibrationTargetPainter oldDelegate) {
    return oldDelegate.target != target ||
        oldDelegate.progress != progress ||
        oldDelegate.currentGaze?.direction != currentGaze?.direction;
  }
}
