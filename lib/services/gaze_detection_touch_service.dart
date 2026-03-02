import 'package:camera/camera.dart';
import '../models/gaze_result.dart';
import 'gaze_detection_service.dart';

/// A thin wrapper around [GazeDetectionService] that captures a single
/// still frame via [CameraController.takePicture] and runs gaze inference.
/// This is used by the "tap-to-verify" touch calibration flow.
class GazeDetectionTouchService {
  final GazeDetectionService _service = GazeDetectionService();

  Future<void> loadModel() => _service.loadModel();

  /// Captures a picture from the camera and runs gaze detection on it.
  /// Returns null if no face is detected or on any error.
  Future<GazeResult?> captureAndPredict(CameraController camera) async {
    try {
      final picture = await camera.takePicture();
      return await _service.predictFromPath(picture.path);
    } catch (e) {
      print('❌ [TouchService] captureAndPredict error: $e');
      return null;
    }
  }

  void dispose() => _service.dispose();
}
