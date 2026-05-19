/// Bug Condition Exploration Test for Bug #1: Glossary Quadratic Duplication
///
/// **Validates: Requirements 1.1, 1.2, 1.3, 2.1, 2.2, 2.3**
///
/// This test encodes the EXPECTED (correct) behavior:
///   outputRowCount(parseGlossaryResponse(input)) == distinctParseableLines(input).length
///
/// On UNFIXED code, this test MUST FAIL with outputRowCount == N² for N >= 2,
/// proving the nested-loop bug exists.
///
/// Bug Condition (from design isBugCondition):
///   input is AIResponse AND
///   parseableLines(input.response).distinctByOriginal.length >= 2 AND
///   outputRowCount(generateGlossary(input)) > parseableLines(input.response).distinctByOriginal.length
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_origin/services/ai_service.dart';

/// Helper: count non-empty lines in a parsed glossary output
int outputRowCount(String glossaryOutput) {
  if (glossaryOutput.trim().isEmpty) return 0;
  return glossaryOutput
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .length;
}

void main() {
  final aiService = AIService();

  group('Bug #1 Exploration: Glossary Quadratic Duplication', () {
    // =========================================================================
    // CONCRETE CASE: 3 distinct lines → expect 3 rows, bug produces 9 (3×3)
    // =========================================================================
    test(
        'Property 1.1: Concrete case — 3 distinct lines should produce exactly 3 rows',
        () {
      // Build a fake AI response with 3 distinct glossary lines
      const fakeAiResponse = '"叶尘","Diệp Trần"\n'
          '"长老","Trưởng lão"\n'
          '"宗","Tông"';

      final result = aiService.parseGlossaryResponse(fakeAiResponse);
      final rowCount = outputRowCount(result);

      // Expected behavior: exactly 3 rows (one per distinct input line)
      // Bug condition: outputRowCount > distinctParseableLines → proves quadratic emission
      expect(
        rowCount,
        equals(3),
        reason:
            'Expected 3 rows for 3 distinct input lines, got $rowCount — '
            'if $rowCount == 9, confirms quadratic emission (3 × 3)',
      );
    });

    // =========================================================================
    // RANDOMIZED PROPERTY: for N in [2, 3, 5, 10, 20], assert outputRowCount == N
    // =========================================================================
    test(
        'Property 1.1: Randomized — for N distinct lines, outputRowCount must equal N',
        () {
      final random = Random(42); // Fixed seed for determinism

      for (final n in [2, 3, 5, 10, 20]) {
        // Generate N distinct "original_i","viet_i" lines
        final lines = List.generate(n, (i) {
          final original = 'term_${i}_${random.nextInt(1000)}';
          final vietnamese = 'nghĩa_${i}_${random.nextInt(1000)}';
          return '"$original","$vietnamese"';
        });

        final input = lines.join('\n');
        final result = aiService.parseGlossaryResponse(input);
        final rowCount = outputRowCount(result);
        final rawLineCount = lines.length;

        // Property: outputRowCount == N
        expect(
          rowCount,
          equals(n),
          reason:
              'For N=$n distinct lines: expected $n rows, got $rowCount — '
              'quadratic bug would produce ${n * n}',
        );

        // Property: outputRowCount <= rawLineCount (no inflation)
        expect(
          rowCount,
          lessThanOrEqualTo(rawLineCount),
          reason:
              'Output row count ($rowCount) must not exceed raw line count ($rawLineCount)',
        );
      }
    });

    // =========================================================================
    // HEADER-COLLISION CASE: headers filtered exactly once, no duplicated content
    // On unfixed code, this may throw ConcurrentModificationError due to
    // removeWhere on the list being iterated (Bug #1.2), OR produce duplicates.
    // Either failure mode confirms the bug.
    // =========================================================================
    test(
        'Property 1.1: Header-collision — headers filtered once, no duplicated content',
        () {
      // Input with header lines AND valid glossary lines
      const fakeAiResponse = 'original,vietnamese\n'
          'term,meaning\n'
          'từ gốc,nghĩa\n'
          '----\n'
          '"叶尘","Diệp Trần"\n'
          '"长老","Trưởng lão"\n'
          '"宗","Tông"';

      // On unfixed code, this may throw ConcurrentModificationError
      // (which also proves the bug — removeWhere on iterated list)
      late String result;
      try {
        result = aiService.parseGlossaryResponse(fakeAiResponse);
      } catch (e) {
        // ConcurrentModificationError confirms Bug #1.2
        // (removeWhere on the same list being iterated by for-in)
        fail(
          'parseGlossaryResponse threw $e — '
          'confirms concurrent modification bug (removeWhere on iterated list)',
        );
      }

      final rowCount = outputRowCount(result);

      // No header lines should appear in output
      final resultLower = result.toLowerCase();
      expect(resultLower.contains('"original"'), isFalse,
          reason: 'Header "original" should be filtered out');
      expect(resultLower.contains('"term"'), isFalse,
          reason: 'Header "term" should be filtered out');
      expect(resultLower.contains('"từ gốc"'), isFalse,
          reason: 'Header "từ gốc" should be filtered out');
      expect(result.contains('----'), isFalse,
          reason: 'Separator "----" should be filtered out');

      // Exactly 3 valid rows (the non-header lines)
      expect(
        rowCount,
        equals(3),
        reason:
            'Expected 3 rows after header filtering, got $rowCount — '
            'headers should be filtered exactly once',
      );
    });

    // =========================================================================
    // BUG CONDITION ASSERTION: explicit check that output does NOT exceed input
    // =========================================================================
    test(
        'Property 1.1: Bug condition — outputRowCount must not exceed distinctParseableLines',
        () {
      // This is the formal bug condition check from the design:
      // outputRowCount(generateGlossary(input)) > parseableLines(input).distinctByOriginal.length
      // If this assertion FAILS, the bug condition is confirmed.

      const fakeAiResponse = '"叶尘","Diệp Trần"\n'
          '"长老","Trưởng lão"\n'
          '"宗","Tông"';

      final result = aiService.parseGlossaryResponse(fakeAiResponse);
      final rowCount = outputRowCount(result);
      const distinctInputLines = 3;

      // The bug condition: outputRowCount > distinctParseableLines
      // We assert the EXPECTED behavior (no duplication)
      expect(
        rowCount <= distinctInputLines,
        isTrue,
        reason:
            'Bug condition detected: outputRowCount ($rowCount) > '
            'distinctParseableLines ($distinctInputLines). '
            'Expected $distinctInputLines rows, got $rowCount — '
            'confirms quadratic emission',
      );
    });
  });
}
