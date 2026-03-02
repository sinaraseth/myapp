import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Result model for the calibration endpoint.
class CalibrationResult {
  final bool success;
  final String? message;
  final double? centerYaw;
  final double? centerPitch;
  final String? error;

  CalibrationResult({
    required this.success,
    this.message,
    this.centerYaw,
    this.centerPitch,
    this.error,
  });

  factory CalibrationResult.fromJson(Map<String, dynamic> json) {
    return CalibrationResult(
      success: true,
      message: json['message'] as String?,
      centerYaw: (json['center_yaw'] as num?)?.toDouble(),
      centerPitch: (json['center_pitch'] as num?)?.toDouble(),
    );
  }

  @override
  String toString() =>
      'CalibrationResult(success: $success, message: $message, '
      'centerYaw: $centerYaw, centerPitch: $centerPitch, error: $error)';
}

/// Result model for the gaze prediction endpoint.
class GazePredictionResult {
  final bool success;
  final double? rawYaw;
  final double? rawPitch;
  final double? deltaYaw;
  final double? deltaPitch;
  final String? direction;
  final double? centerYaw;
  final double? centerPitch;
  final String? error;

  GazePredictionResult({
    required this.success,
    this.rawYaw,
    this.rawPitch,
    this.deltaYaw,
    this.deltaPitch,
    this.direction,
    this.centerYaw,
    this.centerPitch,
    this.error,
  });

  factory GazePredictionResult.fromJson(Map<String, dynamic> json) {
    return GazePredictionResult(
      success: true,
      rawYaw: (json['raw_yaw'] as num?)?.toDouble(),
      rawPitch: (json['raw_pitch'] as num?)?.toDouble(),
      deltaYaw: (json['delta_yaw'] as num?)?.toDouble(),
      deltaPitch: (json['delta_pitch'] as num?)?.toDouble(),
      direction: json['direction'] as String?,
      centerYaw: (json['center_yaw'] as num?)?.toDouble(),
      centerPitch: (json['center_pitch'] as num?)?.toDouble(),
    );
  }

  @override
  String toString() =>
      'GazePredictionResult(success: $success, direction: $direction, '
      'deltaYaw: $deltaYaw, deltaPitch: $deltaPitch, '
      'rawYaw: $rawYaw, rawPitch: $rawPitch)';
}

/// Controller for the Flask-based Gaze Detection API running on localhost:5000.
///
/// Endpoints:
///   POST /calibrate — sets baseline gaze (center yaw/pitch)
///   POST /predict   — predicts gaze direction relative to calibrated center
class ApiController {
  /// Base URL of the Flask server.
  /// For Android emulator use `http://10.0.2.2:5000`.
  /// For physical device use your PC's LAN IP, e.g. `http://192.168.x.x:5000`.
  String baseUrl;

  final http.Client _client;

  /// Connection/response timeout.
  final Duration timeout;

  ApiController({
    this.baseUrl = 'http://10.0.2.2:5000',
    this.timeout = const Duration(seconds: 30),
    http.Client? client,
  }) : _client = client ?? http.Client();

  // ------------------------------------------------------------------
  //  POST /calibrate
  // ------------------------------------------------------------------

  /// Calibrate the gaze model by sending an image of the user looking
  /// straight at the camera. The server stores the baseline yaw & pitch.
  ///
  /// [imageBytes] — raw image bytes (JPEG / PNG).
  Future<CalibrationResult> calibrate(Uint8List imageBytes) async {
    try {
      final base64Image = base64Encode(imageBytes);
      print('🌐 POST $baseUrl/calibrate (${imageBytes.length} bytes)');

      final headers = <String, String>{'Content-Type': 'application/json'};
      if (baseUrl.contains('ngrok')) {
        headers['ngrok-skip-browser-warning'] = '1';
      }

      final response = await _client
          .post(
            Uri.parse('$baseUrl/calibrate'),
            headers: headers,
            body: jsonEncode({'image': base64Image}),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return CalibrationResult.fromJson(json);
      } else {
        print('❌ Calibrate server error (${response.statusCode}):');
        print('   Response body: ${response.body}');
        final body = _tryDecodeBody(response.body);
        return CalibrationResult(
          success: false,
          error:
              body?['error'] ?? 'Calibration failed (${response.statusCode})',
        );
      }
    } catch (e) {
      print('❌ Calibrate error: $e');
      return CalibrationResult(success: false, error: e.toString());
    }
  }

  // ------------------------------------------------------------------
  //  POST /predict
  // ------------------------------------------------------------------

  /// Predict gaze direction from an image.
  /// Make sure [calibrate] has been called at least once before this.
  ///
  /// [imageBytes] — raw image bytes (JPEG / PNG).
  Future<GazePredictionResult> predict(Uint8List imageBytes) async {
    try {
      final base64Image = base64Encode(imageBytes);

      final headers = <String, String>{'Content-Type': 'application/json'};
      if (baseUrl.contains('ngrok')) {
        headers['ngrok-skip-browser-warning'] = '1';
      }

      final response = await _client
          .post(
            Uri.parse('$baseUrl/predict'),
            headers: headers,
            body: jsonEncode({'image': base64Image}),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return GazePredictionResult.fromJson(json);
      } else {
        print('❌ Predict server error (${response.statusCode}):');
        print('   Response body: ${response.body}');
        final body = _tryDecodeBody(response.body);
        return GazePredictionResult(
          success: false,
          error: body?['error'] ?? 'Prediction failed (${response.statusCode})',
        );
      }
    } catch (e) {
      print('❌ Predict error: $e');
      return GazePredictionResult(success: false, error: e.toString());
    }
  }

  // ------------------------------------------------------------------
  //  Helpers
  // ------------------------------------------------------------------

  /// Safely try to decode a JSON response body.
  Map<String, dynamic>? _tryDecodeBody(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Dispose the underlying HTTP client.
  void dispose() {
    _client.close();
  }
}
