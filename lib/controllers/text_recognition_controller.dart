import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class TextRecognitionController {
  final TextRecognizer _textRecognizer = TextRecognizer();

  Future<String> recognizeText(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      return recognizedText.text.isEmpty
          ? 'No text detected'
          : recognizedText.text;
    } catch (e) {
      print('Error recognizing text: $e');
      return 'Error: $e';
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}
