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
  final GazeDetectionController _controller = GazeDetectionController();

  // Animation for progress circle
  late AnimationController _progressAnimationController;
  Animation<double>? _progressAnimation;

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
      if (status == AnimationStatus.completed && _controller.isLookingAtTarget) {
        _controller.advanceToNextTarget();
      }
    });

    _controller.onCenterBaselineStart = () {
      _progressAnimationController.reset();
      _progressAnimationController.forward();
    };

    _controller.onCalibrationComplete = () {
      _showSuccessDialog();
    };

    _controller.initialize();
  }

  @override
  void dispose() {
    _progressAnimationController.dispose();
    _controller.dispose();
    super.dispose();
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
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, child) {
          return Stack(
            children: [
              _buildCameraPreview(),
              if (_controller.isCalibrating) _buildCalibrationOverlay(),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomControls(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCameraPreview() {
    return SizedBox.expand(
      child: Container(
        color: Colors.black,
        child: Center(
          child:
              _controller.isStreaming &&
                  _controller.cameraController != null &&
                  _controller.cameraController!.value.isInitialized
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _controller.cameraController!.value.previewSize!.height,
                          height: _controller.cameraController!.value.previewSize!.width,
                          child: CameraPreview(_controller.cameraController!),
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
    final currentTarget = _controller.currentTarget;

    return AnimatedBuilder(
      animation: _progressAnimation ?? _progressAnimationController,
      builder: (context, child) {
        final progress = currentTarget == 'CENTER' 
            ? (_progressAnimation?.value ?? 0.0) 
            : _controller.currentProgress;

        return CustomPaint(
          size: size,
          painter: CalibrationTargetPainter(
            target: currentTarget,
            progress: progress,
            currentGaze: _controller.currentGaze,
            isMatchingTarget: _controller.isMatchingTarget,
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
            if (_controller.isLoading)
              const CircularProgressIndicator()
            else ...[
              if (_controller.statusMessage.isNotEmpty && !_controller.isCalibrating)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: Text(
                    _controller.statusMessage,
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),

              if (_controller.currentGaze != null && !_controller.isCalibrating)
                Card(
                  color: _getDirectionColor(
                    _controller.currentGaze!.direction,
                  ).withOpacity(0.2),
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text(
                          '👁️ ${_controller.currentGaze!.direction}',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: _getDirectionColor(_controller.currentGaze!.direction),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Yaw: ${_controller.currentGaze!.yawDegrees.toStringAsFixed(1)}° | '
                          'Pitch: ${_controller.currentGaze!.pitchDegrees.toStringAsFixed(1)}°',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                        if (_controller.currentGaze!.estimatedDistanceCm != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '📏 Distance: ~${_controller.currentGaze!.estimatedDistanceCm!.toStringAsFixed(0)} cm',
                            style: TextStyle(
                              fontSize: 14,
                              color:
                                  _controller.currentGaze!.estimatedDistanceCm! <
                                          GazeDetectionController.minDistanceCm ||
                                      _controller.currentGaze!.estimatedDistanceCm! >
                                          GazeDetectionController.maxDistanceCm
                                      ? Colors.orangeAccent
                                      : Colors.greenAccent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_controller.isStreaming && !_controller.isCalibrating)
                    ElevatedButton.icon(
                      onPressed: () => _controller.startCalibration(),
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
                  if (_controller.isCalibrating)
                    ElevatedButton.icon(
                      onPressed: () => _controller.stopCalibration(),
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
                    onPressed: _controller.isLoading ? null : () => _controller.toggleCamera(),
                    icon: Icon(
                      _controller.isStreaming ? Icons.videocam_off : Icons.videocam,
                    ),
                    label: Text(_controller.isStreaming ? 'Stop Camera' : 'Start Camera'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _controller.isStreaming ? Colors.red : Colors.blue,
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
  final bool isMatchingTarget;

  CalibrationTargetPainter({
    required this.target,
    required this.progress,
    this.currentGaze,
    this.isMatchingTarget = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = Colors.black.withOpacity(0.3);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final offset = min(size.width, size.height) * 0.25;

    Color color;
    Offset targetPos;
    String label;

    switch (target) {
      case 'CENTER':
        color = Colors.white;
        targetPos = Offset(centerX, centerY);
        label = 'Look at the dot';
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

      final arrowHeadPaint = Paint()
        ..color = color.withOpacity(0.8)
        ..style = PaintingStyle.fill;

      _drawArrowHead(canvas, arrowEnd, targetPos, arrowHeadPaint, 20);
    }

    if (currentGaze != null) {
      final gazeColor = isMatchingTarget
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

    final targetPaint = Paint()..color = color;
    canvas.drawCircle(targetPos, 12, targetPaint);

    final progressBgPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    final progressArcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(targetPos, 22, progressBgPaint);
    canvas.drawArc(
      Rect.fromCircle(center: targetPos, radius: 22),
      -3.14159 / 2,
      2 * 3.14159 * progress,
      false,
      progressArcPaint,
    );

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
  bool shouldRepaint(CalibrationTargetPainter oldDelegate) {
    return oldDelegate.target != target ||
        oldDelegate.progress != progress ||
        oldDelegate.currentGaze?.direction != currentGaze?.direction ||
        oldDelegate.isMatchingTarget != isMatchingTarget;
  }
}
