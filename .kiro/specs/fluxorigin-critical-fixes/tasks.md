# Implementation Plan

## Overview

Bundled fix for five concurrent FluxOrigin v2.0.2 defects identified in the bugfix and design documents. The plan follows the **bug condition methodology**: exploration tests (Property 1.x) prove each bug exists on UNFIXED code, preservation tests (Property 2.x) lock in non-buggy behavior on UNFIXED code, then the fixes are applied and both phases are re-run for confirmation.

Bugs in scope:
- **Bug #1 (Critical)** — `AIService.generateGlossary` quadratic duplication
- **Bug #2 (High)** — `TranslationController` non-throttled, non-atomic progress saves
- **Bug #3 (Medium)** — Inconsistent logging (`print` / `debugPrint` vs. `DevLogger`)
- **Bug #4 (Medium)** — Hardcoded absolute MSIX `logo_path` in `pubspec.yaml`
- **Bug #5 (Low)** — `DictionaryScreen` silent file-read errors

Test framework: `flutter_test` (no new dependencies). Property-based tests are bounded random/parametric tests with a fixed seed for determinism.

## Tasks

> **Methodology**: Write tests BEFORE the fix. The exploration tests MUST FAIL on unfixed code (proves the bug exists); the preservation tests MUST PASS on unfixed code (captures baseline behavior to preserve).

---

### Phase 1 — Exploration Tests (Bug Condition)

> ⚠️ All tests in this phase MUST FAIL on the UNFIXED code. **Do NOT fix the test or the code if it fails — that failure is the proof the bug exists.**

- [x] 1. Write bug condition exploration test for Bug #1 (Glossary Quadratic Duplication)
  - **Property 1.1: Bug Condition** — `AIService.generateGlossary` Quadratic Duplication
  - **CRITICAL**: This test MUST FAIL on unfixed code — failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the Expected Behavior — when it passes after the fix, it validates Property 1 from design
  - **GOAL**: Surface the `outputRowCount == N²` counterexample on unfixed code
  - **Scoped PBT Approach**: For deterministic bugs, scope to concrete failing cases first, then expand to randomized inputs
  - File: `test/bugfixes/glossary_duplication_test.dart` (new)
  - Concrete case: build a fake AI response of 3 distinct lines (`"叶尘","Diệp Trần"`, `"长老","Trưởng lão"`, `"宗","Tông"`) and run the same parser logic used by `AIService.generateGlossary` (extract the core parser into a thin testable helper or call via a stubbed `AIService` that bypasses the network round-trip). Assert `parsedRowCount == 3`.
  - Randomized property: for `N` in `[2, 3, 5, 10, 20]`, generate `N` distinct `"original_i","viet_i"` lines, parse, assert `outputRowCount(parse(input)) == N` AND `outputRowCount(parse(input)) <= rawLineCount(input)`.
  - Header-collision case: include header lines (`original`, `term`, `từ gốc`, `----`) in the input AND assert filtering happens exactly once (no header lines in output, no duplicated content).
  - **Bug Condition (from design `isBugCondition`)**:
    `input is AIResponse AND parseableLines(input.response).distinctByOriginal.length >= 2 AND outputRowCount(generateGlossary(input)) > parseableLines(input.response).distinctByOriginal.length`
  - Run on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS with `outputRowCount == 9` for `N=3` (3 × 3) — proves the nested-loop bug
  - Document the counterexample in the test output (e.g., `expected 3 rows, got 9 — confirms quadratic emission`)
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1, 1.2, 1.3, 2.1, 2.2, 2.3_

- [x] 2. Write bug condition exploration test for Bug #2 (Translation Progress Throttle + Atomicity)
  - **Property 1.2: Bug Condition** — Per-Chunk Saves and Non-Atomic Write
  - **CRITICAL**: This test MUST FAIL on unfixed code
  - **DO NOT attempt to fix the test or the code when it fails**
  - **GOAL**: Surface (a) one save per chunk and (b) truncated JSON on simulated mid-write failure
  - File: `test/bugfixes/progress_throttle_test.dart` (new)
  - Throttle counterexample: stub `_aiService.translateChunk` to return instantly. Wrap `TranslationProgress.saveToFile` (or inject a counting decorator) to record call count. Run the translation loop on a 20-chunk synthetic input. Assert `saveCallCount <= ceil(20 / 5) + 1 == 5`.
  - **EXPECTED on UNFIXED code**: `saveCallCount == 20` — proves missing throttle.
  - Atomicity counterexample: simulate a mid-write failure by writing a `TranslationProgress` to disk via the current `saveToFile`, then on a second save call inject a deliberate exception after `writeAsString` starts but before flush completes (use a `MockFileSystem` or a custom subclass that throws). Re-read the file. Assert the file is either the previous good snapshot or absent — never partially-written JSON.
  - **EXPECTED on UNFIXED code**: re-read produces a `FormatException` — proves non-atomic write.
  - **Bug Condition (from design `isBugCondition`)**:
    - Throttle: `input is ChunkCompletion AND NOT input.isPause AND NOT input.isError AND NOT input.isFinal AND saveCalledThisChunk(input.chunkIndex)`
    - Atomicity: `input is ProgressSaveRequest AND processKilledMidWrite(input.killAfter) AND fileOnDiskAfterKill(input.filePath) is partiallyWrittenJson`
  - Run on UNFIXED code
  - **EXPECTED OUTCOME**: Both sub-assertions FAIL — confirms Bug #2 in both dimensions
  - Document counterexamples (e.g., `saveCalls=20 vs expected<=5`, `loadFromFile threw FormatException`)
  - Mark task complete when test is written, run, and failures documented
  - _Requirements: 1.4, 1.5, 2.4, 2.5_

- [x] 3. Write bug condition exploration test for Bug #3 (Inconsistent Logging)
  - **Property 1.3: Bug Condition** — `print` in non-UI code AND `debugPrint`-only error paths in UI screens
  - **CRITICAL**: This test MUST FAIL on unfixed code
  - **DO NOT attempt to fix the test or the code when it fails**
  - **GOAL**: Surface every `print(` callsite in `lib/services/`, `lib/controllers/`, `lib/models/` AND every error/warning `debugPrint` in `lib/ui/screens/` that lacks a sibling `DevLogger.*` call
  - File: `test/bugfixes/logging_callsite_scan_test.dart` (new)
  - Static scan: read the source files listed in design's Logging Migration Map (`translation_progress.dart`, `web_search_service.dart`, `translation_controller.dart`, `dictionary_screen.dart`, `translate_screen.dart`, `settings_screen.dart`, `history_screen.dart`) using `dart:io`. For each, run a regex scan for `\bprint\(` (forbidden in services/controllers/models) and for `debugPrint\(` inside `catch` blocks without a sibling `DevLogger\.` call (forbidden in UI screens).
  - Assert: `printCallsites(['lib/services/', 'lib/controllers/', 'lib/models/']) == []` AND `debugPrintWithoutDevLogger(['lib/ui/screens/']) == []`.
  - **Bug Condition (from design `isBugCondition`)**:
    - `input is LogCallsite AND fileIsInScope(input.filePath, ['lib/services/', 'lib/controllers/', 'lib/models/']) AND callsiteUses(input, 'print') AND NOT input.hasDevLoggerCall`
    - `input is LogCallsite AND fileIsInScope(input.filePath, ['lib/ui/screens/']) AND callsiteUses(input, 'debugPrint') AND NOT input.hasDevLoggerCall`
  - Run on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS reporting at least the 5 documented `print(` hits (`translation_progress.dart:63`, `web_search_service.dart:19,29`, `translation_controller.dart:407,434,532`) AND the documented unaccompanied `debugPrint` hits in UI screens
  - Document counterexamples (the exact file:line list)
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.6, 1.7, 2.6, 2.7_

- [x] 4. Write bug condition exploration test for Bug #4 (Hardcoded MSIX `logo_path`)
  - **Property 1.4: Bug Condition** — Absolute, machine-specific `logo_path` in `pubspec.yaml`
  - **CRITICAL**: This test MUST FAIL on unfixed code
  - **DO NOT attempt to fix the test or the code when it fails**
  - **GOAL**: Surface the absolute, non-portable `D:\FluxOrigin\...` path on machines that are not the original developer's
  - File: `test/bugfixes/msix_logo_path_test.dart` (new)
  - Read `pubspec.yaml` from the repo root using `dart:io`. Parse it as YAML (use `package:yaml` which is already a transitive dep of Flutter — verify in `pubspec.lock` first; otherwise scan with a regex).
  - Extract `msix_config.logo_path`. Assert two properties:
    1. `path.isAbsolute(logoPath) == false` — must be workspace-relative.
    2. `File(path.join(repoRoot, logoPath)).existsSync() == true` — the resolved path must point to a committed asset.
  - **Bug Condition (from design `isBugCondition`)**:
    `input is MsixBuildContext AND input.pubspec.msix_config.logo_path is absolutePath AND NOT fileExists(input.pubspec.msix_config.logo_path) on input.machine`
  - Run on UNFIXED code (assuming the test machine is NOT `D:\FluxOrigin`)
  - **EXPECTED OUTCOME**: Test FAILS — `logoPath` is `D:\FluxOrigin\assets\fluxorigin logo.png` which is absolute AND does not exist on the test machine
  - Document the counterexample (the exact value read from `pubspec.yaml`)
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.8, 2.8_

- [x] 5. Write bug condition exploration test for Bug #5 (Silent Dictionary Read Errors)
  - **Property 1.5: Bug Condition** — `DictionaryScreen._loadDictionaries` swallows file-read exceptions
  - **CRITICAL**: This test MUST FAIL on unfixed code
  - **DO NOT attempt to fix the test or the code when it fails**
  - **GOAL**: Surface the missing `DevLogger.warning` entry when a CSV file is unreadable
  - File: `test/bugfixes/dictionary_silent_error_test.dart` (new)
  - Setup: install a test `DevLogger` listener (use a stub or expose `DevLogger.logs` directly — it has a 1000-entry ring buffer). Create a temp directory, write a CSV file with deliberately invalid UTF-8 bytes (e.g., `[0xFF, 0xFE, 0xFD]`).
  - Drive the failing branch: either invoke `_loadDictionaries` directly via a widget test (`pumpWidget(DictionaryScreen)`) or extract the line-counting logic into a testable helper that takes a `File` and returns `(lineCount, didLog)`.
  - Assert two properties:
    1. `lineCount == 0` (graceful fallback preserved)
    2. `DevLogger.logs.any((e) => e.category == 'DictionaryScreen' && e.level == LogLevel.warning && e.message.contains('Failed to count lines'))` — a warning entry MUST be present.
  - **Bug Condition (from design `isBugCondition`)**:
    `input is DictionaryFileEntry AND NOT input.readSucceeds AND NOT devLoggerWasCalled(input.filePath)`
  - Run on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS — the second assertion fails because `catch (_) {}` does not call `DevLogger`
  - Document the counterexample (`DevLogger.logs.length == 0`)
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.9, 2.9_

---

### Phase 2 — Preservation Tests (BEFORE implementing fix)

> ⚠️ All tests in this phase MUST PASS on the UNFIXED code. They lock in the existing behavior so we can prove the fix introduces zero regressions.

- [x] 6. Write preservation property test for `AIService.generateGlossary` non-buggy inputs
  - **Property 2.1: Preservation** — Glossary parser preserves single-line, empty, and header-only behavior
  - **IMPORTANT**: Follow observation-first methodology — observe outputs on UNFIXED code, then encode them as assertions
  - File: `test/bugfixes/glossary_preservation_test.dart` (new)
  - Observation step (run UNFIXED code first, record actual outputs):
    1. Empty input `""` → record output (expected: empty/whitespace-only string).
    2. Header-only input (`"original,vietnamese\n----"`) → record output (expected: empty after filtering).
    3. Single well-formed CSV line `"叶尘","Diệp Trần"` → record exact output bytes.
    4. Single line via `:` fallback (e.g., `"叶尘: Diệp Trần"`) → record bytes.
    5. Single line via ` - ` fallback → record bytes.
    6. Single line via `-` fallback → record bytes.
    7. Single line where `vietnamese.length > 100` → record (expected: filtered out, empty output).
  - Encode observations as the test's expected values.
  - Property variant: for random ASCII single-line inputs of length `<= 100` characters that match one of the four parser fallbacks, assert `parse(input)` is a single-row CSV string with the original-vs-vietnamese split intact.
  - **Preservation Requirement (from design)**: Requirements 3.1 and 3.2 — empty/header-only returns empty; single well-formed line emits `"original","vietnamese"` via the existing CSV → `:` → ` - ` → `-` fallback chain with the 100-char filter intact.
  - Run on UNFIXED code
  - **EXPECTED OUTCOME**: Test PASSES (this captures baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2_

- [x] 7. Write preservation property test for `TranslationProgress.saveToFile` JSON byte-equality
  - **Property 2.2: Preservation** — JSON serialization output is byte-for-byte unchanged
  - **IMPORTANT**: Follow observation-first methodology
  - File: `test/bugfixes/progress_serialization_preservation_test.dart` (new)
  - Observation step: on UNFIXED code, save 6 hand-crafted `TranslationProgress` instances (empty, single chunk, 100 chunks, with non-ASCII Vietnamese content, with embedded newlines, with paused state) to disk and record the resulting bytes.
  - Encode the recorded bytes as expected values (or run save twice and assert determinism on the same input).
  - Property variant: for 100 randomly-generated `TranslationProgress` instances (use a fixed seed `Random(42)` for reproducibility — bounded `rawChunks.length` to `[0, 50]`, `translatedChunks` matching, ASCII + Latin + CJK + emoji content), assert that calling `saveToFile` then `File.readAsBytes()` returns bytes equal to `utf8.encode(jsonEncode(p.toJson()))`.
  - Round-trip: assert `loadFromFile(saveToFile(p)) == p` for the same 100 instances (deep equality on the JSON-decoded map).
  - Throttle-boundary preservation: simulate the existing pause/error/final flush paths and assert each unconditionally writes regardless of throttle state.
  - **Preservation Requirement (from design)**: Requirement 3.5 — JSON content is byte-for-byte equivalent so existing pre-fix progress files remain readable. Requirement 3.4 — pause/error/final still flush.
  - Run on UNFIXED code
  - **EXPECTED OUTCOME**: Test PASSES on all 100 randomized + 6 hand-crafted instances
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.4, 3.5_

- [x] 8. Write preservation property test for existing `DevLogger` callsites and ring buffer
  - **Property 2.3: Preservation** — Existing DevLogger entries (category, level, message, details) are unchanged AND the 1000-entry ring buffer behavior is preserved
  - **IMPORTANT**: Follow observation-first methodology
  - File: `test/bugfixes/dev_logger_preservation_test.dart` (new)
  - Observation step: on UNFIXED code, scan the codebase for every existing `DevLogger().*(...)` callsite. Record `(file, line, category, level, message_template)` for each. Save this manifest as a test fixture.
  - Test 1: After the fix, parse the codebase again and assert each manifest entry still exists (this guards Requirement 3.6 against accidental removal/rename).
  - Test 2: Behavioral preservation — for each callsite, drive its `catch` branch (where reachable from a unit test), and assert `DevLogger.logs.last.category` and `.level` match the manifest. For unreachable branches (e.g., real Wikipedia network failure), use a regex-based source assertion only.
  - Test 3: Ring buffer — push 1500 entries, assert `DevLogger.logs.length == 1000` (oldest 500 evicted). Assert `DevLogger.setEnabled(false)` followed by `info(...)` does not grow the buffer (Requirement 3.7).
  - **Preservation Requirements (from design)**: 3.6 (every existing DevLogger callsite continues to emit the same category/level), 3.7 (`setEnabled(false)` and `_maxLogs = 1000` untouched).
  - Run on UNFIXED code
  - **EXPECTED OUTCOME**: All three tests PASS
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.6, 3.7_

- [x] 9. Write preservation property test for `DictionaryScreen` happy path
  - **Property 2.4: Preservation** — Well-formed CSV files render with the same `{name, entries, fileSize, path}` shape
  - **IMPORTANT**: Follow observation-first methodology
  - File: `test/bugfixes/dictionary_screen_preservation_test.dart` (new)
  - Observation step: on UNFIXED code, prepare 5 CSV fixtures (1-line, 100-line, 5000-line, multi-byte, sub-1KB / 1-100KB / >1MB sizes) and record the rendered list entry for each.
  - Property variant: for random CSV fixtures with `lineCount in [0, 10000]` and `fileSize` spanning the existing MB/KB threshold, assert `lineCount == nonEmptyLineCount` and `fileSize` formatting matches the recorded thresholds.
  - **Preservation Requirement (from design)**: Requirement 3.9 — `lineCount` is non-empty line count, `fileSize` formatted in MB or KB with existing thresholds, list entry shape is `{name, entries, fileSize, path}`.
  - Run on UNFIXED code
  - **EXPECTED OUTCOME**: Test PASSES on all fixtures
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.9_

- [x] 10. Write preservation property test for public APIs and existing test suite
  - **Property 2.5: Preservation** — Public method signatures of affected classes are unchanged, and the existing test suite continues to pass
  - File: `test/bugfixes/public_api_preservation_test.dart` (new)
  - Static API check (using Dart mirrors or a hand-coded list, since mirrors are not available on Flutter — use a manifest comparison instead):
    - `AIService`: keep public methods `generateGlossary(String, String, String, String)`, `translateChunk(...)`, `chatCompletion(...)` (and any other currently-public method) with identical signatures.
    - `TranslationController`: keep `processFile(...)`, `pause()`, `resume()`, etc.
    - `TranslationProgress`: keep `saveToFile(String): Future<void>`, `static loadFromFile(String): Future<TranslationProgress?>`, `toJson()`, `fromJson(...)`.
    - `WebSearchService`: keep `lookupTerm(...)`.
    - `DictionaryScreen`: keep its widget constructor signature.
  - Test runner check: run the existing `test/` suite (`ai_service_refactor_test.dart`, `text_processor_test.dart`, `verify_web_search.dart`, `widget_test.dart`) via `flutter test` and assert exit code 0.
  - **Preservation Requirements (from design)**: 3.10 (public signatures unchanged), 3.11 (existing test suite passes).
  - Run on UNFIXED code
  - **EXPECTED OUTCOME**: API manifest matches expected; existing test suite passes
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.10, 3.11_

- [x] 11. Write preservation smoke check for `flutter run` and non-MSIX build paths
  - **Property 2.6: Preservation** — `flutter run` and `flutter build windows` are unaffected by the MSIX `logo_path` change
  - **IMPORTANT**: This is a manual / scripted smoke check rather than a unit test (the Flutter asset pipeline is environment-dependent)
  - File: `test/bugfixes/flutter_build_preservation.md` (new — a checklist documenting the manual procedure)
  - Document the steps: `flutter clean && flutter pub get && flutter build windows --debug` should succeed; `flutter run -d windows` should boot the app, render the splash, load `assets/fluxorigin_logo.png`, and translate a small file end-to-end.
  - Record baseline timing and asset checksum on UNFIXED code so post-fix verification is comparable.
  - **Preservation Requirement (from design)**: 3.8 — `flutter run` and `flutter build windows` continue to start, render, load assets, and run translations identically. Only `flutter pub run msix:create` is affected by the MSIX path change.
  - Run on UNFIXED code
  - **EXPECTED OUTCOME**: Baseline recorded; build succeeds; app boots
  - Mark task complete when checklist is filled in with baseline data
  - _Requirements: 3.8_

---

### Phase 3 — Fix Implementations

> Apply the fixes guided by the exploration tests from Phase 1 and the preservation tests from Phase 2. After each fix, the corresponding Property 1.x exploration test should pass and ALL Property 2.x preservation tests should still pass.

- [x] 12. Fix Bug #1 — `AIService.generateGlossary` quadratic duplication

  - [x] 12.1 Implement single-pass parser with `LinkedHashMap` deduplication
    - File: `lib/services/ai_service.dart`
    - Remove the outer `for (final line in lines)` wrapper around the parser body
    - Move the header filter out of the loop: `final filtered = lines.where((l) { final lower = l.toLowerCase().trim(); return !(lower.startsWith('original') || lower.startsWith('term') || lower.startsWith('từ gốc') || lower.startsWith('----')); }).toList();`
    - Replace the in-loop `lines.removeWhere(...)` (concurrent-modification hazard)
    - Iterate `filtered` exactly once with `for (var i = 0; i < filtered.length; i++)`
    - Keep the existing CSV-with-quotes → `:` split → ` - ` split → `-` split fallback chain unchanged
    - Keep the 100-character Vietnamese length filter unchanged
    - Deduplicate by `original` using `LinkedHashMap<String, String>` (preserves insertion order; first-occurrence wins)
    - Emit each entry once at the end via `for (final entry in seen.entries) { cleanBuffer.writeln('"${entry.key}","${entry.value}"'); }`
    - Preserve return shape: `return cleanBuffer.toString().trim();`
    - Add `import 'dart:collection';` if `LinkedHashMap` is not yet imported
    - _Bug_Condition: `input is AIResponse AND parseableLines(input.response).distinctByOriginal.length >= 2 AND outputRowCount(generateGlossary(input)) > parseableLines(input.response).distinctByOriginal.length`_
    - _Expected_Behavior: `outputRowCount(generateGlossary(input)) == distinctParseableLines(input).length AND outputRowCount <= rawLineCount(input)` (Property 1 from design)_
    - _Preservation: 3.1, 3.2 — empty/header-only returns empty; single well-formed line emits identical CSV via the existing fallback chain_
    - _Requirements: 2.1, 2.2, 2.3_

  - [x] 12.2 Verify exploration test for Bug #1 now passes
    - **Property 1.1: Expected Behavior** — Glossary Output Has No Duplicates
    - **IMPORTANT**: Re-run the SAME test from task 1 — do NOT write a new test
    - The test from task 1 already encodes the expected behavior
    - When this test passes, it confirms `outputRowCount == distinctLines` for `N >= 2`
    - **EXPECTED OUTCOME**: Test PASSES (confirms Bug #1 is fixed)
    - _Requirements: Property 1 from design / Requirements 2.1, 2.2, 2.3_

- [x] 13. Fix Bug #2 — Translation progress throttle and atomic write

  - [x] 13.1 Implement throttled per-chunk save in `TranslationController.processFile`
    - File: `lib/controllers/translation_controller.dart`
    - Add `static const int _saveEveryNChunks = 5;` (configurable; default 5 per Requirement 2.4)
    - Replace the unconditional `await progress.saveToFile(progressPath);` after `onChunkUpdate?.call(...)` with:
      ```dart
      final bool isFinalChunk = (i + 1) == total;
      final bool isThrottleBoundary = ((i + 1) % _saveEveryNChunks) == 0;
      if (isFinalChunk || isThrottleBoundary) {
        await progress.saveToFile(progressPath);
      }
      ```
    - Preserve the existing pause flush block (mandatory flush regardless of throttle)
    - In the per-chunk `catch (e)` block, add an explicit `await progress.saveToFile(progressPath);` BEFORE the rethrow, so the in-progress chunks since the last throttle boundary are not lost
    - Final completion path remains unchanged (the progress file is deleted post-merge)
    - _Bug_Condition (throttle): `input is ChunkCompletion AND NOT input.isPause AND NOT input.isError AND NOT input.isFinal AND saveCalledThisChunk(input.chunkIndex)`_
    - _Expected_Behavior: At most `ceil(total / N) + 4` saves total; exactly one save on each of pause / error / final, regardless of N (Property 2 from design)_
    - _Preservation: 3.3, 3.4 — chunk update, onChunkUpdate, previousContext refresh, and DevLogger events unchanged; pause/error/final still flush_
    - _Requirements: 2.4_

  - [x] 13.2 Implement atomic temp-file-and-rename in `TranslationProgress.saveToFile`
    - File: `lib/models/translation_progress.dart`
    - Compute `final tempPath = '$filePath.tmp';`
    - Write the full JSON payload via `await File(tempPath).writeAsString(jsonEncode(toJson()), flush: true);`
    - Atomic swap: `await File(tempPath).rename(filePath);` (on Windows NTFS, same-volume rename is atomic; on POSIX it is `rename(2)` which is atomic)
    - On any exception during write or rename, best-effort cleanup: `try { await File(tempPath).delete(); } catch (_) { /* best-effort */ }` then rethrow
    - Preserve `toJson()` and `jsonEncode` arguments verbatim — no whitespace introduced (Requirement 3.5)
    - Public signature unchanged: `Future<void> saveToFile(String filePath) async`
    - _Bug_Condition (atomicity): `input is ProgressSaveRequest AND processKilledMidWrite(input.killAfter) AND fileOnDiskAfterKill(input.filePath) is partiallyWrittenJson`_
    - _Expected_Behavior: After kill, file is either (a) absent, (b) previous good snapshot, or (c) new snapshot — never a partial write (Property 3 from design)_
    - _Preservation: 3.5 — JSON content byte-for-byte equivalent so existing pre-fix progress files remain readable_
    - _Requirements: 2.5_

  - [x] 13.3 Verify exploration test for Bug #2 now passes
    - **Property 1.2: Expected Behavior** — Throttled saves and atomic write
    - **IMPORTANT**: Re-run the SAME test from task 2 — do NOT write a new test
    - **EXPECTED OUTCOME**: Both sub-assertions PASS — `saveCallCount <= ceil(20/5)+1` AND simulated mid-write fault leaves a recoverable file
    - _Requirements: Properties 2 + 3 from design / Requirements 2.4, 2.5_

- [x] 14. Fix Bug #3 — Logging migration to `DevLogger`

  - [x] 14.1 Migrate `print(...)` callsites in services / controllers / models to `DevLogger`
    - File: `lib/models/translation_progress.dart`
      - Add `import '../services/dev_logger.dart';`
      - Line 63: `print('Error loading progress: $e')` → `DevLogger().error('TranslationProgress', 'Error loading progress', details: e.toString());`
    - File: `lib/services/web_search_service.dart`
      - Add `import 'dev_logger.dart';`
      - Line 19: `print("Wikipedia lookup failed for '$term' ($langCode): $e")` → `DevLogger().warning('WebSearchService', "Wikipedia lookup failed for '$term' ($langCode)", details: e.toString());`
      - Line 29: `print("DuckDuckGo lookup failed for '$term': $e")` → `DevLogger().warning('WebSearchService', "DuckDuckGo lookup failed for '$term'", details: e.toString());`
    - File: `lib/controllers/translation_controller.dart`
      - Line 407: `print("Error parsing AI glossary CSV: $e")` → `_logger.warning('TranslationController', 'Error parsing AI glossary CSV', details: e.toString());`
      - Line 434: `print("Error parsing existing glossary CSV: $e")` → `_logger.warning('TranslationController', 'Error parsing existing glossary CSV', details: e.toString());`
      - Line 532: `print("Error enriching glossary: $e")` → `_logger.warning('TranslationController', 'Error enriching glossary', details: e.toString());`
    - _Bug_Condition: `input is LogCallsite AND fileIsInScope(input.filePath, ['lib/services/', 'lib/controllers/', 'lib/models/']) AND callsiteUses(input, 'print') AND NOT input.hasDevLoggerCall`_
    - _Expected_Behavior: zero `print(` callsites in non-UI scope; all error/warning paths route through `DevLogger.*` with stable categories (Property 4 from design)_
    - _Preservation: 3.6 — every existing `DevLogger` callsite unchanged; this task only adds new ones_
    - _Requirements: 2.6_

  - [x] 14.2 Add `DevLogger` companion calls beside `debugPrint` in UI screens
    - Keep each existing `debugPrint(...)` (verbose dev trace) AND add a `DevLogger.error/warning` call so production errors reach the in-app Dev Logs tab
    - File: `lib/controllers/translation_controller.dart`
      - Line 370: keep `debugPrint('Error reading history: $e');` AND add `_logger.warning('TranslationController', 'Error reading history', details: e.toString());`
      - Line 385: keep `debugPrint('Error saving history: $e');` AND add `_logger.error('TranslationController', 'Error saving history', details: e.toString());`
    - File: `lib/ui/screens/translate_screen.dart`
      - Add `import '../../services/dev_logger.dart';` if absent
      - Line 1160: keep `debugPrint("Error picking dictionary: $e");` AND add `DevLogger().warning('TranslateScreen', 'Error picking dictionary', details: e.toString());`
    - File: `lib/ui/screens/settings_screen.dart`
      - Add `import '../../services/dev_logger.dart';` if absent
      - Line 201: keep `debugPrint('Error checking installed models: $e');` AND add `DevLogger().warning('SettingsScreen', 'Error checking installed models', details: e.toString());`
    - File: `lib/ui/screens/history_screen.dart`
      - Add `import '../../services/dev_logger.dart';` if absent
      - Line 116: keep `debugPrint('Error loading history: $e');` AND add `DevLogger().warning('HistoryScreen', 'Error loading history', details: e.toString());`
    - _Bug_Condition: `input is LogCallsite AND fileIsInScope(input.filePath, ['lib/ui/screens/']) AND callsiteUses(input, 'debugPrint') AND NOT input.hasDevLoggerCall`_
    - _Expected_Behavior: every error/warning `debugPrint` in UI screens has a sibling `DevLogger.*` call with the same context (Property 4 from design)_
    - _Preservation: 3.6, 3.7 — existing DevLogger callsites untouched; ring buffer behavior unchanged_
    - _Requirements: 2.7, 2.9_

  - [x] 14.3 Verify exploration test for Bug #3 now passes
    - **Property 1.3: Expected Behavior** — Production error paths reach `DevLogger`
    - **IMPORTANT**: Re-run the SAME test from task 3 — do NOT write a new test
    - **EXPECTED OUTCOME**: zero `print(` callsites in services/controllers/models AND every UI-screen `debugPrint` in a `catch` block has a sibling `DevLogger.*` call
    - _Requirements: Property 4 from design / Requirements 2.6, 2.7, 2.9_

- [x] 15. Fix Bug #4 — MSIX `logo_path` portability

  - [x] 15.1 Replace hardcoded absolute path with workspace-relative path in `pubspec.yaml`
    - File: `pubspec.yaml`
    - Under `msix_config:`, change `logo_path: D:\FluxOrigin\assets\fluxorigin logo.png` to `logo_path: assets/fluxorigin logo.png`
    - Do not touch other keys in `msix_config` (publisher, identity_name, capabilities, etc.) — Requirement 3.10
    - Verify the target file `assets/fluxorigin logo.png` exists and is committed (it is, per design)
    - _Bug_Condition: `input is MsixBuildContext AND input.pubspec.msix_config.logo_path is absolutePath AND NOT fileExists(input.pubspec.msix_config.logo_path) on input.machine`_
    - _Expected_Behavior: `flutter pub run msix:create` resolves `logo_path` to a workspace-relative existing file on any machine (Property 5 from design)_
    - _Preservation: 3.8 — `flutter run` and `flutter build windows` unaffected (they do not consult `msix_config`)_
    - _Requirements: 2.8_

  - [x] 15.2 Verify exploration test for Bug #4 now passes
    - **Property 1.4: Expected Behavior** — MSIX build is portable
    - **IMPORTANT**: Re-run the SAME test from task 4 — do NOT write a new test
    - **EXPECTED OUTCOME**: `path.isAbsolute(logoPath) == false` AND `File(resolvedPath).existsSync() == true`
    - Bonus manual check (recommended where MSIX tooling is available): on a non-D-drive machine, run `flutter pub run msix:create` and assert it succeeds
    - _Requirements: Property 5 from design / Requirement 2.8_

- [x] 16. Fix Bug #5 — `DictionaryScreen` silent file-read errors

  - [x] 16.1 Replace `catch (_) {}` with logging fallback
    - File: `lib/ui/screens/dictionary_screen.dart`
    - Add `import '../../services/dev_logger.dart';`
    - Line ~69: change `} catch (_) {}` (the inner `lineCount` count loop) to:
      ```dart
      } catch (e) {
        DevLogger().warning('DictionaryScreen',
          'Failed to count lines for $filePath: $e');
      }
      ```
    - Keep `lineCount = 0` initial value so the list still renders (Requirements 2.9 + 3.9)
    - At line 89: keep `debugPrint('Error loading dictionaries: $e');` AND add `DevLogger().error('DictionaryScreen', 'Error loading dictionaries', details: e.toString());` (covered by task 14.2 if not already applied)
    - _Bug_Condition: `input is DictionaryFileEntry AND NOT input.readSucceeds AND NOT devLoggerWasCalled(input.filePath)`_
    - _Expected_Behavior: when read fails, `lineCount = 0` AND a `DevLogger.warning('DictionaryScreen', ...)` entry is emitted_
    - _Preservation: 3.9 — well-formed CSV still produces the same `{name, entries, fileSize, path}` list entry_
    - _Requirements: 2.9_

  - [x] 16.2 Verify exploration test for Bug #5 now passes
    - **Property 1.5: Expected Behavior** — Dictionary read errors are observable
    - **IMPORTANT**: Re-run the SAME test from task 5 — do NOT write a new test
    - **EXPECTED OUTCOME**: with an invalid-UTF-8 CSV in the dictionary directory, `lineCount == 0` AND `DevLogger.logs` contains a warning entry with category `DictionaryScreen` and the documented message
    - _Requirements: Requirement 2.9_

---

### Phase 4 — Verify All Preservation Tests Still Pass

- [x] 17. Verify ALL preservation tests still pass after the fixes
  - **Property 2.x: Preservation** (all of them)
  - **IMPORTANT**: Re-run the SAME tests from tasks 6–11 — do NOT write new tests
  - Run `flutter test test/bugfixes/glossary_preservation_test.dart`
  - Run `flutter test test/bugfixes/progress_serialization_preservation_test.dart`
  - Run `flutter test test/bugfixes/dev_logger_preservation_test.dart`
  - Run `flutter test test/bugfixes/dictionary_screen_preservation_test.dart`
  - Run `flutter test test/bugfixes/public_api_preservation_test.dart`
  - Walk through `test/bugfixes/flutter_build_preservation.md` and re-confirm the build/run smoke check
  - **EXPECTED OUTCOME**: All preservation tests PASS (confirms zero regressions)
  - If any preservation test fails, STOP and investigate — the fix has unintended side effects
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10, 3.11_

---

### Phase 5 — Checkpoint

- [x] 18. Checkpoint — Ensure all tests pass and the existing test suite is green
  - Run the full repository test suite: `flutter test`
  - Run `flutter analyze` and confirm zero new warnings introduced (Bug #3 callsites should be gone; `avoid_print` lint is clean for the affected directories)
  - Confirm exploration tests (Property 1.1 through 1.5) all PASS — bugs are fixed
  - Confirm preservation tests (Property 2.1 through 2.6) all PASS — no regressions
  - Confirm the original test files still pass without modification: `ai_service_refactor_test.dart`, `text_processor_test.dart`, `verify_web_search.dart`, `widget_test.dart` (Requirement 3.11)
  - Manually validate the integration scenarios from design's Testing Strategy:
    - End-to-end translation run on a 100-chunk synthetic file: glossary has no duplicate rows, ≤ 21 progress saves, killing the process at any point leaves a consistent file, all `DevLogger` events visible
    - MSIX build smoke test on a fresh clone: `flutter pub run msix:create` succeeds
    - Dev Logs tab visibility: trigger each migrated error path and confirm an entry appears with the documented category and level
    - Resume-from-progress: pause at chunk 7 (with `N=5`, last save was chunk 5), close, reopen, hit Resume; verify it picks up at chunk 6 and the final output is byte-identical to a non-paused run
  - Ensure all tests pass; ask the user if questions arise
  - _Requirements: All (1.1–1.9, 2.1–2.9, 3.1–3.11)_


## Task Dependency Graph

```json
{
  "waves": [
    {
      "wave": 1,
      "name": "Exploration & Preservation Tests (BEFORE any fix)",
      "tasks": ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11"],
      "parallel": true,
      "description": "All tests written and run on UNFIXED code. Phase 1 tests MUST FAIL (proves bugs exist). Phase 2 tests MUST PASS (locks in baseline behavior)."
    },
    {
      "wave": 2,
      "name": "Apply Fixes",
      "tasks": ["12", "13", "14", "15", "16"],
      "parallel": true,
      "description": "Each fix group (12 Bug#1, 13 Bug#2, 14 Bug#3, 15 Bug#4, 16 Bug#5) touches independent files and may run in parallel. Within a group, X.1 (implement) precedes X.2/X.3 (verify exploration test now passes).",
      "dependsOn": [1]
    },
    {
      "wave": 3,
      "name": "Cross-Fix Preservation Re-Run",
      "tasks": ["17"],
      "parallel": false,
      "description": "Re-run all Phase 2 preservation tests after every fix in wave 2 is applied. Confirms zero regressions across the bundled fixes.",
      "dependsOn": [2]
    },
    {
      "wave": 4,
      "name": "Final Checkpoint",
      "tasks": ["18"],
      "parallel": false,
      "description": "Full repo test suite + flutter analyze + integration scenarios from design Testing Strategy.",
      "dependsOn": [3]
    }
  ]
}
```

**Visual dependency map:**

```
Phase 1 (Exploration — must FAIL on unfixed)         Phase 2 (Preservation — must PASS on unfixed)
  1. Bug #1 exploration test                           6. Glossary preservation
  2. Bug #2 exploration test                           7. saveToFile JSON byte-equality preservation
  3. Bug #3 exploration test                           8. DevLogger callsites + ring buffer preservation
  4. Bug #4 exploration test                           9. DictionaryScreen happy-path preservation
  5. Bug #5 exploration test                          10. Public API + existing test suite preservation
                                                      11. flutter run / build windows smoke check
                              │
                              ▼
                    ┌──────────────────────┐
                    │  Phase 3 — Fixes     │
                    └──────────────────────┘
                              │
   ┌──────────────┬───────────┼────────────┬──────────────┐
   ▼              ▼           ▼            ▼              ▼
 12. Bug #1    13. Bug #2  14. Bug #3   15. Bug #4    16. Bug #5
 (12.1 fix)    (13.1 fix   (14.1 print  (15.1 path    (16.1 catch
 (12.2 verify   13.2 fix    14.2 ui     change         16.2 verify
   re-run #1)   13.3 verify 14.3 verify 15.2 verify     re-run #5)
                re-run #2)  re-run #3)  re-run #4)
                              │
                              ▼
                    ┌──────────────────────────────┐
                    │ 17. Verify ALL preservation  │
                    │     tests still pass         │
                    └──────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────────┐
                    │ 18. Final checkpoint │
                    └──────────────────────┘
```

**Hard ordering rules:**
- Tasks 1–5 (exploration) and 6–11 (preservation) MUST be completed BEFORE any fix in Phase 3.
- Each fix sub-task `X.1` MUST come before its verification sub-task `X.2`/`X.3` (same group).
- Fix groups 12–16 are independent of each other in code (different files / different concerns) and MAY be done in any order or in parallel.
- Task 17 MUST come after every fix in 12–16 is applied (verifies cross-fix non-interference).
- Task 18 MUST come last and depends on 17 + every Phase 3 verification sub-task.

## Notes

- **Property numbering convention**: Property 1.x = Bug Condition (one per bug). Property 2.x = Preservation (one per preservation aspect). This matches the design's six Correctness Properties: Properties 1–5 cover the five bug conditions; Property 6 covers preservation across all of them, decomposed here into 2.1–2.6 for testability.
- **Test file layout**: All new tests live under `test/bugfixes/` to keep them isolated from the existing test suite (which must remain unmodified per Requirement 3.11). Existing test files (`ai_service_refactor_test.dart`, `text_processor_test.dart`, `verify_web_search.dart`, `widget_test.dart`) MUST NOT be edited.
- **Property-based testing approach**: Dart does not have a built-in QuickCheck library. Tests use bounded random generation with a fixed seed (`Random(42)`) for determinism. For each property, generate 100 inputs unless otherwise stated. Document the seed in the test header so failures are reproducible.
- **Counterexample documentation**: Each Phase 1 task explicitly documents the counterexample observed on unfixed code (e.g., "for N=3, observed 9 rows instead of 3"). This serves as evidence that the bug exists and that the test correctly reproduces it.
- **Atomic write on Windows**: `File.rename` on the same NTFS volume is atomic (Win32 `MoveFileEx` with `MOVEFILE_REPLACE_EXISTING`). On POSIX it is `rename(2)`, also atomic. The `.tmp` sibling is colocated with the target to guarantee same-volume rename.
- **Throttle factor `N=5`**: Default per Requirement 2.4. Configurable via the private `_saveEveryNChunks` constant; not exposed publicly to keep API stable (Requirement 3.10).
- **MSIX validation**: Task 15.2's automated assertion is portable. The optional manual `flutter pub run msix:create` step is recommended only on machines where the MSIX toolchain is installed.
- **Public API stability (Requirement 3.10)**: No public method signature in `AIService`, `TranslationController`, `TranslationProgress`, `WebSearchService`, or `DictionaryScreen` changes. All fixes are internal.
- **DevLogger ring buffer (Requirement 3.7)**: Adding new callsites does not change `_maxLogs = 1000` behavior. New entries are subject to the same eviction policy. `setEnabled(false)` continues to suppress all entries including the new ones.
- **What is NOT fixed in this spec**: This spec deliberately does not refactor logging beyond the migration map. Higher-level logging architecture (structured fields, sinks, log rotation) is out of scope.
