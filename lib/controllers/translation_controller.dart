import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/translation_progress.dart';
import '../services/ai_service.dart';
import '../services/d_transcreate_service.dart';
import '../services/epub_pipeline_service.dart';
import '../services/qa_verifier_service.dart';
import '../services/web_search_service.dart';
import '../services/dev_logger.dart';
import '../utils/text_processor.dart';
import '../utils/file_parser.dart';
import '../utils/term_miner.dart';
import '../utils/app_strings.dart';

class TranslationController {
  final AIService _aiService = AIService();
  final WebSearchService _webSearchService = WebSearchService();
  final DTranscreateService _dTranscreateService = DTranscreateService();
  final EpubPipelineService _epubPipeline = EpubPipelineService();
  final DevLogger _logger = DevLogger();

  /// Throttle factor: save progress every N chunks (default 5)
  static const int _saveEveryNChunks = 5;

  int _targetChunkSize = 1200;
  bool _deepMode = true;

  QaReport? _lastQaReport;
  List<int>? _lastTranslatedEpubBytes;
  String? _lastWorkspacePath;

  QaReport? get lastQaReport => _lastQaReport;
  List<int>? get lastTranslatedEpubBytes => _lastTranslatedEpubBytes;
  String? get lastWorkspacePath => _lastWorkspacePath;

  /// Set the base URL for AI API
  void setAIUrl(String url) {
    _aiService.setBaseUrl(url);
  }

  /// Set the AI provider type
  void setAIProviderType(AIProviderType type) {
    _aiService.setProviderType(type);
  }

  /// Set BYOK API key(s) for cloud providers (single or newline/comma separated)
  void setAIApiKey(String rawKeys) {
    _aiService.setApiKey(rawKeys);
  }

  /// Configure generation temperature (default 0.2)
  void setTemperature(double temperature) {
    _aiService.setDefaultTemperature(temperature);
  }

  /// Configure target chunk size in characters (default 1200)
  void setChunkSize(int chunkSize) {
    _targetChunkSize = chunkSize.clamp(500, 4000);
  }

  /// Enable or disable full D-Transcreate v1.1.0 deep mode (whole-book mining + QA + workspace)
  void setDeepMode(bool enabled) {
    _deepMode = enabled;
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

  /// Processes the file with resume capability and D-Transcreate v1.1.0 pipeline.
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
    String? userGlossaryPath,
    String? genreOverride,
    bool preserveEpubLayout = true,
    int maxRetries = 2,
  }) async {
    _isPaused = false;
    _lastQaReport = null;
    _lastTranslatedEpubBytes = null;
    _lastWorkspacePath = null;

    _logger.info('Translation', 'Starting translation process', details: '''
File: $filePath
Model: $modelName
Source: $sourceLanguage -> Target: $targetLanguage
Allow Internet: $allowInternet
Resume: $resume
D-Transcreate Deep Mode: $_deepMode | EPUB Layout Lock: $preserveEpubLayout
''');

    final String fileName = path.basenameWithoutExtension(filePath);
    final String progressPath =
        path.join(dictionaryDir, "$fileName.flux_progress.json");
    TranslationProgress? progress =
        await TranslationProgress.loadFromFile(progressPath);

    EpubScanResult? epubScan;
    List<CandidateTerm> minedTerms = const [];
    String styleGuide = '';

    // --- 1. INITIALIZATION OR RESUME ---
    if (progress != null && resume) {
      _logger.info('Translation',
          'Resuming from saved progress: ${progress.currentIndex}/${progress.rawChunks.length} chunks');
      onUpdate(AppStrings.get(appLanguage, 'status_restoring_progress'),
          progress.currentIndex / progress.rawChunks.length);
      styleGuide = progress.styleGuide ?? '';
      await Future.delayed(const Duration(milliseconds: 600));
    } else {
      if (progress != null && !resume) {
        final File progressFile = File(progressPath);
        if (await progressFile.exists()) {
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

      try {
        onUpdate(AppStrings.get(appLanguage, 'status_reading_file'), 0.0);
        _logger.debug('Translation', 'Reading source file...');

        final isEpub = filePath.toLowerCase().endsWith('.epub');
        final isPdf = filePath.toLowerCase().endsWith('.pdf');
        String content = '';
        List<String> chunks = [];

        if (isEpub && preserveEpubLayout) {
          try {
            epubScan = await _epubPipeline.scanEpub(
              filePath,
              targetChunkChars: _targetChunkSize,
            );
            chunks = epubScan.anchoredChunks;
            content = epubScan.fullPlainText;
            _logger.info('Translation', 'File loaded: ${content.length} characters');
          } catch (e) {
            _logger.warning('Translation',
                'Anchor-Locked EPUB scan failed, falling back to plain EPUB extraction: $e');
            content = await compute(_extractTextInIsolate, filePath);
            _logger.info('Translation', 'File loaded: ${content.length} characters');
          }
        } else if (isPdf) {
          final bridged =
              await _dTranscreateService.tryConvertPdfViaBookOps(filePath);
          content = (bridged != null && bridged.trim().isNotEmpty)
              ? bridged
              : await compute(_extractTextInIsolate, filePath);
          _logger.info('Translation', 'File loaded: ${content.length} characters');
        } else {
          content = await compute(_extractTextInIsolate, filePath);
          _logger.info('Translation', 'File loaded: ${content.length} characters');
        }

        onUpdate(AppStrings.get(appLanguage, 'status_analyzing'), 0.1);
        if (chunks.isEmpty) {
          chunks = await compute(
            _smartSplitInIsolate,
            {'content': content, 'targetSize': _targetChunkSize},
          );
        }
        final String sample = TextProcessor.createSample(content);
        _logger.info('Translation', 'Text split into ${chunks.length} chunks');

        // D-Transcreate Whole-Book Term Mining
        if (_deepMode && chunks.isNotEmpty) {
          minedTerms = WholeBookTermMiner.mineTerms(chunks);
        }
        final candidateTermsBlock = _deepMode
            ? WholeBookTermMiner.formatForGlossaryPrompt(minedTerms)
            : null;

        onUpdate(AppStrings.get(appLanguage, 'status_detecting_genre'), 0.2);
        String genreKey;
        if (genreOverride != null &&
            genreOverride.isNotEmpty &&
            genreOverride != 'AUTO') {
          genreKey = genreOverride;
        } else {
          genreKey = (sourceLanguage == 'Tiếng Trung' || _deepMode)
              ? await _aiService.detectGenre(sample, modelName)
              : 'KHAC';
        }
        _logger.info('Translation', 'Detected genre: $genreKey');

        final String systemPrompt =
            _aiService.getSystemPrompt(genreKey, sourceLanguage, targetLanguage);
        _logger.debug('Translation', 'System prompt set', details: systemPrompt);

        if (_deepMode) {
          styleGuide = DTranscreateService.buildStyleAndDossierGuide(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            genre: genreKey,
            candidateTerms: minedTerms,
          );
        }

        final glossaryFile =
            File(path.join(dictionaryDir, "${fileName}_glossary.csv"));

        // === FIX ISSUE #6 ===
        // Honor user-uploaded CSV verbatim when present
        final bool hasUserGlossary = await applyUserGlossary(
          userGlossaryPath: userGlossaryPath,
          glossaryFile: glossaryFile,
        );

        if (!hasUserGlossary) {
          onUpdate(
              AppStrings.get(appLanguage, 'status_creating_glossary'), 0.3);
          final String glossaryCsv = await _aiService.generateGlossary(
            sample,
            modelName,
            sourceLanguage,
            genreKey,
            candidateTermsBlock: candidateTermsBlock,
            targetLanguage: targetLanguage,
          );
          _logger.info('Translation',
              'Glossary generated: ${glossaryCsv.split('\n').length} terms');

          // Merge D-Transcreate Tier-1 domain-filtered terms with AI glossary & existing user edits
          String tier1Seed = '';
          if (_deepMode && targetLanguage == 'Tiếng Việt') {
            tier1Seed = await _dTranscreateService.buildDomainSeededCsv(
              sourceText: content,
              domain: DTranscreateService.domainForGenre(genreKey),
              targetLanguage: targetLanguage,
            );
          }

          try {
            final combinedAiAndSeed =
                tier1Seed.isNotEmpty ? '$tier1Seed\n$glossaryCsv' : glossaryCsv;
            final String mergedCsv = await _smartMergeGlossary(
              aiGeneratedCsv: combinedAiAndSeed,
              existingFile: glossaryFile,
            );

            await glossaryFile.writeAsString(mergedCsv);
            _logger.debug(
                'Translation', 'Glossary saved to: ${glossaryFile.path}');
          } catch (e) {
            _logger.warning('Translation', 'Error saving glossary: $e');
          }
        } else {
          onUpdate(AppStrings.get(appLanguage, 'status_using_user_glossary'),
              0.32);
        }

        String glossary = '';
        if (allowInternet && await glossaryFile.exists()) {
          onUpdate("Đang tra cứu thuật ngữ (RAG)...", 0.35);
          glossary = await _enrichGlossary(
            glossaryFile: glossaryFile,
            targetLanguage: targetLanguage,
            onUpdate: onUpdate,
          );
        } else {
          onUpdate("Chế độ cục bộ - bỏ qua tra cứu Internet...", 0.35);
          if (await glossaryFile.exists()) {
            glossary = await glossaryFile.readAsString();
          }
        }

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
          styleGuide: styleGuide.isNotEmpty ? styleGuide : null,
          epubMetadata: epubScan?.toMetadataJson(),
        );

        await progress.saveToFile(progressPath);
      } catch (e) {
        _logger.error(
            'Translation', 'Initialization failed during glossary generation',
            details: e.toString());
        onUpdate('${AppStrings.get(appLanguage, 'status_error')}: $e', 0.3);
        rethrow;
      }
    }

    // --- 2. TRANSLATION LOOP WITH CONTEXT AWARENESS & AUTO-RETRY ---
    final int total = progress.rawChunks.length;
    String? previousContext;

    if (progress.currentIndex > 0) {
      final lastTranslated =
          progress.translatedChunks[progress.currentIndex - 1];
      if (lastTranslated != null && lastTranslated.isNotEmpty) {
        previousContext = TextProcessor.extractLastSentences(
          EpubPipelineService.stripBlockAnchors(lastTranslated),
          maxLength: 200,
        );
      }
    }

    _logger.info('Translation',
        'Starting translation loop: ${progress.currentIndex}/$total chunks');

    for (int i = progress.currentIndex; i < total; i++) {
      if (_isPaused) {
        _logger.info(
            'Translation', 'Translation paused at chunk ${i + 1}/$total');
        onUpdate(AppStrings.get(appLanguage, 'status_paused'), i / total);
        await progress.saveToFile(progressPath);
        return null;
      }

      final double percent = (i / total);
      onUpdate(
          "${AppStrings.get(appLanguage, 'status_translating')} ${i + 1}/$total...",
          percent);

      try {
        final String chunk = progress.rawChunks[i];
        final String cleanPreviewSrc =
            EpubPipelineService.stripBlockAnchors(chunk);
        _logger.debug('Translation',
            'Translating chunk ${i + 1}/$total (${chunk.length} chars)');

        onChunkUpdate?.call(
          i + 1,
          total,
          cleanPreviewSrc,
          AppStrings.get(appLanguage, 'processing'),
        );

        String translated = '';
        Object? lastError;

        for (int attempt = 0; attempt <= maxRetries; attempt++) {
          if (_isPaused) break;
          try {
            translated = await _aiService.translateChunk(
              chunk,
              progress.systemPrompt,
              progress.glossary,
              modelName,
              sourceLanguage,
              targetLanguage,
              previousContext: previousContext,
              genre: progress.genre,
              styleGuide: styleGuide,
              sliceGlossary: _deepMode,
            );

            // Check critical chunk quality (empty / heavy CJK leakage)
            if (translated.trim().isNotEmpty) {
              final chunkIssues = QaVerifierService.checkChunk(
                chunkIndex: i,
                sourceChunk: chunk,
                translatedChunk: translated,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
              );
              final hasCriticalDefect =
                  chunkIssues.any((iss) => iss.severity == QaSeverity.error);
              if (!hasCriticalDefect || attempt == maxRetries) {
                break;
              }
              _logger.warning('Translation',
                  'Chunk ${i + 1} failed inline QA (${chunkIssues.first.gate}), retrying (${attempt + 1}/$maxRetries)');
            }
          } catch (e) {
            lastError = e;
            if (attempt == maxRetries) rethrow;
            _logger.warning('Translation',
                'Chunk ${i + 1} transient error, backing off before retry ${attempt + 1}/$maxRetries: $e');
            await Future.delayed(Duration(milliseconds: 800 * (attempt + 1)));
          }
        }

        if (_isPaused && translated.isEmpty) {
          await progress.saveToFile(progressPath);
          return null;
        }
        if (translated.isEmpty && lastError != null) {
          throw lastError;
        }

        progress.translatedChunks[i] = translated;
        progress.currentIndex = i + 1;

        _logger.debug('Translation',
            'Chunk ${i + 1} translated (${translated.length} chars)');

        final cleanPreviewTgt =
            EpubPipelineService.stripBlockAnchors(translated);
        onChunkUpdate?.call(i + 1, total, cleanPreviewSrc, cleanPreviewTgt);

        if (cleanPreviewTgt.isNotEmpty) {
          previousContext = TextProcessor.extractLastSentences(
              cleanPreviewTgt,
              maxLength: 200);
        }

        final bool isFinalChunk = (i + 1) == total;
        final bool isThrottleBoundary = ((i + 1) % _saveEveryNChunks) == 0;
        if (isFinalChunk || isThrottleBoundary) {
          await progress.saveToFile(progressPath);
        }
      } catch (e) {
        _logger.error('Translation', 'Error translating chunk ${i + 1}: $e');
        onUpdate("${AppStrings.get(appLanguage, 'status_error')} ${i + 1}: $e",
            percent);
        await progress.saveToFile(progressPath);
        throw Exception(
            "${AppStrings.get(appLanguage, 'status_error')} ${i + 1}: $e");
      }
    }

    // --- 3. FINALIZE: QA AUDIT, EPUB REBUILD & D-TRANSCREATE WORKSPACE EXPORT ---
    _logger.info('Translation', 'Translation complete! Finalizing...');
    onUpdate(AppStrings.get(appLanguage, 'status_merging'), 0.96);

    if (_deepMode) {
      _lastQaReport = QaVerifierService.verifyBook(
        rawChunks: progress.rawChunks,
        translatedChunks: progress.translatedChunks,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        glossaryCsv: progress.glossary,
      );
      _logger.info('Translation',
          'D-Transcreate QA score: ${_lastQaReport!.score}/100 (errors=${_lastQaReport!.errorCount}, warnings=${_lastQaReport!.warningCount})');
    }

    // Rebuild Anchor-Locked EPUB if source was EPUB with metadata
    final meta = progress.epubMetadata;
    if (filePath.toLowerCase().endsWith('.epub') && meta != null) {
      try {
        final blockRefs = (meta['blockRefs'] as List? ?? const [])
            .map((e) => EpubBlockRef.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        final chunkIds = (meta['chunkBlockIds'] as List? ?? const [])
            .map((e) => List<int>.from(e as List))
            .toList();
        if (blockRefs.isNotEmpty && chunkIds.isNotEmpty) {
          _lastTranslatedEpubBytes = await _epubPipeline.rebuildTranslatedEpub(
            sourceEpubPath: filePath,
            blockRefs: blockRefs,
            chunkBlockIds: chunkIds,
            translatedChunks: progress.translatedChunks,
            targetLanguageName: targetLanguage,
          );
          _logger.info('Translation',
              'Rebuilt Anchor-Locked EPUB (${_lastTranslatedEpubBytes!.length} bytes)');
        }
      } catch (e) {
        _logger.warning(
            'Translation', 'Could not rebuild layout-locked EPUB: $e');
      }
    }

    final StringBuffer finalContent = StringBuffer();
    for (final chunk in progress.translatedChunks) {
      if (chunk != null) {
        final cleanedChunk = EpubPipelineService.stripBlockAnchors(chunk);
        if (cleanedChunk.isNotEmpty) {
          finalContent.write(cleanedChunk);
          finalContent.write("\n\n");
        }
      }
    }

    // Export workspace under <projectPath>/workspaces/<bookSlug>
    if (_deepMode && dictionaryDir.isNotEmpty) {
      try {
        final projectDir = path.dirname(dictionaryDir);
        _lastWorkspacePath = await _dTranscreateService.exportWorkspaceArtifacts(
          projectPath: projectDir,
          sourcePath: filePath,
          targetLanguage: targetLanguage,
          sourceLanguage: sourceLanguage,
          genre: progress.genre,
          styleGuide: styleGuide,
          glossaryCsv: progress.glossary,
          rawChunks: progress.rawChunks,
          translatedChunks: progress.translatedChunks,
          minedTerms: minedTerms,
          qaReport: _lastQaReport,
        );
      } catch (e) {
        _logger.warning(
            'Translation', 'Workspace export skipped due to error: $e');
      }
    }

    // Cleanup progress file
    final File progressFile = File(progressPath);
    if (await progressFile.exists()) {
      await progressFile.delete();
    }

    await _addToHistory(
      dictionaryDir: dictionaryDir,
      fileName: fileName,
      status: 'completed',
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      genre: progress.genre,
      qaScore: _lastQaReport?.score,
      workspacePath: _lastWorkspacePath,
    );

    _logger.info('Translation',
        'Translation saved! Final length: ${finalContent.length} chars');
    onUpdate(AppStrings.get(appLanguage, 'status_completed'), 1.0);
    return finalContent.toString().trim();
  }

  Future<void> _addToHistory({
    required String dictionaryDir,
    required String fileName,
    required String status,
    String? sourceLanguage,
    String? targetLanguage,
    String? genre,
    int? qaScore,
    String? workspacePath,
  }) async {
    final historyPath = path.join(dictionaryDir, 'history_log.json');
    final historyFile = File(historyPath);

    List<Map<String, dynamic>> history = [];

    if (await historyFile.exists()) {
      try {
        final content = await historyFile.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          history = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (e) {
        debugPrint('Error reading history: $e');
        _logger.warning('TranslationController', 'Error reading history',
            details: e.toString());
      }
    }

    history.add({
      'fileName': fileName,
      'date': DateTime.now().toIso8601String(),
      'status': status,
      if (sourceLanguage != null) 'sourceLanguage': sourceLanguage,
      if (targetLanguage != null) 'targetLanguage': targetLanguage,
      if (genre != null) 'genre': genre,
      if (qaScore != null) 'qaScore': qaScore,
      if (workspacePath != null) 'workspacePath': workspacePath,
    });

    try {
      await historyFile.writeAsString(jsonEncode(history));
    } catch (e) {
      debugPrint('Error saving history: $e');
      _logger.error('TranslationController', 'Error saving history',
          details: e.toString());
    }
  }

  Future<String> _smartMergeGlossary({
    required String aiGeneratedCsv,
    required File existingFile,
  }) async {
    List<List<dynamic>> aiRows = [];
    try {
      aiRows = const CsvToListConverter().convert(
        aiGeneratedCsv,
        eol: '\n',
        shouldParseNumbers: false,
      );
    } catch (e) {
      _logger.warning(
          'TranslationController', 'Error parsing AI glossary CSV',
          details: e.toString());
    }

    final Map<String, List<String>> aiMap = {};
    for (final row in aiRows) {
      if (row.length >= 2) {
        final original = row[0].toString().trim();
        final translated = row[1].toString().trim();
        final definition = row.length > 2 ? row[2].toString().trim() : "";
        if (original.isNotEmpty) {
          aiMap[original] = [translated, definition];
        }
      }
    }

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
        _logger.warning(
            'TranslationController', 'Error parsing existing glossary CSV',
            details: e.toString());
      }

      final Map<String, List<String>> userMap = {};
      for (final row in existingRows) {
        if (row.length >= 2) {
          final original = row[0].toString().trim();
          final translated = row[1].toString().trim();
          final definition = row.length > 2 ? row[2].toString().trim() : "";
          if (original.isNotEmpty) {
            userMap[original] = [translated, definition];
          }
        }
      }

      final Map<String, List<String>> mergedMap = {...aiMap};
      mergedMap.addAll(userMap);

      final List<List<String>> csvData = mergedMap.entries.map((e) {
        return [e.key, e.value[0], e.value[1]];
      }).toList();

      return const ListToCsvConverter().convert(csvData, eol: '\n');
    } else {
      final List<List<String>> csvData = aiMap.entries.map((e) {
        return [e.key, e.value[0], e.value[1]];
      }).toList();

      return const ListToCsvConverter().convert(csvData, eol: '\n');
    }
  }

  /// Applies a user-provided glossary file verbatim into [glossaryFile] (Issue #6).
  @visibleForTesting
  Future<bool> applyUserGlossary({
    required String? userGlossaryPath,
    required File glossaryFile,
  }) async {
    if (userGlossaryPath == null || userGlossaryPath.trim().isEmpty) {
      return false;
    }

    final userFile = File(userGlossaryPath);
    if (!await userFile.exists()) {
      _logger.warning('Translation',
          'User glossary file not found, falling back to AI generation: $userGlossaryPath');
      return false;
    }

    try {
      final userContent = await userFile.readAsString();
      if (userContent.trim().isEmpty) {
        _logger.warning('Translation',
            'User glossary file is empty, falling back to AI generation: $userGlossaryPath');
        return false;
      }

      final lineCount =
          userContent.split('\n').where((l) => l.trim().isNotEmpty).length;

      await glossaryFile.writeAsString(userContent, flush: true);
      _logger.info('Translation',
          'Applied user glossary ($lineCount lines) from: $userGlossaryPath → ${glossaryFile.path}');
      return true;
    } catch (e) {
      _logger.error(
          'Translation', 'Failed to read user glossary: $userGlossaryPath',
          details: e.toString());
      return false;
    }
  }

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

        while (row.length < 3) {
          row.add("");
          isModified = true;
        }

        final String original = row[0].toString().trim();
        final String definition = row[2].toString().trim();

        if (definition.isEmpty && original.isNotEmpty) {
          onUpdate(
              "Đang tra cứu: $original...", 0.35 + (0.05 * (i / totalRows)));

          final langCode = _getLangCode(targetLanguage);
          final String? result =
              await _webSearchService.lookupTerm(original, langCode);
          if (result != null) {
            row[2] = result;
            isModified = true;
          }

          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      final String newCsv = const ListToCsvConverter().convert(rows, eol: '\n');

      if (isModified) {
        await glossaryFile.writeAsString(newCsv);
      }

      return newCsv;
    } catch (e) {
      _logger.warning('TranslationController', 'Error enriching glossary',
          details: e.toString());
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
      case 'Tiếng Nhật':
        return 'ja';
      case 'Tiếng Hàn':
        return 'ko';
      case 'Tiếng Pháp':
        return 'fr';
      case 'Tiếng Đức':
        return 'de';
      case 'Tiếng Tây Ban Nha':
        return 'es';
      default:
        return 'en';
    }
  }
}

/// Extracts text from file in isolate (supports TXT, MD, EPUB, and PDF).
Future<String> _extractTextInIsolate(String filePath) async {
  return FileParser.extractText(filePath);
}

/// Splits text into chunks in isolate.
List<String> _smartSplitInIsolate(Map<String, dynamic> args) {
  final content = args['content'] as String;
  final targetSize = args['targetSize'] as int? ?? 1000;
  return TextProcessor.smartSplit(content, targetSize: targetSize);
}
