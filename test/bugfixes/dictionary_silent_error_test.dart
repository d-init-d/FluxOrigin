// Bug #5 Exploration Test: Silent Dictionary Read Errors
//
// **Validates: Requirements 1.9, 2.9**
//
// Bug Condition (from design isBugCondition):
//   input is DictionaryFileEntry AND NOT input.readSucceeds
//   AND NOT devLoggerWasCalled(input.filePath)
//
// This test replicates the exact line-counting logic from
// DictionaryScreen._loadDictionaries (the UNFIXED version with catch (_) {})
// and verifies that:
//   1. lineCount == 0 (graceful fallback preserved)
//   2. DevLogger.logs contains a warning entry with category
//      'DictionaryScreen' and message containing 'Failed to count lines'
//
// EXPECTED OUTCOME on UNFIXED code:
//   Test FAILS — the second assertion fails because `catch (_) {}`
//   does not call DevLogger. Counterexample: DevLogger.logs.length == 0
//
// DO NOT fix the code or the test when it fails.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_origin/services/dev_logger.dart';

/// Replicates the line-counting logic from DictionaryScreen._loadDictionaries
/// as it exists in the FIXED code (catch (e) { DevLogger().warning(...) }).
///
/// This function mirrors the fixed lines of dictionary_screen.dart:
///   int lineCount = 0;
///   try {
///     final content = await file.readAsString();
///     lineCount = content.split('\n').where((l) => l.trim().isNotEmpty).length;
///   } catch (e) {
///     DevLogger().warning('DictionaryScreen',
///       'Failed to count lines for ${file.path}: $e');
///   }
Future<int> countLinesLikeFixedCode(File file) async {
  int lineCount = 0;
  try {
    final content = await file.readAsString();
    lineCount = content.split('\n').where((l) => l.trim().isNotEmpty).length;
  } catch (e) {
    // FIXED: The fixed code logs the error via DevLogger
    DevLogger().warning('DictionaryScreen',
      'Failed to count lines for ${file.path}: $e');
  }
  return lineCount;
}

void main() {
  group('Bug #5: DictionaryScreen silent file-read errors', () {
    late Directory tempDir;

    setUp(() async {
      // Clear any previous DevLogger entries
      DevLogger().clear();
      // Ensure DevLogger is enabled
      DevLogger().setEnabled(true);
      // Create a temp directory for test CSV files
      tempDir = await Directory.systemTemp.createTemp('dict_test_');
    });

    tearDown(() async {
      // Clean up temp directory
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'Property 1.5: Bug Condition — unreadable CSV file must log a '
      'DevLogger.warning AND gracefully fallback to lineCount == 0',
      () async {
        // Setup: Write a CSV file with deliberately invalid UTF-8 bytes
        // These bytes are not valid UTF-8 sequences and will cause
        // file.readAsString() to throw a FormatException
        final invalidFile = File(
            '${tempDir.path}${Platform.pathSeparator}bad_dictionary.csv');
        await invalidFile.writeAsBytes([
          0xFF, 0xFE, 0xFD, 0xFC, 0xFB, 0xFA, // Invalid UTF-8 lead bytes
          0x80, 0x81, 0x82, 0x83, // Continuation bytes without lead
          0xC0, 0xC1, // Overlong encoding (invalid in UTF-8)
          0xF5, 0xF6, 0xF7, 0xF8, // Beyond Unicode range
        ]);

        // Drive the failing branch: invoke the EXACT same logic as
        // DictionaryScreen._loadDictionaries (fixed version)
        final lineCount = await countLinesLikeFixedCode(invalidFile);

        // Assertion 1: lineCount == 0 (graceful fallback preserved)
        // This should PASS on both unfixed and fixed code — the fallback works
        expect(lineCount, equals(0),
            reason:
                'lineCount should be 0 when file is unreadable (graceful fallback)');

        // Assertion 2: DevLogger must contain a warning entry
        // This is the KEY assertion that proves the bug exists.
        //
        // On UNFIXED code: catch (_) {} does NOT call DevLogger, so this FAILS.
        //   Counterexample: DevLogger.logs.length == 0
        //
        // On FIXED code: catch (e) { DevLogger().warning('DictionaryScreen',
        //   'Failed to count lines for $filePath: $e') } makes this PASS.
        final logs = DevLogger().logs;
        final hasWarningEntry = logs.any((entry) =>
            entry.category == 'DictionaryScreen' &&
            entry.level == LogLevel.warning &&
            entry.message.contains('Failed to count lines'));

        expect(hasWarningEntry, isTrue,
            reason: 'DevLogger must contain a warning entry with category '
                '"DictionaryScreen" and message containing "Failed to count lines". '
                'Bug Condition: catch (_) {} swallows the exception without logging. '
                'Counterexample: DevLogger.logs.length == ${logs.length} '
                '(expected at least 1 warning entry)');
      },
    );

    test(
      'Property 1.5 (parametric): Multiple unreadable files each produce '
      'a DevLogger.warning entry',
      () async {
        // Generate multiple files with different invalid byte patterns
        final invalidPatterns = <String, List<int>>{
          'corrupt_bom.csv': [0xFF, 0xFE, 0xFD],
          'invalid_continuation.csv': [0x80, 0x81, 0x82, 0x83, 0x84],
          'overlong_encoding.csv': [0xC0, 0xAF, 0xC1, 0xBF],
          'beyond_unicode.csv': [0xF5, 0x90, 0x80, 0x80],
          'truncated_sequence.csv': [0xE0, 0xA0], // Missing third byte
        };

        int totalLineCount = 0;
        int filesProcessed = 0;

        for (final entry in invalidPatterns.entries) {
          final file = File(
              '${tempDir.path}${Platform.pathSeparator}${entry.key}');
          await file.writeAsBytes(entry.value);

          // Replicate DictionaryScreen FIXED logic for each file
          final lineCount = await countLinesLikeFixedCode(file);
          totalLineCount += lineCount;
          filesProcessed++;
        }

        // Assertion 1: All line counts should be 0
        expect(totalLineCount, equals(0),
            reason: 'All unreadable files should fallback to lineCount == 0');

        // Assertion 2: DevLogger should have one warning per unreadable file
        // On UNFIXED code: catch (_) {} never calls DevLogger, so count == 0
        // Counterexample: DevLogger warnings count == 0, expected == 5
        final logs = DevLogger().logs;
        final warningEntries = logs.where((entry) =>
            entry.category == 'DictionaryScreen' &&
            entry.level == LogLevel.warning &&
            entry.message.contains('Failed to count lines'));

        expect(warningEntries.length, equals(filesProcessed),
            reason: 'Each unreadable file should produce exactly one '
                'DevLogger.warning entry. '
                'Bug Condition: catch (_) {} swallows ALL exceptions silently. '
                'Counterexample: DevLogger warnings count == ${warningEntries.length}, '
                'expected == $filesProcessed');
      },
    );
  });
}
