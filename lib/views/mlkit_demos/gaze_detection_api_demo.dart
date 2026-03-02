import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../controllers/api_controller.dart';

class GazeDetectionApiDemo extends StatefulWidget {
  const GazeDetectionApiDemo({super.key});

  @override
  State<GazeDetectionApiDemo> createState() => _GazeDetectionApiDemoState();
}

class _GazeDetectionApiDemoState extends State<GazeDetectionApiDemo>
    with SingleTickerProviderStateMixin {
  late ApiController _apiController;
  CameraController? _cameraController;
  late List<CameraDescription> _cameras;

  bool _isStreaming = false;
  bool _isLoading = false;
  bool _isCalibrating = false;
  bool _isProcessingGaze = false;
  bool _isConnected = false;

  GazePredictionResult? _currentGaze;
  String _statusMessage = '';

  // API URL configuration — user enters full URL (e.g. ngrok URL)
  final TextEditingController _apiUrlController = TextEditingController(
    text: '', // User must paste their ngrok / server URL here
  );

  // Animation for progress circle
  late AnimationController _progressAnimationController;
  Animation<double>? _progressAnimation;

  // Calibration sequence
  final List<String> _calibrationSequence = [
    'CENTER',
    'LEFT',
    'RIGHT',
    'UP',
    'DOWN',
  ];
  int _currentTargetIdx = 0;
  bool _isLookingAtTarget = false;
  bool _isMatchingTarget = false;
  bool _isCalibrated = false;

  // Calibration completion records
  final List<String> _calibrationRecords = [];

  @override
  void initState() {
    super.initState();

    // Detect default IP: use 10.0.2.2 for emulator, prompt for physical device
    _detectDefaultIp();

    _apiController = ApiController();

    _progressAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _progressAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _progressAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed && _isLookingAtTarget) {
        _advanceToNextTarget();
      }
    });

    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _showError('No cameras available.');
        return;
      }
      setState(() => _statusMessage = 'Ready. Start camera to begin.');
    } catch (e) {
      _showError('Initialization Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _isCalibrating = false;
    _progressAnimationController.dispose();
    _cameraController?.dispose();
    _apiController.dispose();
    _apiUrlController.dispose();
    super.dispose();
  }

  /// Auto-detect if running on emulator vs physical device
  void _detectDefaultIp() {
    // On physical device, user must enter their public API URL
    // (e.g., https://xxxx-xx.ngrok-free.app)
    // On emulator, they can use http://10.0.2.2:5000
    _apiUrlController.text = '';
  }

  /// Update the API base URL from the text fields
  void _updateBaseUrl() {
    final url = _apiUrlController.text.trim();
    if (url.isNotEmpty) {
      _apiController.baseUrl = url;
      print('🔧 API URL updated to: ${_apiController.baseUrl}');
    }
  }

  /// Test connectivity to the Flask server
  Future<void> _testConnection() async {
    _updateBaseUrl();
    setState(() {
      _isLoading = true;
      _statusMessage = 'Testing connection to ${_apiController.baseUrl}...';
    });

    try {
      final uri = Uri.parse('${_apiController.baseUrl}/calibrate');
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write('{"image":""}');
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      await response.drain();
      client.close();

      // Even if the server returns an error (no image), we know it's reachable
      setState(() {
        _isConnected = true;
        _statusMessage =
            '✅ Connected to ${_apiController.baseUrl}\nStart camera to begin.';
      });
      print('✅ Server reachable at ${_apiController.baseUrl}');
    } catch (e) {
      setState(() {
        _isConnected = false;
        _statusMessage =
            '❌ Cannot reach ${_apiController.baseUrl}\n'
            'Error: ${e.toString().split('\n').first}\n\n'
            'Make sure:\n'
            '• Flask server is running\n'
            '• Phone & PC are on same WiFi\n'
            '• IP address is correct';
      });
      print('❌ Connection test failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ─── Camera controls ─────────────────────────────────────────────

  Future<void> _toggleCamera() async {
    if (_isStreaming) {
      await _stopCamera();
    } else {
      await _startCamera();
    }
  }

  Future<void> _startCamera() async {
    _updateBaseUrl(); // ensure URL is set before we start
    if (!_isConnected) {
      _showError('Please test and connect to the API server first.');
      return;
    }

    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    _cameraController = CameraController(camera, ResolutionPreset.medium);

    try {
      await _cameraController!.initialize();
      setState(() => _isStreaming = true);
    } catch (e) {
      _showError('Error starting camera: $e');
    }
  }

  Future<void> _stopCamera() async {
    _isCalibrating = false;
    await _cameraController?.dispose();
    _cameraController = null;

    setState(() {
      _isStreaming = false;
      _isCalibrating = false;
      _currentGaze = null;
      _statusMessage = '';
    });
  }

  // ─── Calibration flow ────────────────────────────────────────────

  Future<void> _startCalibration() async {
    if (!_isStreaming || _cameraController == null) return;
    if (!_isConnected) {
      _showError('Please test and connect to the API server first.');
      return;
    }

    // Ensure base URL is up to date
    _updateBaseUrl();

    setState(() {
      _isCalibrating = true;
      _isCalibrated = false;
      _currentTargetIdx = 0;
      _statusMessage = 'Look at: ${_calibrationSequence[_currentTargetIdx]}';
      _isMatchingTarget = false;
      _calibrationRecords.clear();
    });

    print('\n🎯 Starting API-based gaze calibration...');
    print('Target: ${_calibrationSequence[_currentTargetIdx]}');
    print('──────────────────────────────────────────────────');

    _detectGazeContinuously();
  }

  Future<void> _detectGazeContinuously() async {
    while (_isCalibrating &&
        _cameraController != null &&
        _cameraController!.value.isInitialized) {
      await _detectGaze();
    }
  }

  void _stopCalibration() {
    setState(() {
      _isCalibrating = false;
      _currentTargetIdx = 0;
      _statusMessage = '';
    });
    print('🛑 Calibration stopped');
  }

  Future<void> _detectGaze() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (_isProcessingGaze) return;
    _isProcessingGaze = true;

    try {
      final xFile = await _cameraController!.takePicture();
      final imageBytes = await xFile.readAsBytes();

      final currentTarget = _calibrationSequence[_currentTargetIdx];

      if (currentTarget == 'CENTER' && !_isCalibrated) {
        // ── CENTER step: call /calibrate ─────────────────────────
        final calResult = await _apiController.calibrate(imageBytes);

        if (calResult.success) {
          print(
            '📐 Calibrated! center_yaw=${calResult.centerYaw}, '
            'center_pitch=${calResult.centerPitch}',
          );

          _isCalibrated = true;
          _isLookingAtTarget = true;
          _isMatchingTarget = true;
          _progressAnimationController.reset();
          _progressAnimationController.forward(); // auto-advance after 1s

          final record = StringBuffer();
          record.writeln('📐 CENTER baseline collected via API');
          record.writeln(
            '   center_yaw=${calResult.centerYaw?.toStringAsFixed(2)}, '
            'center_pitch=${calResult.centerPitch?.toStringAsFixed(2)}',
          );
          record.writeln('✅ CENTER confirmed!');
          _calibrationRecords.add(record.toString());
        } else {
          print('⚠️ Calibration API error: ${calResult.error}');
          setState(() {
            _statusMessage =
                '⚠️ Server error:\n${calResult.error ?? "Unknown"}\n\nRetrying in 3s...';
          });
          // Throttle retries on server errors to avoid spam
          await Future.delayed(const Duration(seconds: 3));
        }

        setState(() {});
      } else {
        // ── Direction steps (LEFT, RIGHT, UP, DOWN): call /predict ──
        final predResult = await _apiController.predict(imageBytes);

        if (predResult.success) {
          setState(() => _currentGaze = predResult);

          print(
            '📡 [API] target=$currentTarget | '
            'direction=${predResult.direction} | '
            'Δyaw=${predResult.deltaYaw?.toStringAsFixed(2)}° '
            'Δpitch=${predResult.deltaPitch?.toStringAsFixed(2)}°',
          );

          if (_isCalibrating) {
            _checkCalibrationProgress(predResult);
          }
        } else {
          print('⚠️ Predict API error: ${predResult.error}');
          // If calibration needed, reset
          if (predResult.error != null &&
              predResult.error!.contains('Calibration needed')) {
            _isCalibrated = false;
            setState(() {
              _currentTargetIdx = 0;
              _statusMessage = 'Look at: CENTER (re-calibrating...)';
            });
          }
        }
      }
    } catch (e) {
      print('❌ Error detecting gaze: $e');
      // Show connection errors to the user
      if (e.toString().contains('Connection refused') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('TimeoutException')) {
        setState(() {
          _statusMessage =
              '❌ Server unreachable\nCheck IP & ensure Flask is running';
        });
        // Pause briefly to avoid spamming failed requests
        await Future.delayed(const Duration(seconds: 2));
      }
    } finally {
      _isProcessingGaze = false;
    }
  }

  void _checkCalibrationProgress(GazePredictionResult result) {
    final currentTarget = _calibrationSequence[_currentTargetIdx];
    if (currentTarget == 'CENTER') return; // CENTER handled separately

    final detectedDirection = result.direction ?? 'CENTER';

    // Check if detected direction matches the target
    final bool matches = detectedDirection == currentTarget;
    _isMatchingTarget = matches;

    // Calculate progress based on delta values
    double progressValue = 0.0;
    if (result.deltaYaw != null && result.deltaPitch != null) {
      switch (currentTarget) {
        case 'LEFT':
        case 'RIGHT':
          progressValue = (result.deltaPitch!.abs() / 10.0).clamp(0.0, 1.0);
          break;
        case 'UP':
        case 'DOWN':
          progressValue = (result.deltaYaw!.abs() / 8.0).clamp(0.0, 1.0);
          break;
      }
    }

    _progressAnimationController.value = matches ? 1.0 : progressValue;

    print(
      '   🎯 $currentTarget: detected=$detectedDirection | '
      'progress ${(progressValue * 100).toStringAsFixed(0)}% '
      '${matches ? "=> ✅ MATCH" : "=> tracking..."}',
    );

    if (matches) {
      // Direction confirmed!
      final record = StringBuffer();
      record.writeln('✅ $currentTarget confirmed via API');
      record.writeln(
        '   direction=${result.direction}, '
        'Δyaw=${result.deltaYaw?.toStringAsFixed(2)}°, '
        'Δpitch=${result.deltaPitch?.toStringAsFixed(2)}°',
      );
      _calibrationRecords.add(record.toString());

      print('\n✅ $currentTarget REACHED!\n');
      _advanceToNextTarget();
    }

    setState(() {});
  }

  void _advanceToNextTarget() {
    final completedTarget = _calibrationSequence[_currentTargetIdx];
    print('✅ $completedTarget confirmed!');

    _currentTargetIdx++;
    _isLookingAtTarget = false;
    _isMatchingTarget = false;
    _progressAnimationController.reset();

    if (_currentTargetIdx >= _calibrationSequence.length) {
      // All directions done!
      print('\n════════════════════════════════════════════════════════');
      print('📋 FULL CALIBRATION RECORD (API)');
      print('════════════════════════════════════════════════════════');
      for (final record in _calibrationRecords) {
        print(record);
      }
      print('🎉 CALIBRATION COMPLETE! YOU ARE HUMAN!');
      print('════════════════════════════════════════════════════════\n');

      _isCalibrating = false;
      setState(() {
        _statusMessage = '✅ Calibration Complete! You are verified as human!';
      });
      _showSuccessDialog();
    } else {
      setState(() {
        _statusMessage = 'Look at: ${_calibrationSequence[_currentTargetIdx]}';
      });
      print('Next target: ${_calibrationSequence[_currentTargetIdx]}');
    }
  }

  // ─── Dialogs & helpers ───────────────────────────────────────────

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 32),
            SizedBox(width: 8),
            Text('Success!'),
          ],
        ),
        content: const Text(
          'API Calibration complete!\nYou are verified as human! ✅',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _currentTargetIdx = 0;
                _statusMessage = '';
              });
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    setState(() {
      _statusMessage = message;
      _isLoading = false;
    });
  }

  // ─── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Gaze Detection (API)'),
        backgroundColor: Colors.black.withOpacity(0.3),
        elevation: 0,
      ),
      body: Stack(
        children: [
          _buildCameraPreview(),
          if (_isCalibrating) _buildCalibrationOverlay(),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    return SizedBox.expand(
      child: Container(
        color: Colors.black,
        child: Center(
          child:
              _isStreaming &&
                  _cameraController != null &&
                  _cameraController!.value.isInitialized
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _cameraController!.value.previewSize!.height,
                          height: _cameraController!.value.previewSize!.width,
                          child: CameraPreview(_cameraController!),
                        ),
                      ),
                    ),
                    // Center reference circle
                    CustomPaint(
                      size: const Size(240, 240),
                      painter: _ReferenceCirclePainter(),
                    ),
                  ],
                )
              : const Text(
                  'Camera is off',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
        ),
      ),
    );
  }

  Widget _buildCalibrationOverlay() {
    final size = MediaQuery.of(context).size;
    final currentTarget = _calibrationSequence[_currentTargetIdx];

    return AnimatedBuilder(
      animation: _progressAnimation ?? _progressAnimationController,
      builder: (context, child) {
        return CustomPaint(
          size: size,
          painter: _CalibrationTargetPainter(
            target: currentTarget,
            progress: _progressAnimation?.value ?? 0.0,
            detectedDirection: _currentGaze?.direction,
            isMatchingTarget: _isMatchingTarget,
          ),
        );
      },
    );
  }

  Widget _buildBottomControls() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.8), Colors.transparent],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoading)
              const CircularProgressIndicator()
            else ...[
              // API server config
              if (!_isCalibrating && !_isStreaming)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal.withOpacity(0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🌐 Flask Server',
                        style: TextStyle(
                          color: Colors.tealAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _apiUrlController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                labelText: 'API URL',
                                hintText: 'https://xxxx.ngrok-free.app',
                                hintStyle: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                                labelStyle: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey[700]!,
                                  ),
                                ),
                              ),
                              keyboardType: TextInputType.url,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _testConnection,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              minimumSize: Size.zero,
                            ),
                            child: const Text(
                              'Test',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      if (_isConnected)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '✅ Connected',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

              // Status message (hide during calibration — painter shows it)
              if (_statusMessage.isNotEmpty && !_isCalibrating)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal),
                  ),
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Gaze info card
              if (_currentGaze != null && !_isCalibrating)
                Card(
                  color: _getDirectionColor(
                    _currentGaze!.direction ?? 'CENTER',
                  ).withOpacity(0.2),
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text(
                          '👁️ ${_currentGaze!.direction ?? "—"}',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: _getDirectionColor(
                              _currentGaze!.direction ?? 'CENTER',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Δyaw: ${_currentGaze!.deltaYaw?.toStringAsFixed(1) ?? "—"}° | '
                          'Δpitch: ${_currentGaze!.deltaPitch?.toStringAsFixed(1) ?? "—"}°',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // API server info badge (during streaming)
              if (!_isCalibrating && _isStreaming)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.teal.withOpacity(0.4)),
                  ),
                  child: Text(
                    '🌐 ${_apiController.baseUrl}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.tealAccent,
                    ),
                  ),
                ),

              // Control buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isStreaming && !_isCalibrating)
                    ElevatedButton.icon(
                      onPressed: _startCalibration,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Calibration'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    ),
                  if (_isCalibrating)
                    ElevatedButton.icon(
                      onPressed: _stopCalibration,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _toggleCamera,
                    icon: Icon(
                      _isStreaming ? Icons.videocam_off : Icons.videocam,
                    ),
                    label: Text(_isStreaming ? 'Stop Camera' : 'Start Camera'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isStreaming ? Colors.red : Colors.blue,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getDirectionColor(String direction) {
    switch (direction) {
      case 'CENTER':
        return Colors.white;
      case 'RIGHT':
        return Colors.green;
      case 'LEFT':
        return Colors.cyan;
      case 'UP':
        return Colors.red;
      case 'DOWN':
        return Colors.purple;
      default:
        return Colors.white;
    }
  }
}

// ─── Custom painters ─────────────────────────────────────────────────

class _ReferenceCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 120, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CalibrationTargetPainter extends CustomPainter {
  final String target;
  final double progress;
  final String? detectedDirection;
  final bool isMatchingTarget;

  _CalibrationTargetPainter({
    required this.target,
    required this.progress,
    this.detectedDirection,
    this.isMatchingTarget = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Semi-transparent background
    final bgPaint = Paint()..color = Colors.black.withOpacity(0.3);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final offset = min(size.width, size.height) * 0.25;

    Color color;
    Offset targetPos;
    String label;

    switch (target) {
      case 'CENTER':
        color = Colors.white;
        targetPos = Offset(centerX, centerY);
        label = 'Look at the dot';
        break;
      case 'LEFT':
        color = Colors.cyan;
        targetPos = Offset(centerX - offset, centerY);
        label = '⬅️ Look LEFT';
        break;
      case 'RIGHT':
        color = Colors.green;
        targetPos = Offset(centerX + offset, centerY);
        label = 'Look RIGHT ➡️';
        break;
      case 'UP':
        color = Colors.red;
        targetPos = Offset(centerX, centerY - offset);
        label = '⬆️ Look UP';
        break;
      case 'DOWN':
        color = Colors.purple;
        targetPos = Offset(centerX, centerY + offset);
        label = '⬇️ Look DOWN';
        break;
      default:
        return;
    }

    // Draw arrow from center to target
    if (target != 'CENTER') {
      final arrowPaint = Paint()
        ..color = color.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;

      final center = Offset(centerX, centerY);
      final direction = targetPos - center;
      final arrowStart = center + direction * 0.3;
      final arrowEnd = center + direction * 0.7;
      canvas.drawLine(arrowStart, arrowEnd, arrowPaint);

      // Arrowhead
      final headPaint = Paint()
        ..color = color.withOpacity(0.8)
        ..style = PaintingStyle.fill;
      _drawArrowHead(canvas, arrowEnd, targetPos, headPaint, 20);
    }

    // Draw detected gaze indicator
    if (detectedDirection != null) {
      final gazeColor = isMatchingTarget
          ? Colors.greenAccent
          : Colors.yellowAccent;
      final gazePaint = Paint()
        ..color = gazeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;

      final center = Offset(centerX, centerY);
      Offset gazeDirection;

      switch (detectedDirection!) {
        case 'LEFT':
          gazeDirection = Offset(centerX - 150, centerY);
          break;
        case 'RIGHT':
          gazeDirection = Offset(centerX + 150, centerY);
          break;
        case 'UP':
          gazeDirection = Offset(centerX, centerY - 150);
          break;
        case 'DOWN':
          gazeDirection = Offset(centerX, centerY + 150);
          break;
        default:
          gazeDirection = center;
      }

      if (detectedDirection != 'CENTER') {
        canvas.drawLine(center, gazeDirection, gazePaint);
        final dotPaint = Paint()
          ..color = gazeColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(gazeDirection, 12, dotPaint);
        final glowPaint = Paint()
          ..color = gazeColor.withOpacity(0.5)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(gazeDirection, 18, glowPaint);
      } else {
        final dotPaint = Paint()
          ..color = gazeColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, 12, dotPaint);
      }
    } else {
      // No gaze — show hint
      final painter = TextPainter(
        text: TextSpan(
          text: '⚠️ Detecting face...',
          style: TextStyle(
            color: Colors.orange,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black,
                offset: const Offset(2, 2),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      painter.layout();
      painter.paint(canvas, Offset(centerX - painter.width / 2, centerY + 150));
    }

    // Draw target dot
    final targetPaint = Paint()..color = color;
    canvas.drawCircle(targetPos, 12, targetPaint);

    // Progress arc
    final progressBg = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final progressArc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(targetPos, 22, progressBg);
    canvas.drawArc(
      Rect.fromCircle(center: targetPos, radius: 22),
      -pi / 2,
      2 * pi * progress,
      false,
      progressArc,
    );

    // Instruction label
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black,
              offset: const Offset(3, 3),
              blurRadius: 6,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(centerX - textPainter.width / 2, size.height - 200),
    );
  }

  void _drawArrowHead(
    Canvas canvas,
    Offset tip,
    Offset targetPos,
    Paint paint,
    double size,
  ) {
    final direction = targetPos - tip;
    final angle = atan2(direction.dy, direction.dx);
    final left = Offset(
      tip.dx + size * cos(angle + 2.5),
      tip.dy + size * sin(angle + 2.5),
    );
    final right = Offset(
      tip.dx + size * cos(angle - 2.5),
      tip.dy + size * sin(angle - 2.5),
    );
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CalibrationTargetPainter oldDelegate) {
    return oldDelegate.target != target ||
        oldDelegate.progress != progress ||
        oldDelegate.detectedDirection != detectedDirection ||
        oldDelegate.isMatchingTarget != isMatchingTarget;
  }
}
