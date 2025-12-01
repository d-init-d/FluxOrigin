import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/translation_progress.dart';
import '../services/ai_service.dart';
import '../utils/text_processor.dart';

class TranslationController {
  final AIService _aiService = AIService();

  /// Processes the file with resume capability.
  /// [onUpdate] callback returns status message and progress (0.0 to 1.0).
  Future<void> processFile({
    required String filePath,
    required String outputDir,
    required String dictionaryDir,
    required Function(String status, double progress) onUpdate,
  }) async {
    final String progressPath = "$filePath.flux_progress.json";
    TranslationProgress? progress =
        await TranslationProgress.loadFromFile(progressPath);

    // --- 1. INITIALIZATION OR RESUME ---
    if (progress != null) {
      onUpdate("Đã tìm thấy bản lưu cũ. Đang khôi phục tiến độ...", 0.0);
      await Future.delayed(Duration(seconds: 1)); // UX delay
    } else {
      onUpdate("Đang đọc file gốc...", 0.0);
      final File file = File(filePath);
      if (!await file.exists())
        throw Exception("File không tồn tại: $filePath");

      final String content = await file.readAsString();
      final String fileName = path.basenameWithoutExtension(filePath);

      onUpdate("Đang phân tích và chia nhỏ văn bản...", 0.1);
      final List<String> chunks = TextProcessor.smartSplit(content);
      final String sample = TextProcessor.createSample(content);

      onUpdate("AI đang đọc thử để xác định thể loại...", 0.2);
      final String systemPrompt = await _aiService.detectGenre(sample);

      onUpdate("AI đang tạo từ điển tên riêng...", 0.3);
      final String glossary = await _aiService.generateGlossary(sample);

      // Save glossary to dictionaryDir
      try {
        final glossaryFile =
            File(path.join(dictionaryDir, "${fileName}_glossary.txt"));
        await glossaryFile.writeAsString(glossary);
      } catch (e) {
        print("Error saving glossary: $e");
        // Non-critical error, continue
      }

      // Create output path in outputDir
      final String ext = path.extension(filePath);
      final String outputPath =
          path.join(outputDir, "${fileName}_translated$ext");

      progress = TranslationProgress(
        sourcePath: filePath,
        outputPath: outputPath,
        glossary: glossary,
        systemPrompt: systemPrompt,
        rawChunks: chunks,
        translatedChunks: List<String?>.filled(chunks.length, null),
        currentIndex: 0,
        lastUpdated: DateTime.now(),
      );

      await progress.saveToFile(progressPath);
    }

    // --- 2. TRANSLATION LOOP ---
    final int total = progress.rawChunks.length;

    for (int i = progress.currentIndex; i < total; i++) {
      final double percent = (i / total);
      onUpdate("Đang dịch đoạn ${i + 1}/$total...", percent);

      try {
        final String chunk = progress.rawChunks[i];
        final String translated = await _aiService.translateChunk(
            chunk, progress.systemPrompt, progress.glossary);

        progress.translatedChunks[i] = translated;
        progress.currentIndex = i + 1;

        // CRITICAL: Save after every chunk
        await progress.saveToFile(progressPath);
      } catch (e) {
        onUpdate("Lỗi khi dịch đoạn ${i + 1}: $e. Đang thử lại...", percent);
        // Simple retry logic: decrement i to retry this chunk next loop
        // Or just throw to stop and let user resume later.
        // For now, let's throw so the loop stops and user can resume.
        throw Exception("Lỗi dịch thuật tại đoạn ${i + 1}: $e");
      }
    }

    // --- 3. FINALIZE ---
    onUpdate("Đang ghép file kết quả...", 1.0);
    final StringBuffer finalContent = StringBuffer();
    for (final chunk in progress.translatedChunks) {
      if (chunk != null) {
        finalContent.write(chunk);
        finalContent.write("\n\n");
      }
    }

    final File outFile = File(progress.outputPath);
    await outFile.writeAsString(finalContent.toString());

    // Cleanup progress file
    final File progressFile = File(progressPath);
    if (await progressFile.exists()) {
      await progressFile.delete();
    }

    onUpdate("Hoàn tất! File đã lưu tại: ${progress.outputPath}", 1.0);
  }
}
