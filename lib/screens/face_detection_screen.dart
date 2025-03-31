import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/emotion_data.dart';
import '../widgets/face_guide_painter.dart';

class FaceDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const FaceDetectionScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  _FaceDetectionScreenState createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  bool _isDetecting = false;
  String _mood = "Analyzing...";
  String _lightingStatus = "";
  String _faceCondition = "";
  double _confidence = 0.0;
  int _cameraIndex = 0;
  bool _isCameraInitialized = false;
  Color _moodColor = Colors.white;
  Color _lightingColor = Colors.white;
  Color _conditionColor = Colors.white;
  bool _isLowLight = false;
  double _lastProcessedTime = 0;
  static const double _processingInterval = 0.1;
  AnimationController? _animationController;
  Animation<double>? _fadeAnimation;
  Animation<double>? _slideAnimation;
  List<EmotionData> _emotionHistory = [];
  static const String _historyKey = 'emotion_history';
  bool _showHistory = false;
  bool _isAnimationsInitialized = false;
  bool _showGuideOverlay = true;
  bool _showAdvancedMetrics = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _requestCameraPermission();
    _loadEmotionHistory();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeIn),
    );
    _slideAnimation = Tween<double>(begin: 50.0, end: 0.0).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeOut),
    );
    _isAnimationsInitialized = true;
  }

  Future<void> _requestCameraPermission() async {
    var status = await Permission.camera.request();
    if (status.isGranted) {
      _initializeCamera();
    } else {
      setState(() => _mood = "Camera Permission Denied");
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      return;
    }

    try {
      _cameraController = CameraController(
        widget.cameras[_cameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() => _isCameraInitialized = true);
      _startFaceDetection();

      if (_isAnimationsInitialized && _animationController != null) {
        _animationController!.forward();
      }
    } catch (e) {
      setState(() => _isCameraInitialized = false);
    }
  }

  void _switchCamera() async {
    if (widget.cameras.length < 2) {
      return;
    }

    if (_cameraController != null &&
        _cameraController!.value.isStreamingImages) {
      await _cameraController!.stopImageStream();
      await Future.delayed(Duration(milliseconds: 300));
    }

    await _cameraController?.dispose();
    _cameraController = null;

    setState(() => _isCameraInitialized = false);

    _cameraIndex = (_cameraIndex + 1) % widget.cameras.length;

    await Future.delayed(Duration(milliseconds: 500));
    await _initializeCamera();
  }

  void _startFaceDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return;

    _cameraController!.startImageStream((CameraImage image) async {
      if (_isDetecting) return;

      final currentTime = DateTime.now().millisecondsSinceEpoch / 1000;
      if (currentTime - _lastProcessedTime < _processingInterval) return;
      _lastProcessedTime = currentTime;

      _isDetecting = true;

      try {
        final lightingStatus = _analyzeLighting(image);

        final InputImage inputImage = _convertCameraImage(image);
        final List<Face> faces = await _faceDetector.processImage(inputImage);

        if (!mounted) return;

        setState(() {
          _lightingStatus = lightingStatus['status']!;
          _lightingColor = lightingStatus['color']!;
          _isLowLight = lightingStatus['isLowLight']!;

          if (faces.isNotEmpty) {
            final face = faces.first;
            final moodResult = _analyzeMood(face);
            final conditionResult =
            _analyzeFaceCondition(face, lightingStatus['brightness']!);

            _mood = moodResult['mood']!;
            _confidence = moodResult['confidence']!;
            _moodColor = moodResult['color']!;
            _faceCondition = conditionResult['condition']!;
            _conditionColor = conditionResult['color']!;

            _addEmotionData();
          } else {
            _mood = "No face detected";
            _confidence = 0.0;
            _moodColor = Colors.white;
            _faceCondition = "";
            _conditionColor = Colors.white;
          }
        });
      } catch (e) {
      } finally {
        _isDetecting = false;
      }
    });
  }

  InputImage _convertCameraImage(CameraImage image) {
    final bytes = _convertYUV420ToNV21(image);
    final rotation = widget.cameras[_cameraIndex].sensorOrientation;

    final InputImageMetadata metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: _mapRotation(rotation),
      format: InputImageFormat.nv21,
      bytesPerRow: image.width,
    );

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: metadata,
    );
  }

  Uint8List _convertYUV420ToNV21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = ySize ~/ 2;
    final Uint8List nv21 = Uint8List(ySize + uvSize);

    nv21.setRange(0, ySize, image.planes[0].bytes);

    final Uint8List u = image.planes[1].bytes;
    final Uint8List v = image.planes[2].bytes;

    for (int i = 0, uvIndex = ySize; i < u.length; i++) {
      if (uvIndex < nv21.length - 1) {
        nv21[uvIndex++] = v[i];
        nv21[uvIndex++] = u[i];
      }
    }

    return nv21;
  }

  InputImageRotation _mapRotation(int rotation) {
    switch (rotation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  Map<String, dynamic> _analyzeMood(Face face) {
    double? smileProb = face.smilingProbability;
    double? leftEyeOpen = face.leftEyeOpenProbability;
    double? rightEyeOpen = face.rightEyeOpenProbability;
    double? headEulerAngleY = face.headEulerAngleY;
    double? headEulerAngleZ = face.headEulerAngleZ;

    if (smileProb == null) {
      return {
        'mood': "Analyzing...",
        'confidence': 0.0,
        'color': Colors.white,
      };
    }

    double confidence = 0.0;
    String mood = "Neutral 😐";
    Color color = Colors.white;

    if (leftEyeOpen != null && rightEyeOpen != null) {
      double eyeOpenness = (leftEyeOpen + rightEyeOpen) / 2;

      if (eyeOpenness < 0.3) {
        mood = "Tired 😴";
        color = Colors.purple;
        confidence = 1 - eyeOpenness;
      } else if (eyeOpenness < 0.5 && smileProb < 0.3) {
        mood = "Stressed 😫";
        color = Colors.red;
        confidence = 0.8;
      }
    }

    if (smileProb > 0.8) {
      mood = "Very Happy 😄";
      color = Colors.green;
      confidence = smileProb;
    } else if (smileProb > 0.5) {
      mood = "Happy 🙂";
      color = Colors.lightGreen;
      confidence = smileProb;
    } else if (smileProb < 0.2) {
      mood = "Sad 😢";
      color = Colors.blue;
      confidence = 1 - smileProb;
    }

    if (headEulerAngleY != null && headEulerAngleZ != null) {
      if (headEulerAngleY.abs() > 20 || headEulerAngleZ.abs() > 20) {
        mood = "Looking Away 👀";
        color = Colors.yellow;
        confidence = 0.8;
      }
    }

    if (_isLowLight) {
      confidence *= 0.8;
    }

    return {
      'mood': mood,
      'confidence': confidence,
      'color': color,
    };
  }

  Map<String, dynamic> _analyzeLighting(CameraImage image) {
    final Uint8List yPlane = image.planes[0].bytes;
    int totalBrightness = 0;
    int totalContrast = 0;
    int previousPixel = 0;

    for (int i = 0; i < yPlane.length; i += 10) {
      int currentPixel = yPlane[i];
      totalBrightness += currentPixel;
      totalContrast += (currentPixel - previousPixel).abs();
      previousPixel = currentPixel;
    }

    double averageBrightness = totalBrightness / (yPlane.length ~/ 10);
    double averageContrast = totalContrast / (yPlane.length ~/ 10);
    double normalizedBrightness = averageBrightness / 255.0;
    double normalizedContrast = averageContrast / 255.0;

    String status;
    Color color;
    bool isLowLight;

    if (normalizedBrightness < 0.3) {
      status = "Low Light ";
      color = Colors.orange;
      isLowLight = true;
    } else if (normalizedBrightness > 0.8) {
      status = "Too Bright ";
      color = Colors.yellow;
      isLowLight = false;
    } else {
      status = "Good Lighting ";
      color = Colors.green;
      isLowLight = false;
    }

    return {
      'status': status,
      'color': color,
      'isLowLight': isLowLight,
      'brightness': normalizedBrightness,
      'contrast': normalizedContrast,
    };
  }

  Map<String, dynamic> _analyzeFaceCondition(Face face, double brightness) {
    double? leftEyeOpen = face.leftEyeOpenProbability;
    double? rightEyeOpen = face.rightEyeOpenProbability;
    double? headEulerAngleY = face.headEulerAngleY;
    double? headEulerAngleZ = face.headEulerAngleZ;

    String condition = "Normal";
    Color color = Colors.green;
    double confidence = 1.0;

    if (leftEyeOpen != null && rightEyeOpen != null) {
      double eyeOpenness = (leftEyeOpen + rightEyeOpen) / 2;

      if (eyeOpenness < 0.3) {
        condition = "Fatigued";
        color = Colors.orange;
        confidence = 1 - eyeOpenness;
      } else if (eyeOpenness < 0.5) {
        condition = "Tired";
        color = Colors.yellow;
        confidence = 0.8;
      }
    }

    if (headEulerAngleY != null && headEulerAngleZ != null) {
      if (headEulerAngleY.abs() > 20 || headEulerAngleZ.abs() > 20) {
        condition = "Distracted";
        color = Colors.red;
        confidence = 0.9;
      }
    }

    if (brightness < 0.3) {
      condition += " (Low Light)";
      confidence *= 0.8;
    } else if (brightness > 0.8) {
      condition += " (Bright Light)";
      confidence *= 0.9;
    }

    return {
      'condition': condition,
      'color': color,
      'confidence': confidence,
    };
  }

  Future<void> _loadEmotionHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyJson = prefs.getString(_historyKey);
    if (historyJson != null) {
      final List<dynamic> historyList = json.decode(historyJson);
      setState(() {
        _emotionHistory =
            historyList.map((json) => EmotionData.fromJson(json)).toList();
      });
    }
  }

  Future<void> _saveEmotionHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String historyJson =
    json.encode(_emotionHistory.map((data) => data.toJson()).toList());
    await prefs.setString(_historyKey, historyJson);
  }

  void _addEmotionData() {
    if (_mood != "Analyzing..." && _mood != "No face detected") {
      setState(() {
        _emotionHistory.add(EmotionData(
          mood: _mood,
          confidence: _confidence,
          timestamp: DateTime.now(),
          condition: _faceCondition,
          lightingStatus: _lightingStatus,
        ));

        if (_emotionHistory.length > 100) {
          _emotionHistory.removeAt(0);
        }
      });
      _saveEmotionHistory();
    }
  }

  @override
  void dispose() {
    if (_isAnimationsInitialized && _animationController != null) {
      _animationController!.dispose();
    }
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        primaryColor: Color(0xFF6200EE),
        scaffoldBackgroundColor: Color(0xFF121212),
        cardColor: Color(0xFF1E1E1E),
        colorScheme: ColorScheme.dark(
          primary: Color(0xFF6200EE),
          secondary: Color(0xFF03DAC6),
          surface: Color(0xFF1E1E1E),
          background: Color(0xFF121212),
        ),
      ),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Colors.black.withOpacity(0.2),
              ),
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF6200EE), Color(0xFF03DAC6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(Icons.face, size: 20, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text(
                "Emotion Analyzer",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: AnimatedSwitcher(
                duration: Duration(milliseconds: 300),
                child: Icon(
                  _showHistory ? Icons.camera_alt : Icons.insights,
                  key: ValueKey(_showHistory),
                ),
              ),
              onPressed: () => setState(() => _showHistory = !_showHistory),
              tooltip: _showHistory ? "Camera View" : "Emotion History",
            ),
            IconButton(
              icon: Icon(Icons.info_outline),
              onPressed: () => _showInfoDialog(context),
              tooltip: "About",
            ),
          ],
        ),
        body: _showHistory ? _buildHistoryView() : _buildCameraView(),
        bottomNavigationBar: _showHistory
            ? null
            : _buildBottomControls(),
      ),
    );
  }

  Widget _buildBottomControls() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 80,
          padding: EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.1),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBottomNavItem(
                icon: Icons.grid_on,
                label: "Guide",
                isActive: _showGuideOverlay,
                onTap: () => setState(() => _showGuideOverlay = !_showGuideOverlay),
              ),
              _buildCaptureButton(),
              _buildBottomNavItem(
                icon: Icons.insights,
                label: "Metrics",
                isActive: _showAdvancedMetrics,
                onTap: () => setState(() => _showAdvancedMetrics = !_showAdvancedMetrics),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? Color(0xFF6200EE).withOpacity(0.2)
                  : Colors.transparent,
              border: Border.all(
                color: isActive ? Color(0xFF6200EE) : Colors.white30,
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? Color(0xFF6200EE) : Colors.white54,
              size: 20,
            ),
          ),
          SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isActive ? Color(0xFF6200EE) : Colors.white54,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _switchCamera,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0xFF6200EE), Color(0xFF03DAC6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0xFF6200EE).withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          Icons.flip_camera_ios,
          color: Colors.white,
          size: 30,
        ),
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          decoration: BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Color(0xFF6200EE).withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6200EE), Color(0xFF03DAC6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.psychology, color: Colors.white, size: 28),
                      SizedBox(width: 12),
                      Text(
                        "Emotion Analyzer",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Features",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6200EE),
                      ),
                    ),
                    SizedBox(height: 16),
                    _buildFeatureItem(
                      icon: Icons.face,
                      title: "Emotion Detection",
                      description: "Analyzes facial expressions in real-time to identify emotional states",
                    ),
                    _buildFeatureItem(
                      icon: Icons.nightlight_round,
                      title: "Fatigue Analysis",
                      description: "Detects signs of tiredness through eye openness tracking",
                    ),
                    _buildFeatureItem(
                      icon: Icons.wb_sunny,
                      title: "Lighting Assessment",
                      description: "Evaluates ambient lighting conditions for optimal detection",
                    ),
                    _buildFeatureItem(
                      icon: Icons.insights,
                      title: "Emotion History",
                      description: "Tracks and stores emotion data over time for analysis",
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.white12),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "Got it",
                    style: TextStyle(
                      color: Color(0xFF03DAC6),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Color(0xFF6200EE).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: Color(0xFF03DAC6),
              size: 20,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryView() {
    if (_emotionHistory.isEmpty) {
      return _buildEmptyHistoryView();
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF121212),
            Color(0xFF262626),
          ],
        ),
      ),
      child: Column(
        children: [
          _buildHistoryHeader(),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _emotionHistory.length,
              itemBuilder: (context, index) {
                final data = _emotionHistory[_emotionHistory.length - 1 - index];
                return _buildHistoryCard(data, index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 100, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Emotion History",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              IconButton(
                icon: Icon(Icons.filter_list),
                onPressed: () {},
                tooltip: "Filter history",
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            "${_emotionHistory.length} entries recorded",
            style: TextStyle(
              color: Colors.white60,
              fontSize: 14,
            ),
          ),
          SizedBox(height: 20),
          Container(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildFilterChip(label: "All", isSelected: true),
                _buildFilterChip(label: "Happy", isSelected: false),
                _buildFilterChip(label: "Sad", isSelected: false),
                _buildFilterChip(label: "Tired", isSelected: false),
                _buildFilterChip(label: "Stressed", isSelected: false),
              ],
            ),
          ),
          SizedBox(height: 10),
          Divider(color: Colors.white12),
        ],
      ),
    );
  }

  Widget _buildFilterChip({required String label, required bool isSelected}) {
    return Container(
      margin: EdgeInsets.only(right: 10),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        showCheckmark: false,
        backgroundColor: Colors.white.withOpacity(0.08),
        selectedColor: Color(0xFF6200EE).withOpacity(0.2),
        labelStyle: TextStyle(
          color: isSelected ? Color(0xFF6200EE) : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        shape: StadiumBorder(
          side: BorderSide(
            color: isSelected ? Color(0xFF6200EE) : Colors.transparent,
            width: 1.5,
          ),
        ),
        onSelected: (bool selected) {},
      ),
    );
  }

  Widget _buildHistoryCard(EmotionData data, int index) {
    final color = _getMoodColor(data.mood);

    return AnimatedOpacity(
        opacity: 1.0,
        duration: Duration(milliseconds: 300),
    child: Container(
    margin: EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
    color: Color(0xFF1E1E1E),
    borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              gradient: LinearGradient(
                colors: [color.withOpacity(0.3), Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      _getMoodIcon(data.mood),
                      color: color,
                      size: 24,
                    ),
                    SizedBox(width: 12),
                    Text(
                      data.mood,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bubble_chart,
                        size: 16,
                        color: color,
                      ),
                      SizedBox(width: 4),
                      Text(
                        "${(data.confidence * 100).toStringAsFixed(0)}%",
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: Colors.white60,
                    ),
                    SizedBox(width: 8),
                    Text(
                      _formatDate(data.timestamp),
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildDetailItem(
                        icon: Icons.face,
                        label: "Condition",
                        value: data.condition,
                      ),
                    ),
                    Expanded(
                      child: _buildDetailItem(
                        icon: Icons.lightbulb_outline,
                        label: "Lighting",
                        value: data.lightingStatus,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: Colors.white60,
        ),
        SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                ),
              ),
              SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final dateToCheck = DateTime(
      dateTime.year,
      dateTime.month,
      dateTime.day,
    );

    if (dateToCheck == today) {
      return "Today, ${_formatTime(dateTime)}";
    } else if (dateToCheck == yesterday) {
      return "Yesterday, ${_formatTime(dateTime)}";
    } else {
      return "${dateTime.day}/${dateTime.month}/${dateTime.year}, ${_formatTime(dateTime)}";
    }
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }

  Widget _buildEmptyHistoryView() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF121212),
            Color(0xFF262626),
          ],
        ),
      ),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: 100),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Color(0xFF1E1E1E),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.timeline,
              size: 60,
              color: Color(0xFF6200EE),
            ),
          ),
          SizedBox(height: 32),
          Text(
            "No Emotion History",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "Start using the emotion analyzer to track and record your mood patterns over time.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ),
          SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _showHistory = false;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF6200EE),
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.camera_alt),
                SizedBox(width: 8),
                Text(
                  "Go to Camera",
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    if (!_isCameraInitialized) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Color(0xFF6200EE)),
            ),
            SizedBox(height: 16),
            Text("Initializing camera..."),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_cameraController!),
        if (_showGuideOverlay)
          CustomPaint(
            painter: FaceGuidePainter(),
          ),
        _buildOverlayInfo(),
        _buildBottomInfoPanel(),
      ],
    );
  }

  Widget _buildOverlayInfo() {
    return SafeArea(
      child: Container(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isAnimationsInitialized)
              FadeTransition(
                opacity: _fadeAnimation!,
                child: SlideTransition(
                  position: Tween(
                    begin: Offset(0, -0.5),
                    end: Offset.zero,
                  ).animate(_animationController!),
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wb_sunny,
                          color: _lightingColor,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          _lightingStatus,
                          style: TextStyle(
                            color: _lightingColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Spacer(),
            if (_showAdvancedMetrics)
              Container(
                margin: EdgeInsets.only(bottom: 16),
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Advanced Metrics",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF03DAC6),
                      ),
                    ),
                    SizedBox(height: 12),
                    _buildMetricItem(
                      label: "Face Condition",
                      value: _faceCondition,
                      color: _conditionColor,
                    ),
                    SizedBox(height: 8),
                    _buildMetricItem(
                      label: "Confidence",
                      value: "${(_confidence * 100).toStringAsFixed(0)}%",
                      color: _moodColor,
                    ),
                    SizedBox(height: 8),
                    _buildMetricItem(
                      label: "Processing Rate",
                      value: "${(1 / _processingInterval).toStringAsFixed(1)} FPS",
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem({
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomInfoPanel() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 80,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 16),
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _moodColor.withOpacity(0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _moodColor.withOpacity(0.3),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getMoodIcon(_mood),
                  color: _moodColor,
                  size: 28,
                ),
                SizedBox(width: 12),
                Text(
                  _mood,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _confidence,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      colors: [_moodColor.withOpacity(0.7), _moodColor],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getMoodColor(String mood) {
    if (mood.contains("Happy")) {
      return Colors.green;
    } else if (mood.contains("Sad")) {
      return Colors.blue;
    } else if (mood.contains("Tired")) {
      return Colors.purple;
    } else if (mood.contains("Stressed")) {
      return Colors.red;
    } else if (mood.contains("Looking Away")) {
      return Colors.yellow;
    } else {
      return Colors.white;
    }
  }

  IconData _getMoodIcon(String mood) {
    if (mood.contains("Happy") || mood.contains("😄") || mood.contains("🙂")) {
      return Icons.sentiment_very_satisfied;
    } else if (mood.contains("Sad") || mood.contains("😢")) {
      return Icons.sentiment_dissatisfied;
    } else if (mood.contains("Tired") || mood.contains("😴")) {
      return Icons.nightlight_round;
    } else if (mood.contains("Stressed") || mood.contains("😫")) {
      return Icons.sentiment_very_dissatisfied;
    } else if (mood.contains("Looking Away") || mood.contains("👀")) {
      return Icons.remove_red_eye;
    } else if (mood.contains("No face")) {
      return Icons.face_retouching_off;
    } else if (mood.contains("Analyzing")) {
      return Icons.psychology;
    } else {
      return Icons.sentiment_neutral;
    }
  }
}
