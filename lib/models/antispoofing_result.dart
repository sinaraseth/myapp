import 'package:flutter/material.dart';

class AntispoofingResult {
  final bool isLive;
  final double liveProb;
  final double spoofProb;
  final double confidence;
  final String status;
  final Rect? faceBbox;

  AntispoofingResult({
    required this.isLive,
    required this.liveProb,
    required this.spoofProb,
    required this.confidence,
    required this.status,
    this.faceBbox,
  });

  Map<String, dynamic> toJson() => {
    'is_live': isLive,
    'live_prob': liveProb,
    'spoof_prob': spoofProb,
    'confidence': confidence,
    'status': status,
    'face_bbox': faceBbox != null
        ? {
            'left': faceBbox!.left,
            'top': faceBbox!.top,
            'right': faceBbox!.right,
            'bottom': faceBbox!.bottom,
          }
        : null,
  };
}
