/// Preservation Property Test for existing DevLogger callsites and ring buffer
///
/// **Validates: Requirements 3.6, 3.7**
///
/// Property 2.3: Preservation — Existing DevLogger entries (category, level,
/// message, details) are unchanged AND the 1000-entry ring buffer behavior
/// is preserved.
///
/// Observation-first methodology: on UNFIXED code, scanned the codebase for
/// every existing `DevLogger().*(...)`  / `_logger.*(...)`  callsite. Recorded
/// (file, category, level) for each. This manifest is encoded below.
///
/// Test 1: Source-level manifest — assert each callsite still exists in source.
/// Test 2: Behavioral preservation — drive DevLogger directly and verify
///          category/level match the manifest for reachable paths.
/// Test 3: Ring buffer — push 1500 entries, assert length == 1000 (oldest 500
///          evicted). Assert setEnabled(false) suppresses new entries.
///
/// This test MUST PASS on UNFIXED code (captures baseline to preserve).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_origin/services/dev_logger.dart';

/// Represents a known DevLogger callsite in the codebase.
class CallsiteEntry {
  final String file;
  final String category;
  final String level; // info, warning, error, debug, request, response
  final String messageFragment; // A substring of the message to match in source

  const CallsiteEntry({
    required this.file,
    required this.category,
    required this.level,
    required this.messageFragment,
  });

  @override
  String toString() =>
      'CallsiteEntry(file: $file, category: $category, level: $level, msg: $messageFragment)';
}

/// The manifest of all existing DevLogger callsites observed on UNFIXED code.
/// Each entry records the file path (relative to lib/), category, level, and
/// a unique message fragment that identifies the callsite in source.
const List<CallsiteEntry> _manifest = [
  // === lib/services/ai_service.dart ===
  CallsiteEntry(
    file: 'lib/services/ai_service.dart',
    category: 'AIService',
    level: 'info',
    messageFragment: 'Base URL set to:',
  ),
  CallsiteEntry(
    file: 'lib/services/ai_service.dart',
    category: 'AIService',
    level: 'info',
    messageFragment: 'Provider type set to:',
  ),
  CallsiteEntry(
    file: 'lib/services/ai_service.dart',
    category: 'AIService',
    level: 'error',
    messageFragment: 'chatCompletion failed: Model name is required',
  ),
  CallsiteEntry(
    file: 'lib/services/ai_service.dart',
    category: 'AIService',
    level: 'request',
    messageFragment: 'POST',
  ),
  CallsiteEntry(
    file: 'lib/services/ai_service.dart',
    category: 'AIService',
    level: 'response',
    messageFragment: 'OK 200',
  ),
  CallsiteEntry(
    file: 'lib/services/ai_service.dart',
    category: 'AIService',
    level: 'error',
    messageFragment: 'API Error',
  ),
  CallsiteEntry(
    file: 'lib/services/ai_service.dart',
    category: 'AIService',
    level: 'error',
    messageFragment: 'chatCompletion failed',
  ),
  CallsiteEntry(
    file: 'lib/services/ai_service.dart',
    category: 'AIService',
    level: 'warning',
    messageFragment: 'Model management not supported for LM Studio. Please load models',
  ),
  CallsiteEntry(
    file: 'lib/services/ai_service.dart',
    category: 'AIService',
    level: 'warning',
    messageFragment: 'Model management not supported for LM Studio. Please manage models',
  ),

  // === lib/controllers/translation_controller.dart ===
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'info',
    messageFragment: 'Starting translation process',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'info',
    messageFragment: 'Resuming from saved progress',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'warning',
    messageFragment: 'File delete attempt',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'warning',
    messageFragment: 'Could not delete progress file after 3 attempts',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'debug',
    messageFragment: 'Reading source file',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'info',
    messageFragment: 'File loaded:',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'info',
    messageFragment: 'Text split into',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'info',
    messageFragment: 'Detected genre:',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'debug',
    messageFragment: 'System prompt set',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'info',
    messageFragment: 'Glossary generated:',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'debug',
    messageFragment: 'Glossary saved to:',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'warning',
    messageFragment: 'Error saving glossary:',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'error',
    messageFragment: 'Initialization failed during glossary generation',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'info',
    messageFragment: 'Starting translation loop:',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'info',
    messageFragment: 'Translation paused at chunk',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'debug',
    messageFragment: 'Translating chunk',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'debug',
    messageFragment: 'translated',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'error',
    messageFragment: 'Error translating chunk',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'info',
    messageFragment: 'Translation complete! Finalizing',
  ),
  CallsiteEntry(
    file: 'lib/controllers/translation_controller.dart',
    category: 'Translation',
    level: 'info',
    messageFragment: 'Translation saved! Final length:',
  ),
];

void main() {
  group('Property 2.3: Preservation — DevLogger callsites and ring buffer', () {
    // =========================================================================
    // TEST 1: Source-level manifest — assert each callsite still exists
    // Guards Requirement 3.6 against accidental removal/rename.
    // =========================================================================
    test('Test 1: All manifest callsites exist in source files', () {
      // Find the project root by looking for pubspec.yaml
      Directory projectRoot = Directory.current;
      while (!File('${projectRoot.path}/pubspec.yaml').existsSync()) {
        final parent = projectRoot.parent;
        if (parent.path == projectRoot.path) {
          fail('Could not find project root (pubspec.yaml not found)');
        }
        projectRoot = parent;
      }

      final missingCallsites = <String>[];

      for (final entry in _manifest) {
        final filePath = '${projectRoot.path}/${entry.file}';
        final file = File(filePath);

        if (!file.existsSync()) {
          missingCallsites.add(
              'FILE NOT FOUND: ${entry.file} (expected callsite: ${entry.messageFragment})');
          continue;
        }

        final content = file.readAsStringSync();

        // Verify the callsite still exists by checking:
        // 1. The message fragment is present in the file
        // 2. The category string is present in the file
        // 3. The level method is present in the file
        final hasMessage = content.contains(entry.messageFragment);
        final hasCategory = content.contains("'${entry.category}'");
        final hasLevel = content.contains('.${entry.level}(');

        if (!hasMessage) {
          missingCallsites.add(
              'MESSAGE MISSING in ${entry.file}: "${entry.messageFragment}"');
        }
        if (!hasCategory) {
          missingCallsites.add(
              'CATEGORY MISSING in ${entry.file}: "${entry.category}"');
        }
        if (!hasLevel) {
          missingCallsites.add(
              'LEVEL MISSING in ${entry.file}: .${entry.level}(');
        }
      }

      expect(missingCallsites, isEmpty,
          reason:
              'All existing DevLogger callsites must be preserved (Requirement 3.6).\n'
              'Missing:\n${missingCallsites.join('\n')}');
    });

    // =========================================================================
    // TEST 2: Behavioral preservation — drive DevLogger directly and verify
    // category/level match for reachable paths.
    // For unreachable branches (network failures, etc.), Test 1's source-level
    // assertion is sufficient.
    // =========================================================================
    test('Test 2: DevLogger emits correct category and level for each method',
        () {
      final logger = DevLogger();

      // Clear any existing logs
      logger.clear();
      expect(logger.logs, isEmpty);

      // Drive each level method and verify the emitted entry
      logger.info('AIService', 'Base URL set to: http://localhost:11434');
      expect(logger.logs.first.category, equals('AIService'));
      expect(logger.logs.first.level, equals(LogLevel.info));
      expect(logger.logs.first.message,
          contains('Base URL set to: http://localhost:11434'));

      logger.clear();

      logger.error('AIService', 'chatCompletion failed: Model name is required');
      expect(logger.logs.first.category, equals('AIService'));
      expect(logger.logs.first.level, equals(LogLevel.error));
      expect(logger.logs.first.message,
          contains('chatCompletion failed: Model name is required'));

      logger.clear();

      logger.warning('AIService',
          'Model management not supported for LM Studio. Please load models in LM Studio app.');
      expect(logger.logs.first.category, equals('AIService'));
      expect(logger.logs.first.level, equals(LogLevel.warning));
      expect(logger.logs.first.message,
          contains('Model management not supported'));

      logger.clear();

      logger.request('AIService',
          'POST http://localhost:11434/api/chat | Model: llama3 | Messages: 2');
      expect(logger.logs.first.category, equals('AIService'));
      expect(logger.logs.first.level, equals(LogLevel.request));
      expect(logger.logs.first.message, contains('POST'));

      logger.clear();

      logger.response('AIService', 'OK 200 | 150ms | 500 chars',
          details: 'response content...');
      expect(logger.logs.first.category, equals('AIService'));
      expect(logger.logs.first.level, equals(LogLevel.response));
      expect(logger.logs.first.message, contains('OK 200'));
      expect(logger.logs.first.details, equals('response content...'));

      logger.clear();

      logger.debug('Translation', 'Reading source file...');
      expect(logger.logs.first.category, equals('Translation'));
      expect(logger.logs.first.level, equals(LogLevel.debug));
      expect(logger.logs.first.message, contains('Reading source file'));

      logger.clear();

      logger.info('Translation', 'Starting translation process',
          details: 'File: test.txt\nModel: llama3');
      expect(logger.logs.first.category, equals('Translation'));
      expect(logger.logs.first.level, equals(LogLevel.info));
      expect(logger.logs.first.message, contains('Starting translation process'));
      expect(logger.logs.first.details, contains('File: test.txt'));

      logger.clear();

      // Verify LogEntry fields are populated correctly
      logger.info('TestCategory', 'Test message', details: 'Test details');
      final entry = logger.logs.first;
      expect(entry.timestamp, isNotNull);
      expect(entry.category, equals('TestCategory'));
      expect(entry.level, equals(LogLevel.info));
      expect(entry.message, equals('Test message'));
      expect(entry.details, equals('Test details'));

      logger.clear();
    });

    // =========================================================================
    // TEST 3: Ring buffer — push 1500 entries, assert length == 1000
    // (oldest 500 evicted). Assert setEnabled(false) suppresses new entries.
    // Requirement 3.7: setEnabled(false) and _maxLogs = 1000 untouched.
    // =========================================================================
    test('Test 3: Ring buffer caps at 1000 entries and setEnabled(false) suppresses',
        () {
      final logger = DevLogger();

      // Ensure logger is enabled
      logger.setEnabled(true);
      logger.clear();
      expect(logger.logs.length, equals(0));

      // Push 1500 entries
      for (var i = 0; i < 1500; i++) {
        logger.info('RingBufferTest', 'Entry $i');
      }

      // Assert ring buffer caps at 1000
      expect(logger.logs.length, equals(1000),
          reason:
              'Ring buffer must cap at 1000 entries (_maxLogs = 1000, Requirement 3.7)');

      // The newest entry should be the last one pushed (index 0 since newest first)
      expect(logger.logs.first.message, equals('Entry 1499'),
          reason: 'Newest entry should be at index 0 (newest-first order)');

      // The oldest entry in the buffer should be entry 500 (entries 0-499 evicted)
      expect(logger.logs.last.message, equals('Entry 500'),
          reason:
              'Oldest 500 entries should be evicted, oldest remaining is Entry 500');

      // Now test setEnabled(false) suppresses entries
      final countBefore = logger.logs.length;
      logger.setEnabled(false);

      // Try to add more entries while disabled
      logger.info('RingBufferTest', 'Should not appear 1');
      logger.warning('RingBufferTest', 'Should not appear 2');
      logger.error('RingBufferTest', 'Should not appear 3');
      logger.debug('RingBufferTest', 'Should not appear 4');
      logger.request('RingBufferTest', 'Should not appear 5');
      logger.response('RingBufferTest', 'Should not appear 6');

      // Buffer should not have grown
      expect(logger.logs.length, equals(countBefore),
          reason:
              'setEnabled(false) must suppress all entries — buffer must not grow (Requirement 3.7)');

      // Verify none of the suppressed messages appear
      expect(
          logger.logs
              .any((e) => e.message.contains('Should not appear')),
          isFalse,
          reason: 'No suppressed entries should be in the buffer');

      // Re-enable and verify logging works again
      logger.setEnabled(true);
      logger.info('RingBufferTest', 'After re-enable');
      expect(logger.logs.first.message, equals('After re-enable'),
          reason: 'After re-enabling, logging should work normally');

      // Clean up
      logger.clear();
      logger.setEnabled(true);
    });

    // =========================================================================
    // TEST 3b: Ring buffer eviction order — verify FIFO eviction
    // =========================================================================
    test('Test 3b: Ring buffer evicts oldest entries first (FIFO)', () {
      final logger = DevLogger();
      logger.setEnabled(true);
      logger.clear();

      // Push exactly 1000 entries
      for (var i = 0; i < 1000; i++) {
        logger.info('FIFOTest', 'Entry $i');
      }
      expect(logger.logs.length, equals(1000));

      // Push one more — should evict the oldest (Entry 0)
      logger.info('FIFOTest', 'Entry 1000');
      expect(logger.logs.length, equals(1000),
          reason: 'Buffer must stay at 1000 after overflow');
      expect(logger.logs.first.message, equals('Entry 1000'),
          reason: 'Newest entry at front');
      expect(logger.logs.last.message, equals('Entry 1'),
          reason: 'Entry 0 should be evicted, oldest remaining is Entry 1');

      // Clean up
      logger.clear();
    });

    // =========================================================================
    // TEST 3c: setEnabled getter reflects state
    // =========================================================================
    test('Test 3c: isEnabled getter reflects setEnabled state', () {
      final logger = DevLogger();

      logger.setEnabled(true);
      expect(logger.isEnabled, isTrue);

      logger.setEnabled(false);
      expect(logger.isEnabled, isFalse);

      // Restore
      logger.setEnabled(true);
    });
  });
}
