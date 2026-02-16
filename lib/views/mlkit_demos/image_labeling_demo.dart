import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import '../../controllers/image_labeling_controller.dart';

class ImageLabelingDemo extends StatefulWidget {
  const ImageLabelingDemo({super.key});

  @override
  State<ImageLabelingDemo> createState() => _ImageLabelingDemoState();
}

class _ImageLabelingDemoState extends State<ImageLabelingDemo> {
  CameraController? _cameraController;
  late List<CameraDescription> _cameras;
  bool _isProcessing = false;
  bool _isCameraActive = false;
  List<ImageLabel> _labels = [];

  final ImageLabelingController _imageLabelingController =
      ImageLabelingController();

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

  Future<void> _captureAndLabel() async {
    if (_isProcessing || _cameraController == null) return;

    setState(() {
      _isProcessing = true;
      _labels = [];
    });

    try {
      final image = await _cameraController!.takePicture();
      final labels = await _imageLabelingController.labelImage(
        File(image.path),
      );

      if (mounted) {
        setState(() {
          _labels = labels;
        });
      }

      // Clean up the temporary file
      await File(image.path).delete();
    } catch (e) {
      print('Error labeling image: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _toggleCamera() {
    setState(() {
      _isCameraActive = !_isCameraActive;
      if (!_isCameraActive) {
        _labels = [];
      }
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _imageLabelingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Image Labeling Demo'),
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
                    if (_labels.isNotEmpty) _buildLabelsList(),
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

    return SizedBox.expand(
      child: Container(
        color: Colors.black,
        child: _isCameraActive
            ? CameraPreview(_cameraController!)
            : const Center(
                child: Text(
                  'Camera Off\n\nTap "Start Camera" to begin',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton.icon(
            onPressed: _toggleCamera,
            icon: Icon(_isCameraActive ? Icons.videocam_off : Icons.videocam),
            label: Text(_isCameraActive ? 'Stop Camera' : 'Start Camera'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isCameraActive ? Colors.red : Colors.green,
            ),
          ),
          ElevatedButton.icon(
            onPressed: _isCameraActive && !_isProcessing
                ? _captureAndLabel
                : null,
            icon: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.camera_alt),
            label: const Text('Capture & Label'),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelsList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _labels.length,
        itemBuilder: (context, index) {
          final label = _labels[index];
          final confidence = (label.confidence * 100).toStringAsFixed(1);
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.red.withOpacity(0.2),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              title: Text(
                label.label,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$confidence%',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
