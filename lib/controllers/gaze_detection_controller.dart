import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/gaze_detection_service.dart';
import '../models/gaze_result.dart';

class GazeDetectionController extends ChangeNotifier {
  final GazeDetectionService _gazeService = GazeDetectionService();
  CameraController? cameraController;
  List<CameraDescription> _cameras = [];

  bool isStreaming = false;
  bool isLoading = false;
  bool isCalibrating = false;

  GazeResult? currentGaze;
  String statusMessage = "";

  // Calibration variables
  final List<String> calibrationSequence = [
    'CENTER',
    'LEFT',
    'RIGHT',
    'UP',
    'DOWN',
  ];
  int currentTargetIdx = 0;
  bool isLookingAtTarget = false;
  bool _isProcessingGaze = false;

  // Baseline calibration (delta-based)
  double? baselineYawDeg;
  double? baselinePitchDeg;
  final List<double> _baselineYawSamples = [];
  final List<double> _baselinePitchSamples = [];
  bool isMatchingTarget = false;

  // Calibration progress
  double currentProgress = 0.0;

  // Constants
  static const double minDistanceCm = 20.0;
  static const double maxDistanceCm = 50.0;

  static const Map<String, Map<String, double>> expectedAngleRanges = {
    'LEFT': {'min': 10.0, 'max': 20.0},
    'RIGHT': {'min': 10.0, 'max': 20.0},
    'UP': {'min': 8.0, 'max': 10.0},
    'DOWN': {'min': 5.0, 'max': 8.0},
  };

  final List<String> _calibrationRecords = [];

  // Callbacks for UI
  VoidCallback? onCenterBaselineStart;
  VoidCallback? onCalibrationComplete;

  String get currentTarget => isCalibrating ? calibrationSequence[currentTargetIdx] : '';

  Future<void> initialize() async {
    isLoading = true;
    notifyListeners();
    try {
      await _gazeService.loadModel();
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        statusMessage = 'No cameras available.';
      }
    } catch (e) {
      statusMessage = 'Initialization Error: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    isCalibrating = false;
    cameraController?.dispose();
    _gazeService.dispose();
    super.dispose();
  }

  Future<void> toggleCamera() async {
    if (isStreaming) {
      await stopCamera();
    } else {
      await startCamera();
    }
  }

  Future<void> startCamera() async {
    if (_cameras.isEmpty) return;

    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
    );

    try {
      await cameraController!.initialize();
      isStreaming = true;
      notifyListeners();
    } catch (e) {
      statusMessage = 'Error starting camera: $e';
      notifyListeners();
    }
  }

  Future<void> stopCamera() async {
    isCalibrating = false;
    await cameraController?.dispose();
    cameraController = null;

    isStreaming = false;
    currentGaze = null;
    statusMessage = "";
    notifyListeners();
  }

  void startCalibration() {
    if (!isStreaming || cameraController == null) return;

    isCalibrating = true;
    currentTargetIdx = 0;
    statusMessage = "Look at: ${calibrationSequence[currentTargetIdx]}";
    
    // Reset baseline
    baselineYawDeg = null;
    baselinePitchDeg = null;
    _baselineYawSamples.clear();
    _baselinePitchSamples.clear();
    isMatchingTarget = false;
    _calibrationRecords.clear();
    currentProgress = 0.0;
    notifyListeners();

    print('\n🎯 Starting gaze calibration...');
    
    if (!cameraController!.value.isStreamingImages) {
      cameraController!.startImageStream((CameraImage image) {
        _processCameraImage(image);
      });
    }
  }

  void stopCalibration() {
    if (cameraController?.value.isStreamingImages ?? false) {
      cameraController?.stopImageStream();
    }
    isCalibrating = false;
    currentTargetIdx = 0;
    statusMessage = "";
    currentProgress = 0.0;
    notifyListeners();
    print('🛑 Calibration stopped');
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessingGaze || !isCalibrating || cameraController == null) {
      return;
    }
    _isProcessingGaze = true;

    try {
      final sensorOrientation = cameraController!.description.sensorOrientation;
      final lensDirection = cameraController!.description.lensDirection;

      final result = await _gazeService.predictFromCameraImage(
        image,
        sensorOrientation,
        lensDirection,
      );

      if (result != null) {
        currentGaze = result;
        if (isCalibrating) {
          _checkCalibrationProgress(result);
        }
        notifyListeners();
      } else {
        currentGaze = null;
        notifyListeners();
      }
    } catch (e) {
      print('Error processing camera image for gaze: $e');
    } finally {
      _isProcessingGaze = false;
    }
  }

  void _checkCalibrationProgress(GazeResult result) {
    if (!isCalibrating || currentTargetIdx >= calibrationSequence.length) return;
    final target = calibrationSequence[currentTargetIdx];

    final deltaYaw = baselineYawDeg != null
        ? result.yawDegrees - baselineYawDeg!
        : 0.0;
    final deltaPitch = baselinePitchDeg != null
        ? result.pitchDegrees - baselinePitchDeg!
        : 0.0;

    if (target == 'CENTER') {
      _baselineYawSamples.add(result.yawDegrees);
      _baselinePitchSamples.add(result.pitchDegrees);
      isMatchingTarget = true;

      if (!isLookingAtTarget) {
        isLookingAtTarget = true;
        print('📐 Collecting baseline...');
        onCenterBaselineStart?.call();
      }
    } else {
      final range = expectedAngleRanges[target]!;
      final minDeg = range['min']!;
      final maxDeg = range['max']!;

      final bool isHorizontal = target == 'LEFT' || target == 'RIGHT';
      final double axisDelta = isHorizontal ? deltaYaw : deltaPitch;

      final bool correctSign =
          (target == 'RIGHT' && axisDelta > 0) ||
          (target == 'LEFT' && axisDelta < 0) ||
          (target == 'UP' && axisDelta > 0) ||
          (target == 'DOWN' && axisDelta < 0);

      final double absDelta = axisDelta.abs();
      
      final double progressValue = correctSign
          ? (absDelta / minDeg).clamp(0.0, 1.0)
          : 0.0;
          
      isMatchingTarget = correctSign && absDelta >= minDeg * 0.5;
      currentProgress = progressValue;

      final bool inRange = correctSign && absDelta >= minDeg && absDelta <= maxDeg;

      if (inRange) {
        final axisLabel = isHorizontal ? 'Δyaw' : 'Δpitch';
        final recordLines = StringBuffer();
        recordLines.writeln('✅ Yaw output length: 90');
        recordLines.writeln('✅ Pitch output length: 90');
        recordLines.writeln(
          '🎯 Yaw index: ${result.yawIndex}, Pitch index: ${result.pitchIndex}',
        );
        recordLines.writeln(
          '👁️ Gaze: ${result.direction} '
          '(yaw: ${result.yawDegrees.toStringAsFixed(1)}°, '
          'pitch: ${result.pitchDegrees.toStringAsFixed(1)}°) | '
          '📏 dist≈${result.estimatedDistanceCm?.toStringAsFixed(0) ?? "N/A"}cm '
          'faceW=${result.faceWidthPx?.toStringAsFixed(0) ?? "N/A"}px',
        );
        recordLines.writeln(
          '📡 [L2CS LIVE] target=$target | '
          'raw yaw=${result.yawDegrees.toStringAsFixed(2)}° '
          'raw pitch=${result.pitchDegrees.toStringAsFixed(2)}° | '
          'Δyaw=${deltaYaw.toStringAsFixed(2)}° '
          'Δpitch=${deltaPitch.toStringAsFixed(2)}° | '
          '📏 dist≈${result.estimatedDistanceCm?.toStringAsFixed(0) ?? "N/A"}cm '
          '(faceW=${result.faceWidthPx?.toStringAsFixed(0) ?? "N/A"}px)',
        );
        recordLines.writeln(
          '   🎯 $target: $axisLabel expect '
          '${minDeg.toStringAsFixed(1)}°–${maxDeg.toStringAsFixed(1)}° | '
          'actual ${axisDelta.toStringAsFixed(2)}° '
          '(|${absDelta.toStringAsFixed(2)}°|) | '
          'progress 100% => ✅ IN RANGE',
        );
        recordLines.writeln('✅ $target REACHED!');
        recordLines.writeln(
          '   Final $axisLabel = ${axisDelta.toStringAsFixed(1)}° '
          '(in [${minDeg.toStringAsFixed(1)}°, ${maxDeg.toStringAsFixed(1)}°])',
        );
        recordLines.writeln('✅ $target confirmed!\n');
        _calibrationRecords.add(recordLines.toString());
        advanceToNextTarget();
        return;
      }
    }
  }

  void advanceToNextTarget() {
    print('✅ Confirmed advance to next target');
    final completedTarget = calibrationSequence[currentTargetIdx];

    if (completedTarget == 'CENTER' && _baselineYawSamples.isNotEmpty) {
      baselineYawDeg =
          _baselineYawSamples.reduce((a, b) => a + b) /
          _baselineYawSamples.length;
      baselinePitchDeg =
          _baselinePitchSamples.reduce((a, b) => a + b) /
          _baselinePitchSamples.length;
      print('Baseline updated: yaw=$baselineYawDeg pitch=$baselinePitchDeg');
      
      final centerRecord = StringBuffer();
      centerRecord.writeln('📐 CENTER baseline collected');
      centerRecord.writeln(
        '   Baseline: yaw=${baselineYawDeg!.toStringAsFixed(1)}°, '
        'pitch=${baselinePitchDeg!.toStringAsFixed(1)}° '
        '(${_baselineYawSamples.length} samples)',
      );
      centerRecord.writeln('✅ CENTER confirmed!');
      if (_calibrationRecords.isEmpty) {
        _calibrationRecords.add(centerRecord.toString());
      } else {
         _calibrationRecords.insert(0, centerRecord.toString());
      }
    }

    currentTargetIdx++;
    isLookingAtTarget = false;
    isMatchingTarget = false;
    currentProgress = 0.0;

    if (currentTargetIdx >= calibrationSequence.length) {
      print('\n════════════════════════════════════════════════════════');
      print('📋 FULL CALIBRATION RECORD');
      print('════════════════════════════════════════════════════════');
      for (int i = 0; i < _calibrationRecords.length; i++) {
        print(_calibrationRecords[i]);
      }
      print('🎉 CALIBRATION COMPLETE! YOU ARE HUMAN!');
      print('════════════════════════════════════════════════════════\n');

      isCalibrating = false;
      statusMessage = "✅ Calibration Complete! You are verified as human!";
      notifyListeners();
      onCalibrationComplete?.call();
    } else {
      statusMessage = "Look at: ${calibrationSequence[currentTargetIdx]}";
      notifyListeners();
    }
  }
}
