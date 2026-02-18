import 'package:flutter/material.dart';
import 'mlkit_demos/live_detection_demo.dart';
import 'mlkit_demos/live_detection_demo_mlkit.dart';
import 'mlkit_demos/text_recognition_demo.dart';
import 'mlkit_demos/face_mesh_demo.dart';
import 'mlkit_demos/barcode_scanning_demo.dart';
import 'mlkit_demos/image_labeling_demo.dart';
import 'mlkit_demos/gaze_detection_demo.dart';
// import 'mlkit_demos/object_detection_demo.dart';

class MLKitDemoListScreen extends StatelessWidget {
  const MLKitDemoListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final demos = [
      {
        'title': 'Liveness Detection (Plugin)',
        'description': 'Real-time blink & smile detection ',
        'icon': Icons.face_retouching_natural,
        'color': Colors.pink,
        'screen': const LivenessDetectionPluginDemo(),
      },
      {
        'title': 'Liveness Detection (ML Kit)',
        'description': 'Image-based spoof detection',
        'icon': Icons.face_retouching_natural,
        'color': Colors.deepPurple,
        'screen': const LivenessDetectionDemoMLKit(),
      },
      {
        'title': 'Gaze Direction Detection',
        'description': 'Track eye gaze direction & calibration',
        'icon': Icons.remove_red_eye,
        'color': Colors.indigo,
        'screen': const GazeDetectionDemo(),
      },
      {
        'title': 'Text Recognition',
        'description': 'Recognize text in images',
        'icon': Icons.text_fields,
        'color': Colors.green,
        'screen': const TextRecognitionDemo(),
      },
      {
        'title': 'Face Mesh Detection',
        'description': 'Detect facial mesh and contours',
        'icon': Icons.face_6,
        'color': Colors.purple,
        'screen': const FaceMeshDemo(),
      },
      {
        'title': 'Barcode Scanning',
        'description': 'Scan and decode barcodes',
        'icon': Icons.qr_code_scanner,
        'color': Colors.orange,
        'screen': const BarcodeScanningDemo(),
      },
      {
        'title': 'Image Labeling',
        'description': 'Identify objects in images',
        'icon': Icons.label,
        'color': Colors.red,
        'screen': const ImageLabelingDemo(),
      },
      // {
      //   'title': 'Object Detection',
      //   'description': 'Detect and track objects',
      //   'icon': Icons.center_focus_strong,
      //   'color': Colors.teal,
      //   'screen': const ObjectDetectionDemo(),
      // },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('ML Kit Demos'),
        backgroundColor: Colors.blue,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: demos.length,
        itemBuilder: (context, index) {
          final demo = demos[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                radius: 30,
                backgroundColor: (demo['color'] as Color).withOpacity(0.2),
                child: Icon(
                  demo['icon'] as IconData,
                  color: demo['color'] as Color,
                  size: 30,
                ),
              ),
              title: Text(
                demo['title'] as String,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  demo['description'] as String,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => demo['screen'] as Widget,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
