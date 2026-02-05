import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:math';

class AntispoofingResult {
  final bool isLive;
  final double liveProb;
  final double spoofProb;
  final double confidence;
  final String status;
  final Rect? faceBbox;

  AntispoofingResult({
    required this.isLive,
    required this.liveProb,
    required this.spoofProb,
    required this.confidence,
    required this.status,
    this.faceBbox,
  });

  Map<String, dynamic> toJson() => {
    'is_live': isLive,
    'live_prob': liveProb,
    'spoof_prob': spoofProb,
    'confidence': confidence,
    'status': status,
    'face_bbox': faceBbox != null
        ? {
            'left': faceBbox!.left,
            'top': faceBbox!.top,
            'right': faceBbox!.right,
            'bottom': faceBbox!.bottom,
          }
        : null,
  };
}

class AntispoofingService {
  OrtSession? _session;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: false,
      enableClassification: false,
      minFaceSize: 0.15,
    ),
  );

  static const List<double> mean = [0.485, 0.456, 0.406];
  static const List<double> std = [0.229, 0.224, 0.225];
  static const int inputSize = 224;

  Future<void> loadModel() async {
    try {
      print('🔍 Checking for model in assets...');

      // Check if asset exists first
      ByteData assetData;
      try {
        assetData = await rootBundle.load('assets/antispoofing.onnx');
        print('✅ Asset found! Size: ${assetData.lengthInBytes} bytes');
      } catch (e) {
        print('❌ Asset NOT found in bundle: $e');
        print('Make sure assets/antispoofing.onnx is in pubspec.yaml');
        throw Exception(
          'Model file not found in assets. Run: flutter clean && flutter pub get',
        );
      }

      // Get app directory for persistent storage
      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/antispoofing.onnx';
      final modelFile = File(modelPath);

      print('📁 Model will be saved to: $modelPath');

      // Copy model from assets to file system
      if (!await modelFile.exists()) {
        print('📦 Copying model to file system...');
        await modelFile.writeAsBytes(
          assetData.buffer.asUint8List(),
          flush: true,
        );
        print(
          '✅ Model copied successfully (${await modelFile.length()} bytes)',
        );
      } else {
        print('✅ Model already exists at: $modelPath');
      }

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

      print('✅ Model loaded successfully!');
    } catch (e) {
      print('❌ Error loading model: $e');
      rethrow;
    }
  }

  Future<AntispoofingResult> predictFromBytes(Uint8List imageBytes) async {
    File? tempFile;
    try {
      // Decode, flip, and re-encode the image
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) {
        throw Exception('Failed to decode image');
      }
      final flippedImage = img.flipHorizontal(image);
      final flippedImageBytes = Uint8List.fromList(img.encodeJpg(flippedImage));

      // Write to a temporary file to create an InputImage
      final tempDir = await getTemporaryDirectory();
      tempFile = File(
        '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(flippedImageBytes);

      return await predict(tempFile);
    } catch (e) {
      print('❌ Prediction error from bytes: $e');
      rethrow;
    } finally {
      // Clean up the temporary file
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<AntispoofingResult> predict(File imageFile) async {
    if (_session == null) {
      throw Exception('Model not loaded. Call loadModel() first.');
    }

    try {
      final imageBytes = await imageFile.readAsBytes();
      final image = img.decodeImage(imageBytes);

      if (image == null) {
        throw Exception('Failed to decode image');
      }

      final inputImage = InputImage.fromFile(imageFile);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        return AntispoofingResult(
          isLive: false,
          liveProb: 0.0,
          spoofProb: 0.0,
          confidence: 0.0,
          status: 'no_face',
        );
      }

      final face = faces.first;
      final boundingBox = face.boundingBox;

      const padding = 20;
      final x1 = (boundingBox.left - padding).clamp(0, image.width).toInt();
      final y1 = (boundingBox.top - padding).clamp(0, image.height).toInt();
      final x2 = (boundingBox.right + padding).clamp(0, image.width).toInt();
      final y2 = (boundingBox.bottom + padding).clamp(0, image.height).toInt();

      final faceCropped = img.copyCrop(
        image,
        x: x1,
        y: y1,
        width: x2 - x1,
        height: y2 - y1,
      );

      final inputTensor = _preprocessImage(faceCropped);

      final shape = [1, 3, inputSize, inputSize];
      final ortValue = OrtValueTensor.createTensorWithDataList(
        inputTensor,
        shape,
      );
      final runOptions = OrtRunOptions();
      final outputs = await _session!.runAsync(runOptions, {'input': ortValue});

      final outputRaw = outputs?[0]?.value;
      if (outputRaw == null || outputRaw is! List || outputRaw.isEmpty) {
        throw Exception("Invalid model output");
      }

      final outputList = outputRaw.first as List;
      final liveProb = outputList[0] as double;
      final spoofProb = outputList[1] as double;

      final expLive = exp(liveProb);
      final expSpoof = exp(spoofProb);
      final sum = expLive + expSpoof;

      final normalizedLive = expLive / sum;
      final normalizedSpoof = expSpoof / sum;

      final isLive = normalizedLive > 0.5;
      final confidence = isLive ? normalizedLive : normalizedSpoof;

      return AntispoofingResult(
        isLive: isLive,
        liveProb: normalizedLive,
        spoofProb: normalizedSpoof,
        confidence: confidence,
        status: 'success',
        faceBbox: boundingBox,
      );
    } catch (e) {
      print('❌ Prediction error: $e');
      rethrow;
    }
  }

  Float32List _preprocessImage(img.Image image) {
    final resized = img.copyResize(
      image,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    final Float32List inputData = Float32List(1 * 3 * inputSize * inputSize);
    int pixelIndex = 0;

    for (int c = 0; c < 3; c++) {
      for (int h = 0; h < inputSize; h++) {
        for (int w = 0; w < inputSize; w++) {
          final pixel = resized.getPixel(w, h);
          double value;

          if (c == 0) {
            value = pixel.r / 255.0;
          } else if (c == 1) {
            value = pixel.g / 255.0;
          } else {
            value = pixel.b / 255.0;
          }

          inputData[pixelIndex++] = (value - mean[c]) / std[c];
        }
      }
    }

    return inputData;
  }

  void dispose() {
    _session?.release();
    _faceDetector.close();
  }
}
