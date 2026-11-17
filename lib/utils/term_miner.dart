/// Whole-book named-entity, acronym, CJK bracketed term, and special-term miner.
///
/// Mirrors D-Transcreate v1.1.0 `book_ops.py mine-terms` in pure Dart so FluxOrigin
/// discovers recurring characters, locations, sects, artifacts, and acronyms across
/// ALL chapters (early, middle, and late) instead of relying solely on a 3-point sample.
class CandidateTerm {
  final String term;
  final String category;
  final int count;
  final int firstChunkIndex;

  const CandidateTerm({
    required this.term,
    required this.category,
    required this.count,
    required this.firstChunkIndex,
  });
}

class WholeBookTermMiner {
  static const Set<String> _stopwords = {
    'a', 'an', 'the', 'and', 'or', 'but', 'if', 'then', 'else', 'when', 'while',
    'where', 'for', 'from', 'with', 'without', 'into', 'onto', 'upon', 'inside',
    'outside', 'across', 'through', 'between', 'among', 'against', 'toward',
    'towards', 'after', 'before', 'during', 'under', 'over', 'above', 'below',
    'in', 'on', 'at', 'by', 'to', 'of', 'as', 'is', 'was', 'were', 'are', 'be',
    'been', 'being', 'has', 'have', 'had', 'do', 'does', 'did', 'will', 'would',
    'can', 'could', 'may', 'might', 'shall', 'should', 'must', 'this', 'that',
    'these', 'those', 'he', 'she', 'it', 'they', 'we', 'you', 'i', 'his', 'her',
    'its', 'their', 'our', 'your', 'my', 'who', 'whom', 'whose', 'which', 'what',
    'why', 'how', 'chapter', 'part', 'section', 'book', 'volume', 'prologue',
    'epilogue', 'appendix', 'table', 'figure', 'note', 'notes', 'page', 'monday',
    'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
    'january', 'february', 'march', 'april', 'june', 'july', 'august',
    'september', 'october', 'november', 'december', 'yes', 'no', 'well', 'now',
    'just', 'only', 'even', 'still', 'also', 'once', 'here', 'there',
  };

  static final RegExp _anchorPattern = RegExp(r'<!--\s*@b\d+\s*-->');
  static final RegExp _mdLinkPattern = RegExp(r'!?\[([^\]]+)\]\([^)]+\)');
  static final RegExp _titlePhrasePattern = RegExp(
    r'\b([A-Z][a-zA-Z\u00C0-\u024F\x27\-]{1,}(?:\s+(?:of|the|de|van|von|al|la|le|[A-Z][a-zA-Z\u00C0-\u024F\x27\-]{1,})){1,4})\b',
  );
  static final RegExp _midSentenceCapPattern = RegExp(
    r'(?<=[,;:\-\s])[a-z\u00C0-\u024F]+\s+([A-Z][a-zA-Z\u00C0-\u024F]{2,})\b',
  );
  static final RegExp _acronymPattern = RegExp(r'\b([A-Z]{2,8})\b');
  static final RegExp _cjkBracketPattern = RegExp(
    r'[《「『【〈]([^《》「」『』【】〈〉\n]{2,18})[》」』】〉]',
  );
  static final RegExp _italicTermPattern = RegExp(
    r'(?<!\*)\*([A-Za-z][A-Za-z\u00C0-\u024F\s\-]{2,36})\*(?!\*)',
  );

  /// Scans all [chunks] and returns recurring candidate terms sorted by frequency.
  static List<CandidateTerm> mineTerms(
    List<String> chunks, {
    int topN = 120,
    int minFreq = 2,
  }) {
    final counts = <String, int>{};
    final categories = <String, String>{};
    final firstChunk = <String, int>{};

    void record(String rawTerm, String category, int chunkIdx) {
      var cleaned = rawTerm.trim().replaceAll(RegExp(r'^[\s\x27".,;:!?()\[\]]+|[\s\x27".,;:!?()\[\]]+$'), '');
      if (cleaned.length < 2) return;

      if (category == 'proper-phrase' || category == 'entity' || category == 'special-term') {
        final words = cleaned.split(RegExp(r'\s+'));
        while (words.length > 1 && _stopwords.contains(words.first.toLowerCase())) {
          words.removeAt(0);
        }
        cleaned = words.join(' ');
        if (cleaned.length < 2) return;
      }

      if (_stopwords.contains(cleaned.toLowerCase())) return;
      if (RegExp(r'^\d+$').hasMatch(cleaned)) return;

      // Roman numerals filter for short acronyms like II, III, IV, VI
      if (category == 'acronym' && RegExp(r'^[IVXLCDM]+$').hasMatch(cleaned)) {
        return;
      }

      counts[cleaned] = (counts[cleaned] ?? 0) + 1;
      categories.putIfAbsent(cleaned, () => category);
      firstChunk.putIfAbsent(cleaned, () => chunkIdx);
    }

    for (var i = 0; i < chunks.length; i++) {
      var text = chunks[i]
          .replaceAll(_anchorPattern, ' ')
          .replaceAllMapped(_mdLinkPattern, (m) => m.group(1) ?? '');

      for (final m in _titlePhrasePattern.allMatches(text)) {
        final phrase = m.group(1);
        if (phrase != null) record(phrase, 'proper-phrase', i);
      }

      for (final m in _midSentenceCapPattern.allMatches(text)) {
        final word = m.group(1);
        if (word != null) record(word, 'entity', i);
      }

      for (final m in _acronymPattern.allMatches(text)) {
        final acro = m.group(1);
        if (acro != null) record(acro, 'acronym', i);
      }

      for (final m in _cjkBracketPattern.allMatches(text)) {
        final inner = m.group(1);
        if (inner != null) record(inner, 'cjk-term', i);
      }

      for (final m in _italicTermPattern.allMatches(text)) {
        final ital = m.group(1);
        if (ital != null && !ital.contains('\n')) {
          record(ital, 'special-term', i);
        }
      }
    }

    final results = <CandidateTerm>[];
    for (final entry in counts.entries) {
      final term = entry.key;
      final count = entry.value;
      final cat = categories[term] ?? 'entity';
      // Always keep CJK bracketed terms or multi-word proper phrases seen at least minFreq;
      // keep single-occurrence CJK bracketed names if the corpus is short (<= 5 chunks).
      final effectiveMin = (cat == 'cjk-term' && chunks.length <= 5) ? 1 : minFreq;
      if (count >= effectiveMin) {
        results.add(CandidateTerm(
          term: term,
          category: cat,
          count: count,
          firstChunkIndex: firstChunk[term] ?? 0,
        ));
      }
    }

    results.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      final byIdx = a.firstChunkIndex.compareTo(b.firstChunkIndex);
      if (byIdx != 0) return byIdx;
      return a.term.compareTo(b.term);
    });

    if (results.length > topN) {
      return results.sublist(0, topN);
    }
    return results;
  }

  /// Formats mined terms cleanly for inclusion in glossary prompts or Source_Map.md.
  static String formatForGlossaryPrompt(
    List<CandidateTerm> terms, {
    int limit = 60,
  }) {
    if (terms.isEmpty) return '';
    final buffer = StringBuffer();
    for (final item in terms.take(limit)) {
      buffer.writeln('- ${item.term} (${item.category}, count=${item.count}, first_chunk=${item.firstChunkIndex + 1})');
    }
    return buffer.toString().trim();
  }
}
