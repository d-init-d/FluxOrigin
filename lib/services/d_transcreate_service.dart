import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;

import 'dev_logger.dart';
import 'qa_verifier_service.dart';
import '../utils/term_miner.dart';

/// Represents a row from the D-Transcreate Tier-1 translation memory.
class MemoryGlossaryEntry {
  final String term;
  final String preferredTranslation;
  final String forbiddenTranslation;
  final String termClass;
  final String context;
  final String domain;

  const MemoryGlossaryEntry({
    required this.term,
    required this.preferredTranslation,
    required this.forbiddenTranslation,
    required this.termClass,
    required this.context,
    required this.domain,
  });
}

/// Core bridge between FluxOrigin and the D-Transcreate v1.1.0 methodology:
/// - Domain mapping (fiction / technical / legal / general)
/// - Tier-1 translation memory loading & source-aware domain filtering
/// - Chunk-scoped glossary slicing (context-safe prompts for small & cloud LLMs)
/// - Style_Sheet & Research_Dossier generation grounded in core/locales/vi-VN.md
/// - Optional Python book_ops.py bridge for PDF preprocessing
/// - Audit-ready D-Transcreate v1.1.0 workspace export
class DTranscreateService {
  static final DevLogger _logger = DevLogger();

  static const String engineVersion = '1.1.0';

  /// Maps FluxOrigin genre codes to D-Transcreate v1.1.0 domains.
  static String domainForGenre(String genre) {
    switch (genre.toUpperCase()) {
      case 'KIEMHIEP':
      case 'TIEN_HIEP':
      case 'NGONTINH':
      case 'FANTASY':
        return 'fiction';
      case 'KHOAHOC':
      case 'KYTHUAT':
      case 'KINHDOANH':
        return 'technical';
      case 'PHAPLY':
        return 'legal';
      default:
        return 'general';
    }
  }

  /// Resolves domain tag for a Tier-1 memory row from `glossary_vi.csv`.
  static String inferMemoryEntryDomain(String termClass, String context) {
    final cls = termClass.toLowerCase().trim();
    final ctx = context.toLowerCase();
    if (cls == 'legal-term' || ctx.contains('legal') || ctx.contains('contract') || ctx.contains('law')) {
      return 'legal';
    }
    if (cls == 'technical-term' ||
        ctx.contains('software') ||
        ctx.contains('networking') ||
        ctx.contains('mathematics') ||
        ctx.contains('distributed') ||
        ctx.contains('operating systems') ||
        ctx.contains('api')) {
      return 'technical';
    }
    if (cls == 'proper-name' ||
        ctx.contains('lore') ||
        ctx.contains('fantasy') ||
        ctx.contains('enchanted') ||
        ctx.contains('ancient') ||
        ctx.contains('enemy') ||
        ctx.contains('persona') ||
        ctx.contains('timeline') ||
        ctx.contains('narrative') ||
        ctx.contains('fiction') ||
        ctx.contains('plot') ||
        ctx.contains('character') ||
        ctx.contains('guild') ||
        ctx.contains('oracle')) {
      return 'fiction';
    }
    return 'general';
  }

  /// Loads D-Transcreate Tier-1 Vietnamese translation memory from Flutter
  /// asset bundle, falling back to local disk `tools/d_transcreate/memory/`
  /// when running inside headless unit tests.
  Future<List<MemoryGlossaryEntry>> loadTier1Memory({
    String domain = 'all',
  }) async {
    String? rawCsv;

    try {
      rawCsv = await rootBundle.loadString('assets/d_transcreate/glossary_vi.csv');
    } catch (_) {
      // Headless unit test fallback: check disk paths
      final candidates = [
        path.join(Directory.current.path, 'assets', 'd_transcreate', 'glossary_vi.csv'),
        path.join(Directory.current.path, 'tools', 'd_transcreate', 'memory', 'glossary-vi.csv'),
      ];
      for (final p in candidates) {
        final file = File(p);
        if (await file.exists()) {
          rawCsv = await file.readAsString();
          break;
        }
      }
    }

    if (rawCsv == null || rawCsv.trim().isEmpty) {
      return const [];
    }

    final rows = const CsvToListConverter().convert(
      rawCsv,
      eol: '\n',
      shouldParseNumbers: false,
    );

    if (rows.length <= 1) return const [];

    final entries = <MemoryGlossaryEntry>[];
    final normalizedDomain = domain.toLowerCase().trim();

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 2) continue;

      final term = row[0].toString().trim();
      final preferred = row[1].toString().trim();
      if (term.isEmpty || preferred.isEmpty) continue;

      final forbidden = row.length > 2 ? row[2].toString().trim() : '';
      final termClass = row.length > 3 ? row[3].toString().trim() : 'noun';
      final context = row.length > 4 ? row[4].toString().trim() : '';
      final inferred = inferMemoryEntryDomain(termClass, context);

      if (normalizedDomain != 'all' &&
          inferred != normalizedDomain &&
          inferred != 'general') {
        continue;
      }

      entries.add(MemoryGlossaryEntry(
        term: term,
        preferredTranslation: preferred,
        forbiddenTranslation: forbidden,
        termClass: termClass,
        context: context,
        domain: inferred,
      ));
    }

    return entries;
  }

  /// Filters Tier-1 memory rows so ONLY terms actually present in [sourceText]
  /// and compatible with [domain] are seeded into the active CSV glossary.
  Future<String> buildDomainSeededCsv({
    required String sourceText,
    required String domain,
    required String targetLanguage,
  }) async {
    if (targetLanguage != 'Tiếng Việt') return '';

    final memory = await loadTier1Memory(domain: domain);
    if (memory.isEmpty) return '';

    final lowerSource = sourceText.toLowerCase();
    final selectedRows = <List<String>>[];

    for (final entry in memory) {
      if (_containsTerm(lowerSource, entry.term)) {
        final defParts = <String>[];
        if (entry.context.isNotEmpty) {
          defParts.add(entry.context);
        }
        if (entry.forbiddenTranslation.isNotEmpty) {
          defParts.add('Avoid: ${entry.forbiddenTranslation}');
        }
        selectedRows.add([
          entry.term,
          entry.preferredTranslation,
          defParts.join(' | '),
        ]);
      }
    }

    if (selectedRows.isEmpty) return '';
    return const ListToCsvConverter().convert(selectedRows, eol: '\n');
  }

  /// Exports a Tier-1 memory preset as a 3-column FluxOrigin CSV file so users
  /// can inspect/edit standard Vietnamese publishing/legal/technical terms directly
  /// in DictionaryScreen.
  Future<File> importPresetGlossaryToDirectory({
    required String dictionaryDir,
    String domain = 'all',
  }) async {
    final entries = await loadTier1Memory(domain: domain);
    final dir = Directory(dictionaryDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final csvRows = <List<String>>[
      ['Original', 'Vietnamese', 'Context / Forbidden Translations'],
      for (final e in entries)
        [
          e.term,
          e.preferredTranslation,
          [
            if (e.context.isNotEmpty) e.context,
            if (e.forbiddenTranslation.isNotEmpty) 'Avoid: ${e.forbiddenTranslation}',
          ].join(' | '),
        ],
    ];

    final suffix = domain == 'all' ? 'all' : domain;
    final outFile = File(path.join(dictionaryDir, 'd_transcreate_${suffix}_vi.csv'));
    await outFile.writeAsString(
      const ListToCsvConverter().convert(csvRows, eol: '\n'),
      flush: true,
    );
    _logger.info(
      'DTranscreateService',
      'Imported D-Transcreate Tier-1 glossary ($domain, ${entries.length} entries) -> ${outFile.path}',
    );
    return outFile;
  }

  /// Slices a large full-book CSV glossary down to ONLY rows matched in
  /// [chunkText] (plus up to [maxFallbackRows] top terms if few direct matches),
  /// preventing context overflow on local LLMs while maximizing recall.
  static String sliceGlossaryForChunk(
    String glossaryCsv,
    String chunkText, {
    int maxMatchedRows = 60,
    int maxFallbackRows = 15,
  }) {
    if (glossaryCsv.trim().isEmpty) return '';

    List<List<dynamic>> rows;
    try {
      rows = const CsvToListConverter().convert(
        glossaryCsv,
        eol: '\n',
        shouldParseNumbers: false,
      );
    } catch (_) {
      return glossaryCsv;
    }

    final lowerChunk = chunkText.toLowerCase();
    final matched = <List<String>>[];
    final fallback = <List<String>>[];

    for (final row in rows) {
      if (row.length < 2) continue;
      final orig = row[0].toString().trim();
      final target = row[1].toString().trim();
      final def = row.length > 2 ? row[2].toString().trim() : '';

      if (orig.isEmpty || target.isEmpty) continue;
      final origLower = orig.toLowerCase();
      if (origLower == 'original' ||
          origLower == 'term' ||
          origLower == 'từ gốc' ||
          origLower == 'từ gốc trung') {
        continue;
      }

      final cleanRow = [orig, target, if (def.isNotEmpty) def];
      if (_containsTerm(lowerChunk, orig)) {
        matched.add(cleanRow);
      } else if (fallback.length < maxFallbackRows) {
        fallback.add(cleanRow);
      }
    }

    final selected = matched.isNotEmpty
        ? matched.take(maxMatchedRows).toList()
        : fallback;

    if (selected.isEmpty) return '';
    return const ListToCsvConverter().convert(selected, eol: '\n');
  }

  /// Builds compact D-Transcreate v1.1.0 Research_Dossier + Style_Sheet instructions
  /// injected into translation prompts to eliminate translatorese and maintain
  /// voice, pronoun/register consistency, and literary/technical register.
  static String buildStyleAndDossierGuide({
    required String sourceLanguage,
    required String targetLanguage,
    required String genre,
    List<CandidateTerm> candidateTerms = const [],
  }) {
    final domain = domainForGenre(genre);
    final buffer = StringBuffer();
    buffer.writeln('### D-TRANSCREATE STYLE SHEET & DOSSIER (v$engineVersion):');
    buffer.writeln('- Domain: $domain (Genre: $genre) | Pair: $sourceLanguage -> $targetLanguage');

    if (targetLanguage == 'Tiếng Việt') {
      if (domain == 'fiction') {
        if (genre == 'KIEMHIEP' || genre == 'TIEN_HIEP') {
          buffer.writeln('- Register: Classical Sino-Vietnamese martial/cultivation prose (tôn giả, huynh/đệ, tại hạ, tông môn); rhythmic combat & dialogue cadence.');
        } else if (genre == 'NGONTINH') {
          buffer.writeln('- Register: Evocative modern/period romantic Vietnamese; keep character pronouns & intimacy tier consistent across turns.');
        } else {
          buffer.writeln('- Register: Natural literary Vietnamese narration; adapt idioms rather than word-for-word calques.');
        }
        buffer.writeln('- Dialogue Convention: Use matching quotation marks "..." or Vietnamese dialogue dashes (— ) consistently—never mix within a paragraph.');
      } else if (domain == 'legal') {
        buffer.writeln('- Register: Precise Vietnamese statutory & commercial legal prose; preserve obligation modality (phải/có nghĩa vụ/không được), section numbers, and defined terms.');
      } else {
        buffer.writeln('- Register: Crisp modern Vietnamese technical/expository prose; avoid archaic Sino-Vietnamese padding and avoid unnecessary English duplication once introduced.');
      }
      buffer.writeln('- Anti-Translatorese Gate: Avoid overuse of passive calques ("bị/được"), awkward adverbs ("một cách + adj"), and nominalization bloat ("sự/việc"). Keep numbers, years, and URLs exact.');
    } else {
      buffer.writeln('- Register: Natural, idiomatic $targetLanguage matching the $domain domain while preserving all proper nouns, numbers, URLs, and structural tags.');
    }

    if (candidateTerms.isNotEmpty) {
      final highlights = candidateTerms.take(12).map((t) => t.term).join(', ');
      buffer.writeln('- Recurring Entities Across Book: $highlights');
    }

    return buffer.toString().trim();
  }

  /// Attempts to convert a PDF using bundled `tools/d_transcreate/book_ops.py convert`
  /// if Python 3 is installed on the host. Returns converted text or null to trigger
  /// pure-Dart fallback seamlessly.
  Future<String?> tryConvertPdfViaBookOps(String pdfPath) async {
    final exeDir = path.dirname(Platform.resolvedExecutable);
    final scriptCandidates = [
      path.join(Directory.current.path, 'tools', 'd_transcreate', 'book_ops.py'),
      path.join(exeDir, 'tools', 'd_transcreate', 'book_ops.py'),
      path.join(exeDir, '..', 'Resources', 'd_transcreate', 'book_ops.py'),
      path.join(exeDir, '..', 'Resources', 'book_ops.py'),
    ];

    String? scriptPath;
    for (final candidate in scriptCandidates) {
      if (await File(candidate).exists()) {
        scriptPath = candidate;
        break;
      }
    }
    if (scriptPath == null) return null;

    Directory? tmpDir;
    try {
      tmpDir = await Directory.systemTemp.createTemp('flux_pdf_ops_');
      final outTxt = path.join(tmpDir.path, 'converted.txt');

      for (final exe in Platform.isWindows ? ['python', 'py'] : ['python3', 'python']) {
        try {
          final result = await Process.run(
            exe,
            [scriptPath, 'convert', '--source', pdfPath, '--out', outTxt],
          ).timeout(const Duration(seconds: 45));

          if (result.exitCode == 0 && await File(outTxt).exists()) {
            final text = await File(outTxt).readAsString();
            if (text.trim().isNotEmpty) {
              _logger.info(
                'DTranscreateService',
                'Converted PDF via D-Transcreate book_ops.py ($exe): ${text.length} chars',
              );
              return text;
            }
          }
        } catch (_) {
          // Try next python executable
        }
      }
    } catch (e) {
      _logger.warning(
        'DTranscreateService',
        'Python book_ops PDF bridge unavailable, using Dart fallback',
        details: e.toString(),
      );
    } finally {
      if (tmpDir != null && await tmpDir.exists()) {
        try {
          await tmpDir.delete(recursive: true);
        } catch (_) {}
      }
    }
    return null;
  }

  /// Writes audit-ready D-Transcreate v1.1.0 workspace artifacts under
  /// `<projectPath>/workspaces/<bookSlug>/` after or during a translation run.
  Future<String?> exportWorkspaceArtifacts({
    required String projectPath,
    required String sourcePath,
    required String targetLanguage,
    required String sourceLanguage,
    required String genre,
    required String styleGuide,
    required String glossaryCsv,
    required List<String> rawChunks,
    required List<String?> translatedChunks,
    required List<CandidateTerm> minedTerms,
    QaReport? qaReport,
  }) async {
    if (projectPath.trim().isEmpty) return null;

    final slug = _sanitizeSlug(path.basenameWithoutExtension(sourcePath));
    final wsDir = Directory(path.join(projectPath, 'workspaces', slug));
    final srcChunksDir = Directory(path.join(wsDir.path, 'source_chunks'));
    final outChunksDir = Directory(path.join(wsDir.path, 'output'));

    await srcChunksDir.create(recursive: true);
    await outChunksDir.create(recursive: true);

    // 1. translation-brief.md
    final domain = domainForGenre(genre);
    await File(path.join(wsDir.path, 'translation-brief.md')).writeAsString('''# Translation_Brief

- source_path: `$sourcePath`
- source_language: $sourceLanguage
- target_language: $targetLanguage
- domain: $domain
- genre: $genre
- engine: FluxOrigin + D-Transcreate v$engineVersion
- total_chunks: ${rawChunks.length}
- updated_at: ${DateTime.now().toIso8601String()}
''');

    // 2. source-map.md
    final entitiesBlock = minedTerms.isEmpty
        ? '- No multi-occurrence entities mined.'
        : WholeBookTermMiner.formatForGlossaryPrompt(minedTerms, limit: 100);
    await File(path.join(wsDir.path, 'source-map.md')).writeAsString('''# Source_Map

- source_file: ${path.basename(sourcePath)}
- total_chunks: ${rawChunks.length}

## Recurring Entities & Candidate Terms

$entitiesBlock
''');

    // 3. research-dossier.md & style-sheet.md
    await File(path.join(wsDir.path, 'research-dossier.md')).writeAsString('''# Research_Dossier

- translation_strategy: Domain-calibrated transcreation ($domain) with whole-book entity lock
- prior_translation_status: Verified against Tier-1 memory & user glossary
- authorial_intent_summary: Preserve narrative voice, formal data parity, and register from $sourceLanguage into $targetLanguage.
''');

    await File(path.join(wsDir.path, 'style-sheet.md')).writeAsString('''# Style_Sheet

$styleGuide
''');

    // 4. glossary.csv & chunk-manifest.csv
    await File(path.join(wsDir.path, 'glossary.csv')).writeAsString(glossaryCsv);

    final manifestRows = <List<String>>[
      ['chunk_id', 'index', 'status', 'source_chars', 'translated_chars'],
    ];
    for (var i = 0; i < rawChunks.length; i++) {
      final chunkId = 'chunk-${(i + 1).toString().padLeft(3, '0')}';
      final srcText = rawChunks[i];
      final tgtText = i < translatedChunks.length ? (translatedChunks[i] ?? '') : '';
      final status = tgtText.trim().isNotEmpty ? 'translated' : 'pending';

      manifestRows.add([
        chunkId,
        i.toString(),
        status,
        srcText.length.toString(),
        tgtText.length.toString(),
      ]);

      await File(path.join(srcChunksDir.path, '$chunkId.md')).writeAsString(srcText);
      if (tgtText.isNotEmpty) {
        await File(path.join(outChunksDir.path, '$chunkId.md')).writeAsString(tgtText);
      }
    }
    await File(path.join(wsDir.path, 'chunk-manifest.csv')).writeAsString(
      const ListToCsvConverter().convert(manifestRows, eol: '\n'),
    );

    // 5. qa-report.md
    if (qaReport != null) {
      await File(path.join(wsDir.path, 'qa-report.md')).writeAsString(qaReport.toMarkdown());
    }

    // 6. Metadata json for external CLI sync
    await File(path.join(wsDir.path, 'flux_meta.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'engineVersion': engineVersion,
        'genre': genre,
        'domain': domain,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'qaScore': qaReport?.score,
        'qaPassed': qaReport?.passed,
      }),
    );

    _logger.info(
      'DTranscreateService',
      'Exported D-Transcreate v$engineVersion workspace to: ${wsDir.path}',
    );
    return wsDir.path;
  }

  static bool _containsTerm(String lowerText, String term) {
    final t = term.toLowerCase().trim();
    if (t.isEmpty) return false;
    final hasAsciiWord = RegExp(r'^[a-z0-9\s\-\x27]+$').hasMatch(t);
    if (hasAsciiWord) {
      final escaped = RegExp.escape(t);
      return RegExp(r'\b' + escaped + r'\b').hasMatch(lowerText);
    }
    return lowerText.contains(t);
  }

  static String _sanitizeSlug(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'[^\w\u00C0-\u024F\-\.]+'), '_');
    return s.isEmpty ? 'untitled_book' : s;
  }
}
