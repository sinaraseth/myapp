// Example usage of AntispoofingController
// Shows how to test both API and ONNX model methods

import 'dart:io';
import 'package:flutter/services.dart';
import '../controllers/antispoofing_controller.dart';
import '../models/antispoofing_result.dart';
import '../models/api_result.dart';

class AntispoofingExample {
  final AntispoofingController controller = AntispoofingController();

  // ==========================================
  // OPTION 1: Test with LOCAL ONNX MODEL
  // ==========================================
  Future<void> testWithOnnxModel(File imageFile) async {
    print('🔬 Testing with LOCAL ONNX Model...\n');

    // Load the model first
    await controller.loadModel();

    // Make prediction
    final AntispoofingResult result = await controller.predict(imageFile);

    print('Result from ONNX Model:');
    print('  Is Live: ${result.isLive}');
    print('  Confidence: ${(result.confidence * 100).toStringAsFixed(2)}%');
    print('  Status: ${result.status}');
  }

  // From bytes
  Future<void> testWithOnnxModelFromBytes(Uint8List imageBytes) async {
    print('🔬 Testing with LOCAL ONNX Model (from bytes)...\n');

    await controller.loadModel();
    final AntispoofingResult result = await controller.predictFromBytes(
      imageBytes,
    );

    print('Result from ONNX Model:');
    print('  Is Live: ${result.isLive}');
    print('  Confidence: ${(result.confidence * 100).toStringAsFixed(2)}%');
  }

  // ==========================================
  // OPTION 2: Test with HUGGING FACE API
  // ==========================================
  Future<void> testWithApi(File imageFile) async {
    print('🌐 Testing with Hugging Face API...\n');

    // No need to load model for API
    final ApiResult result = await controller.predictWithApi(imageFile);

    print('Result from API:');
    print('  Success: ${result.success}');
    print('  Status Code: ${result.statusCode}');
    if (result.success) {
      print('  Data: ${result.data}');
    } else {
      print('  Error: ${result.error}');
    }
  }

  // From bytes
  Future<void> testWithApiFromBytes(Uint8List imageBytes) async {
    print('🌐 Testing with Hugging Face API (from bytes)...\n');

    final ApiResult result = await controller.predictWithApiFromBytes(
      imageBytes,
    );

    print('Result from API:');
    print('  Success: ${result.success}');
    if (result.success) {
      print('  Data: ${result.data}');
    } else {
      print('  Error: ${result.error}');
    }
  }

  // ==========================================
  // OPTION 3: Test BOTH and COMPARE
  // ==========================================
  Future<void> testBothMethods(File imageFile) async {
    print('⚖️  Testing BOTH methods for comparison...\n');

    // Test ONNX Model
    print('--- LOCAL ONNX MODEL ---');
    await controller.loadModel();
    final AntispoofingResult onnxResult = await controller.predict(imageFile);
    print('ONNX - Is Live: ${onnxResult.isLive}');
    print(
      'ONNX - Confidence: ${(onnxResult.confidence * 100).toStringAsFixed(2)}%\n',
    );

    // Test API
    print('--- HUGGING FACE API ---');
    final ApiResult apiResult = await controller.predictWithApi(imageFile);
    print('API - Success: ${apiResult.success}');
    print('API - Data: ${apiResult.data}\n');

    print('=== Comparison Complete ===');
  }

  void dispose() {
    controller.dispose();
  }
}
