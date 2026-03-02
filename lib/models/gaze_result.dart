import 'dart:math';

class GazeResult {
  final double pitch;
  final double yaw;
  final String direction;
  final double pitchDegrees;
  final double yawDegrees;
  final double? estimatedDistanceCm;
  final double? faceWidthPx;
  final int? pitchIndex;
  final int? yawIndex;

  GazeResult({
    required this.pitch,
    required this.yaw,
    required this.direction,
    required this.pitchDegrees,
    required this.yawDegrees,
    this.estimatedDistanceCm,
    this.faceWidthPx,
    this.pitchIndex,
    this.yawIndex,
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
    final bool isRight = pitchDeg > leftRightThreshold;
    final bool isLeft = pitchDeg < -leftRightThreshold;
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

  static String detectDirectionFromBaseline(
    double currentPitchDeg,
    double currentYawDeg,
    double baselinePitchDeg,
    double baselineYawDeg,
    String target, {
    double threshold = 2.5,
  }) {
    final deltaPitch = currentPitchDeg - baselinePitchDeg;
    final deltaYaw = currentYawDeg - baselineYawDeg;

    // Thresholds for delta movement from baseline
    // Matched to dot offset (~140px) at typical phone distance (~35cm)
    final leftRightThreshold = threshold; // 2.5°
    final upThreshold = threshold * 0.7; // ~1.75° delta
    final downThreshold = threshold * 0.7; // ~1.75° delta

    // Directions according to current logic (deltaPitch handles L/R, deltaYaw handles U/D)
    
    // For LEFT/RIGHT, ONLY care about deltaPitch
    if (target == 'LEFT' || target == 'RIGHT') {
      if (deltaPitch < -leftRightThreshold) return "LEFT";
      if (deltaPitch > leftRightThreshold) return "RIGHT";
      // Fallback if they didn't look far enough left/right
      return "CENTER";
    }

    // For UP/DOWN, ONLY care about deltaYaw
    if (target == 'UP' || target == 'DOWN') {
      if (deltaYaw > upThreshold) return "UP";
      if (deltaYaw < -downThreshold) return "DOWN";
      // Fallback if they didn't look far enough up/down
      return "CENTER";
    }

    // Default/fallback for unexpected targets
    return "CENTER";
  }
}
