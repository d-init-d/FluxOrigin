import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/translation_progress.dart';
import '../services/ai_service.dart';
import '../services/web_search_service.dart';
import '../services/dev_logger.dart';
import '../utils/text_processor.dart';
import '../utils/file_parser.dart';
import '../utils/app_strings.dart';

class TranslationController {
  final AIService _aiService = AIService();
  final WebSearchService _webSearchService = WebSearchService();
  final DevLogger _logger = DevLogger();

  /// Set the base URL for AI API
  void setAIUrl(String url) {
    _aiService.setBaseUrl(url);
  }

  /// Set the AI provider type
  void setAIProviderType(AIProviderType type) {
    _aiService.setProviderType(type);
  }

  // Pause control
  bool _isPaused = false;

  /// Request to pause the translation after the current chunk
  void requestPause() {
    _isPaused = true;
  }

  /// Reset pause state (call before starting/resuming)
  void resetPause() {
    _isPaused = false;
  }

  /// Check if a progress file exists for the given document
  /// Returns progress percentage (0.0 to 1.0) if exists, null otherwise
  Future<double?> getProgressPercentage(
      String filePath, String dictionaryDir) async {
    final String fileName = path.basenameWithoutExtension(filePath);
    final String progressPath =
        path.join(dictionaryDir, "$fileName.flux_progress.json");
    final progress = await TranslationProgress.loadFromFile(progressPath);
    if (progress == null) return null;
    if (progress.rawChunks.isEmpty) return null;
    return progress.currentIndex / progress.rawChunks.length;
  }

  /// Check if a progress file exists for the given document
  Future<bool> hasProgress(String filePath, String dictionaryDir) async {
    final String fileName = path.basenameWithoutExtension(filePath);
    final String progressPath =
        path.join(dictionaryDir, "$fileName.flux_progress.json");
    final File progressFile = File(progressPath);
    return await progressFile.exists();
  }

  /// Delete progress file for the given document
  Future<void> deleteProgress(String filePath, String dictionaryDir) async {
    final String fileName = path.basenameWithoutExtension(filePath);
    final String progressPath =
        path.join(dictionaryDir, "$fileName.flux_progress.json");
    final File progressFile = File(progressPath);
    if (await progressFile.exists()) {
      await progressFile.delete();
    }
  }

  /// Processes the file with resume capability.
  /// [onUpdate] callback returns status message and progress (0.0 to 1.0).
  /// [onChunkUpdate] callback returns current chunk index, total chunks, source chunk, and translated chunk.
  /// [allowInternet] controls whether web search (RAG) is used for glossary enrichment.
  /// [resume] if true and progress exists, resume from saved state; if false, start fresh.
  /// Returns the translated content as a String, or null if paused.
  Future<String?> processFile({
    required String filePath,
    required String dictionaryDir,
    required String modelName,
    required String sourceLanguage,
    required String targetLanguage,
    required Function(String status, double progress) onUpdate,
    Function(int currentIndex, int total, String sourceChunk,
            String translatedChunk)?
        onChunkUpdate,
    required bool allowInternet,
    bool resume = false,
    String appLanguage = 'vi',
  }) async {
    // Reset pause state at start
    _isPaused = false;

    _logger.info('Translation', 'Starting translation process', details: '''
File: $filePath
Model: $modelName
Source: $sourceLanguage -> Target: $targetLanguage
Allow Internet: $allowInternet
Resume: $resume
''');

    final String fileName = path.basenameWithoutExtension(filePath);
    final String progressPath =
        path.join(dictionaryDir, "$fileName.flux_progress.json");
    TranslationProgress? progress =
        await TranslationProgress.loadFromFile(progressPath);

    // --- 1. INITIALIZATION OR RESUME ---
    if (progress != null && resume) {
      _logger.info('Translation',
          'Resuming from saved progress: ${progress.currentIndex}/${progress.rawChunks.length} chunks');
      onUpdate(AppStrings.get(appLanguage, 'status_restoring_progress'),
          progress.currentIndex / progress.rawChunks.length);
      await Future.delayed(const Duration(seconds: 1)); // UX delay
    } else {
      // If not resuming or no progress, delete old progress and start fresh
      if (progress != null && !resume) {
        final File progressFile = File(progressPath);
        if (await progressFile.exists()) {
          // Retry loop to handle Windows file lock (OS Error 32)
          bool deleted = false;
          for (int attempt = 1; attempt <= 3; attempt++) {
            try {
              await progressFile.delete();
              deleted = true;
              break;
            } on PathAccessException catch (e) {
              _logger.warning('Translation',
                  'File delete attempt $attempt/3 failed (OS Error 32): $e');
              if (attempt < 3) {
                await Future.delayed(const Duration(milliseconds: 500));
              }
            }
          }
          if (!deleted) {
            _logger.warning('Translation',
                'Could not delete progress file after 3 attempts. Proceeding anyway (writeAsString may overwrite).');
          }
        }
        progress = null;
      }

      // INITIALIZATION SECTION - Wrapped in try-catch to handle AI service failures
      try {
        onUpdate(AppStrings.get(appLanguage, 'status_reading_file'), 0.0);
        _logger.debug('Translation', 'Reading source file...');

        // Extract text content based on file type (TXT or EPUB)
        // Use compute() for heavy EPUB parsing to avoid blocking UI
        final String content = await compute(_extractTextInIsolate, filePath);
        final String fileName = path.basenameWithoutExtension(filePath);
        _logger.info('Translation', 'File loaded: ${content.length} characters');

        onUpdate(AppStrings.get(appLanguage, 'status_analyzing'), 0.1);
        // Use compute() for heavy text splitting to avoid blocking UI
        final List<String> chunks = await compute(_smartSplitInIsolate, content);
        final String sample = TextProcessor.createSample(content);
        _logger.info('Translation', 'Text split into ${chunks.length} chunks');

        onUpdate(AppStrings.get(appLanguage, 'status_detecting_genre'), 0.2);
        // Chỉ detect genre nếu nguồn là Tiếng Trung, các trường hợp khác dùng "KHAC"
        final String genreKey = sourceLanguage == 'Tiếng Trung'
            ? await _aiService.detectGenre(sample, modelName)
            : "KHAC";
        _logger.info('Translation', 'Detected genre: $genreKey');

        final String systemPrompt =
            _aiService.getSystemPrompt(genreKey, sourceLanguage, targetLanguage);
        _logger.debug('Translation', 'System prompt set', details: systemPrompt);

        onUpdate(AppStrings.get(appLanguage, 'status_creating_glossary'), 0.3);
        final String glossaryCsv = await _aiService.generateGlossary(
            sample, modelName, sourceLanguage, genreKey);
        _logger.info('Translation',
            'Glossary generated: ${glossaryCsv.split('\n').length} terms');

        // Smart Merge: Merge AI glossary with existing user CSV
        final glossaryFile =
            File(path.join(dictionaryDir, "${fileName}_glossary.csv"));

        try {
          final String mergedCsv = await _smartMergeGlossary(
            aiGeneratedCsv: glossaryCsv,
            existingFile: glossaryFile,
          );

          // Save merged glossary as CSV
          await glossaryFile.writeAsString(mergedCsv);
          _logger.debug('Translation', 'Glossary saved to: ${glossaryFile.path}');
        } catch (e) {
          _logger.warning('Translation', 'Error saving glossary: $e');
          // Non-critical error, continue
        }

        // Enrich Glossary: Lookup definitions (only if Internet is allowed)
        String glossary;
        if (allowInternet) {
          onUpdate("Đang tra cứu thuật ngữ (RAG)...", 0.35);
          glossary = await _enrichGlossary(
            glossaryFile: glossaryFile,
            targetLanguage: targetLanguage,
            onUpdate: onUpdate,
          );
        } else {
          onUpdate("Chế độ cục bộ - bỏ qua tra cứu Internet...", 0.35);
          glossary = await glossaryFile.readAsString();
        }

        // Create output path in outputDir
        // Note: In new flow, we don't save automatically, but we keep this field
        // in TranslationProgress for compatibility or future use.
        const String outputPath = "";

        progress = TranslationProgress(
          sourcePath: filePath,
          outputPath: outputPath,
          glossary: glossary,
          systemPrompt: systemPrompt,
          genre: genreKey,
          rawChunks: chunks,
          translatedChunks: List<String?>.filled(chunks.length, null),
          currentIndex: 0,
          lastUpdated: DateTime.now(),
        );

        await progress.saveToFile(progressPath);
      } catch (e) {
        // Log the initialization error
        _logger.error('Translation', 'Initialization failed during glossary generation', details: e.toString());
        
        // CRITICAL: Update UI with error status so it doesn't stay stuck at "Creating glossary"
        onUpdate(AppStrings.get(appLanguage, 'status_error') + ': $e', 0.3);
        
        // Rethrow to stop execution and let caller handle the error
        rethrow;
      }
    }

    // --- 2. TRANSLATION LOOP WITH CONTEXT AWARENESS ---
    final int total = progress.rawChunks.length;
    String? previousContext;

    // If resuming, extract context from the last translated chunk
    if (progress.currentIndex > 0) {
      final lastTranslated =
          progress.translatedChunks[progress.currentIndex - 1];
      if (lastTranslated != null && lastTranslated.isNotEmpty) {
        previousContext =
            TextProcessor.extractLastSentences(lastTranslated, maxLength: 200);
      }
    }

    _logger.info('Translation',
        'Starting translation loop: ${progress.currentIndex}/$total chunks');

    for (int i = progress.currentIndex; i < total; i++) {
      // Check for pause request BEFORE processing next chunk
      if (_isPaused) {
        _logger.info(
            'Translation', 'Translation paused at chunk ${i + 1}/$total');
        onUpdate(AppStrings.get(appLanguage, 'status_paused'), i / total);
        await progress.saveToFile(progressPath);
        return null; // Return null to indicate paused state
      }

      final double percent = (i / total);
      onUpdate("${AppStrings.get(appLanguage, 'status_translating')} ${i + 1}/$total...", percent);

      try {
        final String chunk = progress.rawChunks[i];
        _logger.debug('Translation',
            'Translating chunk ${i + 1}/$total (${chunk.length} chars)');

        // Notify UI about current chunk being processed
        onChunkUpdate?.call(i + 1, total, chunk, AppStrings.get(appLanguage, 'processing'));

        final String translated = await _aiService.translateChunk(
          chunk,
          progress.systemPrompt,
          progress.glossary,
          modelName,
          sourceLanguage,
          targetLanguage,
          previousContext: previousContext,
          genre: progress.genre,
        );

        progress.translatedChunks[i] = translated;
        progress.currentIndex = i + 1;

        _logger.debug('Translation',
            'Chunk ${i + 1} translated (${translated.length} chars)');

        // Notify UI about translated result
        onChunkUpdate?.call(i + 1, total, chunk, translated);

        // Update context for next iteration
        if (translated.isNotEmpty) {
          previousContext =
              TextProcessor.extractLastSentences(translated, maxLength: 200);
        }

        // CRITICAL: Save after every chunk
        await progress.saveToFile(progressPath);
      } catch (e) {
        _logger.error('Translation', 'Error translating chunk ${i + 1}: $e');
        onUpdate("${AppStrings.get(appLanguage, 'status_error')} ${i + 1}: $e", percent);
        // Simple retry logic: decrement i to retry this chunk next loop
        // Or just throw to stop and let user resume later.
        // For now, let's throw so the loop stops and user can resume.
        throw Exception("${AppStrings.get(appLanguage, 'status_error')} ${i + 1}: $e");
      }
    }

    // --- 3. FINALIZE ---
    _logger.info('Translation', 'Translation complete! Finalizing...');
    onUpdate(AppStrings.get(appLanguage, 'status_merging'), 1.0);
    final StringBuffer finalContent = StringBuffer();
    for (final chunk in progress.translatedChunks) {
      if (chunk != null) {
        finalContent.write(chunk);
        finalContent.write("\n\n");
      }
    }

    // Cleanup progress file
    final File progressFile = File(progressPath);
    if (await progressFile.exists()) {
      await progressFile.delete();
    }

    // Add to history log
    await _addToHistory(
      dictionaryDir: dictionaryDir,
      fileName: fileName,
      status: 'completed',
    );

    _logger.info('Translation',
        'Translation saved! Final length: ${finalContent.length} chars');
    onUpdate(AppStrings.get(appLanguage, 'status_completed'), 1.0);
    return finalContent.toString();
  }

  /// Adds a translation entry to the history log
  Future<void> _addToHistory({
    required String dictionaryDir,
    required String fileName,
    required String status,
  }) async {
    final historyPath = path.join(dictionaryDir, 'history_log.json');
    final historyFile = File(historyPath);

    List<Map<String, dynamic>> history = [];

    // Load existing history
    if (await historyFile.exists()) {
      try {
        final content = await historyFile.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          history = decoded.cast<Map<String, dynamic>>();
        }
      } catch (e) {
        // If file is corrupted, start fresh
        debugPrint('Error reading history: $e');
      }
    }

    // Add new entry
    history.add({
      'fileName': fileName,
      'date': DateTime.now().toIso8601String(),
      'status': status,
    });

    // Save history
    try {
      await historyFile.writeAsString(jsonEncode(history));
    } catch (e) {
      debugPrint('Error saving history: $e');
    }
  }

  /// Smart Merge: Merges AI-generated CSV with existing user CSV
  /// Keeps user edits, adds new AI entries
  /// Smart Merge: Merges AI-generated CSV with existing user CSV
  /// Keeps user edits, adds new AI entries
  /// Preserves 3 columns: Original, Vietnamese, Definition
  Future<String> _smartMergeGlossary({
    required String aiGeneratedCsv,
    required File existingFile,
  }) async {
    // Parse AI-generated CSV
    List<List<dynamic>> aiRows = [];
    try {
      aiRows = const CsvToListConverter().convert(
        aiGeneratedCsv,
        eol: '\n',
        shouldParseNumbers: false,
      );
    } catch (e) {
      print("Error parsing AI glossary CSV: $e");
    }

    // Create a map from AI data: Original Name -> [Vietnamese Name, Definition]
    final Map<String, List<String>> aiMap = {};
    for (final row in aiRows) {
      if (row.length >= 2) {
        final original = row[0].toString().trim();
        final vietnamese = row[1].toString().trim();
        final definition = row.length > 2 ? row[2].toString().trim() : "";
        if (original.isNotEmpty) {
          aiMap[original] = [vietnamese, definition];
        }
      }
    }

    // If existing file exists, load and preserve user edits
    if (await existingFile.exists()) {
      List<List<dynamic>> existingRows = [];
      try {
        final String existingContent = await existingFile.readAsString();
        existingRows = const CsvToListConverter().convert(
          existingContent,
          eol: '\n',
          shouldParseNumbers: false,
        );
      } catch (e) {
        print("Error parsing existing glossary CSV: $e");
      }

      // User edits take priority
      final Map<String, List<String>> userMap = {};
      for (final row in existingRows) {
        if (row.length >= 2) {
          final original = row[0].toString().trim();
          final vietnamese = row[1].toString().trim();
          final definition = row.length > 2 ? row[2].toString().trim() : "";
          if (original.isNotEmpty) {
            userMap[original] = [vietnamese, definition];
          }
        }
      }

      // Merge: User edits + New AI entries
      // Start with AI map, then overwrite with User map
      final Map<String, List<String>> mergedMap = {...aiMap};
      mergedMap.addAll(userMap);

      // Convert back to CSV
      final List<List<String>> csvData = mergedMap.entries.map((e) {
        return [e.key, e.value[0], e.value[1]];
      }).toList();

      return const ListToCsvConverter().convert(csvData, eol: '\n');
    } else {
      // No existing file, use AI-generated CSV but ensure 3 columns structure
      final List<List<String>> csvData = aiMap.entries.map((e) {
        return [e.key, e.value[0], e.value[1]];
      }).toList();

      return const ListToCsvConverter().convert(csvData, eol: '\n');
    }
  }

  /// Enriches the glossary by looking up definitions for terms
  Future<String> _enrichGlossary({
    required File glossaryFile,
    required String targetLanguage,
    required Function(String, double) onUpdate,
  }) async {
    if (!await glossaryFile.exists()) return "";

    try {
      final String content = await glossaryFile.readAsString();
      List<List<dynamic>> rows = const CsvToListConverter().convert(
        content,
        eol: '\n',
        shouldParseNumbers: false,
      );

      bool isModified = false;
      final int totalRows = rows.length;

      for (int i = 0; i < totalRows; i++) {
        final row = rows[i];
        if (row.isEmpty) continue;

        // Ensure row has at least 3 columns
        while (row.length < 3) {
          row.add(""); // Add empty definition
          isModified = true;
        }

        final String original = row[0].toString().trim();
        // final String vietnamese = row[1].toString().trim();
        String definition = row[2].toString().trim();

        // If definition is empty, lookup
        if (definition.isEmpty && original.isNotEmpty) {
          onUpdate(
              "Đang tra cứu: $original...", 0.35 + (0.05 * (i / totalRows)));

          final langCode = _getLangCode(targetLanguage);
          final String? result =
              await _webSearchService.lookupTerm(original, langCode);
          if (result != null) {
            row[2] =
                result; // ListToCsvConverter will handle escaping quotes/commas
            isModified = true;
          }

          // Delay to avoid rate limiting
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      // Always convert back to ensure consistent 3-column format and proper escaping
      final String newCsv = const ListToCsvConverter().convert(rows, eol: '\n');

      if (isModified) {
        await glossaryFile.writeAsString(newCsv);
      }

      return newCsv;
    } catch (e) {
      print("Error enriching glossary: $e");
      // Return original content if enrichment fails to avoid data loss
      return await glossaryFile.readAsString();
    }
  }

  String _getLangCode(String languageName) {
    switch (languageName) {
      case 'Tiếng Việt':
        return 'vi';
      case 'Tiếng Anh':
        return 'en';
      case 'Tiếng Trung':
        return 'zh';
      default:
        return 'en'; // Mặc định là Anh
    }
  }
}

// Top-level functions for compute() isolate execution
// These must be top-level or static to work with compute()

/// Extracts text from file in isolate (supports TXT and EPUB)
Future<String> _extractTextInIsolate(String filePath) async {
  return FileParser.extractText(filePath);
}

/// Splits text into chunks in isolate
List<String> _smartSplitInIsolate(String content) {
  return TextProcessor.smartSplit(content);
}
