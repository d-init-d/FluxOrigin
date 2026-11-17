import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_origin/services/ai_service.dart';
import 'package:flux_origin/services/d_transcreate_service.dart';
import 'package:flux_origin/services/epub_pipeline_service.dart';
import 'package:flux_origin/services/qa_verifier_service.dart';
import 'package:flux_origin/utils/file_parser.dart';
import 'package:flux_origin/utils/term_miner.dart';
import 'package:path/path.dart' as path;

void main() {
  group('D-Transcreate v1.1.0 WholeBookTermMiner', () {
    test('mines recurring proper nouns, CJK brackets, acronyms, and strips stopwords', () {
      final chunks = [
        'Inside Silver Spire, Captain Vane studied the EBITDA report and 《九阳真经》.',
        'At dusk inside Silver Spire, Captain Vane met 「太虚宗」 elders using EBITDA metrics.',
        'The *Chrono Blade* shimmered near Silver Spire beside *Chrono Blade* runes.',
      ];

      final mined = WholeBookTermMiner.mineTerms(chunks, minFreq: 2);
      final termNames = mined.map((m) => m.term).toList();

      expect(termNames, contains('Silver Spire'));
      expect(termNames, contains('Captain Vane'));
      expect(termNames, contains('EBITDA'));
      expect(termNames, contains('九阳真经'));
      expect(termNames, contains('太虚宗'));
      expect(termNames, contains('Chrono Blade'));
      expect(termNames.any((t) => t.startsWith('Inside ')), isFalse,
          reason: 'Leading English prepositions/stopwords must be stripped');
    });
  });

  group('D-Transcreate v1.1.0 Service (Tier-1 Memory, Domain Filter, Slicing & Workspace)', () {
    late Directory tmpDir;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('flux_dtranscreate_test_');
    });

    tearDown(() async {
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
    });

    test('domainForGenre & source-filtered Tier-1 memory block cross-domain bleed', () async {
      expect(DTranscreateService.domainForGenre('KIEMHIEP'), equals('fiction'));
      expect(DTranscreateService.domainForGenre('KYTHUAT'), equals('technical'));
      expect(DTranscreateService.domainForGenre('PHAPLY'), equals('legal'));

      final service = DTranscreateService();
      const techSource =
          'Prologue\nTo prevent a Deadlock and improve Latency or Throughput, apply Idempotency and enforce a strict Rate limit. Avoid Artifact fantasy lore.';
      final techSeed = await service.buildDomainSeededCsv(
        sourceText: techSource,
        domain: 'technical',
        targetLanguage: 'Tiếng Việt',
      );

      expect(techSeed, contains('Idempotency'));
      expect(techSeed, contains('Tính lũy đẳng'));
      expect(techSeed, contains('Deadlock'));
      expect(techSeed, contains('Khóa chết'));
      // Artifact belongs to fiction domain (fantasy/museum), must NOT bleed into technical seeding
      expect(techSeed.contains('Cổ vật'), isFalse);
    });

    test('sliceGlossaryForChunk filters to relevant chunk terms', () {
      const fullCsv = '"Captain Vane","Thuyền trưởng Vane","Leader"\n'
          '"Silver Spire","Tháp Bạc","Citadel"\n'
          '"Unrelated Sword","Vô Danh Kiếm","Not in chunk"';

      final sliced = DTranscreateService.sliceGlossaryForChunk(
        fullCsv,
        'Captain Vane entered the base of Silver Spire quietly.',
        maxFallbackRows: 0,
      );

      expect(sliced, contains('Captain Vane'));
      expect(sliced, contains('Silver Spire'));
      expect(sliced.contains('Unrelated Sword'), isFalse);
    });

    test('exportWorkspaceArtifacts emits audit-ready D-Transcreate v1.1.0 workspace', () async {
      final service = DTranscreateService();
      final srcFile = path.join(tmpDir.path, 'Novel One.txt');
      final chunks = ['Prologue text by Captain Vane.'];
      final translated = ['Lời mở đầu của Thuyền trưởng Vane.'];
      final report = QaVerifierService.verifyBook(
        rawChunks: chunks,
        translatedChunks: translated,
        sourceLanguage: 'Tiếng Anh',
        targetLanguage: 'Tiếng Việt',
        glossaryCsv: '"Captain Vane","Thuyền trưởng Vane"',
      );

      final wsPath = await service.exportWorkspaceArtifacts(
        projectPath: tmpDir.path,
        sourcePath: srcFile,
        targetLanguage: 'Tiếng Việt',
        sourceLanguage: 'Tiếng Anh',
        genre: 'FANTASY',
        styleGuide: 'Consistent voice.',
        glossaryCsv: '"Captain Vane","Thuyền trưởng Vane"',
        rawChunks: chunks,
        translatedChunks: translated,
        minedTerms: const [
          CandidateTerm(
              term: 'Captain Vane',
              category: 'proper-phrase',
              count: 4,
              firstChunkIndex: 0),
        ],
        qaReport: report,
      );

      expect(wsPath, isNotNull);
      expect(File(path.join(wsPath!, 'translation-brief.md')).existsSync(), isTrue);
      expect(File(path.join(wsPath, 'source-map.md')).existsSync(), isTrue);
      expect(File(path.join(wsPath, 'research-dossier.md')).existsSync(), isTrue);
      expect(File(path.join(wsPath, 'style-sheet.md')).existsSync(), isTrue);
      expect(File(path.join(wsPath, 'glossary.csv')).existsSync(), isTrue);
      expect(File(path.join(wsPath, 'chunk-manifest.csv')).existsSync(), isTrue);
      expect(File(path.join(wsPath, 'qa-report.md')).existsSync(), isTrue);
      expect(File(path.join(wsPath, 'source_chunks', 'chunk-001.md')).existsSync(), isTrue);
      expect(File(path.join(wsPath, 'output', 'chunk-001.md')).existsSync(), isTrue);
    });
  });

  group('Anchor-Locked Layout-Preserving EPUB Engine', () {
    late Directory tmpDir;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('flux_epub_test_');
    });

    tearDown(() async {
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
    });

    test('scanEpub -> split paragraphs + inline footnotes + table cells -> rebuildTranslatedEpub', () async {
      final epubPath = path.join(tmpDir.path, 'sample.epub');
      final archive = Archive();
      final mime = utf8.encode('application/epub+zip');
      archive.addFile(ArchiveFile.noCompress('mimetype', mime.length, mime));

      void addStr(String name, String data) {
        final b = utf8.encode(data);
        archive.addFile(ArchiveFile(name, b.length, b));
      }

      addStr('META-INF/container.xml', '''<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');

      addStr('OEBPS/package.opf', '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Anchor Lock Test</dc:title>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="css" href="style.css" media-type="text/css"/>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
  </spine>
</package>''');

      addStr('OEBPS/style.css', 'p.dialogue-para { font-style: italic; }');

      addStr('OEBPS/ch1.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><link rel="stylesheet" href="style.css"/></head>
<body>
  <h2 class="subhead">Part Two: The Ledger</h2>
  <p id="p1" class="dialogue-para">“Wait![1]” she shouted. “Where is the ledger?” <a id="ref1" href="notes.xhtml#fn1" epub:type="noteref"><sup>1</sup></a></p>
  <table><tr><th>Item</th><td>Brass Compass</td></tr></table>
</body>
</html>''');

      await File(epubPath).writeAsBytes(ZipEncoder().encode(archive)!);

      final pipeline = EpubPipelineService();
      final scan = await pipeline.scanEpub(epubPath, targetChunkChars: 4000);

      expect(scan.anchoredChunks, hasLength(1));
      expect(scan.anchoredChunks.first, contains('<!-- @b0 -->'));
      expect(scan.anchoredChunks.first, contains('[1](notes.xhtml#fn1)'));
      expect(scan.blockRefs.length, equals(4)); // h2, p, th, td

      // Simulate translation with split Vietnamese dialogue & exclamation before footnote link
      const translatedChunk = '''<!-- @b0 -->
Phần Hai: Cuốn Sổ Cái

<!-- @b1 -->
— Khoan đã![1](notes.xhtml#fn1) — Cô hét lên.

— Cuốn sổ cái đâu rồi?

— Trả lời ngay!

<!-- @b2 -->
Vật phẩm

<!-- @b3 -->
La bàn bằng đồng''';

      final rebuiltBytes = await pipeline.rebuildTranslatedEpub(
        sourceEpubPath: epubPath,
        blockRefs: scan.blockRefs,
        chunkBlockIds: scan.chunkBlockIds,
        translatedChunks: [translatedChunk],
        targetLanguageName: 'Tiếng Việt',
      );

      final rebuiltArchive = ZipDecoder().decodeBytes(rebuiltBytes);
      expect(rebuiltArchive.files.first.name, equals('mimetype'));

      final opfOut = utf8.decode(
          rebuiltArchive.findFile('OEBPS/package.opf')!.content as List<int>);
      expect(opfOut, contains('<dc:language>vi</dc:language>'));

      final xhtmlOut = utf8.decode(
          rebuiltArchive.findFile('OEBPS/ch1.xhtml')!.content as List<int>);
      expect(xhtmlOut, contains('<h2 class="subhead">Phần Hai: Cuốn Sổ Cái</h2>'));
      expect(xhtmlOut, contains('<a id="ref1" href="notes.xhtml#fn1" epub:type="noteref"><sup>1</sup></a>'));
      expect(RegExp('id="p1"').allMatches(xhtmlOut).length, equals(1),
          reason: 'Cloned split paragraphs must strip duplicate id attributes');
      expect(RegExp('class="dialogue-para"').allMatches(xhtmlOut).length, equals(3),
          reason: 'All 3 split dialogue turns must preserve original CSS class');
      expect(xhtmlOut, contains('<th>Vật phẩm</th><td>La bàn bằng đồng</td>'));
      expect(xhtmlOut.contains('@b0'), isFalse);
      expect(EpubPipelineService.stripBlockAnchors(translatedChunk).contains('@b0'), isFalse);
    });

    test('buildCleanEpubFromText produces valid EPUB archive from text', () {
      final bytes = EpubPipelineService.buildCleanEpubFromText(
        title: 'Sách Kiểm Thử',
        content: '# Chương Một\n\nĐoạn văn thứ nhất.',
        targetLanguageName: 'Tiếng Việt',
      );
      final decoded = ZipDecoder().decodeBytes(bytes);
      final ch = utf8.decode(
          decoded.findFile('OEBPS/content.xhtml')!.content as List<int>);
      final opf = utf8.decode(
          decoded.findFile('OEBPS/package.opf')!.content as List<int>);

      expect(opf, contains('<dc:language>vi</dc:language>'));
      expect(ch, contains('<h1>Chương Một</h1>'));
      expect(ch, contains('<p>Đoạn văn thứ nhất.</p>'));
    });
  });

  group('QaVerifierService Deterministic QA', () {
    test('detects script leakage, formal data mismatch, glossary drift & locale calques', () {
      final report = QaVerifierService.verifyBook(
        rawChunks: [
          'In 2026, Captain Vane visited https://example.org with 500 soldiers.',
          'Another paragraph about clean prose.',
        ],
        translatedChunks: [
          'Vào năm 2025, 队长 đã đến thăm nơi khác cùng một cách một cách một cách.',
          'Một đoạn văn ổn.',
        ],
        sourceLanguage: 'Tiếng Anh',
        targetLanguage: 'Tiếng Việt',
        glossaryCsv: '"Captain Vane","Thuyền trưởng Vane"',
      );

      expect(report.passed, isFalse);
      expect(report.errorCount, greaterThanOrEqualTo(0));
      final gates = report.issues.map((i) => i.gate).toSet();
      expect(gates, contains('formal-data')); // missing URL & 2026
      expect(gates, contains('glossary-compliance')); // missing Thuyền trưởng Vane
      expect(gates, contains('script-leakage')); // leftover CJK 队长
    });
  });

  group('AIService BYOK URL Builders, Key Rotation Parsing & Masking', () {
    test('builds correct provider URLs without double /v1', () {
      expect(
        AIService.buildOpenAiChatUrl('https://api.openai.com/v1'),
        equals('https://api.openai.com/v1/chat/completions'),
      );
      expect(
        AIService.buildOpenAiChatUrl('https://api.openai.com/'),
        equals('https://api.openai.com/v1/chat/completions'),
      );
      expect(
        AIService.buildOpenAiChatUrl(
            'https://generativelanguage.googleapis.com/v1beta/openai'),
        equals(
            'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions'),
      );
      expect(
        AIService.buildAnthropicMessagesUrl('https://api.anthropic.com'),
        equals('https://api.anthropic.com/v1/messages'),
      );
      expect(
        AIService.buildAnthropicModelsUrl('https://api.anthropic.com/v1'),
        equals('https://api.anthropic.com/v1/models'),
      );
    });

    test('parses multi-line/comma BYOK keys and masks secrets safely', () {
      final keys = AIService.parseApiKeys(
          'sk-key-alpha\nsk-key-beta, sk-key-alpha; sk-key-gamma\n');
      expect(keys, equals(['sk-key-alpha', 'sk-key-beta', 'sk-key-gamma']));
      expect(AIService.maskApiKey('sk-proj-1234567890abcd'),
          equals('sk-p***abcd'));
      expect(AIService.maskApiKey('short'), equals('***'));
    });
  });

  group('Multi-format FileParser (PDF FlateDecode & Markdown)', () {
    test('extracts compressed FlateDecode PDF streams and strips repeating headers', () {
      final pages = [
        'JOURNAL HEADER\nBT /F1 12 Tf 72 700 Td (First page paragraph.) Tj ET\n1',
        'JOURNAL HEADER\nBT /F1 12 Tf 72 700 Td (Second page paragraph.) Tj ET\n2',
        'JOURNAL HEADER\nBT /F1 12 Tf 72 700 Td (Third page paragraph.) Tj ET\n3',
      ];

      final pdfBuf = StringBuffer('%PDF-1.4\n');
      for (final p in pages) {
        final compressed = zlib.encode(latin1.encode('BT\n$p\nET'));
        pdfBuf.write('1 0 obj\n<< /Length ${compressed.length} /Filter /FlateDecode >>\nstream\n');
        pdfBuf.write(latin1.decode(compressed));
        pdfBuf.write('\nendstream\nendobj\n');
      }

      final extracted = FileParser.extractTextFromPdfBytes(latin1.encode(pdfBuf.toString()));
      expect(extracted, contains('First page paragraph.'));
      expect(extracted, contains('Second page paragraph.'));
      expect(extracted, contains('Third page paragraph.'));
    });

    test('extractTextFromEpub reads EPUB cleanly without legacy epubx', () async {
      final tmpDir = await Directory.systemTemp.createTemp('flux_epub_parse_');
      try {
        final epubFile = File(path.join(tmpDir.path, 'sample.epub'));
        final bytes = EpubPipelineService.buildCleanEpubFromText(
          title: 'Kiểm Thử EPUB',
          content: '# Chương Một\n\nNội dung thuần Dart ổn định.',
          targetLanguageName: 'Tiếng Việt',
        );
        await epubFile.writeAsBytes(bytes, flush: true);

        final text = await FileParser.extractTextFromEpub(epubFile.path);
        expect(text, contains('Chương Một'));
        expect(text, contains('Nội dung thuần Dart ổn định.'));

        await expectLater(
          FileParser.extractTextFromEpub(path.join(tmpDir.path, 'missing.epub')),
          throwsException,
        );
      } finally {
        if (await tmpDir.exists()) {
          await tmpDir.delete(recursive: true);
        }
      }
    });
  });
}
