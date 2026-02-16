import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import '../../controllers/barcode_controller.dart';

class BarcodeScanningDemo extends StatefulWidget {
  const BarcodeScanningDemo({super.key});

  @override
  State<BarcodeScanningDemo> createState() => _BarcodeScanningDemoState();
}

class _BarcodeScanningDemoState extends State<BarcodeScanningDemo> {
  CameraController? _cameraController;
  late List<CameraDescription> _cameras;
  bool _isProcessing = false;
  bool _isCameraActive = false;
  List<Barcode> _barcodes = [];

  final BarcodeController _barcodeController = BarcodeController();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      final camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      setState(() {});
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  Future<void> _toggleCamera() async {
    if (_isCameraActive) {
      setState(() {
        _isCameraActive = false;
        _barcodes = [];
      });
    } else {
      setState(() {
        _isCameraActive = true;
      });
      _startBarcodeScanning();
    }
  }

  Future<void> _startBarcodeScanning() async {
    while (_isCameraActive && mounted) {
      if (_isProcessing || _cameraController == null) {
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }

      _isProcessing = true;

      try {
        final image = await _cameraController!.takePicture();
        final barcodes = await _barcodeController.scanBarcodes(
          File(image.path),
        );

        if (mounted) {
          setState(() {
            _barcodes = barcodes;
          });
        }

        // Clean up the temporary file
        await File(image.path).delete();
      } catch (e) {
        print('Error scanning barcodes: $e');
      } finally {
        _isProcessing = false;
      }

      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Barcode Scanning Demo'),
        backgroundColor: Colors.black.withOpacity(0.3),
        elevation: 0,
      ),
      body: Container(
        color: Colors.black,
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: _buildCameraPreview(),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_barcodes.isNotEmpty) _buildBarcodeInfo(),
                    _buildControls(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Stack(
      children: [
        SizedBox.expand(
          child: _isCameraActive
              ? CameraPreview(_cameraController!)
              : Container(
                  color: Colors.black,
                  child: const Center(
                    child: Text(
                      'Camera Off',
                      style: TextStyle(color: Colors.white, fontSize: 24),
                    ),
                  ),
                ),
        ),
        if (_barcodes.isNotEmpty && _isCameraActive)
          Positioned.fill(
            child: CustomPaint(painter: BarcodePainter(_barcodes)),
          ),
      ],
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton.icon(
        onPressed: _toggleCamera,
        icon: Icon(_isCameraActive ? Icons.stop : Icons.play_arrow),
        label: Text(_isCameraActive ? 'Stop Scanning' : 'Start Scanning'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isCameraActive ? Colors.red : Colors.orange,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildBarcodeInfo() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _barcodes.length,
        itemBuilder: (context, index) {
          final barcode = _barcodes[index];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Barcode ${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Type: ${barcode.type.name}'),
                  if (barcode.displayValue != null)
                    Text('Value: ${barcode.displayValue}'),
                  if (barcode.rawValue != null)
                    Text('Raw: ${barcode.rawValue}'),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class BarcodePainter extends CustomPainter {
  final List<Barcode> barcodes;

  BarcodePainter(this.barcodes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.green;

    for (final barcode in barcodes) {
      if (barcode.boundingBox != null) {
        canvas.drawRect(barcode.boundingBox!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(BarcodePainter oldDelegate) => true;
}
