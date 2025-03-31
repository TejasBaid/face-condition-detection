import 'dart:convert';

class EmotionData {
  final String mood;
  final double confidence;
  final DateTime timestamp;
  final String condition;
  final String lightingStatus;

  EmotionData({
    required this.mood,
    required this.confidence,
    required this.timestamp,
    required this.condition,
    required this.lightingStatus,
  });

  Map<String, dynamic> toJson() => {
    'mood': mood,
    'confidence': confidence,
    'timestamp': timestamp.toIso8601String(),
    'condition': condition,
    'lightingStatus': lightingStatus,
  };

  factory EmotionData.fromJson(Map<String, dynamic> json) => EmotionData(
    mood: json['mood'],
    confidence: json['confidence'],
    timestamp: DateTime.parse(json['timestamp']),
    condition: json['condition'],
    lightingStatus: json['lightingStatus'],
  );
}
