import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as video_thumbnail;
import '../controllers/antispoofing_controller.dart';
import '../models/antispoofing_result.dart';
import 'hybrid_verification_screen.dart';

class AntispoofingScreen extends StatefulWidget {
  const AntispoofingScreen({super.key});

  @override
  State<AntispoofingScreen> createState() => _AntispoofingScreenState();
}

class _AntispoofingScreenState extends State<AntispoofingScreen> {
  final AntispoofingController _antispoofingService = AntispoofingController();
  CameraController? _cameraController;
  late List<CameraDescription> _cameras;

  bool _isStreaming = false;
  bool _isRecording = false;
  bool _isLoading = false;
  int _countdown = 3;
  Timer? _countdownTimer;
  Timer? _recordingTimer;

  AntispoofingResult? _result;
  String _statusMessage = "";
  List<AntispoofingResult> _capturedResults = [];

  // Video upload summary results
  int _totalVideosProcessed = 0;
  int _liveCount = 0;
  int _spoofCount = 0;
  int _noDetectionCount = 0;
  bool _showSummary = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      await _antispoofingService.loadModel();
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _showError('No cameras available.');
        return;
      }
    } catch (e) {
      _showError('Initialization Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _countdownTimer?.cancel();
    _recordingTimer?.cancel();
    // _antispoofingService.dispose();
    super.dispose();
  }

  Future<void> _toggleWebcam() async {
    if (_isStreaming) {
      await _stopWebcam();
    } else {
      await _startWebcam();
    }
  }

  Future<void> _startWebcam() async {
    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    _cameraController = CameraController(camera, ResolutionPreset.high);

    try {
      await _cameraController!.initialize();
      setState(() => _isStreaming = true);
    } catch (e) {
      _showError('Error starting webcam: $e');
    }
  }

  Future<void> _stopWebcam() async {
    // Stop recording if in progress
    if (_isRecording && _cameraController != null) {
      try {
        await _cameraController!.stopVideoRecording();
      } catch (e) {
        print('Error stopping video recording: $e');
      }
    }

    // Cancel all timers
    _countdownTimer?.cancel();
    _recordingTimer?.cancel();

    // Dispose camera controller
    await _cameraController?.dispose();
    _cameraController = null;

    setState(() {
      _isStreaming = false;
      _isRecording = false;
      _isLoading = false;
      _result = null;
      _statusMessage = "";
      _capturedResults.clear();
    });
  }

  Future<void> _startRecording() async {
    if (!_isStreaming || _cameraController == null || _isRecording) return;

    setState(() {
      _isRecording = true;
      _countdown = 3;
      _result = null;
      _statusMessage = "Recording 3s video...";
      _capturedResults.clear();
    });

    // Start countdown timer
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
      }
    });

    // Start video recording
    try {
      await _cameraController!.startVideoRecording();

      // Stop after 3 seconds
      _recordingTimer = Timer(
        const Duration(seconds: 3),
        _stopRecordingAndExtractFrames,
      );
    } catch (e) {
      _showError('Error starting video recording: $e');
    }
  }

  Future<void> _stopRecordingAndExtractFrames() async {
    if (_cameraController == null) return;

    setState(() {
      _isRecording = false;
      _isLoading = true;
      _statusMessage = "Stopping video recording...";
    });

    try {
      // Stop video recording
      final videoFile = await _cameraController!.stopVideoRecording();

      setState(() {
        _statusMessage = "Extracting frames from video...";
      });

      // Extract frames at 1 FPS (3 frames from 3-second video)
      await _extractAndProcessFrames(videoFile.path);
    } catch (e) {
      _showError('Error recording video: $e');
    }
  }

  Future<void> _extractAndProcessFrames(String videoPath) async {
    try {
      // For simplicity, we'll capture frames at 0s, 1.5s, and 3s by reading the video
      // Since Flutter camera doesn't provide direct frame extraction,
      // we'll simulate by taking snapshots during the recording period
      // For a real implementation, you'd need a video processing package

      setState(() {
        _statusMessage = "Processing video frames...";
      });

      // Read the video file
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        throw Exception('Video file not found');
      }

      // Since we can't easily extract frames from video in Flutter without additional packages,
      // we'll use a workaround: capture multiple images during recording
      // For now, let's process the video as if we extracted frames
      // In production, you'd use packages like video_player or ffmpeg_kit_flutter

      // Simulate frame extraction by capturing 3 images at intervals
      await _captureMultipleFrames();
    } catch (e) {
      _showError('Error extracting frames: $e');
    }
  }

  Future<void> _captureMultipleFrames() async {
    if (_cameraController == null) return;

    final startTime = DateTime.now();
    const fps = 3; // Frames per second
    const videoDuration = 2; // Video duration in seconds
    const totalFrames = fps * videoDuration; // frames total

    print('\n🎬 ========================================');
    print('🎬 Starting frame capture and processing');
    print(
      '🎬 Target: $totalFrames frames at ${fps}fps from ${videoDuration}s video',
    );
    print('🎬 ========================================');

    try {
      // Capture frames at 10fps = every 100ms
      for (int i = 1; i <= totalFrames; i++) {
        final frameStartTime = DateTime.now();

        setState(() {
          _statusMessage = "Processing frame $i/$totalFrames...";
        });

        print('\n📸 Capturing frame $i/$totalFrames...');
        final image = await _cameraController!.takePicture();
        final imageBytes = await image.readAsBytes();

        print('🤖 Running model on frame $i...');
        final result = await _antispoofingService.predictFromBytes(imageBytes);
        _capturedResults.add(result);

        final frameDuration = DateTime.now().difference(frameStartTime);
        print('✅ Frame $i processed in ${frameDuration.inMilliseconds}ms');
        print(
          '   Result: ${result.isLive ? "LIVE" : "SPOOF"} (${(result.confidence * 100).toStringAsFixed(2)}% confidence)',
        );

        // Delay between captures to simulate 10fps (100ms per frame)
        if (i < totalFrames) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      final totalDuration = DateTime.now().difference(startTime);
      print('\n⏱️  ========================================');
      print('⏱️  Total frames processed: ${_capturedResults.length}');
      print(
        '⏱️  Total processing time: ${totalDuration.inMilliseconds}ms (${(totalDuration.inMilliseconds / 1000).toStringAsFixed(2)}s)',
      );
      print(
        '⏱️  Average time per frame: ${(totalDuration.inMilliseconds / _capturedResults.length).toStringAsFixed(2)}ms',
      );
      print(
        '⏱️  Actual FPS achieved: ${(_capturedResults.length / (totalDuration.inMilliseconds / 1000)).toStringAsFixed(2)} fps',
      );
      print('⏱️  ========================================\n');

      // Now average the results
      _averageResults();
    } catch (e) {
      print('❌ Error processing frames: $e');
      _showError('Error processing frames: $e');
    }
  }

  void _averageResults() {
    if (_capturedResults.isEmpty) {
      print('❌ No frames captured for averaging');
      _showError('No frames captured');
      return;
    }

    print('\n📊 ========================================');
    print('📊 AVERAGING RESULTS FROM ${_capturedResults.length} FRAMES');
    print('📊 ========================================');

    // Filter out 'no_face' results
    final validResults = _capturedResults
        .where((r) => r.status == 'success')
        .toList();

    if (validResults.isEmpty) {
      print('⚠️ No valid face detections found in any frame');
      setState(() {
        _result = _capturedResults.first; // Show the no_face result
        _isLoading = false;
        _statusMessage = "";
      });
      return;
    }

    // Calculate average probabilities
    double avgLiveProb =
        validResults.map((r) => r.liveProb).reduce((a, b) => a + b) /
        validResults.length;
    double avgSpoofProb =
        validResults.map((r) => r.spoofProb).reduce((a, b) => a + b) /
        validResults.length;
    double avgConfidence =
        validResults.map((r) => r.confidence).reduce((a, b) => a + b) /
        validResults.length;
    bool isLive = avgLiveProb > 0.5;

    print(
      '📊 Valid frames analyzed: ${validResults.length}/${_capturedResults.length}',
    );
    print('📊 Final verdict: ${isLive ? "✅ LIVE" : "❌ SPOOF"}');
    print('📊 Live probability: ${(avgLiveProb * 100).toStringAsFixed(2)}%');
    print('📊 Spoof probability: ${(avgSpoofProb * 100).toStringAsFixed(2)}%');
    print('📊 Confidence: ${(avgConfidence * 100).toStringAsFixed(2)}%');
    print('📊 ========================================\n');

    setState(() {
      _result = AntispoofingResult(
        isLive: isLive,
        liveProb: avgLiveProb,
        spoofProb: avgSpoofProb,
        confidence: avgConfidence,
        status: 'success',
        faceBbox: validResults.first.faceBbox,
      );
      _isLoading = false;
      _statusMessage = "Analyzed ${validResults.length} frames";
    });

    print('✅ UI updated with final result\n');
  }

  void _showError(String message) {
    setState(() {
      _statusMessage = message;
      _isLoading = false;
    });
  }

  // ==========================================
  // VIDEO UPLOAD FUNCTIONALITY
  // ==========================================

  Future<void> _pickAndProcessVideos() async {
    try {
      // Pick multiple video files
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) {
        return; // User cancelled
      }

      // Reset summary counters
      setState(() {
        _isLoading = true;
        _statusMessage = "Processing ${result.files.length} videos...";
        _totalVideosProcessed = 0;
        _liveCount = 0;
        _spoofCount = 0;
        _noDetectionCount = 0;
        _showSummary = false;
        _result = null;
      });

      print('\n🎬 ========================================');
      print('🎬 Starting batch video processing');
      print('🎬 Total videos: ${result.files.length}');
      print('🎬 ========================================\n');

      // Process each video
      for (int i = 0; i < result.files.length; i++) {
        final file = result.files[i];
        if (file.path == null) continue;

        setState(() {
          _statusMessage =
              "Processing video ${i + 1}/${result.files.length}...";
        });

        print(
          '📹 Processing video ${i + 1}/${result.files.length}: ${file.name}',
        );

        try {
          final videoResult = await _processVideoFile(File(file.path!));

          // Update counters based on result
          _totalVideosProcessed++;
          if (videoResult.status == 'no_face') {
            _noDetectionCount++;
            print('   ⚠️  No face detected');
          } else if (videoResult.isLive) {
            _liveCount++;
            print(
              '   ✅ LIVE (${(videoResult.confidence * 100).toStringAsFixed(2)}%)',
            );
          } else {
            _spoofCount++;
            print(
              '   ❌ SPOOF (${(videoResult.confidence * 100).toStringAsFixed(2)}%)',
            );
          }
        } catch (e) {
          print('   ❌ Error processing video: $e');
          _noDetectionCount++;
          _totalVideosProcessed++;
        }

        setState(() {});
      }

      print('\n📊 ========================================');
      print('📊 BATCH PROCESSING COMPLETE');
      print('📊 Total videos: $_totalVideosProcessed');
      print('📊 Live: $_liveCount');
      print('📊 Spoof: $_spoofCount');
      print('📊 No detection: $_noDetectionCount');
      print('📊 ========================================\n');

      setState(() {
        _isLoading = false;
        _showSummary = true;
        _statusMessage = "Processed $_totalVideosProcessed videos";
      });
    } catch (e) {
      print('❌ Error picking videos: $e');
      _showError('Error: $e');
    }
  }

  Future<AntispoofingResult> _processVideoFile(File videoFile) async {
    VideoPlayerController? videoController;
    final List<File> extractedFrames = [];

    try {
      // Initialize video controller to get duration
      videoController = VideoPlayerController.file(videoFile);
      await videoController.initialize();

      final duration = videoController.value.duration;
      print('   📹 Video duration: ${duration.inSeconds}s');

      if (duration.inMilliseconds <= 0) {
        throw Exception('Video duration is invalid');
      }

      // Calculate three positions (at 1/4, 1/2, and 3/4 of duration) in milliseconds
      final position1Ms = duration.inMilliseconds ~/ 4;
      final position2Ms = duration.inMilliseconds ~/ 2;
      final position3Ms = (duration.inMilliseconds * 3) ~/ 4;
      print(
        '   📸 Extracting 3 frames at ${(position1Ms / 1000).toStringAsFixed(1)}s, ${(position2Ms / 1000).toStringAsFixed(1)}s, and ${(position3Ms / 1000).toStringAsFixed(1)}s...',
      );

      // Create temporary directory for extracted frames
      final tempDir = await getTemporaryDirectory();

      Future<File> extractFrameAt(int positionMs) async {
        final framePath = await video_thumbnail.VideoThumbnail.thumbnailFile(
          video: videoFile.path,
          thumbnailPath: tempDir.path,
          imageFormat: video_thumbnail.ImageFormat.JPEG,
          timeMs: positionMs,
          quality: 90,
        );

        if (framePath == null) {
          throw Exception('Failed to extract frame from video');
        }

        final frameFile = File(framePath);
        if (!await frameFile.exists()) {
          throw Exception('Frame file was not created');
        }

        return frameFile;
      }

      final frame1 = await extractFrameAt(position1Ms);
      extractedFrames.add(frame1);
      final frame2 = await extractFrameAt(position2Ms);
      extractedFrames.add(frame2);
      final frame3 = await extractFrameAt(position3Ms);
      extractedFrames.add(frame3);
      print('   ✅ 3 frames extracted successfully');

      // Process all frames with antispoofing service
      final results = <AntispoofingResult>[];
      for (final frame in extractedFrames) {
        results.add(await _antispoofingService.predict(frame));
      }

      final validResults = results.where((r) => r.status == 'success').toList();

      if (validResults.isEmpty) {
        return results.isNotEmpty
            ? results.first
            : AntispoofingResult(
                isLive: false,
                liveProb: 0.0,
                spoofProb: 0.0,
                confidence: 0.0,
                status: 'no_face',
              );
      }

      final avgLiveProb =
          validResults.map((r) => r.liveProb).reduce((a, b) => a + b) /
          validResults.length;
      final avgSpoofProb =
          validResults.map((r) => r.spoofProb).reduce((a, b) => a + b) /
          validResults.length;
      final avgConfidence =
          validResults.map((r) => r.confidence).reduce((a, b) => a + b) /
          validResults.length;

      final isLive = avgLiveProb > 0.5;

      return AntispoofingResult(
        isLive: isLive,
        liveProb: avgLiveProb,
        spoofProb: avgSpoofProb,
        confidence: avgConfidence,
        status: 'success',
        faceBbox: validResults.first.faceBbox,
      );
    } catch (e) {
      print('   ❌ Error processing video file: $e');
      rethrow;
    } finally {
      await videoController?.dispose();

      // Clean up extracted frames
      for (final frame in extractedFrames) {
        if (await frame.exists()) {
          try {
            await frame.delete();
          } catch (e) {
            print('   ⚠️  Could not delete temporary frame: $e');
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Live Stream | Face Anti-Spoofing Detection'),
        backgroundColor: Colors.black.withOpacity(0.3),
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Full screen camera
          _buildVideoDisplay(),

          // Overlay controls at bottom
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
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  if (_statusMessage.isNotEmpty && !_isLoading)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        _statusMessage,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.blue,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (_showSummary) _buildSummaryCard(),
                  if (_result != null && !_showSummary) _buildResultCard(),
                  _buildControls(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoDisplay() {
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
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.rotationY(3.14159),
                            child: CameraPreview(_cameraController!),
                          ),
                        ),
                      ),
                    ),
                    if (_isRecording)
                      Container(
                        color: Colors.black.withOpacity(0.5),
                        child: Text(
                          '$_countdown',
                          style: const TextStyle(
                            fontSize: 96,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                )
              : const Text(
                  'Webcam is off',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          // Upload Videos & Hybrid buttons
          if (!_isStreaming && !_isLoading)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _pickAndProcessVideos,
                  icon: const Icon(Icons.upload_file),
                  label: const Text(
                    'Upload Videos',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HybridVerificationScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.verified_user),
                  label: const Text('Hybrid', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          // Webcam controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isStreaming && !_isRecording && !_isLoading)
                ElevatedButton(
                  onPressed: _startRecording,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 20,
                    ),
                  ),
                  child: const Text(
                    'Start Recording',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _isLoading || _isRecording ? null : _toggleWebcam,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isStreaming ? Colors.red : Colors.blue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 20,
                  ),
                ),
                child: Text(
                  _isStreaming ? 'Stop Webcam' : 'Start Webcam',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    if (_result == null) return const SizedBox.shrink();

    final status = _result!.status;
    final isLive = _result!.isLive;
    final cardColor = status == 'no_face'
        ? Colors.yellow.shade700
        : (isLive ? Colors.green : Colors.red);
    final statusText = status == 'no_face'
        ? '⚠️ No Face Detected'
        : (isLive ? '✅ LIVE' : '❌ SPOOF');

    return Card(
      color: cardColor.withOpacity(0.1),
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              statusText,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: cardColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (status != 'no_face') ...[
              _buildResultRow('Live Probability:', _result!.liveProb),
              _buildResultRow('Spoof Probability:', _result!.spoofProb),
              _buildResultRow('Confidence:', _result!.confidence),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text(
            '${(value * 100).toStringAsFixed(2)}%',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      color: Colors.blueGrey.withOpacity(0.2),
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '📊 Batch Processing Results',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _buildSummaryRow(
              '📹 Total Videos:',
              _totalVideosProcessed.toString(),
              Colors.white,
            ),
            const Divider(height: 20, color: Colors.white30),
            _buildSummaryRow('✅ Live:', _liveCount.toString(), Colors.green),
            _buildSummaryRow('❌ Spoof:', _spoofCount.toString(), Colors.red),
            _buildSummaryRow(
              '⚠️  No Detection:',
              _noDetectionCount.toString(),
              Colors.yellow.shade700,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 18,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
