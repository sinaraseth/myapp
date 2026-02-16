import 'dart:io';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';

class FaceMeshController {
  final FaceMeshDetector _faceMeshDetector = FaceMeshDetector(
    option: FaceMeshDetectorOptions.faceMesh,
  );

  Future<List<FaceMesh>> detectFaceMesh(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final faceMeshes = await _faceMeshDetector.processImage(inputImage);
      return faceMeshes;
    } catch (e) {
      print('Error detecting face mesh: $e');
      return [];
    }
  }

  void dispose() {
    _faceMeshDetector.close();
  }
}
