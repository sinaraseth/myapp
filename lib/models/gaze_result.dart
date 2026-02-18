import 'dart:math';

class GazeResult {
  final double pitch;
  final double yaw;
  final String direction;
  final double pitchDegrees;
  final double yawDegrees;

  GazeResult({
    required this.pitch,
    required this.yaw,
    required this.direction,
    required this.pitchDegrees,
    required this.yawDegrees,
  });

  static String detectDirection(
    double pitch,
    double yaw, {
    double threshold = 7.0,
  }) {
    final pitchDeg = pitch * 180 / pi;
    final yawDeg = yaw * 180 / pi;

    // Per-direction thresholds (degrees)
    final leftRightThreshold = threshold; // 10°
    final upThreshold = threshold * 0.3; // 3° - very easy (small angle needed)
    final downThreshold = threshold * 0.5; // 5° - easy

    // Check each direction independently
    final bool isLeft = pitchDeg > leftRightThreshold;
    final bool isRight = pitchDeg < -leftRightThreshold;
    final bool isUp = yawDeg > upThreshold;
    final bool isDown = yawDeg < -downThreshold;

    // If nothing exceeds threshold, it's CENTER
    if (!isLeft && !isRight && !isUp && !isDown) {
      return "CENTER";
    }

    // Compare relative strength to pick dominant direction
    // Normalize each axis by its own threshold so they're comparable
    final hStrength = pitchDeg.abs() / leftRightThreshold;
    final vStrength = isUp
        ? yawDeg.abs() / upThreshold
        : yawDeg.abs() / downThreshold;

    if (vStrength >= hStrength) {
      if (isDown) return "DOWN";
      if (isUp) return "UP";
    }

    if (hStrength >= vStrength) {
      if (isLeft) return "LEFT";
      if (isRight) return "RIGHT";
    }

    // Fallback
    if (isUp) return "UP";
    if (isDown) return "DOWN";
    if (isLeft) return "LEFT";
    if (isRight) return "RIGHT";

    return "CENTER";
  }
}
