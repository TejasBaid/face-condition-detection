import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'screens/face_detection_screen.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(FaceDetectionApp());
}

class FaceDetectionApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Color(0xFF1A1A1A),
        cardTheme: CardTheme(
          color: Colors.black.withOpacity(0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.white10),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: Colors.white.withOpacity(0.2),
          elevation: 0,
          extendedTextStyle: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
      home: FaceDetectionScreen(),
    );
  }
}
