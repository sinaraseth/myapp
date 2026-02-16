import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import '../../controllers/face_mesh_controller.dart';

class FaceMeshDemo extends StatefulWidget {
  const FaceMeshDemo({super.key});

  @override
  State<FaceMeshDemo> createState() => _FaceMeshDemoState();
}

class _FaceMeshDemoState extends State<FaceMeshDemo> {
  CameraController? _cameraController;
  late List<CameraDescription> _cameras;
  bool _isProcessing = false;
  bool _isCameraActive = false;
  List<FaceMesh> _faceMeshes = [];

  final FaceMeshController _faceMeshController = FaceMeshController();

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
        ResolutionPreset.medium,
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
        _faceMeshes = [];
      });
    } else {
      setState(() {
        _isCameraActive = true;
      });
      _startFaceMeshDetection();
    }
  }

  Future<void> _startFaceMeshDetection() async {
    while (_isCameraActive && mounted) {
      if (_isProcessing || _cameraController == null) {
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }

      _isProcessing = true;

      try {
        final image = await _cameraController!.takePicture();
        final faceMeshes = await _faceMeshController.detectFaceMesh(
          File(image.path),
        );

        if (mounted) {
          setState(() {
            _faceMeshes = faceMeshes;
          });
        }

        // Clean up the temporary file
        await File(image.path).delete();
      } catch (e) {
        print('Error detecting face mesh: $e');
      } finally {
        _isProcessing = false;
      }

      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceMeshController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Face Mesh Demo'),
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
                  children: [_buildMeshInfo(), _buildControls()],
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
        if (_faceMeshes.isNotEmpty && _isCameraActive)
          Positioned.fill(
            child: CustomPaint(painter: FaceMeshPainter(_faceMeshes)),
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
        label: Text(_isCameraActive ? 'Stop Detection' : 'Start Detection'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isCameraActive ? Colors.red : Colors.purple,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildMeshInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Text(
        _faceMeshes.isEmpty
            ? 'No face mesh detected'
            : '${_faceMeshes.length} face mesh(es) detected\nTotal points: ${_faceMeshes.fold(0, (sum, mesh) => sum + mesh.points.length)}',
        style: const TextStyle(fontSize: 16),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class FaceMeshPainter extends CustomPainter {
  final List<FaceMesh> faceMeshes;

  FaceMeshPainter(this.faceMeshes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.blue.withOpacity(0.5)
      ..strokeWidth = 1.0;

    for (final faceMesh in faceMeshes) {
      // Draw bounding box
      final rect = faceMesh.boundingBox;
      final boxPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.green
        ..strokeWidth = 3.0;
      canvas.drawRect(rect, boxPaint);

      // Draw mesh points
      for (final point in faceMesh.points) {
        canvas.drawCircle(
          Offset(point.x.toDouble(), point.y.toDouble()),
          2,
          paint,
        );
      }

      // Draw contours if available
      for (final contour in faceMesh.contours.values) {
        final contourPaint = Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.yellow
          ..strokeWidth = 2.0;

        final path = Path();
        if (contour != null && contour.isNotEmpty) {
          path.moveTo(contour[0].x.toDouble(), contour[0].y.toDouble());
          for (int i = 1; i < contour.length; i++) {
            path.lineTo(contour[i].x.toDouble(), contour[i].y.toDouble());
          }
          path.close();
        }
        canvas.drawPath(path, contourPaint);
      }
    }
  }

  @override
  bool shouldRepaint(FaceMeshPainter oldDelegate) => true;
}
