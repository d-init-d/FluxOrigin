import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as path;
import 'translation_controller.dart';
import '../services/ai_service.dart';
import '../services/dev_logger.dart';

/// Status of a single file within a batch run.
enum BatchFileStatus {
  pending,
  running,
  done,
  failed,
  skipped,
}

/// Result of a single file within a batch run.
class BatchFileResult {
  final String filePath;
  final String fileName;
  BatchFileStatus status;
  String? errorMessage;
  String? outputPath;
  int? qaScore;

  BatchFileResult({
    required this.filePath,
    required this.fileName,
    this.status = BatchFileStatus.pending,
    this.errorMessage,
    this.outputPath,
    this.qaScore,
  });
}

/// Aggregated progress info for a batch run.
class BatchProgress {
  final int total;
  final int completed;
  final int failed;
  final int skipped;
  final String? currentFile;

  const BatchProgress({
    required this.total,
    required this.completed,
    required this.failed,
    required this.skipped,
    this.currentFile,
  });

  /// 0.0..1.0 — overall progress (counts done + failed + skipped as finished).
  double get fraction {
    if (total <= 0) return 0.0;
    return (completed + failed + skipped) / total;
  }
}

/// Final aggregated result of a batch run.
class BatchResult {
  final List<BatchFileResult> files;
  final int succeeded;
  final int failed;
  final int skipped;

  const BatchResult({
    required this.files,
    required this.succeeded,
    required this.failed,
    required this.skipped,
  });

  int get total => files.length;
}

/// Translates every matching file in a folder sequentially.
///
/// Reuses [TranslationController.processFile] for each file so D-Transcreate
/// mining, Anchor-Locked EPUB rebuilds, BYOK multi-key rotation, QA gates,
/// pause/resume, and issue #6 user-glossary handling apply across batches.
class BatchTranslationController {
  final TranslationController _translationController = TranslationController();
  final DevLogger _logger = DevLogger();

  bool _isPaused = false;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  void setAIUrl(String url) => _translationController.setAIUrl(url);
  void setAIProviderType(AIProviderType type) =>
      _translationController.setAIProviderType(type);
  void setAIApiKey(String rawKeys) =>
      _translationController.setAIApiKey(rawKeys);
  void setTemperature(double temperature) =>
      _translationController.setTemperature(temperature);
  void setChunkSize(int chunkSize) =>
      _translationController.setChunkSize(chunkSize);
  void setDeepMode(bool enabled) =>
      _translationController.setDeepMode(enabled);

  void requestPause() {
    _isPaused = true;
    _translationController.requestPause();
  }

  void resetPause() {
    _isPaused = false;
    _translationController.resetPause();
  }

  static Future<List<String>> scanFolder(
    String folderPath, {
    bool recursive = false,
    List<String> extensions = const ['.txt'],
  }) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      return const [];
    }

    final results = <String>[];
    final lowerExts = extensions.map((e) => e.toLowerCase()).toList();

    Future<void> walk(Directory d) async {
      await for (final entity in d.list(followLinks: false)) {
        final name = path.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (entity is Directory) {
          if (recursive) {
            await walk(entity);
          }
        } else if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (lowerExts.contains(ext)) {
            results.add(entity.path);
          }
        }
      }
    }

    await walk(dir);
    results.sort();
    return results;
  }

  Future<BatchResult> translateFolder({
    required String folderPath,
    required String dictionaryDir,
    required String modelName,
    required String sourceLanguage,
    required String targetLanguage,
    required bool allowInternet,
    String? userGlossaryPath,
    bool recursive = false,
    bool skipExisting = false,
    List<String> extensions = const ['.txt'],
    required Function(BatchProgress progress) onUpdate,
    String appLanguage = 'vi',
    bool preserveOriginalFormat = false,
    String? genreOverride,
  }) async {
    if (_isRunning) {
      throw StateError(
          'BatchTranslationController is already running. Wait for the current batch to finish or pause it.');
    }
    _isRunning = true;
    _isPaused = false;
    _translationController.resetPause();

    _logger.info('Batch', 'Starting batch translation', details: '''
Folder: $folderPath
Recursive: $recursive
Skip existing: $skipExisting
Extensions: $extensions
Shared glossary: ${userGlossaryPath ?? "<none>"}
Preserve format: $preserveOriginalFormat
''');

    try {
      final files = await scanFolder(folderPath,
          recursive: recursive, extensions: extensions);
      final results = files
          .map((f) => BatchFileResult(
                filePath: f,
                fileName: path.basename(f),
              ))
          .toList();

      _logger.info('Batch', 'Found ${results.length} file(s) to translate');

      if (results.isEmpty) {
        onUpdate(const BatchProgress(
          total: 0,
          completed: 0,
          failed: 0,
          skipped: 0,
        ));
        return const BatchResult(
            files: [], succeeded: 0, failed: 0, skipped: 0);
      }

      int completed = 0;
      int failed = 0;
      int skipped = 0;

      for (int i = 0; i < results.length; i++) {
        if (_isPaused) {
          _logger.info('Batch',
              'Paused at file ${i + 1}/${results.length} (${results[i].fileName})');
          for (int j = i; j < results.length; j++) {
            results[j].status = BatchFileStatus.pending;
          }
          break;
        }

        final result = results[i];
        result.status = BatchFileStatus.running;
        onUpdate(BatchProgress(
          total: results.length,
          completed: completed,
          failed: failed,
          skipped: skipped,
          currentFile: result.fileName,
        ));

        final outputPath = _deriveOutputPath(
          result.filePath,
          preserveOriginalFormat: preserveOriginalFormat,
        );
        final outputFile = File(outputPath);
        if (skipExisting && await outputFile.exists()) {
          result.status = BatchFileStatus.skipped;
          result.outputPath = outputPath;
          skipped++;
          _logger.info('Batch', 'Skipped (output exists): ${result.fileName}');
          continue;
        }

        try {
          final translated = await _translationController.processFile(
            filePath: result.filePath,
            dictionaryDir: dictionaryDir,
            modelName: modelName,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            allowInternet: allowInternet,
            userGlossaryPath: userGlossaryPath,
            appLanguage: appLanguage,
            genreOverride: genreOverride,
            preserveEpubLayout: preserveOriginalFormat,
            onUpdate: (_, __) {},
            onChunkUpdate: (_, __, ___, ____) {},
          );

          if (translated == null) {
            result.status = BatchFileStatus.pending;
            result.errorMessage = 'paused';
            _isPaused = true;
            break;
          }

          final epubBytes = _translationController.lastTranslatedEpubBytes;
          if (preserveOriginalFormat &&
              result.filePath.toLowerCase().endsWith('.epub') &&
              epubBytes != null &&
              epubBytes.isNotEmpty) {
            await outputFile.writeAsBytes(epubBytes, flush: true);
          } else {
            await outputFile.writeAsString(translated, flush: true);
          }

          result.status = BatchFileStatus.done;
          result.outputPath = outputPath;
          result.qaScore = _translationController.lastQaReport?.score;
          completed++;
          _logger.info('Batch',
              'Done: ${result.fileName} → $outputPath (${translated.length} chars, QA=${result.qaScore ?? "n/a"})');
        } catch (e) {
          result.status = BatchFileStatus.failed;
          result.errorMessage = e.toString();
          failed++;
          _logger.error('Batch', 'Failed: ${result.fileName}',
              details: e.toString());
        }
      }

      final finalProgress = BatchProgress(
        total: results.length,
        completed: completed,
        failed: failed,
        skipped: skipped,
      );
      onUpdate(finalProgress);

      _logger.info('Batch',
          'Batch finished: $completed succeeded, $failed failed, $skipped skipped');

      return BatchResult(
        files: results,
        succeeded: completed,
        failed: failed,
        skipped: skipped,
      );
    } finally {
      _isRunning = false;
    }
  }

  /// Default output path next to the source: `<originalName>_translated.txt`,
  /// or preserves `.epub`/`.md` extension when [preserveOriginalFormat] is true.
  static String _deriveOutputPath(
    String sourcePath, {
    bool preserveOriginalFormat = false,
  }) {
    final dir = path.dirname(sourcePath);
    final name = path.basenameWithoutExtension(sourcePath);
    if (preserveOriginalFormat) {
      final lower = sourcePath.toLowerCase();
      if (lower.endsWith('.epub')) {
        return path.join(dir, '${name}_translated.epub');
      }
      if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
        return path.join(dir, '${name}_translated.md');
      }
    }
    return path.join(dir, '${name}_translated.txt');
  }

  @visibleForTesting
  static String debugDeriveOutputPath(String sourcePath) =>
      _deriveOutputPath(sourcePath);
}
