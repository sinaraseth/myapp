import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class LivenessController {
  FaceDetector? _faceDetector;

  void initializeFaceDetector() {
    final options = FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      minFaceSize: 0.15,
    );
    _faceDetector = FaceDetector(options: options);
  }

  Future<List<Face>> detectFaces(String imagePath) async {
    if (_faceDetector == null) {
      throw Exception('Face detector not initialized');
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _faceDetector!.processImage(inputImage);
      return faces;
    } catch (e) {
      print('Face detection error: $e');
      return [];
    }
  }

  bool checkBlink(Face face, bool leftEyeWasOpen, bool rightEyeWasOpen) {
    final leftEyeOpen = (face.leftEyeOpenProbability ?? 1.0) > 0.5;
    final rightEyeOpen = (face.rightEyeOpenProbability ?? 1.0) > 0.5;

    return leftEyeWasOpen && rightEyeWasOpen && !leftEyeOpen && !rightEyeOpen;
  }

  bool checkSmile(Face face) {
    final smileProb = face.smilingProbability ?? 0.0;
    return smileProb > 0.7;
  }

  double getLeftEyeOpenProbability(Face face) {
    return (face.leftEyeOpenProbability ?? 1.0) > 0.5 ? 1.0 : 0.0;
  }

  double getRightEyeOpenProbability(Face face) {
    return (face.rightEyeOpenProbability ?? 1.0) > 0.5 ? 1.0 : 0.0;
  }

  void dispose() {
    _faceDetector?.close();
  }
}
