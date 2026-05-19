/// Bug Condition Exploration Test for Bug #3: Inconsistent Logging
///
/// **Validates: Requirements 1.6, 1.7, 2.6, 2.7**
///
/// This test performs a static scan of source files to detect:
///   1. `print(` callsites in non-UI code (lib/services/, lib/controllers/, lib/models/)
///      — these should use DevLogger instead
///   2. `debugPrint(` callsites in UI screens (lib/ui/screens/) inside catch blocks
///      that lack a sibling `DevLogger.` call — these need a DevLogger companion
///
/// Bug Condition (from design isBugCondition):
///   input is LogCallsite AND fileIsInScope(input.filePath, ['lib/services/', 'lib/controllers/', 'lib/models/'])
///     AND callsiteUses(input, 'print') AND NOT input.hasDevLoggerCall
///   OR
///   input is LogCallsite AND fileIsInScope(input.filePath, ['lib/ui/screens/'])
///     AND callsiteUses(input, 'debugPrint') AND NOT input.hasDevLoggerCall
///
/// On UNFIXED code, this test MUST FAIL reporting at least:
///   - print( hits: translation_progress.dart:63, web_search_service.dart:19,29,
///     translation_controller.dart:407,434,532
///   - debugPrint without DevLogger hits in UI screens
///
/// CRITICAL: This test is EXPECTED TO FAIL on unfixed code.
/// DO NOT attempt to fix the test or the code when it fails.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Represents a logging callsite found during static scan
class LogCallsite {
  final String filePath;
  final int lineNumber;
  final String callType; // 'print' or 'debugPrint'
  final String lineContent;

  LogCallsite({
    required this.filePath,
    required this.lineNumber,
    required this.callType,
    required this.lineContent,
  });

  @override
  String toString() => '$filePath:$lineNumber [$callType] ${lineContent.trim()}';
}

/// Find the project root by looking for pubspec.yaml
String findProjectRoot() {
  // Start from the test file location and walk up
  Directory current = Directory.current;

  // Try common locations relative to where tests run
  final candidates = [
    current.path,
    '${current.path}/../../..',
    Directory('${current.path}').parent.parent.parent.path,
  ];

  for (final candidate in candidates) {
    if (File('$candidate/pubspec.yaml').existsSync()) {
      return candidate;
    }
  }

  // Fallback: walk up from current directory
  Directory dir = current;
  while (dir.path != dir.parent.path) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }

  fail('Could not find project root (no pubspec.yaml found)');
}

/// Scan files in the given scopes for bare `print(` calls (forbidden in non-UI code)
List<LogCallsite> scanForPrintCallsites(String projectRoot, List<String> scopes) {
  final results = <LogCallsite>[];
  final printRegex = RegExp(r'\bprint\(');

  for (final scope in scopes) {
    final scopeDir = Directory('$projectRoot/$scope');
    if (!scopeDir.existsSync()) continue;

    for (final entity in scopeDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final relativePath = entity.path
          .replaceAll('\\', '/')
          .replaceFirst('$projectRoot/'.replaceAll('\\', '/'), '');
      final lines = entity.readAsLinesSync();

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Skip comments
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('*') || trimmed.startsWith('///')) {
          continue;
        }
        if (printRegex.hasMatch(line)) {
          // Make sure it's not debugPrint or a method like printSomething
          // The regex \bprint\( ensures word boundary before 'print'
          // But we need to exclude 'debugPrint(' and 'Sprint(' etc.
          // Check that the character before 'print' (if any) is not alphanumeric
          final match = printRegex.firstMatch(line);
          if (match != null) {
            final matchStart = match.start;
            // Verify it's truly a bare print( and not debugPrint( or similar
            if (matchStart > 0) {
              final charBefore = line[matchStart - 1];
              if (RegExp(r'[a-zA-Z_]').hasMatch(charBefore)) {
                continue; // Part of another identifier like debugPrint
              }
            }
            results.add(LogCallsite(
              filePath: relativePath,
              lineNumber: i + 1,
              callType: 'print',
              lineContent: line,
            ));
          }
        }
      }
    }
  }

  return results;
}

/// Scan UI screen files for `debugPrint(` inside catch blocks without a sibling DevLogger call
List<LogCallsite> scanForDebugPrintWithoutDevLogger(String projectRoot, List<String> scopes) {
  final results = <LogCallsite>[];
  final debugPrintRegex = RegExp(r'\bdebugPrint\(');
  final devLoggerRegex = RegExp(r'DevLogger|_logger\.');

  for (final scope in scopes) {
    final scopeDir = Directory('$projectRoot/$scope');
    if (!scopeDir.existsSync()) continue;

    for (final entity in scopeDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final relativePath = entity.path
          .replaceAll('\\', '/')
          .replaceFirst('$projectRoot/'.replaceAll('\\', '/'), '');
      final lines = entity.readAsLinesSync();

      // Track catch block regions
      // Simple heuristic: find debugPrint calls and check if there's a DevLogger
      // call within the same catch block (within ~10 lines before/after)
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('*') || trimmed.startsWith('///')) {
          continue;
        }

        if (debugPrintRegex.hasMatch(line)) {
          // Check if this debugPrint is inside or near a catch block
          // Look backwards for 'catch' within 10 lines
          bool isInCatchContext = false;
          for (int j = i; j >= (i - 10).clamp(0, lines.length); j--) {
            if (lines[j].contains('catch')) {
              isInCatchContext = true;
              break;
            }
          }

          if (!isInCatchContext) continue;

          // Check if there's a DevLogger call nearby (within the same catch block)
          // Look within ±5 lines for a DevLogger call
          bool hasDevLoggerSibling = false;
          final searchStart = (i - 5).clamp(0, lines.length - 1);
          final searchEnd = (i + 5).clamp(0, lines.length - 1);
          for (int j = searchStart; j <= searchEnd; j++) {
            if (j == i) continue; // Skip the debugPrint line itself
            if (devLoggerRegex.hasMatch(lines[j])) {
              hasDevLoggerSibling = true;
              break;
            }
          }

          if (!hasDevLoggerSibling) {
            results.add(LogCallsite(
              filePath: relativePath,
              lineNumber: i + 1,
              callType: 'debugPrint',
              lineContent: line,
            ));
          }
        }
      }
    }
  }

  return results;
}

void main() {
  final projectRoot = findProjectRoot();

  group('Bug #3 Exploration: Inconsistent Logging Callsite Scan', () {
    test(
      'Property 1.3: No bare print() calls in services/controllers/models',
      () {
        // Scan non-UI code for forbidden print() calls
        final printCallsites = scanForPrintCallsites(
          projectRoot,
          ['lib/services', 'lib/controllers', 'lib/models'],
        );

        // Document what was found
        if (printCallsites.isNotEmpty) {
          // ignore: avoid_print
          print('\n=== PRINT CALLSITES FOUND (Bug #3 confirmed) ===');
          for (final callsite in printCallsites) {
            // ignore: avoid_print
            print('  $callsite');
          }
          // ignore: avoid_print
          print('=== Total: ${printCallsites.length} forbidden print() calls ===\n');
        }

        // Assert: no print() calls should exist in non-UI code
        // On UNFIXED code, this WILL FAIL — proving the bug exists
        expect(
          printCallsites,
          isEmpty,
          reason: 'Found ${printCallsites.length} bare print() calls in non-UI code. '
              'These should use DevLogger instead. '
              'Callsites: ${printCallsites.map((c) => '${c.filePath}:${c.lineNumber}').join(', ')}',
        );
      },
    );

    test(
      'Property 1.3: No debugPrint() without DevLogger companion in UI screens',
      () {
        // Scan UI screens for debugPrint in catch blocks without DevLogger sibling
        final debugPrintCallsites = scanForDebugPrintWithoutDevLogger(
          projectRoot,
          ['lib/ui/screens'],
        );

        // Document what was found
        if (debugPrintCallsites.isNotEmpty) {
          // ignore: avoid_print
          print('\n=== DEBUGPRINT WITHOUT DEVLOGGER FOUND (Bug #3 confirmed) ===');
          for (final callsite in debugPrintCallsites) {
            // ignore: avoid_print
            print('  $callsite');
          }
          // ignore: avoid_print
          print('=== Total: ${debugPrintCallsites.length} unaccompanied debugPrint() calls ===\n');
        }

        // Assert: every debugPrint in a catch block should have a DevLogger sibling
        // On UNFIXED code, this WILL FAIL — proving the bug exists
        expect(
          debugPrintCallsites,
          isEmpty,
          reason: 'Found ${debugPrintCallsites.length} debugPrint() calls in UI screens '
              'without a sibling DevLogger call. '
              'Callsites: ${debugPrintCallsites.map((c) => '${c.filePath}:${c.lineNumber}').join(', ')}',
        );
      },
    );
  });
}
