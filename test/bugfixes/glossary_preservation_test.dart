/// Preservation Property Test for `AIService.generateGlossary` non-buggy inputs
///
/// **Validates: Requirements 3.1, 3.2**
///
/// Property 2.1: Preservation — Glossary parser preserves single-line, empty,
/// and header-only behavior.
///
/// Observation-first methodology: outputs were observed on UNFIXED code and
/// encoded as assertions below.
///
/// Observed baseline behavior on UNFIXED code:
///   - Empty input "" → returns "" (empty string)
///   - Header-only inputs → throws ConcurrentModificationError (bug manifestation)
///     After fix, should return empty. Test accepts both behaviors.
///   - Single well-formed CSV line → returns `"original","vietnamese"`
///   - Single line via : fallback → returns `"original","vietnamese"`
///   - Single line via " - " fallback → returns `"original","vietnamese"`
///   - Single line via "-" fallback → returns `"original","vietnamese"`
///   - Single line where vietnamese.length > 100 → returns "" (filtered out)
///
/// This test MUST PASS on UNFIXED code (captures baseline to preserve).
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

  group('Property 2.1: Preservation — Glossary parser non-buggy inputs', () {
    // =========================================================================
    // OBSERVATION 1: Empty input → empty output
    // Requirement 3.1: empty/header-only returns empty
    // =========================================================================
    test('Empty input returns empty string', () {
      final result = aiService.parseGlossaryResponse('');

      expect(result, isEmpty,
          reason: 'Empty input must produce empty output (Requirement 3.1)');
      expect(result.trim(), isEmpty,
          reason: 'Empty input trimmed must also be empty');
    });

    // =========================================================================
    // OBSERVATION 2: Header-only input
    // On UNFIXED code: throws ConcurrentModificationError (bug #1.2 side-effect)
    // After fix: should return empty string
    // Preservation: accept either behavior (throw or empty)
    // Requirement 3.1: empty/header-only returns empty (post-fix target)
    // =========================================================================
    test('Header-only input either throws or returns empty', () {
      // On unfixed code, header-only inputs with N>=1 lines trigger the
      // ConcurrentModificationError because removeWhere empties the list
      // while the outer for-in is iterating it.
      // After fix, this should return empty.
      // Both outcomes are acceptable for preservation.
      try {
        final result =
            aiService.parseGlossaryResponse('original,vietnamese\n----');
        // If it doesn't throw, it must return empty (all lines are headers)
        expect(result.trim(), isEmpty,
            reason:
                'Header-only input must produce empty output after filtering');
      } on ConcurrentModificationError {
        // This is the observed behavior on UNFIXED code — acceptable
        // The bug causes removeWhere to empty the list mid-iteration
      }
    });

    // =========================================================================
    // OBSERVATION 3: Single well-formed CSV line
    // Requirement 3.2: single well-formed line emits "original","vietnamese"
    // =========================================================================
    test('Single CSV line with quotes produces correct output', () {
      final result = aiService.parseGlossaryResponse('"叶尘","Diệp Trần"');

      // Observed output: "叶尘","Diệp Trần" (exactly 16 bytes)
      expect(result, equals('"叶尘","Diệp Trần"'),
          reason:
              'Single CSV line must emit "original","vietnamese" (Requirement 3.2)');
      expect(outputRowCount(result), equals(1),
          reason: 'Single input line must produce exactly 1 output row');
    });

    // =========================================================================
    // OBSERVATION 4: Single line via : fallback
    // Requirement 3.2: existing CSV → : → " - " → "-" fallback chain
    // =========================================================================
    test('Single line via colon fallback produces correct output', () {
      final result = aiService.parseGlossaryResponse('叶尘: Diệp Trần');

      // Observed: colon splits into original="叶尘", vietnamese="Diệp Trần"
      // Output: "叶尘","Diệp Trần"
      expect(result, equals('"叶尘","Diệp Trần"'),
          reason:
              'Colon fallback must split and emit "original","vietnamese" (Requirement 3.2)');
      expect(outputRowCount(result), equals(1));
    });

    // =========================================================================
    // OBSERVATION 5: Single line via " - " fallback
    // =========================================================================
    test('Single line via dash-space fallback produces correct output', () {
      final result = aiService.parseGlossaryResponse('叶尘 - Diệp Trần');

      // Observed: " - " splits into original="叶尘", vietnamese="Diệp Trần"
      // Output: "叶尘","Diệp Trần"
      expect(result, equals('"叶尘","Diệp Trần"'),
          reason:
              '" - " fallback must split and emit "original","vietnamese" (Requirement 3.2)');
      expect(outputRowCount(result), equals(1));
    });

    // =========================================================================
    // OBSERVATION 6: Single line via "-" fallback (last resort)
    // =========================================================================
    test('Single line via hyphen fallback produces correct output', () {
      final result = aiService.parseGlossaryResponse('叶尘-Diệp Trần');

      // Observed: "-" splits into original="叶尘", vietnamese="Diệp Trần"
      // Output: "叶尘","Diệp Trần"
      expect(result, equals('"叶尘","Diệp Trần"'),
          reason:
              'Hyphen fallback must split and emit "original","vietnamese" (Requirement 3.2)');
      expect(outputRowCount(result), equals(1));
    });

    // =========================================================================
    // OBSERVATION 7: Single line where vietnamese.length > 100 → filtered out
    // Requirement 3.2: 100-char filter intact
    // =========================================================================
    test('Single line with vietnamese > 100 chars is filtered out', () {
      final longVietnamese = 'A' * 101;
      final result =
          aiService.parseGlossaryResponse('"叶尘","$longVietnamese"');

      // Observed: returns "" (empty) because vietnamese.length > 100
      expect(result, isEmpty,
          reason:
              'Vietnamese > 100 chars must be filtered out (Requirement 3.2)');
      expect(outputRowCount(result), equals(0));
    });

    // =========================================================================
    // OBSERVATION 8: Comma-separated without quotes (CSV fallback)
    // =========================================================================
    test('Comma-separated without quotes uses CSV fallback', () {
      final result = aiService.parseGlossaryResponse('叶尘,Diệp Trần');

      // Observed: comma splits into original="叶尘", vietnamese="Diệp Trần"
      // Output: "叶尘","Diệp Trần"
      expect(result, equals('"叶尘","Diệp Trần"'),
          reason:
              'Comma-separated input must use CSV fallback (Requirement 3.2)');
      expect(outputRowCount(result), equals(1));
    });

    // =========================================================================
    // PROPERTY VARIANT: Random ASCII single-line inputs matching fallback parsers
    // For random inputs of length <= 100 that match one of the four parser
    // fallbacks, assert parse(input) is a single-row CSV string with the
    // original-vs-vietnamese split intact.
    // =========================================================================
    test(
        'Property variant: random single-line inputs produce correct split via fallback chain',
        () {
      final random = Random(42); // Fixed seed for determinism

      // Generate random ASCII terms that will be parsed by each fallback
      for (var i = 0; i < 50; i++) {
        final originalLen = random.nextInt(10) + 1;
        final vietnameseLen = random.nextInt(20) + 1;

        // Generate random ASCII strings (letters only, no special chars)
        final original = String.fromCharCodes(
            List.generate(originalLen, (_) => 65 + random.nextInt(26)));
        final vietnamese = String.fromCharCodes(
            List.generate(vietnameseLen, (_) => 97 + random.nextInt(26)));

        // Ensure vietnamese <= 100 chars (always true given vietnameseLen <= 20)
        expect(vietnamese.length, lessThanOrEqualTo(100));

        // Choose a random separator from the fallback chain
        final separators = [',', ': ', ' - ', '-'];
        final sep = separators[random.nextInt(separators.length)];

        String input;
        if (sep == ',') {
          // Comma-separated (CSV without quotes fallback)
          input = '$original,$vietnamese';
        } else {
          input = '$original$sep$vietnamese';
        }

        final result = aiService.parseGlossaryResponse(input);

        // Property: single-line input produces exactly 1 output row
        expect(
          outputRowCount(result),
          equals(1),
          reason:
              'Single-line input "$input" must produce exactly 1 row, got "${result}"',
        );

        // Property: output contains the original and vietnamese parts
        expect(result.contains('"$original"'), isTrue,
            reason:
                'Output must contain quoted original "$original" for input "$input"');
        expect(result.contains('"$vietnamese"'), isTrue,
            reason:
                'Output must contain quoted vietnamese "$vietnamese" for input "$input"');

        // Property: output format is "original","vietnamese"
        expect(result, equals('"$original","$vietnamese"'),
            reason:
                'Output must be exactly "original","vietnamese" for input "$input"');
      }
    });

    // =========================================================================
    // EDGE CASE: Vietnamese exactly 100 chars (boundary) — should be kept
    // =========================================================================
    test('Vietnamese exactly 100 chars is preserved (boundary)', () {
      final vietnamese100 = 'B' * 100;
      final result =
          aiService.parseGlossaryResponse('"TestTerm","$vietnamese100"');

      // 100 chars is NOT > 100, so it should be kept
      expect(result, equals('"TestTerm","$vietnamese100"'),
          reason: 'Vietnamese at exactly 100 chars must be preserved');
      expect(outputRowCount(result), equals(1));
    });

    // =========================================================================
    // EDGE CASE: Vietnamese exactly 101 chars (boundary) — should be filtered
    // =========================================================================
    test('Vietnamese exactly 101 chars is filtered (boundary)', () {
      final vietnamese101 = 'B' * 101;
      final result =
          aiService.parseGlossaryResponse('"TestTerm","$vietnamese101"');

      // 101 chars IS > 100, so it should be filtered out
      expect(result, isEmpty,
          reason: 'Vietnamese at 101 chars must be filtered out');
      expect(outputRowCount(result), equals(0));
    });
  });
}
