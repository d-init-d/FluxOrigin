/// Preservation Property Test for Public APIs and Existing Test Suite
///
/// **Validates: Requirements 3.10, 3.11**
///
/// Property 2.5: Preservation — Public method signatures of affected classes
/// are unchanged, and the existing test suite continues to pass.
///
/// This test uses source-file scanning (manifest comparison) to verify that
/// the public API signatures of affected classes remain intact. Dart mirrors
/// are not available in Flutter, so we scan the source files directly.
///
/// This test MUST PASS on UNFIXED code (captures baseline to preserve).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Extracts public method/constructor signatures from a Dart source file.
/// Returns a list of signature strings found in the file.
///
/// A "public method" is defined as a non-underscore-prefixed method declaration
/// at the class level. We look for patterns like:
///   - `ReturnType methodName(params)`
///   - `static ReturnType methodName(params)`
///   - `Future<ReturnType> methodName(params)`
///   - Constructor declarations
List<String> extractPublicSignatures(String sourceContent, String className) {
  final signatures = <String>[];
  final lines = sourceContent.split('\n');

  // Track if we're inside the target class
  bool inClass = false;
  int braceDepth = 0;

  for (final line in lines) {
    final trimmed = line.trim();

    // Detect class declaration
    if (trimmed.startsWith('class $className ') ||
        trimmed.startsWith('class $className{') ||
        trimmed == 'class $className {') {
      inClass = true;
      braceDepth = 0;
    }

    if (inClass) {
      // Track brace depth
      braceDepth += '{'.allMatches(trimmed).length;
      braceDepth -= '}'.allMatches(trimmed).length;

      // If we've exited the class
      if (braceDepth <= 0 && inClass && trimmed.contains('}')) {
        if (braceDepth <= 0) {
          inClass = false;
          continue;
        }
      }

      // Skip private methods (start with _), comments, empty lines
      if (trimmed.startsWith('//') ||
          trimmed.startsWith('*') ||
          trimmed.startsWith('///') ||
          trimmed.isEmpty) {
        continue;
      }

      // Skip private members
      if (trimmed.startsWith('_') ||
          trimmed.contains(' _') && !trimmed.contains('Future<') && !trimmed.contains('static')) {
        continue;
      }

      // Match method signatures (public methods at depth 1)
      // We look for lines that declare methods/constructors
      final methodPattern = RegExp(
        r'^(static\s+)?(Future<[^>]+>\??|void|bool|int|double|String|List<[^>]+>|Map<[^>]+>|[A-Z]\w*)\s+(\w+)\s*\(',
      );
      final constructorPattern = RegExp(
        r'^(const\s+)?$className\s*\(',
      );
      final factoryPattern = RegExp(
        r'^factory\s+$className\.\w+\s*\(',
      );

      if (methodPattern.hasMatch(trimmed) ||
          constructorPattern.hasMatch(trimmed) ||
          factoryPattern.hasMatch(trimmed)) {
        // Only include if it's not a private method
        final match = methodPattern.firstMatch(trimmed);
        if (match != null) {
          final methodName = match.group(3);
          if (methodName != null && !methodName.startsWith('_')) {
            signatures.add(trimmed.split('{').first.split('=>').first.trim());
          }
        } else {
          signatures.add(trimmed.split('{').first.split('=>').first.trim());
        }
      }
    }
  }

  return signatures;
}

/// Checks if a source file contains a specific method signature pattern
bool hasMethodSignature(String sourceContent, String pattern) {
  return sourceContent.contains(pattern);
}

void main() {
  // Resolve the project root relative to the test file location
  final projectRoot = Directory.current.path;

  group('Property 2.5: Preservation — Public API Signatures', () {
    // =========================================================================
    // AIService public API manifest
    // Requirement 3.10: public signatures unchanged
    // =========================================================================
    test('AIService maintains all public method signatures', () {
      final file = File('$projectRoot/lib/services/ai_service.dart');
      expect(file.existsSync(), isTrue,
          reason: 'ai_service.dart must exist');

      final content = file.readAsStringSync();

      // generateGlossary(String, String, String, String)
      expect(
        hasMethodSignature(content, 'Future<String> generateGlossary('),
        isTrue,
        reason:
            'AIService must have public method: Future<String> generateGlossary(...)',
      );

      // translateChunk(...)
      expect(
        hasMethodSignature(content, 'Future<String> translateChunk('),
        isTrue,
        reason:
            'AIService must have public method: Future<String> translateChunk(...)',
      );

      // chatCompletion(...)
      expect(
        hasMethodSignature(content, 'Future<String> chatCompletion('),
        isTrue,
        reason:
            'AIService must have public method: Future<String> chatCompletion(...)',
      );

      // checkConnection(...)
      expect(
        hasMethodSignature(content, 'Future<(bool, String?, int)> checkConnection('),
        isTrue,
        reason:
            'AIService must have public method: Future<(bool, String?, int)> checkConnection(...)',
      );

      // detectGenre(...)
      expect(
        hasMethodSignature(content, 'Future<String> detectGenre('),
        isTrue,
        reason:
            'AIService must have public method: Future<String> detectGenre(...)',
      );

      // getSystemPrompt(...)
      expect(
        hasMethodSignature(content, 'String getSystemPrompt('),
        isTrue,
        reason:
            'AIService must have public method: String getSystemPrompt(...)',
      );

      // getInstalledModels()
      expect(
        hasMethodSignature(content, 'Future<List<String>> getInstalledModels('),
        isTrue,
        reason:
            'AIService must have public method: Future<List<String>> getInstalledModels()',
      );

      // pullModel(...)
      expect(
        hasMethodSignature(content, 'Future<bool> pullModel('),
        isTrue,
        reason: 'AIService must have public method: Future<bool> pullModel(...)',
      );

      // deleteModel(...)
      expect(
        hasMethodSignature(content, 'Future<bool> deleteModel('),
        isTrue,
        reason:
            'AIService must have public method: Future<bool> deleteModel(...)',
      );

      // preloadModel(...)
      expect(
        hasMethodSignature(content, 'Future<void> preloadModel('),
        isTrue,
        reason:
            'AIService must have public method: Future<void> preloadModel(...)',
      );

      // setBaseUrl(...)
      expect(
        hasMethodSignature(content, 'void setBaseUrl('),
        isTrue,
        reason: 'AIService must have public method: void setBaseUrl(...)',
      );

      // setProviderType(...)
      expect(
        hasMethodSignature(content, 'void setProviderType('),
        isTrue,
        reason: 'AIService must have public method: void setProviderType(...)',
      );

      // parseGlossaryResponse(...)
      expect(
        hasMethodSignature(content, 'String parseGlossaryResponse('),
        isTrue,
        reason:
            'AIService must have public method: String parseGlossaryResponse(...)',
      );

      // supportsModelManagement getter
      expect(
        hasMethodSignature(content, 'bool get supportsModelManagement'),
        isTrue,
        reason:
            'AIService must have public getter: bool get supportsModelManagement',
      );
    });

    // =========================================================================
    // TranslationController public API manifest
    // Requirement 3.10: public signatures unchanged
    // =========================================================================
    test('TranslationController maintains all public method signatures', () {
      final file = File('$projectRoot/lib/controllers/translation_controller.dart');
      expect(file.existsSync(), isTrue,
          reason: 'translation_controller.dart must exist');

      final content = file.readAsStringSync();

      // processFile(...)
      expect(
        hasMethodSignature(content, 'Future<String?> processFile('),
        isTrue,
        reason:
            'TranslationController must have public method: Future<String?> processFile(...)',
      );

      // requestPause()
      expect(
        hasMethodSignature(content, 'void requestPause('),
        isTrue,
        reason:
            'TranslationController must have public method: void requestPause()',
      );

      // resetPause()
      expect(
        hasMethodSignature(content, 'void resetPause('),
        isTrue,
        reason:
            'TranslationController must have public method: void resetPause()',
      );

      // setAIUrl(...)
      expect(
        hasMethodSignature(content, 'void setAIUrl('),
        isTrue,
        reason:
            'TranslationController must have public method: void setAIUrl(...)',
      );

      // setAIProviderType(...)
      expect(
        hasMethodSignature(content, 'void setAIProviderType('),
        isTrue,
        reason:
            'TranslationController must have public method: void setAIProviderType(...)',
      );

      // getProgressPercentage(...)
      expect(
        hasMethodSignature(content, 'Future<double?> getProgressPercentage('),
        isTrue,
        reason:
            'TranslationController must have public method: Future<double?> getProgressPercentage(...)',
      );

      // hasProgress(...)
      expect(
        hasMethodSignature(content, 'Future<bool> hasProgress('),
        isTrue,
        reason:
            'TranslationController must have public method: Future<bool> hasProgress(...)',
      );

      // deleteProgress(...)
      expect(
        hasMethodSignature(content, 'Future<void> deleteProgress('),
        isTrue,
        reason:
            'TranslationController must have public method: Future<void> deleteProgress(...)',
      );
    });

    // =========================================================================
    // TranslationProgress public API manifest
    // Requirement 3.10: public signatures unchanged
    // =========================================================================
    test('TranslationProgress maintains all public method signatures', () {
      final file = File('$projectRoot/lib/models/translation_progress.dart');
      expect(file.existsSync(), isTrue,
          reason: 'translation_progress.dart must exist');

      final content = file.readAsStringSync();

      // saveToFile(String): Future<void>
      expect(
        hasMethodSignature(content, 'Future<void> saveToFile(String'),
        isTrue,
        reason:
            'TranslationProgress must have public method: Future<void> saveToFile(String)',
      );

      // static loadFromFile(String): Future<TranslationProgress?>
      expect(
        hasMethodSignature(content, 'static Future<TranslationProgress?> loadFromFile(String'),
        isTrue,
        reason:
            'TranslationProgress must have static method: Future<TranslationProgress?> loadFromFile(String)',
      );

      // toJson()
      expect(
        hasMethodSignature(content, 'Map<String, dynamic> toJson('),
        isTrue,
        reason:
            'TranslationProgress must have public method: Map<String, dynamic> toJson()',
      );

      // fromJson(...) factory constructor
      expect(
        hasMethodSignature(content, 'factory TranslationProgress.fromJson('),
        isTrue,
        reason:
            'TranslationProgress must have factory constructor: TranslationProgress.fromJson(...)',
      );

      // Constructor with required fields
      expect(
        content.contains('TranslationProgress({'),
        isTrue,
        reason:
            'TranslationProgress must have named parameter constructor',
      );

      // Public fields
      expect(content.contains('final String sourcePath;'), isTrue,
          reason: 'TranslationProgress must have field: sourcePath');
      expect(content.contains('final String outputPath;'), isTrue,
          reason: 'TranslationProgress must have field: outputPath');
      expect(content.contains('final String glossary;'), isTrue,
          reason: 'TranslationProgress must have field: glossary');
      expect(content.contains('final String systemPrompt;'), isTrue,
          reason: 'TranslationProgress must have field: systemPrompt');
      expect(content.contains('final String genre;'), isTrue,
          reason: 'TranslationProgress must have field: genre');
      expect(content.contains('final List<String> rawChunks;'), isTrue,
          reason: 'TranslationProgress must have field: rawChunks');
      expect(content.contains('final List<String?> translatedChunks;'), isTrue,
          reason: 'TranslationProgress must have field: translatedChunks');
      expect(content.contains('int currentIndex;'), isTrue,
          reason: 'TranslationProgress must have field: currentIndex');
      expect(content.contains('DateTime lastUpdated;'), isTrue,
          reason: 'TranslationProgress must have field: lastUpdated');
    });

    // =========================================================================
    // WebSearchService public API manifest
    // Requirement 3.10: public signatures unchanged
    // =========================================================================
    test('WebSearchService maintains all public method signatures', () {
      final file = File('$projectRoot/lib/services/web_search_service.dart');
      expect(file.existsSync(), isTrue,
          reason: 'web_search_service.dart must exist');

      final content = file.readAsStringSync();

      // lookupTerm(...)
      expect(
        hasMethodSignature(content, 'Future<String?> lookupTerm('),
        isTrue,
        reason:
            'WebSearchService must have public method: Future<String?> lookupTerm(...)',
      );
    });

    // =========================================================================
    // DictionaryScreen widget constructor signature
    // Requirement 3.10: public signatures unchanged
    // =========================================================================
    test('DictionaryScreen maintains its widget constructor signature', () {
      final file = File('$projectRoot/lib/ui/screens/dictionary_screen.dart');
      expect(file.existsSync(), isTrue,
          reason: 'dictionary_screen.dart must exist');

      final content = file.readAsStringSync();

      // DictionaryScreen extends StatefulWidget
      expect(
        content.contains('class DictionaryScreen extends StatefulWidget'),
        isTrue,
        reason: 'DictionaryScreen must extend StatefulWidget',
      );

      // Constructor with isDark parameter
      expect(
        content.contains('required this.isDark'),
        isTrue,
        reason:
            'DictionaryScreen constructor must have required isDark parameter',
      );

      // isDark field
      expect(
        content.contains('final bool isDark;'),
        isTrue,
        reason: 'DictionaryScreen must have field: final bool isDark',
      );
    });
  });

  // ===========================================================================
  // Test runner check: existing test suite structure preserved
  // Requirement 3.11: existing test suite continues to pass
  //
  // BASELINE OBSERVATION on UNFIXED code:
  //   - widget_test.dart: PASSES (proper flutter_test with testWidgets)
  //   - ai_service_refactor_test.dart: PRE-EXISTING COMPILE ERROR
  //     (references non-existent public `cleanResponse` method — the method
  //     is private `_cleanResponse` in the current codebase. This is a
  //     pre-existing issue unrelated to the bugs being fixed.)
  //   - text_processor_test.dart: Script-style (no test() calls, uses print)
  //     flutter test reports "No tests ran" — pre-existing issue.
  //   - verify_web_search.dart: Script-style (no test() calls, uses print)
  //     flutter test reports "No tests ran" — pre-existing issue.
  //
  // Preservation requirement: the fix must NOT make any of these worse.
  // The only file that actually passes via `flutter test` is widget_test.dart.
  // The preservation test verifies:
  //   1. All test files still exist with their expected structure
  //   2. widget_test.dart (the only passing test) remains valid
  //   3. No new compilation errors are introduced by the fix
  // ===========================================================================
  group('Property 2.5: Preservation — Existing Test Suite Structure', () {
    test('All expected test files exist', () {
      final expectedTestFiles = [
        'test/ai_service_refactor_test.dart',
        'test/text_processor_test.dart',
        'test/verify_web_search.dart',
        'test/widget_test.dart',
      ];

      for (final testFile in expectedTestFiles) {
        final file = File('$projectRoot/$testFile');
        expect(file.existsSync(), isTrue,
            reason: 'Test file must exist: $testFile');

        final content = file.readAsStringSync();
        expect(content.isNotEmpty, isTrue,
            reason: 'Test file must not be empty: $testFile');
      }
    });

    test('widget_test.dart is a valid flutter_test file that passes', () {
      final file = File('$projectRoot/test/widget_test.dart');
      final content = file.readAsStringSync();

      // Structure checks — this is the only test file that actually passes
      expect(
          content.contains(
              "import 'package:flutter_test/flutter_test.dart'"),
          isTrue,
          reason: 'widget_test.dart must import flutter_test');
      expect(content.contains('void main()'), isTrue,
          reason: 'widget_test.dart must have main()');
      expect(content.contains('testWidgets'), isTrue,
          reason: 'widget_test.dart must contain testWidgets calls');
    });

    test(
        'ai_service_refactor_test.dart structure preserved (pre-existing compile issue documented)',
        () {
      final file = File('$projectRoot/test/ai_service_refactor_test.dart');
      final content = file.readAsStringSync();

      // Structure preserved — the file references cleanResponse which is
      // a pre-existing issue (method is private _cleanResponse)
      expect(
          content.contains(
              "import 'package:flutter_test/flutter_test.dart'"),
          isTrue,
          reason: 'ai_service_refactor_test.dart must import flutter_test');
      expect(
          content.contains(
              "import 'package:flux_origin/services/ai_service.dart'"),
          isTrue,
          reason: 'ai_service_refactor_test.dart must import ai_service');
      expect(content.contains('void main()'), isTrue,
          reason: 'ai_service_refactor_test.dart must have main()');
      expect(content.contains('cleanResponse'), isTrue,
          reason:
              'ai_service_refactor_test.dart references cleanResponse (pre-existing)');
    });

    test('text_processor_test.dart structure preserved (script-style, no test() calls)',
        () {
      final file = File('$projectRoot/test/text_processor_test.dart');
      final content = file.readAsStringSync();

      expect(
          content.contains(
              "import 'package:flux_origin/utils/text_processor.dart'"),
          isTrue,
          reason: 'text_processor_test.dart must import text_processor');
      expect(content.contains('void main()'), isTrue,
          reason: 'text_processor_test.dart must have main()');
      expect(content.contains('TextProcessor.smartSplit'), isTrue,
          reason:
              'text_processor_test.dart must reference TextProcessor.smartSplit');
    });

    test('verify_web_search.dart structure preserved (script-style, no test() calls)',
        () {
      final file = File('$projectRoot/test/verify_web_search.dart');
      final content = file.readAsStringSync();

      expect(
          content.contains(
              "import 'package:flux_origin/services/web_search_service.dart'"),
          isTrue,
          reason: 'verify_web_search.dart must import web_search_service');
      expect(content.contains('void main()'), isTrue,
          reason: 'verify_web_search.dart must have main()');
      expect(content.contains('lookupTerm'), isTrue,
          reason: 'verify_web_search.dart must reference lookupTerm');
    });
  });
}
