import 'dart:convert';
import 'dart:io';
import '../services/dev_logger.dart';

class TranslationProgress {
  final String sourcePath;
  final String outputPath;
  final String glossary;
  final String systemPrompt;
  final String genre;
  final List<String> rawChunks;
  final List<String?> translatedChunks;
  int currentIndex;
  DateTime lastUpdated;

  // Optional v3.0 D-Transcreate metadata (omitted from JSON when null to
  // preserve byte-exact baseline serialization).
  final String? styleGuide;
  final Map<String, dynamic>? epubMetadata;
  final Map<String, dynamic>? qaSummary;

  TranslationProgress({
    required this.sourcePath,
    required this.outputPath,
    required this.glossary,
    required this.systemPrompt,
    required this.genre,
    required this.rawChunks,
    required this.translatedChunks,
    required this.currentIndex,
    required this.lastUpdated,
    this.styleGuide,
    this.epubMetadata,
    this.qaSummary,
  });

  Map<String, dynamic> toJson() {
    return {
      'sourcePath': sourcePath,
      'outputPath': outputPath,
      'glossary': glossary,
      'systemPrompt': systemPrompt,
      'genre': genre,
      'rawChunks': rawChunks,
      'translatedChunks': translatedChunks,
      'currentIndex': currentIndex,
      'lastUpdated': lastUpdated.toIso8601String(),
      if (styleGuide != null) 'styleGuide': styleGuide,
      if (epubMetadata != null) 'epubMetadata': epubMetadata,
      if (qaSummary != null) 'qaSummary': qaSummary,
    };
  }

  factory TranslationProgress.fromJson(Map<String, dynamic> json) {
    return TranslationProgress(
      sourcePath: json['sourcePath'],
      outputPath: json['outputPath'],
      glossary: json['glossary'],
      systemPrompt: json['systemPrompt'],
      genre: json['genre'] ?? 'KHAC',
      rawChunks: List<String>.from(json['rawChunks']),
      translatedChunks: List<String?>.from(json['translatedChunks']),
      currentIndex: json['currentIndex'],
      lastUpdated: DateTime.parse(json['lastUpdated']),
      styleGuide: json['styleGuide'] as String?,
      epubMetadata: json['epubMetadata'] is Map
          ? Map<String, dynamic>.from(json['epubMetadata'] as Map)
          : null,
      qaSummary: json['qaSummary'] is Map
          ? Map<String, dynamic>.from(json['qaSummary'] as Map)
          : null,
    );
  }

  static Future<TranslationProgress?> loadFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content);
      return TranslationProgress.fromJson(json);
    } catch (e) {
      DevLogger().error('TranslationProgress', 'Error loading progress',
          details: e.toString());
      return null;
    }
  }

  Future<void> saveToFile(String filePath) async {
    lastUpdated = DateTime.now();
    final tempPath = '$filePath.tmp';
    try {
      await File(tempPath).writeAsString(jsonEncode(toJson()), flush: true);
      await File(tempPath).rename(filePath);
    } catch (e) {
      try {
        await File(tempPath).delete();
      } catch (_) {
        // best-effort cleanup
      }
      rethrow;
    }
  }
}
