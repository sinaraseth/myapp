import 'dart:io';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class BarcodeController {
  final BarcodeScanner _barcodeScanner = BarcodeScanner();

  Future<List<Barcode>> scanBarcodes(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final barcodes = await _barcodeScanner.processImage(inputImage);
      return barcodes;
    } catch (e) {
      print('Error scanning barcodes: $e');
      return [];
    }
  }

  void dispose() {
    _barcodeScanner.close();
  }
}
