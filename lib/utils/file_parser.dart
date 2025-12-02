import 'dart:io';
import 'package:epubx/epubx.dart';
import 'package:html/parser.dart' as html_parser;

/// Utility class for parsing different file formats
class FileParser {
  /// Extracts plain text content from an EPUB file
  /// Throws Exception if file is corrupted, DRM protected, or unreadable
  static Future<String> extractTextFromEpub(String filePath) async {
    final File file = File(filePath);
    
    if (!await file.exists()) {
      throw Exception('File EPUB không tồn tại: $filePath');
    }

    try {
      final bytes = await file.readAsBytes();
      final EpubBook epubBook = await EpubReader.readBook(bytes);
      
      final StringBuffer textContent = StringBuffer();
      
      // Get content from chapters
      final chapters = epubBook.Chapters;
      if (chapters != null && chapters.isNotEmpty) {
        for (final chapter in chapters) {
          _extractChapterText(chapter, textContent);
        }
      }
      
      // If no chapters found, try to extract from content files directly
      if (textContent.isEmpty) {
        final content = epubBook.Content;
        if (content?.Html != null) {
          for (final htmlFile in content!.Html!.values) {
            final htmlContent = htmlFile.Content;
            if (htmlContent != null) {
              final plainText = _stripHtmlTags(htmlContent);
              if (plainText.isNotEmpty) {
                textContent.writeln(plainText);
                textContent.writeln();
              }
            }
          }
        }
      }
      
      final result = textContent.toString().trim();
      
      if (result.isEmpty) {
        throw Exception('Không thể trích xuất nội dung từ file EPUB. File có thể bị DRM hoặc không có nội dung text.');
      }
      
      return result;
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Lỗi đọc file EPUB: $e. File có thể bị hỏng hoặc được bảo vệ DRM.');
    }
  }
  
  /// Recursively extracts text from a chapter and its sub-chapters
  static void _extractChapterText(EpubChapter chapter, StringBuffer buffer) {
    // Add chapter title if available
    final title = chapter.Title;
    if (title != null && title.isNotEmpty) {
      buffer.writeln('\n--- $title ---\n');
    }
    
    // Extract text from chapter content
    final htmlContent = chapter.HtmlContent;
    if (htmlContent != null && htmlContent.isNotEmpty) {
      final plainText = _stripHtmlTags(htmlContent);
      if (plainText.isNotEmpty) {
        buffer.writeln(plainText);
        buffer.writeln();
      }
    }
    
    // Process sub-chapters recursively
    final subChapters = chapter.SubChapters;
    if (subChapters != null) {
      for (final subChapter in subChapters) {
        _extractChapterText(subChapter, buffer);
      }
    }
  }
  
  /// Strips HTML tags and returns plain text
  static String _stripHtmlTags(String htmlString) {
    if (htmlString.isEmpty) return '';
    try {
      var document = html_parser.parse(htmlString);
      return document.body?.text.trim() ?? '';
    } catch (e) {
      // Fallback: simple regex-based tag removal
      return htmlString.replaceAll(RegExp(r'<[^>]*>'), '');
    }
  }
  
  /// Determines file type and extracts text content accordingly
  /// Returns plain text content from either TXT or EPUB files
  static Future<String> extractText(String filePath) async {
    final extension = filePath.toLowerCase();
    
    if (extension.endsWith('.epub')) {
      return extractTextFromEpub(filePath);
    } else if (extension.endsWith('.txt')) {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File không tồn tại: $filePath');
      }
      return file.readAsString();
    } else {
      throw Exception('Định dạng file không được hỗ trợ. Chỉ chấp nhận .TXT và .EPUB');
    }
  }
}
