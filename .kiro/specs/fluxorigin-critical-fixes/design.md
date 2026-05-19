# FluxOrigin Critical Fixes Bugfix Design

## Overview

This design covers five concurrent defects in FluxOrigin v2.0.2 (Flutter Windows desktop AI book translator) that share a common regression surface — the translation pipeline and the dev-logging story. They are bundled into one fix because each is small in scope, none changes public APIs, and the same set of files (`ai_service.dart`, `translation_controller.dart`, `translation_progress.dart`, plus four UI screens and `pubspec.yaml`) is touched by more than one bug.

The general fix strategy:

1. **Bug #1 (Critical) — generateGlossary quadratic duplication**: Replace the nested-loop-with-mid-iteration-mutation pattern in `AIService.generateGlossary` with a single-pass parser that filters headers once, parses each line at most once, and dedupes by `original` term using a `LinkedHashMap` to preserve insertion order.
2. **Bug #2 (High) — non-throttled, non-atomic progress saves**: Introduce a chunk-counter throttle in the translation loop (default `N=5`, configurable, with mandatory flushes on pause/error/stop/final) and rewrite `TranslationProgress.saveToFile` to use a temp-file-and-rename atomic write pattern.
3. **Bug #3 (Medium) — inconsistent logging**: Migrate every `print(...)` call in `lib/services/`, `lib/controllers/`, `lib/models/` to `DevLogger().error(...)` / `.warning(...)` / `.info(...)` with a stable category string per file. Add `DevLogger` calls beside the existing `debugPrint(...)` calls in `lib/ui/screens/` so production error paths are visible in the in-app Dev Logs tab.
4. **Bug #4 (Medium) — hardcoded MSIX `logo_path`**: Change `pubspec.yaml > msix_config > logo_path` from the absolute `D:\FluxOrigin\assets\fluxorigin logo.png` to the workspace-relative `assets/fluxorigin logo.png` that is already committed.
5. **Bug #5 (Low) — silent file-read errors in DictionaryScreen**: Replace `catch (_) {}` with `catch (e) { DevLogger().warning('DictionaryScreen', 'Failed to count lines for $filePath: $e'); }`, keeping the `lineCount = 0` fallback so the list still renders.

The design does not introduce new dependencies, does not change public method signatures, and does not require migration of existing on-disk progress JSON or glossary CSV files.

## Glossary

- **Bug_Condition (C)**: Predicate that identifies the exact set of inputs / runtime states that trigger one of the five bugs (per-bug definitions below).
- **Property (P)**: Predicate that the post-fix output must satisfy when `C` holds (per-bug definitions below).
- **Preservation**: All inputs/states where `C` does NOT hold must produce byte-identical (or behaviorally identical) output before and after the fix.
- **AIService.generateGlossary**: Method in `lib/services/ai_service.dart` that takes an AI raw response (multi-line string) plus model/source-language/genre context and returns a glossary CSV string of the form `"original","vietnamese"\n...`.
- **TranslationProgress.saveToFile**: Method in `lib/models/translation_progress.dart` that serializes the in-memory `TranslationProgress` to JSON and writes it to disk.
- **TranslationController translation loop**: The `for (int i = progress.currentIndex; i < total; i++)` loop in `processFile` in `lib/controllers/translation_controller.dart` that calls `_aiService.translateChunk(...)` and persists progress.
- **DevLogger**: Singleton in `lib/services/dev_logger.dart` exposing `info / warning / error / debug / request / response` with a category string and optional details. Has a 1000-entry ring buffer and feeds the in-app Dev Logs tab.
- **MSIX `logo_path`**: The `msix_config.logo_path` key in `pubspec.yaml`, consumed by `flutter pub run msix:create`. Resolved relative to the project root when the value is not absolute.
- **DictionaryScreen.\_loadDictionaries**: Method in `lib/ui/screens/dictionary_screen.dart` that scans the dictionary directory for CSV files and computes `lineCount` for each.

## Bug Details

### Bug Condition

There are five sub-conditions. The composite bug condition `C(input)` for this spec is the disjunction of the five.

**Formal Specification (composite):**

```
FUNCTION isBugCondition(input)
  INPUT: input - one of
           AIResponse (multi-line string + (modelName, sourceLanguage, genre)),
           ChunkCompletion (chunkIndex, total, isPause, isError, isFinal),
           ProgressSaveRequest (progress: TranslationProgress, filePath: String, killAfter: Duration?),
           LogCallsite (filePath, line, category, level, hasDevLoggerCall),
           MsixBuildContext (machine: String, repoPath: String, pubspec: Yaml),
           DictionaryFileEntry (filePath, readSucceeds: bool)
  OUTPUT: boolean

  RETURN
    // Bug #1
    (input is AIResponse
       AND parseableLines(input.response).distinctByOriginal.length >= 2
       AND outputRowCount(generateGlossary(input)) > parseableLines(input.response).distinctByOriginal.length)
    OR
    // Bug #2 (throttling part)
    (input is ChunkCompletion
       AND NOT input.isPause AND NOT input.isError AND NOT input.isFinal
       AND saveCalledThisChunk(input.chunkIndex))
    OR
    // Bug #2 (atomicity part)
    (input is ProgressSaveRequest
       AND processKilledMidWrite(input.killAfter)
       AND fileOnDiskAfterKill(input.filePath) is partiallyWrittenJson)
    OR
    // Bug #3
    (input is LogCallsite
       AND fileIsInScope(input.filePath, ['lib/services/', 'lib/controllers/', 'lib/models/'])
       AND callsiteUses(input, 'print') AND NOT input.hasDevLoggerCall)
    OR
    (input is LogCallsite
       AND fileIsInScope(input.filePath, ['lib/ui/screens/'])
       AND callsiteUses(input, 'debugPrint') AND NOT input.hasDevLoggerCall)
    OR
    // Bug #4
    (input is MsixBuildContext
       AND input.pubspec.msix_config.logo_path is absolutePath
       AND NOT fileExists(input.pubspec.msix_config.logo_path) on input.machine)
    OR
    // Bug #5
    (input is DictionaryFileEntry
       AND NOT input.readSucceeds
       AND NOT devLoggerWasCalled(input.filePath))
END FUNCTION
```

### Examples

Bug #1 — quadratic duplication:

- Input: AI response with 3 distinct lines `"叶尘","Diệp Trần"`, `"长老","Trưởng lão"`, `"宗","Tông"`. Expected output: 3 rows. Actual output: 9 rows (each line emitted 3 times) because the inner `for (var i = 0; i < lines.length; i++)` runs once per outer-loop iteration.
- Input: AI response with 1 valid line `"叶尘,Diệp Trần"`. Expected: 1 row. Actual: 1 row (passes today by accident — the bug only manifests for `N >= 2`).

Bug #2 — non-throttled saves:

- Input: 200-chunk book translation. Expected: ≤ 41 disk writes (initial + every 5 chunks + final). Actual: 200 disk writes, one per chunk, each serializing the full `rawChunks + translatedChunks` arrays (multi-MB JSON each).

Bug #2 — non-atomic write:

- Input: User SIGKILLs the process while `file.writeAsString(jsonEncode(toJson()), flush: true)` is in flight at chunk 87 of 200. Expected: progress file remains the last successfully-flushed snapshot (e.g., chunk 85). Actual: progress file is truncated mid-JSON, `loadFromFile` throws `FormatException`, user loses all 87 chunks.

Bug #3 — `print` in non-UI code:

- Input: `lib/models/translation_progress.dart:63` runs `print('Error loading progress: $e')` when JSON is malformed. Expected: entry visible in Dev Logs tab with category `TranslationProgress`. Actual: entry only on stdout, invisible in production builds and in-app.

Bug #3 — `debugPrint` in UI screens:

- Input: `lib/ui/screens/dictionary_screen.dart:89` runs `debugPrint('Error loading dictionaries: $e')` in release build. Expected: entry visible in Dev Logs tab. Actual: silenced (debugPrint is a no-op in release).

Bug #4 — hardcoded MSIX path:

- Input: Contributor clones the repo to `C:\dev\flux-origin` and runs `flutter pub run msix:create`. Expected: build succeeds using `assets/fluxorigin logo.png`. Actual: build fails with `Cannot find logo at D:\FluxOrigin\assets\fluxorigin logo.png`.

Bug #5 — silent dictionary read errors:

- Input: A CSV file in the dictionary directory has invalid UTF-8 bytes. Expected: `lineCount = 0` AND a `DevLogger().warning('DictionaryScreen', 'Failed to count lines for ...')` entry. Actual: `lineCount = 0` silently; the user has no way to know the file was unreadable.

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors** (mirroring `bugfix.md` clauses 3.1–3.11):

- 3.1 — `generateGlossary` on an empty / header-only / unparseable input continues to return an empty (or whitespace-only) string.
- 3.2 — `generateGlossary` on a single well-formed line still emits exactly `"original","vietnamese"`, with the existing parser fallback chain (CSV → `:` split → ` - ` split → `-` split) and the 100-character Vietnamese length filter.
- 3.3 — The translation loop still updates `progress.translatedChunks[i]`, calls `onChunkUpdate`, refreshes `previousContext`, and emits the same `DevLogger.info` / `DevLogger.debug` / `DevLogger.error` events it does today (logging events are not removed by this fix; only the throttle and atomicity change).
- 3.4 — Pause / per-chunk error / final completion still write progress before returning or rethrowing (these are unconditional flushes that override the throttle).
- 3.5 — `saveToFile` produces JSON that is byte-for-byte equivalent to the current implementation's output for a given `TranslationProgress` instance, so existing pre-fix progress files remain readable by `loadFromFile`.
- 3.6 — Every existing `DevLogger` callsite continues to emit the same category and level. The fix only adds new callsites and re-routes `print` / `debugPrint` callsites; it does not alter or remove any existing `DevLogger.*` call.
- 3.7 — `DevLogger.setEnabled(false)` continues to suppress all entries; the 1000-entry ring buffer (`_maxLogs`) is untouched.
- 3.8 — `flutter run` (non-MSIX path) continues to start, render the splash, load assets, and run translations identically. The MSIX `logo_path` change does not affect the regular Flutter asset pipeline.
- 3.9 — `DictionaryScreen._loadDictionaries` on a normal, well-formed CSV continues to compute `lineCount` as the number of non-empty lines, format `fileSize` in MB or KB with the existing thresholds, and append a `{name, entries, fileSize, path}` entry to the rendered list.
- 3.10 — `AIService`, `TranslationController`, `TranslationProgress`, `WebSearchService`, and `DictionaryScreen` keep the same public method signatures and return types — no caller in `lib/ui/` requires changes to keep compiling.
- 3.11 — The existing test suite under `test/` (`ai_service_refactor_test.dart`, `text_processor_test.dart`, `verify_web_search.dart`, `widget_test.dart`) continues to pass without modification.

**Scope:**

All inputs / states where `isBugCondition` returns false must be completely unaffected. This explicitly includes:

- Mouse interactions, keyboard navigation, and any UI flow not in the listed screens.
- Translation runs that do not involve glossary generation with `N >= 2` distinct lines.
- Progress saves on pause / error / final (these still happen unconditionally).
- Existing `DevLogger.*` callsites (no changes to the calls themselves).
- `flutter run`, `flutter build windows`, IDE debug runs (only `flutter pub run msix:create` is affected by the MSIX path change).
- Well-formed CSV files in the dictionary directory.

The actual expected correct behavior under the bug condition is defined formally in the **Correctness Properties** section below.

## Hypothesized Root Cause

Bug-by-bug analysis of the most likely causes:

1. **Bug #1 — `generateGlossary` quadratic duplication**:
   - **Concurrent modification + double iteration**: The outer `for (final line in lines)` and the inner `for (var i = 0; i < lines.length; i++)` are nested. The inner loop fully re-iterates all lines on every outer iteration, producing N×N rows. On top of that, `lines.removeWhere(...)` is called on the same list the outer for-in is iterating, which is a defined-but-fragile concurrent modification.
   - **Misplaced refactor**: This looks like an intermediate refactor where the developer started moving from "loop once, filter inline" to "filter, then parse" but left both loops in place. The outer loop body should not exist — the entire parse should be a single pass over the already-filtered `lines`.

2. **Bug #2 — non-throttled, non-atomic saves**:
   - **Throttling missed by design**: The `await progress.saveToFile(progressPath)` call inside the per-chunk loop was added to guarantee resume-from-progress, with no consideration for I/O cost. There is no chunk counter, no time-based debounce, no dirty flag.
   - **Atomicity overlooked**: `File.writeAsString(..., flush: true)` only guarantees the bytes that were written are flushed, not that the file reaches a consistent state. If the process is killed during `writeAsString`, the file is truncated to whatever was written so far. The fix is the standard temp-file-and-rename pattern: rename is atomic on Windows NTFS for same-volume operations.

3. **Bug #3 — inconsistent logging**:
   - **Code accreted over time**: `print(...)` calls were probably added during early prototyping and never migrated. `debugPrint(...)` was added in UI code under the assumption that it would behave like a logger in release builds (it doesn't — it's silenced).
   - **No lint enforcement**: The project has `flutter_lints` but `avoid_print` is not strictly enforced for the call paths in question, so they slipped through.

4. **Bug #4 — hardcoded MSIX `logo_path`**:
   - **Local-path leak**: The path was set to a developer-specific location (`D:\FluxOrigin\...`) during initial setup and never normalized. The `msix` package supports relative paths from the project root, so the existing `assets/fluxorigin logo.png` (already committed) is the natural target.

5. **Bug #5 — silent error swallowing**:
   - **Defensive but invisible**: `catch (_) {}` was added to keep the dictionary list rendering even if one CSV file failed to read. The intent (graceful fallback) is correct; the omission (no log) is the bug. Adding a `DevLogger.warning` preserves the fallback while making the failure observable.

## Correctness Properties

Property 1: Bug Condition — Glossary Output Has No Duplicates

_For any_ AI response with `N >= 0` parseable, distinct-by-`original` glossary lines, the fixed `AIService.generateGlossary` SHALL emit exactly one CSV row per distinct `original` term, where the row content is the existing parser's `"$original","$vietnamese"` for that term. Concretely: `outputRowCount(generateGlossary(input)) == distinctParseableLines(input).length`, and `outputRowCount(generateGlossary(input)) <= rawLineCount(input)` for any input.

**Validates: Requirements 2.1, 2.2, 2.3**

Property 2: Bug Condition — Progress Saves Are Throttled With Mandatory Boundary Flushes

_For any_ translation run of `total` chunks completed with throttle factor `N` (default `N=5`), the fixed `TranslationController.processFile` SHALL invoke `progress.saveToFile(progressPath)` at most `ceil(total / N) + 4` times in total (initial + every Nth chunk + pause + error + final), AND SHALL invoke it exactly once on each of: pause request observed, per-chunk exception caught, final-completion finalize, regardless of `N`.

**Validates: Requirements 2.4**

Property 3: Bug Condition — Progress File Is Atomically Written

_For any_ call to `TranslationProgress.saveToFile(filePath)` that is interrupted at any byte offset by a process kill, the file at `filePath` after recovery SHALL either (a) not exist, (b) contain the previous successfully-completed snapshot byte-for-byte, or (c) contain the new snapshot byte-for-byte. It SHALL NEVER contain a truncated / partially-written JSON document. In particular: `loadFromFile(filePath)` either returns `null` (file missing) or a valid `TranslationProgress` instance that decodes cleanly.

**Validates: Requirements 2.5**

Property 4: Bug Condition — Production Error Paths Reach DevLogger

_For any_ source file under `lib/services/`, `lib/controllers/`, or `lib/models/`, the fixed code SHALL contain zero `print(...)` callsites. _For any_ source file under `lib/ui/screens/`, every `debugPrint(...)` callsite on an error / warning path SHALL have an accompanying `DevLogger().error(...)` or `DevLogger().warning(...)` call with a stable category string and the same error context.

**Validates: Requirements 2.6, 2.7, 2.9**

Property 5: Bug Condition — MSIX Build Succeeds On Any Machine

_For any_ machine on which the repository is cloned to a path `P`, after the fix `flutter pub run msix:create` SHALL resolve `msix_config.logo_path` to `<P>/assets/fluxorigin logo.png` (a file already committed) and the build SHALL NOT fail with a "logo not found" error attributable to a per-developer path.

**Validates: Requirements 2.8**

Property 6: Preservation — Non-Buggy Inputs Are Byte-Identical

_For any_ input where `isBugCondition` returns false, the fixed code SHALL produce the same observable result as the original code. Concretely:

- For `generateGlossary` on a single well-formed line, output bytes match.
- For `saveToFile`, the final JSON content for a given `TranslationProgress` instance matches the pre-fix output byte-for-byte (the atomic-write change is a write-strategy change, not a serialization change).
- For `flutter run` and `flutter build windows`, behavior is identical (only `flutter pub run msix:create` is affected by the path change).
- For all existing `DevLogger.*` callsites, the emitted category, level, message, and details are unchanged.
- For `DictionaryScreen._loadDictionaries` on a well-formed CSV, the rendered list entry matches.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10, 3.11**

## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct, the per-file changes are:

---

**File 1**: `lib/services/ai_service.dart`

**Function**: `generateGlossary(String sample, String modelName, String sourceLanguage, String genre)`

**Specific Changes**:

1. **Remove the outer `for (final line in lines)` wrapper**: The entire body of `generateGlossary` after `final List<String> lines = response.split('\n');` becomes a single pass, not nested.
2. **Move the header filter out of the loop and apply it exactly once** on a defensive copy:
   - Replace the in-loop `lines.removeWhere(...)` with a single `final filtered = lines.where((l) { final lower = l.toLowerCase().trim(); return !(lower.startsWith('original') || lower.startsWith('term') || lower.startsWith('từ gốc') || lower.startsWith('----')); }).toList();`.
3. **Iterate `filtered` once** with `for (var i = 0; i < filtered.length; i++)`, keeping the existing CSV parsing fallback chain (CSV-with-quotes → `:` split → ` - ` split → `-` split) and the 100-character Vietnamese length filter exactly as they are today.
4. **Deduplicate by `original`** using a `LinkedHashMap<String, String>` (preserves insertion order). On collision, keep the first occurrence (this is the AI's primary suggestion, lower entries are usually copy-paste duplicates).
5. **Emit each entry once** at the end:
   ```dart
   for (final entry in seen.entries) {
     cleanBuffer.writeln('"${entry.key}","${entry.value}"');
   }
   ```
6. **Preserve the existing return shape**: still `return cleanBuffer.toString().trim();` so callers in `TranslationController._smartMergeGlossary` and `_enrichGlossary` see no API change.

Pseudocode of the new core:

```
FUNCTION generateGlossary(sample, modelName, sourceLanguage, genre)
  response := await chatCompletion(...)             // unchanged
  lines := response.split('\n')                     // unchanged
  filtered := lines.where(NOT isHeaderLine).toList()  // <-- ONE-PASS FILTER
  seen := LinkedHashMap<String, String>()           // <-- DEDUP
  FOR i = 0 to filtered.length - 1 DO               // <-- SINGLE LOOP
    line := filtered[i].trim()
    IF line.isEmpty THEN CONTINUE
    (original, vietnamese) := parseLine(line)       // existing CSV → : → " - " → "-" cascade
    IF original == null OR vietnamese == null THEN CONTINUE
    IF vietnamese.length > 100 THEN CONTINUE
    IF seen.containsKey(original) THEN CONTINUE     // <-- DEDUP
    seen[original] := vietnamese
  END FOR
  buffer := StringBuffer()
  FOR (k, v) IN seen DO buffer.writeln('"$k","$v"')
  RETURN buffer.toString().trim()
END FUNCTION
```

---

**File 2**: `lib/models/translation_progress.dart`

**Function**: `saveToFile(String filePath)`

**Specific Changes**:

1. **Atomic-write pattern (temp file + rename)**:
   - Compute `final tempPath = '$filePath.tmp';`.
   - Write the full JSON payload to `tempPath` via `await File(tempPath).writeAsString(jsonEncode(toJson()), flush: true);`.
   - Rename atomically: `await File(tempPath).rename(filePath);` (on Windows NTFS, same-volume rename is atomic; on POSIX it is `rename(2)` which is atomic).
   - On any exception during write or rename, attempt to delete the temp file: `try { await File(tempPath).delete(); } catch (_) { /* best-effort */ }`, then rethrow.
2. **Preserve the existing serialization output byte-for-byte** (Requirement 3.5): no change to `toJson()`, no change to `jsonEncode` arguments, no whitespace introduced.
3. **Replace `print('Error loading progress: $e')` at line 63** in `loadFromFile` with `DevLogger().error('TranslationProgress', 'Error loading progress', details: e.toString());`. Add the import: `import '../services/dev_logger.dart';`.
4. **Public signature unchanged**: still `Future<void> saveToFile(String filePath) async` and `static Future<TranslationProgress?> loadFromFile(String filePath) async` (Requirement 3.10).

Pseudocode:

```
FUNCTION saveToFile(filePath)
  lastUpdated := DateTime.now()
  payload := jsonEncode(toJson())
  tempPath := filePath + '.tmp'
  TRY
    await File(tempPath).writeAsString(payload, flush: true)
    await File(tempPath).rename(filePath)            // <-- ATOMIC SWAP
  CATCH e
    TRY File(tempPath).delete() CATCH (_) END
    RETHROW e
  END TRY
END FUNCTION
```

---

**File 3**: `lib/controllers/translation_controller.dart`

**Function**: `processFile(...)` translation loop, plus `_addToHistory`, `_smartMergeGlossary`, `_enrichGlossary`.

**Specific Changes**:

1. **Throttled progress saves in the translation loop**:
   - Add a private constant: `static const int _saveEveryNChunks = 5;` (configurable; default 5 per requirement 2.4).
   - Replace the unconditional `await progress.saveToFile(progressPath);` at line ~310 (after `onChunkUpdate?.call(i + 1, total, chunk, translated);`) with:
     ```dart
     final bool isFinalChunk = (i + 1) == total;
     final bool isThrottleBoundary = ((i + 1) % _saveEveryNChunks) == 0;
     if (isFinalChunk || isThrottleBoundary) {
       await progress.saveToFile(progressPath);
     }
     ```
   - **Mandatory flushes** (already present in the code, keep them):
     - On pause: the existing `if (_isPaused) { ... await progress.saveToFile(progressPath); return null; }` block.
     - On per-chunk exception: add an explicit `await progress.saveToFile(progressPath);` inside the `catch (e) { ... }` block before the `throw Exception(...)`, so the user can resume from the chunk that failed (currently the catch only logs and rethrows, so any in-progress chunks since the last throttle save are lost).
   - **Final completion**: keep the post-loop flow as-is. The progress file is deleted after merging the final content, so no extra save needed there.
2. **Logging migration in this file** (Bug #3, requirements 2.6, 2.7):
   - Line 370: `debugPrint('Error reading history: $e');` → keep `debugPrint` (UI-adjacent dev trace) AND add `_logger.warning('TranslationController', 'Error reading history', details: e.toString());`.
   - Line 385: `debugPrint('Error saving history: $e');` → same pattern, add `_logger.error('TranslationController', 'Error saving history', details: e.toString());`.
   - Line 407: `print("Error parsing AI glossary CSV: $e");` → replace with `_logger.warning('TranslationController', 'Error parsing AI glossary CSV', details: e.toString());`.
   - Line 434: `print("Error parsing existing glossary CSV: $e");` → replace with `_logger.warning('TranslationController', 'Error parsing existing glossary CSV', details: e.toString());`.
   - Line 532: `print("Error enriching glossary: $e");` → replace with `_logger.warning('TranslationController', 'Error enriching glossary', details: e.toString());`.
   - All replacements use the existing `_logger` field (`final DevLogger _logger = DevLogger();`).
3. **Public signatures unchanged** (Requirement 3.10).

---

**File 4**: `lib/services/web_search_service.dart`

**Specific Changes**:

1. Add import: `import 'dev_logger.dart';`.
2. Add singleton instance access: `final DevLogger _logger = DevLogger();` (or call `DevLogger().warning(...)` directly).
3. Line 19: `print("Wikipedia lookup failed for '$term' ($langCode): $e");` → `DevLogger().warning('WebSearchService', "Wikipedia lookup failed for '$term' ($langCode)", details: e.toString());`.
4. Line 29: `print("DuckDuckGo lookup failed for '$term': $e");` → `DevLogger().warning('WebSearchService', "DuckDuckGo lookup failed for '$term'", details: e.toString());`.
5. **Public signature of `lookupTerm` unchanged** (Requirement 3.10).

---

**File 5**: `lib/ui/screens/dictionary_screen.dart`

**Specific Changes**:

1. **Bug #5 — replace silent swallow at line 69**:
   - Change `} catch (_) {}` (the inner `lineCount` count loop) to:
     ```dart
     } catch (e) {
       DevLogger().warning('DictionaryScreen',
         'Failed to count lines for $filePath: $e');
     }
     ```
   - Keep `lineCount = 0` initial value so the list still renders (Requirement 2.9 + 3.9).
2. **Bug #3 — line 89 `debugPrint`**:
   - Keep the existing `debugPrint('Error loading dictionaries: $e');` AND add `DevLogger().error('DictionaryScreen', 'Error loading dictionaries', details: e.toString());` so the error surfaces in production.
3. Add import: `import '../../services/dev_logger.dart';`.

---

**File 6**: `lib/ui/screens/translate_screen.dart`

**Specific Changes**:

1. Line 1160: keep existing `debugPrint("Error picking dictionary: $e");` AND add `DevLogger().warning('TranslateScreen', 'Error picking dictionary', details: e.toString());`.
2. Add import: `import '../../services/dev_logger.dart';` if not already present.

---

**File 7**: `lib/ui/screens/settings_screen.dart`

**Specific Changes**:

1. Line 201: keep `debugPrint('Error checking installed models: $e');` AND add `DevLogger().warning('SettingsScreen', 'Error checking installed models', details: e.toString());`.
2. Add import: `import '../../services/dev_logger.dart';` if not already present.

---

**File 8**: `lib/ui/screens/history_screen.dart`

**Specific Changes**:

1. Line 116: keep `debugPrint('Error loading history: $e');` AND add `DevLogger().warning('HistoryScreen', 'Error loading history', details: e.toString());`.
2. Add import: `import '../../services/dev_logger.dart';` if not already present.

---

**File 9**: `pubspec.yaml`

**Specific Changes**:

1. Under `msix_config:`, change:
   ```yaml
   logo_path: D:\FluxOrigin\assets\fluxorigin logo.png
   ```
   to:
   ```yaml
   logo_path: assets/fluxorigin logo.png
   ```
2. No other key in `msix_config` is changed (publisher, identity_name, capabilities, etc. are preserved).
3. The `flutter` block already exposes assets; the MSIX config resolves `logo_path` relative to the project root, which matches the on-disk `assets/fluxorigin logo.png` already committed.
4. Verify `flutter run` and `flutter build windows` are unaffected (Requirement 3.8) — these paths do not consult `msix_config`.

---

### Logging Migration Map (consolidated)

| File | Line | Before | After (category) | Level |
|---|---|---|---|---|
| `lib/models/translation_progress.dart` | 63 | `print('Error loading progress: $e')` | `DevLogger().error('TranslationProgress', ...)` | error |
| `lib/services/web_search_service.dart` | 19 | `print("Wikipedia lookup failed ...")` | `DevLogger().warning('WebSearchService', ...)` | warning |
| `lib/services/web_search_service.dart` | 29 | `print("DuckDuckGo lookup failed ...")` | `DevLogger().warning('WebSearchService', ...)` | warning |
| `lib/controllers/translation_controller.dart` | 370 | `debugPrint('Error reading history: $e')` | keep + `_logger.warning('TranslationController', ...)` | warning |
| `lib/controllers/translation_controller.dart` | 385 | `debugPrint('Error saving history: $e')` | keep + `_logger.error('TranslationController', ...)` | error |
| `lib/controllers/translation_controller.dart` | 407 | `print("Error parsing AI glossary CSV: $e")` | `_logger.warning('TranslationController', ...)` | warning |
| `lib/controllers/translation_controller.dart` | 434 | `print("Error parsing existing glossary CSV: $e")` | `_logger.warning('TranslationController', ...)` | warning |
| `lib/controllers/translation_controller.dart` | 532 | `print("Error enriching glossary: $e")` | `_logger.warning('TranslationController', ...)` | warning |
| `lib/ui/screens/dictionary_screen.dart` | 69 | `catch (_) {}` | `catch (e) { DevLogger().warning('DictionaryScreen', ...) }` | warning |
| `lib/ui/screens/dictionary_screen.dart` | 89 | `debugPrint('Error loading dictionaries: $e')` | keep + `DevLogger().error('DictionaryScreen', ...)` | error |
| `lib/ui/screens/translate_screen.dart` | 1160 | `debugPrint("Error picking dictionary: $e")` | keep + `DevLogger().warning('TranslateScreen', ...)` | warning |
| `lib/ui/screens/settings_screen.dart` | 201 | `debugPrint('Error checking installed models: $e')` | keep + `DevLogger().warning('SettingsScreen', ...)` | warning |
| `lib/ui/screens/history_screen.dart` | 116 | `debugPrint('Error loading history: $e')` | keep + `DevLogger().warning('HistoryScreen', ...)` | warning |

After the fix: `lib/services/`, `lib/controllers/`, `lib/models/` contain zero `print(` callsites. UI screens may still contain `debugPrint(` (verbose dev trace) but every error/warning path also has a `DevLogger.*` callsite.

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate each bug on unfixed code, then verify the fix works correctly and preserves existing behavior. All tests run under the existing `flutter_test` framework — no new dependencies are introduced.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate each bug BEFORE implementing the fix. Confirm or refute the root cause analysis. If a hypothesis is refuted, re-hypothesize.

**Test Plan**: For each bug, write a minimal test that exercises only the buggy code path on the UNFIXED implementation, observe the failure, and use the failure shape to confirm the root cause.

**Test Cases**:

1. **Bug #1 quadratic counterexample** (will fail on unfixed code):
   Construct a fake AI response of three valid lines and call a thin wrapper that runs the same parser logic as `generateGlossary`. Assert `outputRows.length == 3`. On unfixed code, observe `outputRows.length == 9` (3 × 3) — confirms quadratic duplication via nested loop.
2. **Bug #2 throttle counterexample** (will fail on unfixed code):
   Run the translation loop with a stubbed `_aiService.translateChunk` that returns instantly, on a 20-chunk synthetic input, and instrument `TranslationProgress.saveToFile` to count calls. Assert `saveCalls <= ceil(20/5) + 1 == 5`. On unfixed code, observe `saveCalls == 20` — confirms per-chunk save.
3. **Bug #2 atomicity counterexample** (manual; will fail on unfixed code):
   Run a real translation, send `Ctrl+C` (or kill the process) during a save. On unfixed code, observe a truncated JSON file that fails `loadFromFile`. The fix's temp+rename pattern eliminates this window.
4. **Bug #3 callsite scan counterexample** (will fail on unfixed code):
   Run `flutter analyze` with `avoid_print: error` enabled, OR a simple `grep -nP '\bprint\(' lib/services lib/controllers lib/models`. On unfixed code, expect 5 hits (`translation_progress.dart:63`, `web_search_service.dart:19,29`, `translation_controller.dart:407,434,532`). After fix: 0 hits.
5. **Bug #4 MSIX path counterexample** (will fail on unfixed code on any non-D-drive machine):
   Run `flutter pub run msix:create` from a CI runner / second developer machine. On unfixed code, build fails with a logo-not-found error referencing `D:\FluxOrigin\...`. After fix: build succeeds.
6. **Bug #5 silent error counterexample** (will fail on unfixed code):
   Inject a CSV file with invalid UTF-8 into the dictionary directory, open the Dictionary screen. On unfixed code, observe `lineCount = 0` AND zero entries in the Dev Logs tab. After fix: warning entry is present.

**Expected Counterexamples**:

- Bug #1: row count = `N²` instead of `N`. Possible causes confirmed: (a) nested loop, (b) mid-iteration `removeWhere`, (c) duplicate emit per outer iteration — all three present.
- Bug #2: save call count proportional to total chunks; partial-write JSON observable on kill.
- Bug #3: `print(` matches in `lib/services/`, `lib/controllers/`, `lib/models/`; `debugPrint` lines in UI screens are silent in release.
- Bug #4: MSIX build fails on any non-D-drive machine with hardcoded-path error.
- Bug #5: invisible failure in Dev Logs.

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed function produces the expected behavior.

**Pseudocode:**

```
FOR ALL input WHERE isBugCondition(input) DO
  CASE input.type OF
    AIResponse:
      result := generateGlossary_fixed(input)
      ASSERT outputRowCount(result) == distinctParseableLines(input).length
    ChunkCompletion (non-boundary):
      ASSERT NOT saveToFileWasCalled(input.chunkIndex)
    ProgressSaveRequest (with mid-write kill):
      ASSERT loadFromFile(input.filePath) is null OR validTranslationProgress
    LogCallsite (services/controllers/models):
      ASSERT NOT containsPrint(input.filePath)
    LogCallsite (ui/screens):
      ASSERT containsDevLoggerCall(input.filePath, sameContext)
    MsixBuildContext:
      ASSERT msixBuild(input.repoPath) succeeds
    DictionaryFileEntry (read fails):
      ASSERT devLoggerWasCalled(input.filePath) AND lineCount == 0
  END CASE
END FOR
```

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed function produces the same result as the original function.

**Pseudocode:**

```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT generateGlossary_original(input)        == generateGlossary_fixed(input)
  ASSERT saveToFile_original(input).fileBytes    == saveToFile_fixed(input).fileBytes
  ASSERT saveCallCount_fixed(input)              == saveCallCount_original(input)
                                                    on pause/error/final
  ASSERT existingDevLoggerCalls_original(input)  == existingDevLoggerCalls_fixed(input)
  ASSERT dictionaryListEntry_original(input)     == dictionaryListEntry_fixed(input)
  ASSERT flutterRun_original(input)              == flutterRun_fixed(input)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking on `generateGlossary` and `saveToFile` because:

- It generates many test cases automatically across the input domain (random AI responses, random `TranslationProgress` shapes).
- It catches edge cases manual unit tests miss (e.g., quoted commas in the AI response, very large rawChunks arrays).
- It provides strong guarantees that behavior is unchanged for all non-buggy inputs.

For Bug #3, #4, #5 the preservation check is a static / single-shot integration check rather than a property-based check.

**Test Plan**: Observe behavior on UNFIXED code for non-buggy inputs (single-line glossary, well-formed CSV, normal `flutter run`, normal MSIX build on the original D-drive), record outputs, then re-run on FIXED code and compare byte-for-byte.

**Test Cases**:

1. **Glossary single-line preservation**: Feed a single well-formed line through both old and new `generateGlossary`. Assert byte-equal output.
2. **Glossary empty/header-only preservation**: Feed empty / header-only / unparseable input. Assert both return empty / whitespace-only string.
3. **saveToFile JSON preservation**: For 1000 randomly-generated `TranslationProgress` instances, assert `oldImpl(p).bytes == newImpl(p).bytes` (i.e., the temp+rename change does not alter the JSON content).
4. **Throttle boundary preservation**: For runs ending exactly on a multiple of N (e.g., 25 chunks with N=5), and for runs that pause/error mid-throttle window, assert progress state is recoverable from the file.
5. **DevLogger non-regression**: For every existing `DevLogger.*` callsite, assert it still fires with the same category, level, and message after the fix.
6. **DictionaryScreen happy-path preservation**: For a well-formed CSV, assert the rendered list entry has the same `{name, entries, fileSize, path}` shape.
7. **flutter run preservation**: After the `pubspec.yaml` change, `flutter run -d windows` boots the app, splashes, loads assets, and translates a small file end-to-end identically.
8. **Existing test suite preservation**: `flutter test` continues to pass `ai_service_refactor_test.dart`, `text_processor_test.dart`, `verify_web_search.dart`, `widget_test.dart` without modification (Requirement 3.11).

### Unit Tests

- **AIService.generateGlossary**:
  - Empty response → empty string.
  - Single valid line → single CSV row.
  - 3 distinct lines → exactly 3 CSV rows (no duplication).
  - 3 lines with one exact duplicate → 2 CSV rows (deduped by `original`).
  - Header-only response → empty string.
  - Response with mixed valid lines and headers → only valid lines emitted.
- **TranslationProgress.saveToFile / loadFromFile**:
  - Save then load round-trip equals input.
  - Saving over an existing file produces the new content (temp file is cleaned up).
  - Saving when temp file already exists from a crashed previous run still succeeds (overwrite the orphan temp).
- **TranslationController throttle**:
  - 5 chunks with `N=5`: exactly 1 throttled save + 0 boundary saves (final delete handles the end).
  - 7 chunks with `N=5`: exactly 1 throttled save (at chunk 5) + final-completion path handles 6 and 7 by deleting the file post-merge.
  - Pause at chunk 3 with `N=5`: exactly 1 mandatory save (the pause flush).
  - Error at chunk 3 with `N=5`: exactly 1 mandatory save (the error flush) before rethrow.
- **DictionaryScreen**:
  - CSV with unreadable bytes → `lineCount = 0` AND `DevLogger.warning` entry present.
  - Well-formed CSV → `lineCount` equals non-empty line count, no logger entry.
- **Logging migration**:
  - Static check: zero `print(` callsites in `lib/services/`, `lib/controllers/`, `lib/models/`.
  - Static check: every `debugPrint(` in `lib/ui/screens/` has a sibling `DevLogger.` call within the same `catch` block.

### Property-Based Tests

- **Property 1 (generateGlossary)**: For random AI responses sampled from a grammar that mixes valid CSV lines, header lines, malformed lines, and quoted commas, the output row count never exceeds the count of distinct-by-`original` parseable lines.
- **Property 2 (throttle bound)**: For random `(total, N)` pairs with `1 <= total <= 500` and `1 <= N <= 50`, the number of `saveToFile` calls during a clean run is exactly `floor(total / N)` (or `floor(total / N) + 1` if the final chunk is also a boundary), plus zero pause/error/final saves.
- **Property 3 (atomic write)**: For random JSON payloads, after `saveToFile` returns, the file content equals the payload byte-for-byte; if a write is simulated to fail mid-flight (by stubbing the temp-write to throw), the original file (if any) is unchanged.
- **Property 6 (preservation byte-equality)**: For random `TranslationProgress` instances, `saveToFile_old(p).bytes == saveToFile_new(p).bytes`.

### Integration Tests

- **End-to-end translation run** (manual or automated): Translate a 100-chunk synthetic `.txt` file using a stubbed AI service. Assert: glossary CSV has no duplicate rows, progress file is written ≤ 21 times, killing the process at any point leaves the file in a consistent state, all `DevLogger` events are visible in the Dev Logs tab.
- **MSIX build smoke test**: On a fresh clone (no `D:\FluxOrigin` directory present), run `flutter pub run msix:create` and assert it succeeds. Inspect the generated MSIX manifest for the embedded logo.
- **Dev Logs tab visibility**: Trigger each migrated error path (corrupt progress JSON, failing Wikipedia lookup, malformed glossary CSV, unreadable dictionary file, history file corruption) and assert each emits a Dev Logs entry with the documented category and level.
- **Resume-from-progress**: Start a translation, pause at chunk 7 (with `N=5`, last save was at chunk 5), close the app, reopen, hit Resume. Assert it picks up at chunk 6 (i.e., the pause save was the source of truth) and the final output is byte-identical to a non-paused run.
