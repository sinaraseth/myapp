import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'dart:ui' show Size;
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';
import '../models/gaze_result.dart';

class GazeDetectionService {
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

  static const int inputSize = 448;

  // ── Face-distance estimation constants ──────────────────────────────
  // Average adult inter-ear face width ≈ 14 cm.
  static const double _realFaceWidthCm = 14.0;
  // Approximate horizontal focal length in pixels for 480p (medium preset).
  // Most front cameras have ~60-70° horizontal FOV.
  // At 640 px wide: focalPx ≈ 640 / (2 * tan(65°/2)) ≈ 640 / 1.27 ≈ 504.
  // Adjust if the camera is very different.
  static const double _defaultFocalLengthPx = 504.0;

  /// Estimate distance (cm) from camera to face using the pinhole model:
  ///   distance = (realFaceWidth × focalLength) / facePixelWidth
  /// [imageWidth] is used to scale the focal length if resolution differs.
  double _estimateDistanceCm(double facePixelWidth, int imageWidth) {
    // Scale focal length proportionally to actual image width vs 640
    final scaledFocal = _defaultFocalLengthPx * (imageWidth / 640.0);
    return (_realFaceWidthCm * scaledFocal) / facePixelWidth;
  }

  Future<void> loadModel() async {
    try {
      print('🔍 Loading L2CS Gaze360 model...');

      // Check if asset exists
      ByteData assetData;
      try {
        assetData = await rootBundle.load('assets/l2cs_gaze360.onnx');
        print('✅ Asset found! Size: ${assetData.lengthInBytes} bytes');
      } catch (e) {
        print('❌ Asset NOT found in bundle: $e');
        throw Exception(
          'Model file not found in assets. Ensure assets/l2cs_gaze360.onnx is in pubspec.yaml',
        );
      }

      // Get app directory for persistent storage
      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/l2cs_gaze360.onnx';
      final modelFile = File(modelPath);

      print('📁 Model will be saved to: $modelPath');

      // Delete existing model to force reload
      if (await modelFile.exists()) {
        print('🗑️ Deleting old model...');
        await modelFile.delete();
      }

      // Copy model from assets to file system
      print('📦 Copying model to file system...');
      await modelFile.writeAsBytes(assetData.buffer.asUint8List(), flush: true);
      print('✅ Model copied successfully (${await modelFile.length()} bytes)');

      // Verify file exists and has content
      if (!await modelFile.exists()) {
        throw Exception('Model file was not created successfully');
      }

      final fileSize = await modelFile.length();
      print('📊 Model file size: $fileSize bytes');

      if (fileSize == 0) {
        throw Exception('Model file is empty');
      }

      // Create session from file path
      print('🔧 Creating ONNX session...');
      final sessionOptions = OrtSessionOptions();
      _session = OrtSession.fromFile(modelFile, sessionOptions);

      // Print input/output names for debugging
      print('📋 Model Inputs:');
      for (var input in _session!.inputNames) {
        print('   - $input');
      }
      print('📋 Model Outputs:');
      for (var output in _session!.outputNames) {
        print('   - $output');
      }

      print('✅ Gaze model loaded successfully!');
    } catch (e) {
      print('❌ Error loading gaze model: $e');
      rethrow;
    }
  }

  Future<GazeResult?> predict(
    File imageFile, {
    bool isFrontCamera = true,
  }) async {
    return predictFromPath(imageFile.path, isFrontCamera: isFrontCamera);
  }

  Future<GazeResult?> predictFromBytes(Uint8List imageBytes) async {
    // Save bytes to temp file for face detection
    try {
      final tempDir = await getApplicationDocumentsDirectory();
      final tempFile = File('${tempDir.path}/temp_gaze.jpg');
      await tempFile.writeAsBytes(imageBytes);
      final result = await predictFromPath(tempFile.path);
      // Clean up
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      return result;
    } catch (e) {
      print('❌ Error in predictFromBytes: $e');
      return null;
    }
  }

  Future<GazeResult?> predictFromPath(
    String imagePath, {
    bool isFrontCamera = true,
  }) async {
    try {
      if (_session == null) {
        throw Exception('Model not loaded');
      }

      // Read image bytes for preprocessing
      final imageBytes = await File(imagePath).readAsBytes();

      // Decode image
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // Detect face using file path - this is the correct way for ML Kit
      final inputImage = InputImage.fromFilePath(imagePath);
      print('🔍 Processing image for face detection: $imagePath');
      print('📏 Image size: ${image.width}x${image.height}');

      final faces = await _faceDetector.processImage(inputImage);
      print('👤 Detected ${faces.length} face(s)');

      if (faces.isEmpty) {
        print('⚠️ No face detected in image');
        return null;
      }

      print('✅ Face detected! Bbox: ${faces.first.boundingBox}');

      // Get first face
      final face = faces.first;
      final bbox = face.boundingBox;

      // Expand bounding box slightly
      final expansion = 0.1;
      final expandX = bbox.width * expansion;
      final expandY = bbox.height * expansion;

      final left = max(0, bbox.left - expandX).toInt();
      final top = max(0, bbox.top - expandY).toInt();
      final right = min(image.width, bbox.right + expandX).toInt();
      final bottom = min(image.height, bbox.bottom + expandY).toInt();

      // Crop face
      final faceImage = img.copyCrop(
        image,
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      );

      // Resize to model input size
      final resizedImage = img.copyResize(
        faceImage,
        width: inputSize,
        height: inputSize,
      );

      // Normalize and prepare input tensor
      final inputData = _preprocessImage(resizedImage);

      // Run inference
      final runOptions = OrtRunOptions();

      // Get the actual input name from the model
      final inputName = _session!.inputNames.first;
      print('🔧 Using input name: $inputName');

      final inputs = {
        inputName: OrtValueTensor.createTensorWithDataList(inputData, [
          1,
          3,
          inputSize,
          inputSize,
        ]),
      };

      final outputs = _session!.run(runOptions, inputs);

      print('📊 Raw outputs: $outputs');
      print('📋 Number of outputs: ${outputs?.length}');

      if (outputs == null || outputs.isEmpty) {
        throw Exception('No outputs from model');
      }

      // Log details about each output
      for (int i = 0; i < outputs.length; i++) {
        final output = outputs[i];
        print(
          'Output $i - Type: ${output?.runtimeType}, Value type: ${output?.value?.runtimeType}',
        );
        if (output?.value is List) {
          final list = output!.value as List;
          print('  List length: ${list.length}');
          if (list.isNotEmpty) {
            print('  First element type: ${list.first.runtimeType}');
            print('  First element: ${list.first}');
          }
        }
      }

      // Get yaw and pitch outputs
      List<double> yawOutput;
      List<double> pitchOutput;

      try {
        // Try to get outputs - handle different possible formats
        if (outputs[0]?.value is List<List<double>>) {
          yawOutput = (outputs[0]!.value as List<List<double>>)[0];
        } else if (outputs[0]?.value is List<List<num>>) {
          yawOutput = (outputs[0]!.value as List<List<num>>)
              .map((e) => e.cast<double>())
              .first
              .cast<double>();
        } else if (outputs[0]?.value is List<double>) {
          yawOutput = outputs[0]!.value as List<double>;
        } else {
          throw Exception(
            'Unexpected yaw output format: ${outputs[0]?.value?.runtimeType}',
          );
        }

        if (outputs[1]?.value is List<List<double>>) {
          pitchOutput = (outputs[1]!.value as List<List<double>>)[0];
        } else if (outputs[1]?.value is List<List<num>>) {
          pitchOutput = (outputs[1]!.value as List<List<num>>)
              .map((e) => e.cast<double>())
              .first
              .cast<double>();
        } else if (outputs[1]?.value is List<double>) {
          pitchOutput = outputs[1]!.value as List<double>;
        } else {
          throw Exception(
            'Unexpected pitch output format: ${outputs[1]?.value?.runtimeType}',
          );
        }
      } catch (e) {
        print('❌ Error parsing outputs: $e');
        rethrow;
      }

      print('✅ Yaw output length: ${yawOutput.length}');
      print('✅ Pitch output length: ${pitchOutput.length}');

      // Find max indices (predicted angles)
      final yawIdx = _argMax(yawOutput);
      final pitchIdx = _argMax(pitchOutput);

      print('🎯 Yaw index: $yawIdx, Pitch index: $pitchIdx');

      // Convert to radians (L2CS model outputs bins, convert to degrees then radians)
      // Assuming 90 bins for -90 to 90 degrees
      final yaw = ((yawIdx - 45) * 2 * pi / 180); // Convert to radians
      final pitch = ((pitchIdx - 45) * 2 * pi / 180);

      final yawDeg = yaw * 180 / pi;
      final pitchDeg = pitch * 180 / pi;

      final direction = GazeResult.detectDirection(yaw, pitch);

      // Estimate face distance
      final distanceCm = _estimateDistanceCm(bbox.width, image.width);

      print(
        '👁️ Gaze: $direction (yaw: ${yawDeg.toStringAsFixed(1)}°, pitch: ${pitchDeg.toStringAsFixed(1)}°)'
        ' | 📏 dist≈${distanceCm.toStringAsFixed(0)}cm faceW=${bbox.width.toStringAsFixed(0)}px',
      );

      outputs?[0]?.release();
      outputs?[1]?.release();
      inputs[inputName]?.release();
      runOptions.release();

      return GazeResult(
        yaw: yaw,
        pitch: pitch,
        direction: direction,
        yawDegrees: yawDeg,
        pitchDegrees: pitchDeg,
        estimatedDistanceCm: distanceCm,
        faceWidthPx: bbox.width,
        yawIndex: yawIdx,
        pitchIndex: pitchIdx,
      );
    } catch (e) {
      print('❌ Error in gaze prediction: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  //  Real-time camera stream prediction (no disk I/O)
  // ──────────────────────────────────────────────────────────────────────

  /// Process a live [CameraImage] frame directly in memory.
  /// Much faster than takePicture() + predictFromPath() because it
  /// eliminates JPEG encoding, file writes, file reads, and JPEG decoding.
  Future<GazeResult?> predictFromCameraImage(
    CameraImage cameraImage,
    int sensorOrientation,
    CameraLensDirection lensDirection,
  ) async {
    try {
      if (_session == null) throw Exception('Model not loaded');

      final int width = cameraImage.width;
      final int height = cameraImage.height;

      // 1. Build NV21 bytes for ML Kit face detection
      final Uint8List nv21Bytes;
      if (cameraImage.planes.length == 1) {
        // Already NV21 (ImageFormatGroup.nv21)
        nv21Bytes = cameraImage.planes[0].bytes;
      } else {
        // YUV_420_888 → NV21
        nv21Bytes = _yuv420ToNv21(cameraImage);
      }

      // 2. ML Kit InputImage from raw bytes
      final rotation = _inputImageRotation(sensorOrientation);
      final inputImage = InputImage.fromBytes(
        bytes: nv21Bytes,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: cameraImage.planes[0].bytesPerRow,
        ),
      );

      // 3. Detect faces (fast mode, in-memory)
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) return null;

      // 4. Convert camera frame to img.Image for ONNX
      final img.Image rawImage;
      if (cameraImage.planes.length == 1) {
        rawImage = _nv21ToImage(nv21Bytes, width, height);
      } else {
        rawImage = _yuv420ToImage(cameraImage);
      }

      // 5. Rotate / mirror to match ML Kit coordinate system
      final orientedImage = _orientImage(
        rawImage,
        sensorOrientation,
        lensDirection,
      );

      // 6. Crop face using ML Kit bounding box
      final face = faces.first;
      final bbox = face.boundingBox;

      final expansion = 0.1;
      final expandX = bbox.width * expansion;
      final expandY = bbox.height * expansion;

      final left = max(0, bbox.left - expandX).toInt();
      final top = max(0, bbox.top - expandY).toInt();
      final right = min(
        orientedImage.width.toDouble(),
        bbox.right + expandX,
      ).toInt();
      final bottom = min(
        orientedImage.height.toDouble(),
        bbox.bottom + expandY,
      ).toInt();

      if (right <= left || bottom <= top) return null;

      final faceImage = img.copyCrop(
        orientedImage,
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      );

      // 7. Resize → preprocess → ONNX inference
      final resizedImage = img.copyResize(
        faceImage,
        width: inputSize,
        height: inputSize,
      );

      final inputData = _preprocessImage(resizedImage);

      final runOptions = OrtRunOptions();
      final inputName = _session!.inputNames.first;
      final inputs = {
        inputName: OrtValueTensor.createTensorWithDataList(inputData, [
          1,
          3,
          inputSize,
          inputSize,
        ]),
      };

      final outputs = _session!.run(runOptions, inputs);
      if (outputs == null || outputs.isEmpty) {
        throw Exception('No outputs from model');
      }

      List<double> yawOutput;
      List<double> pitchOutput;

      if (outputs[0]?.value is List<List<double>>) {
        yawOutput = (outputs[0]!.value as List<List<double>>)[0];
      } else if (outputs[0]?.value is List<List<num>>) {
        yawOutput = (outputs[0]!.value as List<List<num>>)
            .map((e) => e.cast<double>())
            .first
            .cast<double>();
      } else if (outputs[0]?.value is List<double>) {
        yawOutput = outputs[0]!.value as List<double>;
      } else {
        throw Exception(
          'Unexpected yaw format: ${outputs[0]?.value?.runtimeType}',
        );
      }

      if (outputs[1]?.value is List<List<double>>) {
        pitchOutput = (outputs[1]!.value as List<List<double>>)[0];
      } else if (outputs[1]?.value is List<List<num>>) {
        pitchOutput = (outputs[1]!.value as List<List<num>>)
            .map((e) => e.cast<double>())
            .first
            .cast<double>();
      } else if (outputs[1]?.value is List<double>) {
        pitchOutput = outputs[1]!.value as List<double>;
      } else {
        throw Exception(
          'Unexpected pitch format: ${outputs[1]?.value?.runtimeType}',
        );
      }

      final yawIdx = _argMax(yawOutput);
      final pitchIdx = _argMax(pitchOutput);

      final yaw = ((yawIdx - 45) * 2 * pi / 180);
      final pitch = ((pitchIdx - 45) * 2 * pi / 180);
      final yawDeg = yaw * 180 / pi;
      final pitchDeg = pitch * 180 / pi;
      final direction = GazeResult.detectDirection(yaw, pitch);

      // Estimate face distance (use oriented image width for focal scaling)
      final distanceCm = _estimateDistanceCm(bbox.width, orientedImage.width);

      outputs?[0]?.release();
      outputs?[1]?.release();
      inputs[inputName]?.release();
      runOptions.release();

      return GazeResult(
        yaw: yaw,
        pitch: pitch,
        direction: direction,
        yawDegrees: yawDeg,
        pitchDegrees: pitchDeg,
        estimatedDistanceCm: distanceCm,
        faceWidthPx: bbox.width,
        yawIndex: yawIdx,
        pitchIndex: pitchIdx,
      );
    } catch (e) {
      print('❌ Error in predictFromCameraImage: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  //  Format conversion helpers
  // ──────────────────────────────────────────────────────────────────────

  /// Convert YUV_420_888 (3 planes) → NV21 (single buffer, V-U interleaved).
  Uint8List _yuv420ToNv21(CameraImage image) {
    final int w = image.width;
    final int h = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

    final nv21 = Uint8List(w * h + w * (h ~/ 2));

    // Y plane
    int idx = 0;
    for (int row = 0; row < h; row++) {
      final int rowStart = row * yPlane.bytesPerRow;
      for (int col = 0; col < w; col++) {
        nv21[idx++] = yPlane.bytes[rowStart + col];
      }
    }
    // Interleave V, U
    for (int row = 0; row < h ~/ 2; row++) {
      final int uvRow = row * uPlane.bytesPerRow;
      for (int col = 0; col < w ~/ 2; col++) {
        final int off = uvRow + col * uvPixelStride;
        nv21[idx++] = vPlane.bytes[off];
        nv21[idx++] = uPlane.bytes[off];
      }
    }
    return nv21;
  }

  /// NV21 buffer → img.Image (RGB).
  img.Image _nv21ToImage(Uint8List nv21, int width, int height) {
    final image = img.Image(width: width, height: height);
    final int ySize = width * height;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yVal = nv21[y * width + x];
        final int uvIdx = ySize + (y ~/ 2) * width + (x & ~1);
        final int vVal = nv21[uvIdx];
        final int uVal = nv21[uvIdx + 1];

        int r = (yVal + 1.370705 * (vVal - 128)).round().clamp(0, 255);
        int g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128))
            .round()
            .clamp(0, 255);
        int b = (yVal + 1.732446 * (uVal - 128)).round().clamp(0, 255);

        image.setPixelRgb(x, y, r, g, b);
      }
    }
    return image;
  }

  /// YUV_420_888 (3 planes) → img.Image (RGB).
  img.Image _yuv420ToImage(CameraImage cam) {
    final int w = cam.width;
    final int h = cam.height;
    final yPlane = cam.planes[0];
    final uPlane = cam.planes[1];
    final vPlane = cam.planes[2];
    final int uvStride = uPlane.bytesPerPixel ?? 1;

    final image = img.Image(width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int yVal = yPlane.bytes[y * yPlane.bytesPerRow + x];
        final int off = (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2) * uvStride;
        final int uVal = uPlane.bytes[off];
        final int vVal = vPlane.bytes[off];

        int r = (yVal + 1.370705 * (vVal - 128)).round().clamp(0, 255);
        int g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128))
            .round()
            .clamp(0, 255);
        int b = (yVal + 1.732446 * (uVal - 128)).round().clamp(0, 255);

        image.setPixelRgb(x, y, r, g, b);
      }
    }
    return image;
  }

  /// Rotate to match ML Kit's coordinate system.
  /// We do NOT flip horizontally here — instead we negate yaw in the
  /// output so the bounding box from ML Kit stays valid on this image.
  img.Image _orientImage(
    img.Image src,
    int sensorOrientation,
    CameraLensDirection lensDirection,
  ) {
    var out = src;
    switch (sensorOrientation) {
      case 90:
        out = img.copyRotate(out, angle: 90);
        break;
      case 180:
        out = img.copyRotate(out, angle: 180);
        break;
      case 270:
        out = img.copyRotate(out, angle: 270);
        break;
    }
    return out;
  }

  /// Sensor orientation degrees → ML Kit InputImageRotation.
  InputImageRotation _inputImageRotation(int sensorOrientation) {
    switch (sensorOrientation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  List<Object> _preprocessImage(img.Image image) {
    final Float32List inputData = Float32List(3 * inputSize * inputSize);
    int index = 0;

    // Normalize to [0, 1] and convert to CHW format
    for (int c = 0; c < 3; c++) {
      for (int y = 0; y < inputSize; y++) {
        for (int x = 0; x < inputSize; x++) {
          final pixel = image.getPixel(x, y);
          double value;
          if (c == 0) {
            value = pixel.r / 255.0; // Red channel
          } else if (c == 1) {
            value = pixel.g / 255.0; // Green channel
          } else {
            value = pixel.b / 255.0; // Blue channel
          }
          inputData[index++] = value;
        }
      }
    }

    return inputData;
  }

  int _argMax(List<double> values) {
    int maxIndex = 0;
    double maxValue = values[0];

    for (int i = 1; i < values.length; i++) {
      if (values[i] > maxValue) {
        maxValue = values[i];
        maxIndex = i;
      }
    }

    return maxIndex;
  }

  void dispose() {
    _faceDetector.close();
    _session?.release();
  }
}
