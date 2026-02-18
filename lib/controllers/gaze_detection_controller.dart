import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';
import '../models/gaze_result.dart';

class GazeDetectionController {
  OrtSession? _session;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableClassification: false,
      enableTracking: false,
      minFaceSize: 0.1, // Reduced to detect smaller faces
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  static const int inputSize = 448;

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

  Future<GazeResult?> predict(File imageFile) async {
    return predictFromPath(imageFile.path);
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

  Future<GazeResult?> predictFromPath(String imagePath) async {
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

      // Get pitch and yaw outputs
      List<double> pitchOutput;
      List<double> yawOutput;

      try {
        // Try to get outputs - handle different possible formats
        if (outputs[0]?.value is List<List<double>>) {
          pitchOutput = (outputs[0]!.value as List<List<double>>)[0];
        } else if (outputs[0]?.value is List<List<num>>) {
          pitchOutput = (outputs[0]!.value as List<List<num>>)
              .map((e) => e.cast<double>())
              .first
              .cast<double>();
        } else if (outputs[0]?.value is List<double>) {
          pitchOutput = outputs[0]!.value as List<double>;
        } else {
          throw Exception(
            'Unexpected pitch output format: ${outputs[0]?.value?.runtimeType}',
          );
        }

        if (outputs[1]?.value is List<List<double>>) {
          yawOutput = (outputs[1]!.value as List<List<double>>)[0];
        } else if (outputs[1]?.value is List<List<num>>) {
          yawOutput = (outputs[1]!.value as List<List<num>>)
              .map((e) => e.cast<double>())
              .first
              .cast<double>();
        } else if (outputs[1]?.value is List<double>) {
          yawOutput = outputs[1]!.value as List<double>;
        } else {
          throw Exception(
            'Unexpected yaw output format: ${outputs[1]?.value?.runtimeType}',
          );
        }
      } catch (e) {
        print('❌ Error parsing outputs: $e');
        rethrow;
      }

      print('✅ Pitch output length: ${pitchOutput.length}');
      print('✅ Yaw output length: ${yawOutput.length}');

      // Find max indices (predicted angles)
      final pitchIdx = _argMax(pitchOutput);
      final yawIdx = _argMax(yawOutput);

      print('🎯 Pitch index: $pitchIdx, Yaw index: $yawIdx');

      // Convert to radians (L2CS model outputs bins, convert to degrees then radians)
      // Assuming 90 bins for -90 to 90 degrees
      final pitch = ((pitchIdx - 45) * 2 * pi / 180); // Convert to radians
      final yaw = ((yawIdx - 45) * 2 * pi / 180);

      final pitchDeg = pitch * 180 / pi;
      final yawDeg = yaw * 180 / pi;

      final direction = GazeResult.detectDirection(pitch, yaw);

      print(
        '👁️ Gaze: $direction (pitch: ${pitchDeg.toStringAsFixed(1)}°, yaw: ${yawDeg.toStringAsFixed(1)}°)',
      );

      outputs?[0]?.release();
      outputs?[1]?.release();
      inputs[inputName]?.release();
      runOptions.release();

      return GazeResult(
        pitch: pitch,
        yaw: yaw,
        direction: direction,
        pitchDegrees: pitchDeg,
        yawDegrees: yawDeg,
      );
    } catch (e) {
      print('❌ Error in gaze prediction: $e');
      return null;
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
