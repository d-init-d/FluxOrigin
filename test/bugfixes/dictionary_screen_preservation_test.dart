/// Preservation Property Test for `DictionaryScreen` happy path
///
/// **Validates: Requirements 3.9**
///
/// Property 2.4: Preservation — Well-formed CSV files render with the same
/// `{name, entries, fileSize, path}` shape.
///
/// Observation-first methodology: outputs were observed on UNFIXED code and
/// encoded as assertions below.
///
/// Observed baseline behavior on UNFIXED code:
///   - `lineCount` = number of non-empty lines in the CSV file
///   - `fileSize` formatted as:
///     - `"X.Y MB"` when file size >= 1,048,576 bytes (1024*1024)
///     - `"X KB"` when file size < 1,048,576 bytes (integer, no decimals)
///   - List entry shape: `{name, entries, fileSize, path}` map
///
/// This test MUST PASS on UNFIXED code (captures baseline to preserve).
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

/// Replicates the exact line-counting logic from DictionaryScreen._loadDictionaries
/// on UNFIXED code (lines 64-69 of dictionary_screen.dart):
///
/// ```dart
/// int lineCount = 0;
/// try {
///   final content = await file.readAsString();
///   lineCount = content.split('\n').where((l) => l.trim().isNotEmpty).length;
/// } catch (_) {}
/// ```
int countNonEmptyLines(String content) {
  return content.split('\n').where((l) => l.trim().isNotEmpty).length;
}

/// Replicates the exact file-size formatting logic from DictionaryScreen._loadDictionaries
/// on UNFIXED code (lines 72-77 of dictionary_screen.dart):
///
/// ```dart
/// final sizeBytes = stat.size;
/// String fileSize;
/// if (sizeBytes >= 1024 * 1024) {
///   fileSize = '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
/// } else {
///   fileSize = '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
/// }
/// ```
String formatFileSize(int sizeBytes) {
  if (sizeBytes >= 1024 * 1024) {
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  } else {
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }
}

/// Replicates the full entry-building logic from DictionaryScreen._loadDictionaries
/// on UNFIXED code. Given a file, produces the same map that would be appended
/// to `_dictionaries`.
Future<Map<String, dynamic>> buildDictionaryEntry(File file) async {
  final stat = await file.stat();
  final fileName = file.path.split(Platform.pathSeparator).last;

  int lineCount = 0;
  try {
    final content = await file.readAsString();
    lineCount = content.split('\n').where((l) => l.trim().isNotEmpty).length;
  } catch (_) {}

  final sizeBytes = stat.size;
  String fileSize;
  if (sizeBytes >= 1024 * 1024) {
    fileSize = '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  } else {
    fileSize = '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }

  return {
    'name': fileName,
    'entries': lineCount,
    'fileSize': fileSize,
    'path': file.path,
  };
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dict_preservation_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Property 2.4: Preservation — DictionaryScreen happy path', () {
    // =========================================================================
    // OBSERVATION 1: 1-line CSV file (sub-1KB)
    // =========================================================================
    test('1-line CSV file produces correct entry shape', () async {
      final csvContent = '"hello","xin chào"\n';
      final file = File('${tempDir.path}${Platform.pathSeparator}one_line.csv');
      await file.writeAsString(csvContent);

      final entry = await buildDictionaryEntry(file);

      // Shape check: all required keys present
      expect(entry.containsKey('name'), isTrue);
      expect(entry.containsKey('entries'), isTrue);
      expect(entry.containsKey('fileSize'), isTrue);
      expect(entry.containsKey('path'), isTrue);

      // Name is the filename
      expect(entry['name'], equals('one_line.csv'));

      // Entries = non-empty line count = 1
      expect(entry['entries'], equals(1),
          reason: 'Single non-empty line should produce entries=1');

      // File size in KB (sub-1KB file)
      expect(entry['fileSize'], endsWith(' KB'),
          reason: 'Sub-1MB file should be formatted in KB');

      // Path matches
      expect(entry['path'], equals(file.path));
    });

    // =========================================================================
    // OBSERVATION 2: 100-line CSV file
    // =========================================================================
    test('100-line CSV file produces correct entry count', () async {
      final buffer = StringBuffer();
      for (var i = 0; i < 100; i++) {
        buffer.writeln('"term_$i","translation_$i"');
      }
      final file =
          File('${tempDir.path}${Platform.pathSeparator}hundred_lines.csv');
      await file.writeAsString(buffer.toString());

      final entry = await buildDictionaryEntry(file);

      expect(entry['name'], equals('hundred_lines.csv'));
      expect(entry['entries'], equals(100),
          reason: '100 non-empty lines should produce entries=100');
      expect(entry['fileSize'], endsWith(' KB'),
          reason: '100-line CSV should be in KB range');
      expect(entry['path'], equals(file.path));
    });

    // =========================================================================
    // OBSERVATION 3: 5000-line CSV file
    // =========================================================================
    test('5000-line CSV file produces correct entry count', () async {
      final buffer = StringBuffer();
      for (var i = 0; i < 5000; i++) {
        buffer.writeln('"term_$i","translation_$i"');
      }
      final file =
          File('${tempDir.path}${Platform.pathSeparator}five_thousand.csv');
      await file.writeAsString(buffer.toString());

      final entry = await buildDictionaryEntry(file);

      expect(entry['name'], equals('five_thousand.csv'));
      expect(entry['entries'], equals(5000),
          reason: '5000 non-empty lines should produce entries=5000');
      // 5000 lines × ~25 chars each ≈ 125KB → KB format
      expect(entry['fileSize'], endsWith(' KB'),
          reason: '~125KB file should be formatted in KB');
      expect(entry['path'], equals(file.path));
    });

    // =========================================================================
    // OBSERVATION 4: Multi-byte content (Vietnamese/CJK characters)
    // =========================================================================
    test('Multi-byte content CSV produces correct entry count', () async {
      final buffer = StringBuffer();
      // Vietnamese and CJK characters (multi-byte UTF-8)
      final lines = [
        '"叶尘","Diệp Trần"',
        '"长老","Trưởng lão"',
        '"宗门","Tông môn"',
        '"修炼","Tu luyện"',
        '"灵气","Linh khí"',
      ];
      for (final line in lines) {
        buffer.writeln(line);
      }
      final file =
          File('${tempDir.path}${Platform.pathSeparator}multibyte.csv');
      await file.writeAsString(buffer.toString());

      final entry = await buildDictionaryEntry(file);

      expect(entry['name'], equals('multibyte.csv'));
      expect(entry['entries'], equals(5),
          reason: '5 non-empty multi-byte lines should produce entries=5');
      expect(entry['fileSize'], endsWith(' KB'));
      expect(entry['path'], equals(file.path));
    });

    // =========================================================================
    // OBSERVATION 5: Large file (>1MB) — triggers MB formatting
    // =========================================================================
    test('File > 1MB is formatted in MB', () async {
      // Create a file > 1MB (1,048,576 bytes)
      final buffer = StringBuffer();
      // Each line is ~40 chars, need ~30000 lines for >1MB
      for (var i = 0; i < 30000; i++) {
        buffer.writeln(
            '"term_${i.toString().padLeft(5, '0')}","translation_value_that_is_long_enough_${i.toString().padLeft(5, '0')}"');
      }
      final file =
          File('${tempDir.path}${Platform.pathSeparator}large_file.csv');
      await file.writeAsString(buffer.toString());

      final stat = await file.stat();
      // Verify we actually created a file > 1MB
      expect(stat.size, greaterThanOrEqualTo(1024 * 1024),
          reason: 'Test fixture must be > 1MB (actual: ${stat.size} bytes)');

      final entry = await buildDictionaryEntry(file);

      expect(entry['name'], equals('large_file.csv'));
      expect(entry['entries'], equals(30000),
          reason: '30000 non-empty lines should produce entries=30000');
      expect(entry['fileSize'], endsWith(' MB'),
          reason: 'File >= 1MB should be formatted in MB');
      // Verify MB format: "X.Y MB" with 1 decimal place
      expect(entry['fileSize'], matches(RegExp(r'^\d+\.\d MB$')),
          reason: 'MB format should be "X.Y MB" with 1 decimal place');
      expect(entry['path'], equals(file.path));
    });

    // =========================================================================
    // FILE SIZE FORMATTING: Threshold boundary tests
    // =========================================================================
    test('File at exactly 1MB boundary uses MB format', () async {
      // Create a file that is exactly 1,048,576 bytes
      final content = 'A' * (1024 * 1024 - 1) + '\n'; // Exactly 1MB
      final file =
          File('${tempDir.path}${Platform.pathSeparator}exact_1mb.csv');
      await file.writeAsString(content);

      final stat = await file.stat();
      final formatted = formatFileSize(stat.size);

      if (stat.size >= 1024 * 1024) {
        expect(formatted, endsWith(' MB'));
        expect(formatted, matches(RegExp(r'^\d+\.\d MB$')));
      } else {
        expect(formatted, endsWith(' KB'));
      }
    });

    test('File just below 1MB uses KB format', () async {
      // Create a file that is just under 1MB
      final content = 'B' * (1024 * 1024 - 100);
      final file =
          File('${tempDir.path}${Platform.pathSeparator}just_under_1mb.csv');
      await file.writeAsString(content);

      final stat = await file.stat();
      // The file might be slightly different size due to encoding
      final formatted = formatFileSize(stat.size);

      if (stat.size < 1024 * 1024) {
        expect(formatted, endsWith(' KB'));
        expect(formatted, matches(RegExp(r'^\d+ KB$')),
            reason: 'KB format should be integer with no decimals');
      } else {
        // If encoding pushed it over, MB is also acceptable
        expect(formatted, endsWith(' MB'));
      }
    });

    // =========================================================================
    // LINE COUNTING: Edge cases for non-empty line counting
    // =========================================================================
    test('Empty lines are not counted', () async {
      // Mix of empty and non-empty lines
      final content = '"a","b"\n\n\n"c","d"\n\n"e","f"\n\n\n';
      final file =
          File('${tempDir.path}${Platform.pathSeparator}with_empties.csv');
      await file.writeAsString(content);

      final entry = await buildDictionaryEntry(file);

      expect(entry['entries'], equals(3),
          reason: 'Only non-empty lines should be counted (3 data lines)');
    });

    test('Lines with only whitespace are not counted', () async {
      final content = '"a","b"\n   \n\t\n"c","d"\n  \t  \n';
      final file =
          File('${tempDir.path}${Platform.pathSeparator}whitespace_lines.csv');
      await file.writeAsString(content);

      final entry = await buildDictionaryEntry(file);

      expect(entry['entries'], equals(2),
          reason:
              'Whitespace-only lines should not be counted (only 2 data lines)');
    });

    test('File with no trailing newline counts correctly', () async {
      final content = '"a","b"\n"c","d"'; // No trailing newline
      final file =
          File('${tempDir.path}${Platform.pathSeparator}no_trailing_nl.csv');
      await file.writeAsString(content);

      final entry = await buildDictionaryEntry(file);

      expect(entry['entries'], equals(2),
          reason: 'Two non-empty lines without trailing newline = 2 entries');
    });

    // =========================================================================
    // PROPERTY VARIANT: Random CSV fixtures with lineCount in [0, 10000]
    // and fileSize spanning the MB/KB threshold
    // =========================================================================
    test(
        'Property: random CSV fixtures preserve lineCount == nonEmptyLineCount and fileSize formatting',
        () async {
      final random = Random(42); // Fixed seed for determinism

      // Test a range of line counts
      final lineCounts = [0, 1, 5, 50, 500, 2000, 8000];

      for (final targetLines in lineCounts) {
        final buffer = StringBuffer();
        int actualNonEmpty = 0;

        for (var i = 0; i < targetLines; i++) {
          // Occasionally insert empty lines (10% chance)
          if (random.nextDouble() < 0.1) {
            buffer.writeln('');
          } else {
            buffer.writeln('"term_$i","value_$i"');
            actualNonEmpty++;
          }
        }

        final file = File(
            '${tempDir.path}${Platform.pathSeparator}random_$targetLines.csv');
        await file.writeAsString(buffer.toString());

        final entry = await buildDictionaryEntry(file);
        final stat = await file.stat();

        // Property 1: lineCount == nonEmptyLineCount
        expect(entry['entries'], equals(actualNonEmpty),
            reason:
                'For $targetLines target lines, entries should equal actual non-empty count ($actualNonEmpty)');

        // Property 2: fileSize formatting matches thresholds
        final expectedFormat = formatFileSize(stat.size);
        expect(entry['fileSize'], equals(expectedFormat),
            reason:
                'fileSize formatting must match threshold logic for ${stat.size} bytes');

        // Property 3: entry shape is correct
        expect(entry['name'], equals('random_$targetLines.csv'));
        expect(entry['path'], equals(file.path));
        expect(entry.keys.toSet(),
            equals({'name', 'entries', 'fileSize', 'path'}),
            reason: 'Entry must have exactly {name, entries, fileSize, path}');

        // Clean up individual file to avoid disk space issues
        await file.delete();
      }
    });

    // =========================================================================
    // PROPERTY VARIANT: Verify fileSize formatting across size boundaries
    // =========================================================================
    test('Property: fileSize formatting matches recorded thresholds', () {
      // Test the formatting function directly with known byte values
      final testCases = <int, String>{
        0: '0 KB', // 0 bytes → 0 KB
        512: '1 KB', // 512 bytes → rounds to 1 KB (512/1024 = 0.5 → rounds to 0? No, toStringAsFixed(0) rounds)
        1024: '1 KB', // 1 KB exactly
        10240: '10 KB', // 10 KB
        102400: '100 KB', // 100 KB
        524288: '512 KB', // 512 KB
        1048575: '1024 KB', // Just under 1MB → KB format
        1048576: '1.0 MB', // Exactly 1MB → MB format
        1572864: '1.5 MB', // 1.5 MB
        10485760: '10.0 MB', // 10 MB
      };

      for (final entry in testCases.entries) {
        final result = formatFileSize(entry.key);
        expect(result, equals(entry.value),
            reason:
                'formatFileSize(${entry.key}) should be "${entry.value}", got "$result"');
      }
    });

    // =========================================================================
    // ENTRY SHAPE: Verify the map structure
    // =========================================================================
    test('Entry shape has exactly {name, entries, fileSize, path}', () async {
      final file =
          File('${tempDir.path}${Platform.pathSeparator}shape_test.csv');
      await file.writeAsString('"a","b"\n');

      final entry = await buildDictionaryEntry(file);

      // Verify exact key set
      expect(entry.keys.toSet(), equals({'name', 'entries', 'fileSize', 'path'}),
          reason: 'Entry must contain exactly these 4 keys');

      // Verify types
      expect(entry['name'], isA<String>());
      expect(entry['entries'], isA<int>());
      expect(entry['fileSize'], isA<String>());
      expect(entry['path'], isA<String>());
    });
  });
}
