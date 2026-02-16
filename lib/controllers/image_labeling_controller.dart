import 'dart:io';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

class ImageLabelingController {
  final ImageLabeler _imageLabeler = ImageLabeler(
    options: ImageLabelerOptions(confidenceThreshold: 0.5),
  );

  Future<List<ImageLabel>> labelImage(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final labels = await _imageLabeler.processImage(inputImage);
      return labels;
    } catch (e) {
      print('Error labeling image: $e');
      return [];
    }
  }

  void dispose() {
    _imageLabeler.close();
  }
}
