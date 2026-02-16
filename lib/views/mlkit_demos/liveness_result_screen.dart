import 'dart:typed_data';
import 'package:flutter/material.dart';

class LivenessResultScreen extends StatelessWidget {
  final Uint8List capturedImage;
  final bool isRealPerson;
  final double confidence;

  const LivenessResultScreen({
    super.key,
    required this.capturedImage,
    required this.isRealPerson,
    required this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Liveness Detection Result'),
        backgroundColor: Colors.pink,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Result icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: isRealPerson
                        ? Colors.green.withOpacity(0.2)
                        : Colors.red.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isRealPerson ? Icons.verified_user : Icons.warning,
                    color: isRealPerson ? Colors.green : Colors.red,
                    size: 64,
                  ),
                ),

                const SizedBox(height: 24),

                // Result text
                Text(
                  isRealPerson ? 'REAL PERSON' : 'VALIDATION FAILED',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isRealPerson ? Colors.green : Colors.red,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 16),

                // Confidence
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Text(
                    'Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Captured image
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 350),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isRealPerson ? Colors.green : Colors.red,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: Image.memory(capturedImage, fit: BoxFit.cover),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Validation details
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isRealPerson
                        ? Colors.green.withOpacity(0.15)
                        : Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isRealPerson
                          ? Colors.green.withOpacity(0.3)
                          : Colors.red.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Validation Details',
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildValidationItem(
                        'CameraX Front Camera',
                        isRealPerson,
                      ),
                      const SizedBox(height: 8),
                      _buildValidationItem('Blink Detected', isRealPerson),
                      const SizedBox(height: 8),
                      _buildValidationItem('Smile Detected', isRealPerson),
                      const SizedBox(height: 8),
                      _buildValidationItem(
                        'Live Person Confirmed',
                        isRealPerson,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 20),
                        label: const Text(
                          'Close',
                          style: TextStyle(fontSize: 16),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.refresh, size: 24),
                        label: const Text(
                          'Try Again',
                          style: TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.pink,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildValidationItem(String label, bool passed) {
    return Row(
      children: [
        Icon(
          passed ? Icons.check_circle : Icons.cancel,
          color: passed ? Colors.green : Colors.red,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: Colors.grey[300], fontSize: 14),
          ),
        ),
      ],
    );
  }
}
