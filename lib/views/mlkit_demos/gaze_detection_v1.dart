import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../controllers/gaze_detection_v1_controller.dart';
import '../../models/gaze_result.dart';

class GazeDetectionV1 extends StatefulWidget {
  const GazeDetectionV1({super.key});

  @override
  State<GazeDetectionV1> createState() => _GazeDetectionV1State();
}

class _GazeDetectionV1State extends State<GazeDetectionV1>
    with SingleTickerProviderStateMixin {
  final GazeDetectionV1Controller _controller = GazeDetectionV1Controller();

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    _controller.initialize();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _controller.stopCamera();
    _controller.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────
  //  Dot positional helpers
  // ───────────────────────────────────────────────────────────────

  static const double _dotRadius = 36.0;
  static const double _edgePadding = 0.0;

  Offset _dotPosition(String target, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    switch (target) {
      case 'LEFT':
        return Offset(_edgePadding + _dotRadius, cy);
      case 'RIGHT':
        return Offset(size.width - _edgePadding - _dotRadius, cy);
      case 'UP':
        return Offset(cx, _edgePadding + _dotRadius + kToolbarHeight + 40);
      case 'DOWN':
        return Offset(cx, size.height - _edgePadding - _dotRadius - 100);
      case 'CENTER':
      default:
        return Offset(cx, cy);
    }
  }

  Color _dotColor(String target) {
    switch (target) {
      case 'CENTER':
        return Colors.white;
      case 'LEFT':
        return Colors.cyan;
      case 'RIGHT':
        return Colors.greenAccent;
      case 'UP':
        return Colors.redAccent;
      case 'DOWN':
        return Colors.purpleAccent;
      default:
        return Colors.white;
    }
  }

  // ───────────────────────────────────────────────────────────────
  //  Build
  // ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Gaze Detection V1 (MobileNetV2)'),
        backgroundColor: Colors.black54,
        elevation: 0,
      ),
      body: _controller.isLoading
          ? const _LoadingScreen()
          : !_controller.isStreaming
              ? _buildStartScreen()
              : _controller.calibrationComplete
                  ? _buildResultScreen()
                  : _buildCalibrationScreen(),
    );
  }

  // ───────────────────────────────────────────────────────────────
  //  Screens
  // ───────────────────────────────────────────────────────────────

  Widget _buildStartScreen() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.visibility, size: 80, color: Colors.orangeAccent),
              const SizedBox(height: 24),
              const Text(
                'Gaze Detection V1\n(MobileNetV2)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Uses the MobileNetV2 ONNX model with\n'
                'softmax decoding for gaze estimation.\n\n'
                'The first dot (CENTER) measures your baseline.\n'
                'Following dots verify your relative gaze.\n'
                'Look at each dot, then TAP it!',
                style: TextStyle(color: Colors.grey[300], fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _controller.startCamera,
                icon: const Icon(Icons.videocam),
                label: const Text('Start'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalibrationScreen() {
    final cc = _controller.cameraController!;
    final size = MediaQuery.of(context).size;
    final target = _controller.currentTarget;
    final dotPos = _dotPosition(target, size);
    final color = _dotColor(target);

    return Stack(
      children: [
        // ── Camera preview (full-screen) ──────────────────────────
        SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: cc.value.previewSize!.height,
              height: cc.value.previewSize!.width,
              child: CameraPreview(cc),
            ),
          ),
        ),

        // ── Pulsing dot ──────────────────────────────────────────
        if (!_controller.isCapturing)
          Positioned(
            left: dotPos.dx - _dotRadius,
            top: dotPos.dy - _dotRadius,
            child: GestureDetector(
              onTap: _controller.onDotTapped,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (_, __) {
                  final scale = _pulseAnimation.value;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: _dotRadius * 2,
                      height: _dotRadius * 2,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.85),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.6),
                            blurRadius: 24,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.touch_app,
                        color: Colors.black87,
                        size: 28,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

        // ── Capturing spinner ─────────────────────────────────────
        if (_controller.isCapturing)
          Positioned(
            left: dotPos.dx - _dotRadius,
            top: dotPos.dy - _dotRadius,
            child: SizedBox(
              width: _dotRadius * 2,
              height: _dotRadius * 2,
              child: CircularProgressIndicator(
                color: color,
                strokeWidth: 5,
              ),
            ),
          ),

        // ── Direction arrow label ─────────────────────────────────
        Positioned(
          left: 0,
          right: 0,
          top: size.height * 0.12,
          child: Center(
            child: _DirectionLabel(target: target, color: color),
          ),
        ),

        // ── Status message ────────────────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildBottomBar(color),
        ),
      ],
    );
  }

  Widget _buildBottomBar(Color dotColor) {
    final hasResult = _controller.lastCapturedGaze != null;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.85), Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Step ${_controller.currentTargetIdx + 1} / 5',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            _controller.statusMessage,
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(color: Colors.black, blurRadius: 4),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          if (hasResult) ...[
            const SizedBox(height: 6),
            Text(
              'Detected: ${_controller.lastCapturedGaze!.direction} '
              '(yaw ${_controller.lastCapturedGaze!.yawDegrees.toStringAsFixed(1)}° '
              'pitch ${_controller.lastCapturedGaze!.pitchDegrees.toStringAsFixed(1)}°)',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultScreen() {
    final allPassed = _controller.tapResults.entries
        .every((e) => e.value?.direction == e.key);
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                allPassed
                    ? Icons.verified_user
                    : Icons.warning_amber_rounded,
                color: allPassed ? Colors.greenAccent : Colors.orangeAccent,
                size: 72,
              ),
              const SizedBox(height: 16),
              Text(
                allPassed
                    ? 'You are Verified! 🎉'
                    : 'Verification Incomplete',
                style: TextStyle(
                  color: allPassed ? Colors.greenAccent : Colors.orangeAccent,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _controller.statusMessage,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              ...GazeDetectionV1Controller.sequence.map((dir) {
                final result = _controller.tapResults[dir];
                return _ResultRow(
                  targetDirection: dir,
                  gazeResult: result,
                  color: _dotColor(dir),
                );
              }),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _controller.restart,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
//  Helper Widgets
// ───────────────────────────────────────────────────────────────────────────

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.orangeAccent),
              SizedBox(height: 20),
              Text(
                'Loading MobileNetV2 gaze model...',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      );
}

class _DirectionLabel extends StatelessWidget {
  const _DirectionLabel({required this.target, required this.color});

  final String target;
  final Color color;

  String get _emoji {
    switch (target) {
      case 'LEFT':
        return '⬅️';
      case 'RIGHT':
        return '➡️';
      case 'UP':
        return '⬆️';
      case 'DOWN':
        return '⬇️';
      default:
        return '🎯';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        target == 'CENTER'
            ? '🎯 Set Baseline (CENTER) — TAP the dot'
            : '$_emoji  Look $target — then TAP the dot',
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.targetDirection,
    required this.gazeResult,
    required this.color,
  });

  final String targetDirection;
  final GazeResult? gazeResult;
  final Color color;

  @override
  Widget build(BuildContext context) {
    bool? passed;
    if (gazeResult == null) {
      passed = null;
    } else if (gazeResult!.direction == 'NONE') {
      passed = false;
    } else {
      passed = gazeResult!.direction == targetDirection;
    }

    final icon = passed == true
        ? Icons.check_circle
        : passed == false
            ? Icons.cancel
            : Icons.radio_button_unchecked;

    final iconColor = passed == true
        ? Colors.greenAccent
        : passed == false
            ? Colors.redAccent
            : Colors.white38;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  targetDirection,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (gazeResult != null && gazeResult!.direction != 'NONE')
                  Text(
                    'Yaw: ${gazeResult!.yawDegrees.toStringAsFixed(1)}° | Pitch: ${gazeResult!.pitchDegrees.toStringAsFixed(1)}°',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12),
                  )
                else if (gazeResult != null && gazeResult!.direction == 'NONE')
                  const Text(
                    'No face detected',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
          Column(
            children: [
              Icon(icon, color: iconColor, size: 26),
              const SizedBox(height: 2),
              Text(
                passed == true
                    ? 'PASS'
                    : passed == false
                        ? 'FAIL'
                        : '—',
                style: TextStyle(
                  color: iconColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
