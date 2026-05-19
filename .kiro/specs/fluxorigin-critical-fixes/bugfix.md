# Bugfix Requirements Document

## Introduction

A code audit of FluxOrigin v2.0.2 (Flutter Windows desktop AI book translator) surfaced five defects ranging from a critical correctness bug in glossary generation down to silent error swallowing in the dictionary UI. They are bundled into a single bugfix spec because each one is small in scope, none of them changes public APIs, and they share the same regression surface (the translation pipeline and the dev-logging story).

The bugs and their headline impacts:

- **Bug #1 (Critical)** — `AIService.generateGlossary` duplicates every parsed glossary entry N times due to a double-loop with mid-iteration list mutation, polluting every subsequent translation prompt with bloated CSV.
- **Bug #2 (High)** — `TranslationController` serializes the full progress JSON to disk on every chunk, causing I/O throttling, unnecessary SSD wear, and a corruption window if the user kills the process mid-write.
- **Bug #3 (Medium)** — Inconsistent logging: `print()` and `debugPrint()` are mixed with the canonical `DevLogger`, so production errors disappear and the in-app Dev Logs tab misses important events.
- **Bug #4 (Medium)** — `pubspec.yaml` MSIX config has a hardcoded absolute path (`D:\FluxOrigin\assets\fluxorigin logo.png`) that breaks `flutter pub run msix:create` for any contributor cloning the repo.
- **Bug #5 (Low)** — `DictionaryScreen` swallows file-read errors with `catch (_) {}`, hiding malformed-CSV problems from the user.

The fix must hold the public API of `AIService`, `TranslationController`, `TranslationProgress`, `WebSearchService`, and `DictionaryScreen` stable so no caller in the UI layer breaks.

## Bug Analysis

### Current Behavior (Defect)

What currently happens when the bugs are triggered:

1.1 WHEN `AIService.generateGlossary` receives an AI response containing N ≥ 2 valid glossary lines THEN the system writes approximately N × N rows into `cleanBuffer`, because the outer `for (final line in lines)` loop runs N times and on each iteration the inner `for (var i = 0; i < lines.length; i++)` loop re-parses and re-emits every remaining entry.

1.2 WHEN `AIService.generateGlossary` executes its outer loop body THEN the system calls `lines.removeWhere(...)` against the same `lines` list it is iterating, which is a concurrent-modification hazard against the outer iterator and re-runs the header filter once per line instead of once per response.

1.3 WHEN `AIService.generateGlossary` returns and its output is consumed by `TranslationController` to build the running glossary CSV THEN every subsequent `translateChunk` prompt embeds the duplicated CSV, inflating prompt token usage and degrading model behavior for the rest of the book.

1.4 WHEN the translation loop in `TranslationController` finishes any chunk (line ~310) THEN the system calls `await progress.saveToFile(progressPath)` after every single chunk, serializing the full `rawChunks` and `translatedChunks` arrays with `flush: true` on each call.

1.5 WHEN the user kills the process while `progress.saveToFile` is mid-write THEN the system can leave the JSON progress file in a partially-written, corrupt state because the write is non-atomic (no temp-file-and-rename).

1.6 WHEN error or warning events occur in `lib/models/translation_progress.dart:63`, `lib/controllers/translation_controller.dart:407,434,532`, or `lib/services/web_search_service.dart:19,29` THEN the system invokes bare `print(...)` calls that write to stdout, bypass `DevLogger`, do not appear in the in-app Dev Logs tab, and trigger the `avoid_print` lint.

1.7 WHEN error or warning events occur in `lib/ui/screens/translate_screen.dart:1160`, `settings_screen.dart:201`, `history_screen.dart:116`, `dictionary_screen.dart:89`, or `lib/controllers/translation_controller.dart:370,385` THEN the system uses `debugPrint(...)` which is silenced in release builds and never reaches `DevLogger`, so production error paths leave no in-app trace.

1.8 WHEN a contributor clones the repository on any machine other than the original developer's THEN the system reads `logo_path: D:\FluxOrigin\assets\fluxorigin logo.png` from `pubspec.yaml` and `flutter pub run msix:create` fails because that absolute path does not exist on the contributor's filesystem.

1.9 WHEN a CSV dictionary file in the user's dictionary directory is unreadable, malformed, or raises any exception during `file.readAsString()` in `DictionaryScreen._loadDictionaries` (line ~69) THEN the system catches the exception with `} catch (_) {}` and silently sets `lineCount = 0`, leaving the user and the Dev Logs tab with no indication that a file failed to load.

### Expected Behavior (Correct)

What should happen instead:

2.1 WHEN `AIService.generateGlossary` receives an AI response containing N valid, distinct glossary lines THEN the system SHALL emit exactly one CSV row per distinct parseable entry, regardless of N, with no quadratic duplication.

2.2 WHEN `AIService.generateGlossary` filters out header lines (`original`, `term`, `từ gốc`, lines starting with `----`) THEN the system SHALL apply that filter exactly once before parsing rather than re-running it inside every iteration of the parse loop, and SHALL not mutate the list it is currently iterating with a `for-in` loop.

2.3 WHEN `AIService.generateGlossary` produces its output and `TranslationController` later builds the glossary CSV used in subsequent `translateChunk` prompts THEN the system SHALL pass through a CSV that contains each unique `"original","vietnamese"` row at most once, so prompt size grows linearly with vocabulary instead of quadratically.

2.4 WHEN the translation loop in `TranslationController` completes a chunk THEN the system SHALL persist progress at most once every N chunks where N is configurable with a default of 5, AND SHALL always persist on pause, error, manual stop, and final completion regardless of N, so no completed work is lost.

2.5 WHEN `TranslationProgress.saveToFile` writes the progress JSON THEN the system SHALL use an atomic write pattern (write the full payload to a temporary sibling file, flush it, then rename it over the destination) so a process kill during write cannot leave the destination file partially written or corrupt.

2.6 WHEN error or warning events occur in any non-UI code under `lib/services/`, `lib/controllers/`, or `lib/models/` THEN the system SHALL route them through `DevLogger().error(...)`, `DevLogger().warning(...)`, or `DevLogger().info(...)` with a meaningful category string, and SHALL NOT use bare `print(...)` for those error paths.

2.7 WHEN error events occur in UI screens under `lib/ui/screens/` THEN the system SHALL also call `DevLogger().error(...)` or `DevLogger().warning(...)` for the error path, with `debugPrint(...)` permitted only as an additional verbose dev-only trace alongside the `DevLogger` call.

2.8 WHEN a contributor on any machine runs `flutter pub run msix:create` after cloning the repo THEN the system SHALL resolve `msix_config.logo_path` from `pubspec.yaml` against a workspace-relative location that exists in the repo (specifically `assets/fluxorigin logo.png`, which is already committed) so the build succeeds without per-developer path patching.

2.9 WHEN `DictionaryScreen._loadDictionaries` fails to read a CSV file's contents to count lines THEN the system SHALL log the error via `DevLogger().warning('DictionaryScreen', 'Failed to count lines for $filePath: $e')` so the failure is visible in the Dev Logs tab, AND SHALL still gracefully fall back to `lineCount = 0` so the dictionary list view continues to render.

### Unchanged Behavior (Regression Prevention)

Existing behavior that must be preserved:

3.1 WHEN `AIService.generateGlossary` receives an AI response with zero valid glossary lines (empty response, only headers, or only un-parseable lines) THEN the system SHALL CONTINUE TO return an empty (or whitespace-only) string, matching the pre-fix behavior for the empty case.

3.2 WHEN `AIService.generateGlossary` parses a single well-formed line containing both an original term and a Vietnamese translation THEN the system SHALL CONTINUE TO emit that line as `"original","vietnamese"` using the existing CSV-with-fallback parsing logic (CSV → `:` split → ` - ` split → `-` split, with the 100-character Vietnamese length filter still applied).

3.3 WHEN `TranslationController` runs the translation loop and a chunk completes successfully THEN the system SHALL CONTINUE TO update `progress.translatedChunks[i]`, call `onChunkUpdate`, refresh `previousContext` from the last sentences, and emit the same logging events to `DevLogger` that it does today.

3.4 WHEN `TranslationController` is paused, encounters an error in a chunk, or finishes the final chunk THEN the system SHALL CONTINUE TO write the progress file before returning or rethrowing, so resume-from-progress still works for users who killed the app mid-translation.

3.5 WHEN `TranslationProgress.saveToFile` is called and completes successfully THEN the system SHALL CONTINUE TO produce a progress file whose JSON content is byte-for-byte equivalent to the current implementation's output for the same `TranslationProgress` instance, so existing progress files remain readable by `loadFromFile` and resuming from any pre-fix file still works.

3.6 WHEN any code path that previously logged via `DevLogger` runs THEN the system SHALL CONTINUE TO produce the same `DevLogger` entries with the same category and level, so the Dev Logs tab does not lose any events that were already being recorded.

3.7 WHEN `DevLogger` is invoked in release builds THEN the system SHALL CONTINUE TO honor `DevLogger().setEnabled(...)` and the existing `_maxLogs = 1000` ring-buffer trimming, so adding new `DevLogger` callsites does not change overall logger behavior or memory profile.

3.8 WHEN the developer runs the app via `flutter run` (i.e., not building MSIX) THEN the system SHALL CONTINUE TO start, render the splash, load assets, and run translations exactly as before, because the MSIX `logo_path` change does not affect the regular Flutter asset pipeline.

3.9 WHEN `DictionaryScreen._loadDictionaries` reads a normal, well-formed CSV file in the dictionary directory THEN the system SHALL CONTINUE TO compute `lineCount` as the number of non-empty lines, format `fileSize` in MB or KB using the existing thresholds, and append the dictionary entry to the rendered list with the same shape `{name, entries, fileSize, path}`.

3.10 WHEN any of the affected classes (`AIService`, `TranslationController`, `TranslationProgress`, `WebSearchService`, `DictionaryScreen`) are referenced from existing screens (`translate_screen.dart`, `history_screen.dart`, `dictionary_screen.dart`, `settings_screen.dart`) THEN the system SHALL CONTINUE TO expose the same public method signatures and return types, so no caller in `lib/ui/` requires changes to keep compiling.

3.11 WHEN the existing test suite under `test/` (`ai_service_refactor_test.dart`, `text_processor_test.dart`, `verify_web_search.dart`, `widget_test.dart`) runs against the fixed code THEN the system SHALL CONTINUE TO pass every currently-passing test without modification, except for tests that explicitly assert the buggy behavior (none expected).
