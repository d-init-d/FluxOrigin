import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;
import '../services/epub_pipeline_service.dart';

/// Utility class for parsing desktop book & document formats (.txt, .md, .epub, .pdf).
class FileParser {
  static const Set<String> supportedExtensions = {
    '.txt',
    '.md',
    '.markdown',
    '.epub',
    '.pdf',
  };

  /// Extracts plain text content from an EPUB file using the pure-Dart
  /// D-Transcreate EPUB scanner with a raw XHTML ZIP fallback for non-OPF archives.
  /// Throws Exception if file is corrupted, DRM protected, or unreadable.
  static Future<String> extractTextFromEpub(String filePath) async {
    final File file = File(filePath);

    if (!await file.exists()) {
      throw Exception('File EPUB không tồn tại: $filePath');
    }

    try {
      try {
        final scan = await EpubPipelineService().scanEpub(filePath);
        if (scan.fullPlainText.trim().isNotEmpty) {
          return scan.fullPlainText.trim();
        }
      } catch (_) {
        // Fallback below for non-standard/OPF-less EPUB archives
      }

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final buffer = StringBuffer();

      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final lower = entry.name.toLowerCase();
        if (lower.endsWith('.xhtml') ||
            lower.endsWith('.html') ||
            lower.endsWith('.htm')) {
          final htmlContent =
              utf8.decode(entry.content as List<int>, allowMalformed: true);
          final plainText = _stripHtmlTags(htmlContent);
          if (plainText.isNotEmpty) {
            buffer.writeln(plainText);
            buffer.writeln();
          }
        }
      }

      final result = buffer.toString().trim();
      if (result.isEmpty) {
        throw Exception(
            'Không thể trích xuất nội dung từ file EPUB. File có thể bị DRM hoặc không có nội dung text.');
      }

      return result;
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception(
          'Lỗi đọc file EPUB: $e. File có thể bị hỏng hoặc được bảo vệ DRM.');
    }
  }

  /// Extracts readable text from a PDF file using pure-Dart stream decompression
  /// (/FlateDecode via zlib) and BT..ET text operator parsing.
  static Future<String> extractTextFromPdf(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File PDF không tồn tại: $filePath');
    }
    final bytes = await file.readAsBytes();
    final extracted = extractTextFromPdfBytes(bytes);
    if (extracted.trim().isEmpty) {
      throw Exception(
          'Không thể trích xuất text từ file PDF (PDF có thể là bản scan ảnh hoặc bị mã hóa).');
    }
    return extracted;
  }

  /// Pure-Dart PDF content-stream parser suitable for isolate execution and unit tests.
  static String extractTextFromPdfBytes(List<int> bytes) {
    final latin = latin1.decode(bytes, allowInvalid: true);
    final streamRegex = RegExp(
      r'<<(.*?)>>\s*stream\r?\n(.*?)\r?\nendstream',
      dotAll: true,
    );

    final pagesText = <String>[];

    for (final m in streamRegex.allMatches(latin)) {
      final dict = m.group(1) ?? '';
      final rawStreamStr = m.group(2) ?? '';
      final rawStreamBytes = latin1.encode(rawStreamStr);

      List<int> decodedBytes = rawStreamBytes;
      if (dict.contains('/FlateDecode')) {
        try {
          decodedBytes = zlib.decode(rawStreamBytes);
        } catch (_) {
          // Some PDFs include trailing/leading bytes inside stream bounds
          continue;
        }
      }

      final streamText = latin1.decode(decodedBytes, allowInvalid: true);
      if (!streamText.contains('BT') || !streamText.contains('ET')) {
        continue;
      }

      final extracted = _parsePdfTextBlocks(streamText);
      if (extracted.trim().isNotEmpty) {
        pagesText.add(extracted.trim());
      }
    }

    if (pagesText.isEmpty) {
      // Fallback for uncompressed top-level BT..ET operators
      final direct = _parsePdfTextBlocks(latin);
      if (direct.trim().isNotEmpty) {
        pagesText.add(direct.trim());
      }
    }

    if (pagesText.isEmpty) return '';

    final cleanedPages = _stripRepeatedPdfPageEdges(pagesText);
    return cleanedPages.join('\n\n').trim();
  }

  static String _parsePdfTextBlocks(String streamContent) {
    final btRegex = RegExp(r'\bBT\b(.*?)\bET\b', dotAll: true);
    final lineBuf = StringBuffer();

    for (final bt in btRegex.allMatches(streamContent)) {
      final block = bt.group(1) ?? '';
      final lines = block.split(RegExp(r'\r?\n'));
      for (final line in lines) {
        final tjMatch = RegExp(r'\((?:\\.|[^\\()])*\)\s*(?:Tj|\x27|")').allMatches(line);
        final arrayMatch = RegExp(r'\[(.*?)\]\s*TJ').allMatches(line);

        var lineWritten = false;
        for (final tm in tjMatch) {
          final inner = _extractParenthesizedLiteral(tm.group(0)!);
          if (inner.isNotEmpty) {
            lineBuf.write(_unescapePdfString(inner));
            lineWritten = true;
          }
        }

        for (final am in arrayMatch) {
          final innerArray = am.group(1) ?? '';
          final strParts = RegExp(r'\((?:\\.|[^\\()])*\)|<[0-9A-Fa-f]+>')
              .allMatches(innerArray);
          for (final sp in strParts) {
            final token = sp.group(0)!;
            if (token.startsWith('(')) {
              lineBuf.write(_unescapePdfString(token.substring(1, token.length - 1)));
              lineWritten = true;
            } else if (token.startsWith('<')) {
              lineBuf.write(_decodePdfHexString(token.substring(1, token.length - 1)));
              lineWritten = true;
            }
          }
        }

        // Handle plain hex Tj: <...> Tj
        final hexMatch = RegExp(r'<([0-9A-Fa-f]+)>\s*Tj').allMatches(line);
        for (final hm in hexMatch) {
          lineBuf.write(_decodePdfHexString(hm.group(1)!));
          lineWritten = true;
        }

        if (lineWritten || line.contains('T*') || line.contains('Td') || line.contains('TD')) {
          if (!lineBuf.toString().endsWith('\n')) {
            lineBuf.writeln();
          }
        }
      }
      lineBuf.writeln();
    }

    return lineBuf
        .toString()
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String _extractParenthesizedLiteral(String raw) {
    final start = raw.indexOf('(');
    final end = raw.lastIndexOf(')');
    if (start == -1 || end <= start) return '';
    return raw.substring(start + 1, end);
  }

  static String _unescapePdfString(String s) {
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (s[i] == '\\' && i + 1 < s.length) {
        final next = s[i + 1];
        switch (next) {
          case 'n':
            buf.write('\n');
            i++;
            break;
          case 'r':
            buf.write('\r');
            i++;
            break;
          case 't':
            buf.write('\t');
            i++;
            break;
          case '(':
          case ')':
          case '\\':
            buf.write(next);
            i++;
            break;
          default:
            if (RegExp(r'[0-7]').hasMatch(next)) {
              final endOct = (i + 4 <= s.length) ? i + 4 : s.length;
              final octCandidate = s.substring(i + 1, endOct);
              final octMatch = RegExp(r'^[0-7]{1,3}').firstMatch(octCandidate);
              if (octMatch != null) {
                final code = int.parse(octMatch.group(0)!, radix: 8);
                buf.writeCharCode(code);
                i += octMatch.group(0)!.length;
                break;
              }
            }
            buf.write(next);
            i++;
        }
      } else {
        buf.write(s[i]);
      }
    }
    return buf.toString();
  }

  static String _decodePdfHexString(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s+'), '');
    if (clean.length < 2) return '';
    final padded = clean.length.isOdd ? '${clean}0' : clean;
    final bytes = <int>[];
    for (var i = 0; i < padded.length; i += 2) {
      bytes.add(int.tryParse(padded.substring(i, i + 2), radix: 16) ?? 32);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final units = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        units.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    return latin1.decode(bytes, allowInvalid: true);
  }

  static List<String> _stripRepeatedPdfPageEdges(List<String> pages) {
    if (pages.length < 3) return pages;

    final edgeCounts = <String, int>{};
    String normalizeEdge(String line) =>
        line.trim().replaceAll(RegExp(r'\b\d+\b'), '#').replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

    for (final p in pages) {
      final lines = p.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) continue;
      final edges = {normalizeEdge(lines.first), normalizeEdge(lines.last)};
      for (final e in edges) {
        if (e.length <= 90) {
          edgeCounts[e] = (edgeCounts[e] ?? 0) + 1;
        }
      }
    }

    final threshold = (pages.length / 2).ceil();
    final cleaned = <String>[];
    for (final p in pages) {
      final lines = p.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.isNotEmpty && (edgeCounts[normalizeEdge(lines.first)] ?? 0) >= threshold) {
        lines.removeAt(0);
      }
      if (lines.isNotEmpty &&
          (RegExp(r'^\s*\d+\s*$').hasMatch(lines.last) ||
              (edgeCounts[normalizeEdge(lines.last)] ?? 0) >= threshold)) {
        lines.removeLast();
      }
      if (lines.isNotEmpty) {
        cleaned.add(lines.join('\n'));
      }
    }
    return cleaned.isNotEmpty ? cleaned : pages;
  }

  /// Strips HTML tags and returns plain text.
  static String _stripHtmlTags(String htmlString) {
    if (htmlString.isEmpty) return '';
    try {
      final document = html_parser.parse(htmlString);
      return document.body?.text.trim() ?? '';
    } catch (e) {
      return htmlString.replaceAll(RegExp(r'<[^>]*>'), '');
    }
  }

  /// Determines file type and extracts text content accordingly.
  /// Supports `.txt`, `.md`, `.markdown`, `.epub`, and `.pdf`.
  static Future<String> extractText(String filePath) async {
    final lower = filePath.toLowerCase();

    if (lower.endsWith('.epub')) {
      return extractTextFromEpub(filePath);
    } else if (lower.endsWith('.pdf')) {
      return extractTextFromPdf(filePath);
    } else if (lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.markdown')) {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File không tồn tại: $filePath');
      }
      return file.readAsString();
    } else {
      throw Exception(
          'Định dạng file không được hỗ trợ. Chấp nhận .TXT, .MD, .EPUB và .PDF');
    }
  }
}
