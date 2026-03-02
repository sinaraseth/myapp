import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';
import '../models/gaze_result.dart';

/// Gaze detection service using the MobileNetV2 ONNX model.
///
/// Key differences from the L2CS `GazeDetectionService`:
/// - Loads `mobilenetv2_gaze.onnx` instead of `l2cs_gaze360.onnx`.
/// - Applies ImageNet normalization (mean/std) during preprocessing.
/// - Uses **softmax → weighted-sum** decoding (90 bins, binwidth=4, offset=180°)
///   instead of argmax.
class GazeDetectionV1Service {
  OrtSession? _session;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: false,
      enableClassification: false,
      enableTracking: false,
      minFaceSize: 0.15,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  // ── Model constants (matching onnx_inference.py) ──────────────────────
  static const int inputSize = 448;
  static const int _bins = 90;
  static const double _binwidth = 4.0;
  static const double _angleOffset = 180.0;

  // ImageNet normalization
  static const List<double> _mean = [0.485, 0.456, 0.406];
  static const List<double> _std = [0.229, 0.224, 0.225];

  // Pre-computed index tensor [0, 1, 2, ..., 89]
  late final Float32List _idxTensor;

  // ── Face-distance estimation constants ────────────────────────────────
  static const double _realFaceWidthCm = 14.0;
  static const double _defaultFocalLengthPx = 504.0;

  GazeDetectionV1Service() {
    _idxTensor = Float32List(_bins);
    for (int i = 0; i < _bins; i++) {
      _idxTensor[i] = i.toDouble();
    }
  }

  double _estimateDistanceCm(double facePixelWidth, int imageWidth) {
    final scaledFocal = _defaultFocalLengthPx * (imageWidth / 640.0);
    return (_realFaceWidthCm * scaledFocal) / facePixelWidth;
  }

  // ── Model loading ─────────────────────────────────────────────────────

  Future<void> loadModel() async {
    try {
      print('🔍 Loading MobileNetV2 Gaze model...');

      ByteData assetData;
      try {
        assetData = await rootBundle.load('assets/mobilenetv2_gaze.onnx');
        print('✅ Asset found! Size: ${assetData.lengthInBytes} bytes');
      } catch (e) {
        print('❌ Asset NOT found in bundle: $e');
        throw Exception(
          'Model file not found in assets. '
          'Ensure assets/mobilenetv2_gaze.onnx is in pubspec.yaml',
        );
      }

      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/mobilenetv2_gaze.onnx';
      final modelFile = File(modelPath);

      if (await modelFile.exists()) {
        await modelFile.delete();
      }

      await modelFile.writeAsBytes(
        assetData.buffer.asUint8List(),
        flush: true,
      );
      print('✅ Model copied (${await modelFile.length()} bytes)');

      final sessionOptions = OrtSessionOptions();
      _session = OrtSession.fromFile(modelFile, sessionOptions);

      print('📋 Model Inputs:');
      for (var input in _session!.inputNames) {
        print('   - $input');
      }
      print('📋 Model Outputs:');
      for (var output in _session!.outputNames) {
        print('   - $output');
      }

      print('✅ MobileNetV2 Gaze model loaded successfully!');
    } catch (e) {
      print('❌ Error loading MobileNetV2 gaze model: $e');
      rethrow;
    }
  }

  // ── Prediction entry points ───────────────────────────────────────────

  /// Capture a still frame via [CameraController.takePicture] and run
  /// gaze inference. Returns null if no face is detected or on error.
  Future<GazeResult?> captureAndPredict(CameraController camera) async {
    try {
      final picture = await camera.takePicture();
      return await predictFromPath(picture.path);
    } catch (e) {
      print('❌ [V1Service] captureAndPredict error: $e');
      return null;
    }
  }

  Future<GazeResult?> predictFromPath(
    String imagePath, {
    bool isFrontCamera = true,
  }) async {
    try {
      if (_session == null) throw Exception('Model not loaded');

      final imageBytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(imageBytes);
      if (image == null) throw Exception('Failed to decode image');

      // Face detection via ML Kit
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        print('⚠️ No face detected');
        return null;
      }

      final face = faces.first;
      final bbox = face.boundingBox;

      // Expand bounding box slightly
      const expansion = 0.1;
      final expandX = bbox.width * expansion;
      final expandY = bbox.height * expansion;

      final left = max(0, bbox.left - expandX).toInt();
      final top = max(0, bbox.top - expandY).toInt();
      final right = min(image.width, bbox.right + expandX).toInt();
      final bottom = min(image.height, bbox.bottom + expandY).toInt();

      if (right <= left || bottom <= top) return null;

      // Crop and resize face
      final faceImage = img.copyCrop(
        image,
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      );
      final resizedImage = img.copyResize(
        faceImage,
        width: inputSize,
        height: inputSize,
      );

      // Preprocess with ImageNet normalization
      final inputData = _preprocessImage(resizedImage);

      // Run ONNX inference
      final runOptions = OrtRunOptions();
      final inputName = _session!.inputNames.first;
      final inputs = {
        inputName: OrtValueTensor.createTensorWithDataList(
          inputData,
          [1, 3, inputSize, inputSize],
        ),
      };

      final outputs = _session!.run(runOptions, inputs);
      if (outputs == null || outputs.isEmpty) {
        throw Exception('No outputs from model');
      }

      // Parse yaw / pitch logits
      final yawLogits = _extractOutput(outputs[0]);
      final pitchLogits = _extractOutput(outputs[1]);

      // Softmax → weighted-sum decode (matching onnx_inference.py)
      final yawRad = _decodeSoftmax(yawLogits);
      final pitchRad = _decodeSoftmax(pitchLogits);

      final yawDeg = yawRad * 180 / pi;
      final pitchDeg = pitchRad * 180 / pi;
      final direction = GazeResult.detectDirection(yawRad, pitchRad);

      final distanceCm = _estimateDistanceCm(bbox.width, image.width);

      print(
        '👁️ [MobileNetV2] Gaze: $direction '
        '(yaw: ${yawDeg.toStringAsFixed(1)}°, pitch: ${pitchDeg.toStringAsFixed(1)}°)'
        ' | 📏 dist≈${distanceCm.toStringAsFixed(0)}cm',
      );

      // Clean up
      outputs[0]?.release();
      outputs[1]?.release();
      inputs[inputName]?.release();
      runOptions.release();

      return GazeResult(
        yaw: yawRad,
        pitch: pitchRad,
        direction: direction,
        yawDegrees: yawDeg,
        pitchDegrees: pitchDeg,
        estimatedDistanceCm: distanceCm,
        faceWidthPx: bbox.width,
      );
    } catch (e) {
      print('❌ Error in MobileNetV2 gaze prediction: $e');
      return null;
    }
  }

  // ── Preprocessing ─────────────────────────────────────────────────────

  /// Resize to 448×448, convert to CHW float32, apply ImageNet
  /// normalization: (pixel / 255 − mean) / std.
  List<Object> _preprocessImage(img.Image image) {
    final Float32List data = Float32List(3 * inputSize * inputSize);
    int index = 0;

    for (int c = 0; c < 3; c++) {
      for (int y = 0; y < inputSize; y++) {
        for (int x = 0; x < inputSize; x++) {
          final pixel = image.getPixel(x, y);
          double value;
          if (c == 0) {
            value = pixel.r / 255.0;
          } else if (c == 1) {
            value = pixel.g / 255.0;
          } else {
            value = pixel.b / 255.0;
          }
          // ImageNet normalization
          data[index++] = (value - _mean[c]) / _std[c];
        }
      }
    }

    return data;
  }

  // ── Softmax decoding (matching onnx_inference.py) ─────────────────────

  /// softmax(logits) → weighted sum with idx_tensor → × binwidth − offset → radians
  double _decodeSoftmax(List<double> logits) {
    // softmax
    double maxVal = logits[0];
    for (int i = 1; i < logits.length; i++) {
      if (logits[i] > maxVal) maxVal = logits[i];
    }

    double sumExp = 0.0;
    final probs = Float32List(logits.length);
    for (int i = 0; i < logits.length; i++) {
      probs[i] = exp(logits[i] - maxVal);
      sumExp += probs[i];
    }
    for (int i = 0; i < probs.length; i++) {
      probs[i] /= sumExp;
    }

    // Weighted sum: Σ(prob_i × i)
    double weightedSum = 0.0;
    for (int i = 0; i < probs.length; i++) {
      weightedSum += probs[i] * _idxTensor[i];
    }

    // Convert to degrees then radians
    final degrees = weightedSum * _binwidth - _angleOffset;
    return degrees * pi / 180.0;
  }

  // ── Output parsing helper ─────────────────────────────────────────────

  List<double> _extractOutput(OrtValue? output) {
    if (output?.value is List<List<double>>) {
      return (output!.value as List<List<double>>)[0];
    } else if (output?.value is List<List<num>>) {
      return (output!.value as List<List<num>>)
          .first
          .map((e) => e.toDouble())
          .toList();
    } else if (output?.value is List<double>) {
      return output!.value as List<double>;
    } else {
      throw Exception(
        'Unexpected output format: ${output?.value?.runtimeType}',
      );
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────

  void dispose() {
    _faceDetector.close();
    _session?.release();
  }
}
