import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

import 'dev_logger.dart';

/// Inline attribute metadata captured from original EPUB XHTML tags (`<a>`, `<sup>`, `<img>`).
class EpubInlineAsset {
  final String kind; // 'link' or 'img'
  final String token;
  final String url;
  final Map<String, String> attrs;
  final bool hasSup;

  const EpubInlineAsset({
    required this.kind,
    required this.token,
    required this.url,
    required this.attrs,
    this.hasSup = false,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'token': token,
        'url': url,
        'attrs': attrs,
        'hasSup': hasSup,
      };

  factory EpubInlineAsset.fromJson(Map<String, dynamic> json) {
    return EpubInlineAsset(
      kind: json['kind'] as String? ?? 'link',
      token: json['token'] as String? ?? '',
      url: json['url'] as String? ?? '',
      attrs: Map<String, String>.from(json['attrs'] as Map? ?? {}),
      hasSup: json['hasSup'] as bool? ?? false,
    );
  }
}

/// Maps a single global block anchor (`<!-- @bN -->`) to its exact XHTML spine file.
class EpubBlockRef {
  final int id;
  final String spineHref;
  final String tagName;
  final List<EpubInlineAsset> inlineAssets;

  const EpubBlockRef({
    required this.id,
    required this.spineHref,
    required this.tagName,
    this.inlineAssets = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'spineHref': spineHref,
        'tagName': tagName,
        'inlineAssets': inlineAssets.map((a) => a.toJson()).toList(),
      };

  factory EpubBlockRef.fromJson(Map<String, dynamic> json) {
    final assetsJson = json['inlineAssets'] as List? ?? const [];
    return EpubBlockRef(
      id: json['id'] as int,
      spineHref: json['spineHref'] as String,
      tagName: json['tagName'] as String,
      inlineAssets: assetsJson
          .map((e) => EpubInlineAsset.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

/// Result of scanning an EPUB into anchor-locked chunks for layout-preserving rebuild.
class EpubScanResult {
  final List<String> anchoredChunks;
  final List<EpubBlockRef> blockRefs;
  final List<List<int>> chunkBlockIds;
  final String fullPlainText;

  const EpubScanResult({
    required this.anchoredChunks,
    required this.blockRefs,
    required this.chunkBlockIds,
    required this.fullPlainText,
  });

  Map<String, dynamic> toMetadataJson() => {
        'blockRefs': blockRefs.map((b) => b.toJson()).toList(),
        'chunkBlockIds': chunkBlockIds,
      };
}

/// Pure-Dart implementation of D-Transcreate v1.1.0 **Anchor-Locked EPUB DOM Mode (`<!-- @bN -->`)**.
///
/// Scans EPUB spine XHTML files into sequential `<!-- @bN -->`-anchored leaf blocks while
/// preserving inline footnotes (`<a epub:type="noteref"><sup>1</sup></a>`) and `<img>` tags,
/// then injects translated paragraphs back into their exact DOM containers—stripping duplicate
/// `id=` attributes when splitting paragraphs and preserving table grids, CSS stylesheets, and fonts.
class EpubPipelineService {
  static final DevLogger _logger = DevLogger();

  static const Set<String> _leafBlockTags = {
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'p',
    'li',
    'blockquote',
    'td',
    'th',
    'figcaption',
  };

  static const Set<String> _imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.svg',
    '.webp',
    '.bmp',
    '.avif',
  };

  static final RegExp _blockAnchorPattern = RegExp(r'<!--\s*@b(\d+)\s*-->');

  /// Removes `<!-- @bN -->` block markers cleanly for UI preview, word counts, and `.txt`/`.md` exports.
  static String stripBlockAnchors(String text) {
    return text
        .replaceAll(RegExp(r'<!--\s*@b\d+\s*-->\s*'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// Scans an `.epub` file in reading spine order and produces anchor-locked chunks.
  Future<EpubScanResult> scanEpub(
    String epubPath, {
    int targetChunkChars = 1400,
  }) async {
    final file = File(epubPath);
    if (!await file.exists()) {
      throw Exception('File EPUB không tồn tại: $epubPath');
    }

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final opfPath = _resolveOpfPath(archive);
    final spineHrefs = _resolveSpineHrefs(archive, opfPath);

    final blockRefs = <EpubBlockRef>[];
    final anchoredBlocks = <String>[];
    final plainBlocks = <String>[];

    var nextBlockId = 0;

    for (final href in spineHrefs) {
      final entry = _findArchiveFile(archive, href);
      if (entry == null) continue;

      final xhtmlStr = _decodeUtf8Safe(entry.content as List<int>);
      final doc = _parseXmlSafe(xhtmlStr);
      if (doc == null) continue;

      final root = _findBodyOrRoot(doc);
      if (root == null) continue;

      final elements = _collectLeafBlocks(root);
      for (final elem in elements) {
        final inlineAssets = <EpubInlineAsset>[];
        final extracted = _extractInlineMarkdown(elem, inlineAssets).trim();
        if (extracted.isEmpty) continue;

        final blockId = nextBlockId++;
        blockRefs.add(EpubBlockRef(
          id: blockId,
          spineHref: href,
          tagName: elem.name.local.toLowerCase(),
          inlineAssets: inlineAssets,
        ));
        anchoredBlocks.add('<!-- @b$blockId -->\n$extracted');
        plainBlocks.add(extracted);
      }
    }

    if (anchoredBlocks.isEmpty) {
      throw Exception('Không tìm thấy nội dung XHTML trong EPUB (file có thể có DRM).');
    }

    // Pack blocks into context-safe chunks up to targetChunkChars
    final chunks = <String>[];
    final chunkBlockIds = <List<int>>[];
    final currentBuffer = <String>[];
    final currentIds = <int>[];
    var currentLen = 0;

    for (var i = 0; i < anchoredBlocks.length; i++) {
      final blockText = anchoredBlocks[i];
      final blockId = blockRefs[i].id;

      if (currentBuffer.isNotEmpty &&
          currentLen + blockText.length + 2 > targetChunkChars) {
        chunks.add(currentBuffer.join('\n\n'));
        chunkBlockIds.add(List<int>.from(currentIds));
        currentBuffer.clear();
        currentIds.clear();
        currentLen = 0;
      }

      currentBuffer.add(blockText);
      currentIds.add(blockId);
      currentLen += blockText.length + 2;
    }

    if (currentBuffer.isNotEmpty) {
      chunks.add(currentBuffer.join('\n\n'));
      chunkBlockIds.add(List<int>.from(currentIds));
    }

    _logger.info(
      'EpubPipeline',
      'Scanned EPUB into ${chunks.length} anchored chunks (${blockRefs.length} blocks across ${spineHrefs.length} spine items)',
    );

    return EpubScanResult(
      anchoredChunks: chunks,
      blockRefs: blockRefs,
      chunkBlockIds: chunkBlockIds,
      fullPlainText: plainBlocks.join('\n\n'),
    );
  }

  /// Rebuilds a translated `.epub` preserving CSS, fonts, images, OPF spine,
  /// inline footnotes/links, table cells, and cloned split paragraphs without duplicate `id=`.
  Future<List<int>> rebuildTranslatedEpub({
    required String sourceEpubPath,
    required List<EpubBlockRef> blockRefs,
    required List<List<int>> chunkBlockIds,
    required List<String?> translatedChunks,
    required String targetLanguageName,
  }) async {
    final sourceBytes = await File(sourceEpubPath).readAsBytes();
    final sourceArchive = ZipDecoder().decodeBytes(sourceBytes);

    final translationsByBlockId = <int, String>{};

    // 1. Parse translated chunks for @bN markers, with positional fallback if LLM drops anchors
    for (var cIdx = 0; cIdx < translatedChunks.length; cIdx++) {
      final rawTgt = (translatedChunks[cIdx] ?? '').trim();
      if (rawTgt.isEmpty) continue;

      final expectedIds = cIdx < chunkBlockIds.length ? chunkBlockIds[cIdx] : <int>[];
      final matches = _blockAnchorPattern.allMatches(rawTgt).toList();

      if (matches.isNotEmpty) {
        for (var mIdx = 0; mIdx < matches.length; mIdx++) {
          final idStr = matches[mIdx].group(1);
          final blockId = idStr != null ? int.tryParse(idStr) : null;
          if (blockId == null) continue;

          final contentStart = matches[mIdx].end;
          final contentEnd = (mIdx + 1 < matches.length) ? matches[mIdx + 1].start : rawTgt.length;
          final body = rawTgt.substring(contentStart, contentEnd).trim();
          if (body.isNotEmpty) {
            translationsByBlockId[blockId] = body;
          }
        }
      } else if (expectedIds.isNotEmpty) {
        // Fallback: distribute unanchored paragraphs across expected blocks
        final paras = rawTgt
            .split(RegExp(r'\n{2,}'))
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();
        if (expectedIds.length == 1) {
          translationsByBlockId[expectedIds.first] = paras.join('\n\n');
        } else {
          for (var i = 0; i < expectedIds.length && i < paras.length; i++) {
            final text = (i == expectedIds.length - 1 && paras.length > expectedIds.length)
                ? paras.sublist(i).join('\n\n')
                : paras[i];
            translationsByBlockId[expectedIds[i]] = text;
          }
        }
      }
    }

    // 2. Group block IDs by spineHref
    final blocksBySpine = <String, List<EpubBlockRef>>{};
    for (final ref in blockRefs) {
      blocksBySpine.putIfAbsent(ref.spineHref, () => []).add(ref);
    }

    final opfPath = _resolveOpfPath(sourceArchive);
    final langIso = _isoLanguageCode(targetLanguageName);

    // 3. Build new archive preserving OCF order ('mimetype' first & uncompressed)
    final outArchive = Archive();
    final mimetypeEntry = _findArchiveFile(sourceArchive, 'mimetype');
    final mimeBytes = mimetypeEntry != null
        ? Uint8List.fromList(List<int>.from(mimetypeEntry.content as List<int>))
        : Uint8List.fromList(utf8.encode('application/epub+zip'));
    outArchive.addFile(ArchiveFile.noCompress('mimetype', mimeBytes.length, mimeBytes));

    for (final entry in sourceArchive.files) {
      if (!entry.isFile) continue;
      final normalizedName = _normalizeZipPath(entry.name);
      if (normalizedName == 'mimetype') continue;

      List<int> outBytes = List<int>.from(entry.content as List<int>);

      if (opfPath != null && normalizedName == _normalizeZipPath(opfPath)) {
        outBytes = _updateOpfLanguage(outBytes, langIso);
      } else if (blocksBySpine.containsKey(normalizedName)) {
        outBytes = _applyTranslationsToXhtml(
          xhtmlBytes: outBytes,
          spineRefs: blocksBySpine[normalizedName]!,
          translationsByBlockId: translationsByBlockId,
        );
      }

      final typedOut = Uint8List.fromList(outBytes);
      outArchive.addFile(ArchiveFile(entry.name, typedOut.length, typedOut));
    }

    final encoded = ZipEncoder().encode(outArchive);
    if (encoded == null) {
      throw Exception('Không thể đóng gói EPUB đích.');
    }
    return encoded;
  }

  /// Builds a clean, valid styled EPUB 3 archive from plain translated text / Markdown
  /// (used when source input was `.txt`, `.md`, or `.pdf` and user saves as `.epub`).
  static List<int> buildCleanEpubFromText({
    required String title,
    required String content,
    required String targetLanguageName,
  }) {
    final langIso = _isoLanguageCode(targetLanguageName);
    final cleanContent = stripBlockAnchors(content);
    final paragraphs = cleanContent
        .split(RegExp(r'\n{2,}'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    final bodyBuf = StringBuffer();
    bodyBuf.writeln('<h1 class="book-title">${_escapeXml(title)}</h1>');
    for (final para in paragraphs) {
      if (para.startsWith('# ')) {
        bodyBuf.writeln('<h1>${_escapeXml(para.substring(2).trim())}</h1>');
      } else if (para.startsWith('## ')) {
        bodyBuf.writeln('<h2>${_escapeXml(para.substring(3).trim())}</h2>');
      } else if (para.startsWith('### ')) {
        bodyBuf.writeln('<h3>${_escapeXml(para.substring(4).trim())}</h3>');
      } else {
        bodyBuf.writeln('<p>${_escapeXml(para).replaceAll('\n', '<br/>')}</p>');
      }
    }

    final xhtml = '''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="$langIso" lang="$langIso">
<head>
  <meta charset="utf-8"/>
  <title>${_escapeXml(title)}</title>
  <style type="text/css">
    body { font-family: Georgia, serif; line-height: 1.7; margin: 5%; color: #1b1b1b; }
    h1, h2, h3 { font-family: Georgia, serif; margin-top: 1.4em; }
    p { margin: 0.8em 0; text-align: justify; }
  </style>
</head>
<body>
${bodyBuf.toString()}
</body>
</html>
''';

    final opf = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:fluxorigin:${DateTime.now().millisecondsSinceEpoch}</dc:identifier>
    <dc:title>${_escapeXml(title)}</dc:title>
    <dc:language>$langIso</dc:language>
  </metadata>
  <manifest>
    <item id="ch1" href="content.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
  </spine>
</package>
''';

    const containerXml = '''<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

    final archive = Archive();
    final mimeBytes = utf8.encode('application/epub+zip');
    archive.addFile(ArchiveFile.noCompress('mimetype', mimeBytes.length, mimeBytes));

    void addStr(String name, String data) {
      final b = utf8.encode(data);
      archive.addFile(ArchiveFile(name, b.length, b));
    }

    addStr('META-INF/container.xml', containerXml);
    addStr('OEBPS/package.opf', opf);
    addStr('OEBPS/content.xhtml', xhtml);

    return ZipEncoder().encode(archive) ?? <int>[];
  }

  // ---- Internal EPUB DOM Helpers ----

  static List<int> _applyTranslationsToXhtml({
    required List<int> xhtmlBytes,
    required List<EpubBlockRef> spineRefs,
    required Map<int, String> translationsByBlockId,
  }) {
    final doc = _parseXmlSafe(_decodeUtf8Safe(xhtmlBytes));
    if (doc == null) return xhtmlBytes;

    final root = _findBodyOrRoot(doc);
    if (root == null) return xhtmlBytes;

    final elements = _collectLeafBlocks(root);
    final extractedElems = <XmlElement>[];
    for (final elem in elements) {
      final dummy = <EpubInlineAsset>[];
      if (_extractInlineMarkdown(elem, dummy).trim().isNotEmpty) {
        extractedElems.add(elem);
      }
    }

    // Apply in reverse order so splicing new split sibling nodes never shifts earlier indices
    final count = extractedElems.length < spineRefs.length
        ? extractedElems.length
        : spineRefs.length;

    for (var i = count - 1; i >= 0; i--) {
      final ref = spineRefs[i];
      final translated = translationsByBlockId[ref.id];
      if (translated == null || translated.trim().isEmpty) continue;

      final targetElem = extractedElems[i];
      final cleanText = stripBlockAnchors(translated);
      final paras = cleanText
          .split(RegExp(r'\n+'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      if (paras.isEmpty) continue;

      final canSplit = ref.tagName == 'p' || ref.tagName == 'li';
      if (!canSplit || paras.length == 1) {
        final joined = paras.join('<br/>');
        _replaceElementChildren(targetElem, _inlineMdToXmlNodes(joined, ref.inlineAssets));
        continue;
      }

      // First paragraph stays inside original element (preserving its original id & attributes)
      _replaceElementChildren(targetElem, _inlineMdToXmlNodes(paras.first, ref.inlineAssets));

      final parent = targetElem.parent;
      if (parent != null) {
        final insertBase = parent.children.indexOf(targetElem);
        for (var pIdx = 1; pIdx < paras.length; pIdx++) {
          final clone = XmlElement(
            XmlName(targetElem.name.local),
            targetElem.attributes
                .where((attr) => attr.name.local.toLowerCase() != 'id')
                .map((attr) => XmlAttribute(XmlName(attr.name.qualified), attr.value))
                .toList(),
            _inlineMdToXmlNodes(paras[pIdx], ref.inlineAssets),
          );
          parent.children.insert(insertBase + pIdx, clone);
        }
      }
    }

    return utf8.encode(doc.toXmlString(pretty: false));
  }

  static void _replaceElementChildren(XmlElement elem, List<XmlNode> nodes) {
    elem.children.clear();
    elem.children.addAll(nodes);
  }

  static List<XmlNode> _inlineMdToXmlNodes(
    String text,
    List<EpubInlineAsset> origAssets,
  ) {
    // Handle <br/> markers explicitly injected when non-splittable headings/cells contain newlines
    if (text.contains('<br/>')) {
      final parts = text.split('<br/>');
      final result = <XmlNode>[];
      for (var i = 0; i < parts.length; i++) {
        result.addAll(_convertInlineLinksAndEmphasis(parts[i], origAssets));
        if (i < parts.length - 1) {
          result.add(XmlElement(XmlName('br')));
        }
      }
      return result;
    }
    return _convertInlineLinksAndEmphasis(text, origAssets);
  }

  static List<XmlNode> _convertInlineLinksAndEmphasis(
    String segment,
    List<EpubInlineAsset> origAssets,
  ) {
    final nodes = <XmlNode>[];
    final linkOrImgPattern = RegExp(r'(!?)\[([^\]]*)\]\(([^)]+)\)');
    var cursor = 0;

    for (final match in linkOrImgPattern.allMatches(segment)) {
      final hasBang = match.group(1) == '!';
      final label = match.group(2) ?? '';
      final url = match.group(3) ?? '';

      final isImg = hasBang &&
          (origAssets.any((a) => a.kind == 'img' && a.url == url) ||
              _imageExtensions.any((ext) => url.toLowerCase().endsWith(ext)));

      final textStart = (hasBang && !isImg) ? match.start + 1 : match.start;
      if (textStart > cursor) {
        nodes.addAll(_parseBasicMarkdownEmphasis(segment.substring(cursor, textStart)));
      }

      if (isImg) {
        final orig = origAssets.cast<EpubInlineAsset?>().firstWhere(
              (a) => a!.kind == 'img' && a.url == url,
              orElse: () => null,
            );
        final attrs = <XmlAttribute>[];
        if (orig != null) {
          orig.attrs.forEach((k, v) {
            if (k.toLowerCase() == 'alt') {
              attrs.add(XmlAttribute(XmlName('alt'), label.isNotEmpty ? label : v));
            } else {
              attrs.add(XmlAttribute(XmlName(k), v));
            }
          });
          if (!orig.attrs.containsKey('alt')) {
            attrs.add(XmlAttribute(XmlName('alt'), label));
          }
        } else {
          attrs.add(XmlAttribute(XmlName('src'), url));
          attrs.add(XmlAttribute(XmlName('alt'), label));
        }
        nodes.add(XmlElement(XmlName('img'), attrs));
      } else {
        final orig = origAssets.cast<EpubInlineAsset?>().firstWhere(
              (a) => a!.kind == 'link' && a.url == url,
              orElse: () => null,
            );
        final attrs = <XmlAttribute>[];
        var wrapSup = false;
        if (orig != null) {
          wrapSup = orig.hasSup;
          orig.attrs.forEach((k, v) {
            attrs.add(XmlAttribute(XmlName(k), v));
          });
        } else {
          attrs.add(XmlAttribute(XmlName('href'), url));
        }
        final innerChildren = wrapSup
            ? <XmlNode>[XmlElement(XmlName('sup'), [], [XmlText(label)])]
            : <XmlNode>[XmlText(label)];
        nodes.add(XmlElement(XmlName('a'), attrs, innerChildren));
      }

      cursor = match.end;
    }

    if (cursor < segment.length) {
      nodes.addAll(_parseBasicMarkdownEmphasis(segment.substring(cursor)));
    }

    return nodes;
  }

  static List<XmlNode> _parseBasicMarkdownEmphasis(String text) {
    final nodes = <XmlNode>[];
    final emPattern = RegExp(r'\*\*([^*]+)\*\*|\*([^*]+)\*');
    var cursor = 0;

    for (final m in emPattern.allMatches(text)) {
      if (m.start > cursor) {
        nodes.add(XmlText(text.substring(cursor, m.start)));
      }
      if (m.group(1) != null) {
        nodes.add(XmlElement(XmlName('strong'), [], [XmlText(m.group(1)!)]));
      } else if (m.group(2) != null) {
        nodes.add(XmlElement(XmlName('em'), [], [XmlText(m.group(2)!)]));
      }
      cursor = m.end;
    }

    if (cursor < text.length) {
      nodes.add(XmlText(text.substring(cursor)));
    }
    return nodes;
  }

  static String _extractInlineMarkdown(
    XmlElement elem,
    List<EpubInlineAsset> outAssets,
  ) {
    final buf = StringBuffer();
    for (final child in elem.children) {
      if (child is XmlText) {
        buf.write(child.value);
      } else if (child is XmlElement) {
        final tag = child.name.local.toLowerCase();
        if (tag == 'a') {
          final href = child.getAttribute('href') ?? '';
          final hasSup = child.descendants.whereType<XmlElement>().any((e) => e.name.local.toLowerCase() == 'sup');
          final label = child.innerText.trim();
          if (href.isNotEmpty && label.isNotEmpty) {
            final attrs = <String, String>{};
            for (final a in child.attributes) {
              attrs[a.name.qualified] = a.value;
            }
            outAssets.add(EpubInlineAsset(
              kind: 'link',
              token: label,
              url: href,
              attrs: attrs,
              hasSup: hasSup,
            ));
            buf.write('[$label]($href)');
          } else {
            buf.write(_extractInlineMarkdown(child, outAssets));
          }
        } else if (tag == 'img') {
          final src = child.getAttribute('src') ?? '';
          final alt = child.getAttribute('alt') ?? '';
          if (src.isNotEmpty) {
            final attrs = <String, String>{};
            for (final a in child.attributes) {
              attrs[a.name.qualified] = a.value;
            }
            outAssets.add(EpubInlineAsset(
              kind: 'img',
              token: alt,
              url: src,
              attrs: attrs,
            ));
            buf.write('![$alt]($src)');
          }
        } else if (tag == 'br') {
          buf.write(' ');
        } else {
          buf.write(_extractInlineMarkdown(child, outAssets));
        }
      }
    }
    return buf.toString().replaceAll(RegExp(r'\s+'), ' ');
  }

  static List<XmlElement> _collectLeafBlocks(XmlElement root) {
    final collected = <XmlElement>[];

    void walk(XmlElement node) {
      final tag = node.name.local.toLowerCase();
      if (_leafBlockTags.contains(tag)) {
        final hasNestedLeaf = node.descendants.whereType<XmlElement>().any(
              (d) => d != node && _leafBlockTags.contains(d.name.local.toLowerCase()),
            );
        if (!hasNestedLeaf) {
          collected.add(node);
          return;
        }
      }
      for (final child in node.children.whereType<XmlElement>()) {
        walk(child);
      }
    }

    walk(root);
    return collected;
  }

  static XmlElement? _findBodyOrRoot(XmlDocument doc) {
    final bodies = doc.findAllElements('body');
    if (bodies.isNotEmpty) return bodies.first;
    return doc.rootElement;
  }

  static String? _resolveOpfPath(Archive archive) {
    final containerEntry = _findArchiveFile(archive, 'META-INF/container.xml');
    if (containerEntry != null) {
      final doc = _parseXmlSafe(_decodeUtf8Safe(containerEntry.content as List<int>));
      if (doc != null) {
        for (final rf in doc.findAllElements('rootfile')) {
          final fullPath = rf.getAttribute('full-path');
          if (fullPath != null && fullPath.trim().isNotEmpty) {
            return _normalizeZipPath(fullPath);
          }
        }
      }
    }

    for (final file in archive.files) {
      if (file.name.toLowerCase().endsWith('.opf')) {
        return _normalizeZipPath(file.name);
      }
    }
    return null;
  }

  static List<String> _resolveSpineHrefs(Archive archive, String? opfPath) {
    if (opfPath == null) {
      return archive.files
          .where((f) =>
              f.isFile &&
              (f.name.toLowerCase().endsWith('.xhtml') ||
                  f.name.toLowerCase().endsWith('.html')))
          .map((f) => _normalizeZipPath(f.name))
          .toList()
        ..sort();
    }

    final opfEntry = _findArchiveFile(archive, opfPath);
    if (opfEntry == null) return const [];

    final doc = _parseXmlSafe(_decodeUtf8Safe(opfEntry.content as List<int>));
    if (doc == null) return const [];

    final opfDir = path.posix.dirname(opfPath);
    final manifestHref = <String, String>{};
    final manifestMedia = <String, String>{};

    for (final item in doc.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      final mediaType = item.getAttribute('media-type') ?? '';
      if (id != null && href != null) {
        final resolved = opfDir == '.' ? href : path.posix.join(opfDir, href);
        manifestHref[id] = _normalizeZipPath(Uri.decodeFull(resolved));
        manifestMedia[id] = mediaType.toLowerCase();
      }
    }

    final spine = <String>[];
    for (final ref in doc.findAllElements('itemref')) {
      final idref = ref.getAttribute('idref');
      if (idref != null && manifestHref.containsKey(idref)) {
        final media = manifestMedia[idref] ?? '';
        final href = manifestHref[idref]!;
        if (media.contains('html') ||
            href.toLowerCase().endsWith('.xhtml') ||
            href.toLowerCase().endsWith('.html')) {
          spine.add(href);
        }
      }
    }

    return spine;
  }

  static List<int> _updateOpfLanguage(List<int> opfBytes, String langIso) {
    final doc = _parseXmlSafe(_decodeUtf8Safe(opfBytes));
    if (doc == null) return opfBytes;
    for (final langNode in doc.findAllElements('language', namespace: '*')) {
      langNode.children
        ..clear()
        ..add(XmlText(langIso));
    }
    return utf8.encode(doc.toXmlString(pretty: false));
  }

  static ArchiveFile? _findArchiveFile(Archive archive, String targetPath) {
    final normTarget = _normalizeZipPath(targetPath);
    for (final f in archive.files) {
      if (f.isFile && _normalizeZipPath(f.name) == normTarget) {
        return f;
      }
    }
    return null;
  }

  static String _normalizeZipPath(String raw) {
    return path.posix.normalize(raw.replaceAll('\\', '/')).replaceFirst(RegExp(r'^/'), '');
  }

  static XmlDocument? _parseXmlSafe(String content) {
    try {
      final sanitized = _sanitizeHtmlEntitiesForXml(content);
      return XmlDocument.parse(sanitized);
    } catch (_) {
      return null;
    }
  }

  static String _sanitizeHtmlEntitiesForXml(String raw) {
    return raw
        .replaceAll('&nbsp;', '&#160;')
        .replaceAll('&mdash;', '&#8212;')
        .replaceAll('&ndash;', '&#8211;')
        .replaceAll('&hellip;', '&#8230;')
        .replaceAll('&ldquo;', '&#8220;')
        .replaceAll('&rdquo;', '&#8221;')
        .replaceAll('&lsquo;', '&#8216;')
        .replaceAll('&rsquo;', '&#8217;')
        .replaceAll('&copy;', '&#169;');
  }

  static String _decodeUtf8Safe(List<int> bytes) {
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _escapeXml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static String _isoLanguageCode(String langName) {
    switch (langName) {
      case 'Tiếng Việt':
        return 'vi';
      case 'Tiếng Anh':
        return 'en';
      case 'Tiếng Trung':
        return 'zh';
      case 'Tiếng Nhật':
        return 'ja';
      case 'Tiếng Hàn':
        return 'ko';
      case 'Tiếng Pháp':
        return 'fr';
      case 'Tiếng Đức':
        return 'de';
      case 'Tiếng Tây Ban Nha':
        return 'es';
      default:
        return 'en';
    }
  }
}
