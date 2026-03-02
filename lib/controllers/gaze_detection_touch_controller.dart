import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/gaze_detection_touch_service.dart';
import '../models/gaze_result.dart';

/// Manages state and logic for the "tap-to-verify" gaze calibration.
///
/// Flow:
/// 1. A dot is shown at the position for [currentTarget].
/// 2. User taps the dot → [onDotTapped] is called.
/// 3. We capture a frame and run gaze inference.
/// 4. If the predicted gaze direction matches [currentTarget] → ✅ pass.
/// 5. Result shown for 1 second, then advances to the next target.
/// 6. After all 5 targets, [calibrationComplete] becomes true.
class GazeDetectionTouchController extends ChangeNotifier {
  final GazeDetectionTouchService _service = GazeDetectionTouchService();

  CameraController? cameraController;
  List<CameraDescription> _cameras = [];

  // --- State ---
  bool isLoading = false;
  bool isStreaming = false;
  bool isCapturing = false;      // awaiting picture + inference
  bool calibrationComplete = false;

  GazeResult? lastCapturedGaze;  // gaze at the moment of the last tap

  // Per-direction results (null = not yet attempted)
  final Map<String, GazeResult?> tapResults = {
    'CENTER': null,
    'LEFT': null,
    'RIGHT': null,
    'UP': null,
    'DOWN': null,
  };

  String statusMessage = '';

  // --- Sequence ---
  static const List<String> sequence = [
    'CENTER',
    'LEFT',
    'RIGHT',
    'UP',
    'DOWN',
  ];

  int _currentTargetIdx = 0;
  int get currentTargetIdx => _currentTargetIdx;

  String get currentTarget =>
      _currentTargetIdx < sequence.length ? sequence[_currentTargetIdx] : '';

  // --- Init / Dispose ---

  Future<void> initialize() async {
    isLoading = true;
    notifyListeners();
    try {
      await _service.loadModel();
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        statusMessage = 'No cameras available.';
      }
    } catch (e) {
      statusMessage = 'Init error: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    cameraController?.dispose();
    _service.dispose();
    super.dispose();
  }

  // --- Camera ---

  Future<void> startCamera() async {
    if (_cameras.isEmpty) return;

    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    cameraController = CameraController(camera, ResolutionPreset.high);

    try {
      await cameraController!.initialize();
      isStreaming = true;
      statusMessage = 'Look at the dot and TAP it!';
      notifyListeners();
    } catch (e) {
      statusMessage = 'Camera error: $e';
      notifyListeners();
    }
  }

  Future<void> stopCamera() async {
    await cameraController?.dispose();
    cameraController = null;
    isStreaming = false;
    notifyListeners();
  }

  // --- Tap Handler ---

  /// Called when the user taps the on-screen dot.
  Future<void> onDotTapped() async {
    if (isCapturing ||
        calibrationComplete ||
        cameraController == null ||
        !cameraController!.value.isInitialized) {
      return;
    }

    isCapturing = true;
    statusMessage = '🔍 Checking your gaze...';
    notifyListeners();

    try {
      final result = await _service.captureAndPredict(cameraController!);
      lastCapturedGaze = result;

      final target = currentTarget;

      if (result == null) {
        // No face detected - store a dummy result or leave as null for 'unsuccessful capture'
        // For now let's store a dummy GazeResult with direction 'NONE' to indicate failure
        tapResults[target] = GazeResult(direction: 'NONE', yaw: 0, pitch: 0, pitchDegrees: 0, yawDegrees: 0);
        statusMessage = '❌ No face detected. Try again!';
        print('👁️ [$target] No face detected — FAILED');
      } else {
        String detectedDirection = result.direction;
        bool matched = false;

        if (target == 'CENTER') {
          // Center is the calibration/baseline dot. If we detect a face, we always pass.
          matched = true;
          detectedDirection = 'CENTER'; 
        } else {
          final baselineResult = tapResults['CENTER'];
          if (baselineResult != null && baselineResult.direction != 'NONE') {
            detectedDirection = GazeResult.detectDirectionFromBaseline(
              result.yawDegrees,
              result.pitchDegrees,
              baselineResult.yawDegrees,
              baselineResult.pitchDegrees,
              target,
            );
          }
          matched = detectedDirection == target;
        }

        final finalResult = GazeResult(
          yaw: result.yaw,
          pitch: result.pitch,
          direction: detectedDirection,
          yawDegrees: result.yawDegrees,
          pitchDegrees: result.pitchDegrees,
          estimatedDistanceCm: result.estimatedDistanceCm,
          faceWidthPx: result.faceWidthPx,
          yawIndex: result.yawIndex,
          pitchIndex: result.pitchIndex,
        );

        tapResults[target] = finalResult;

        print(
          '👁️ [$target] Detected: $detectedDirection '
          '(yaw: ${finalResult.yawDegrees.toStringAsFixed(1)}°, '
          'pitch: ${finalResult.pitchDegrees.toStringAsFixed(1)}°) '
          '→ ${matched ? "✅ PASS" : "❌ FAIL"}',
        );
        statusMessage = matched
            ? '✅ Great! You were looking at $target!'
            : '❌ Expected $target, detected $detectedDirection';
      }

      notifyListeners();

      // Show result for 1 second, then advance
      await Future.delayed(const Duration(seconds: 1));
      _advance();
    } catch (e) {
      print('❌ onDotTapped error: $e');
      statusMessage = 'Error: $e';
    } finally {
      isCapturing = false;
      notifyListeners();
    }
  }

  void _advance() {
    _currentTargetIdx++;
    if (_currentTargetIdx >= sequence.length) {
      calibrationComplete = true;
      final passed = tapResults.entries.every((e) => e.value?.direction == e.key);
      statusMessage = passed
          ? '🎉 All directions verified! You are human!'
          : '⚠️ Some directions did not match. Check results below.';
      _printFullRecord();
    } else {
      statusMessage = 'Look at the dot and TAP it!';
    }
    notifyListeners();
  }

  void _printFullRecord() {
    print('\n════════════════════════════════════════════════════════');
    print('📋 FULL TOUCH-GAZE CALIBRATION RECORD');
    print('════════════════════════════════════════════════════════');
    for (final entry in tapResults.entries) {
      final target = entry.key;
      final result = entry.value;

      if (result == null) {
        print('  — $target (Not Attempted)');
      } else if (result.direction == 'NONE') {
        print('  ❌ $target (No Face Detected)');
      } else {
        final matched = result.direction == target;
        final icon = matched ? '✅' : '❌';
        print('  $icon $target → Detected: ${result.direction} '
            '(yaw: ${result.yawDegrees.toStringAsFixed(1)}°, '
            'pitch: ${result.pitchDegrees.toStringAsFixed(1)}°)');
      }
    }
    final allPassed = tapResults.entries.every((e) => e.value?.direction == e.key);
    print(allPassed
        ? '🎉 CALIBRATION COMPLETE! YOU ARE HUMAN!'
        : '⚠️ CALIBRATION INCOMPLETE');
    print('════════════════════════════════════════════════════════\n');
  }

  void restart() {
    _currentTargetIdx = 0;
    calibrationComplete = false;
    lastCapturedGaze = null;
    tapResults.updateAll((key, value) => null);
    statusMessage = 'Look at the dot and TAP it!';
    notifyListeners();
  }
}
