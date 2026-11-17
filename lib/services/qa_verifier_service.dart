import 'package:csv/csv.dart';

/// Issue severity reported by [QaVerifierService].
enum QaSeverity { error, warning }

/// Individual QA finding for a specific chunk or book-wide check.
class QaIssue {
  final int chunkIndex; // 0-based (-1 if book-wide)
  final String gate;
  final QaSeverity severity;
  final String message;

  const QaIssue({
    required this.chunkIndex,
    required this.gate,
    required this.severity,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'chunkIndex': chunkIndex,
        'gate': gate,
        'severity': severity.name,
        'message': message,
      };
}

/// Deterministic QA audit report following D-Transcreate v1.1.0 `verify` gates.
class QaReport {
  final bool passed;
  final int score; // 0..100
  final int totalChunks;
  final int errorCount;
  final int warningCount;
  final int glossaryTermsChecked;
  final int glossaryTermsMatched;
  final List<QaIssue> issues;

  const QaReport({
    required this.passed,
    required this.score,
    required this.totalChunks,
    required this.errorCount,
    required this.warningCount,
    required this.glossaryTermsChecked,
    required this.glossaryTermsMatched,
    required this.issues,
  });

  Map<String, dynamic> toJson() => {
        'passed': passed,
        'score': score,
        'totalChunks': totalChunks,
        'errorCount': errorCount,
        'warningCount': warningCount,
        'glossaryTermsChecked': glossaryTermsChecked,
        'glossaryTermsMatched': glossaryTermsMatched,
        'issues': issues.map((i) => i.toJson()).toList(),
      };

  String toMarkdown() {
    final buf = StringBuffer();
    buf.writeln('# D-Transcreate Deterministic QA Report\n');
    buf.writeln('- **Status:** ${passed ? "PASSED" : "NEEDS REVIEW"}');
    buf.writeln('- **Score:** $score / 100');
    buf.writeln('- **Chunks Audited:** $totalChunks');
    buf.writeln('- **Errors:** $errorCount | **Warnings:** $warningCount');
    buf.writeln('- **Glossary Compliance:** $glossaryTermsMatched / $glossaryTermsChecked matched\n');

    if (issues.isEmpty) {
      buf.writeln('No deterministic QA issues detected.');
    } else {
      buf.writeln('## Findings\n');
      for (final issue in issues.take(80)) {
        final chunkTag = issue.chunkIndex >= 0 ? 'chunk-${(issue.chunkIndex + 1).toString().padLeft(3, '0')}' : 'book';
        final icon = issue.severity == QaSeverity.error ? 'ERROR' : 'WARN';
        buf.writeln('- [$icon] [$chunkTag] (`${issue.gate}`): ${issue.message}');
      }
    }
    return buf.toString();
  }
}

/// Pure-Dart implementation of D-Transcreate v1.1.0 deterministic QA gates:
/// 1. Completeness & language-calibrated length ratio
/// 2. Untranslated CJK / Hangul script leakage
/// 3. Formal-data parity (numbers, percentages, years, URLs)
/// 4. Approved glossary term compliance
/// 5. Vietnamese anti-translatorese & dialogue style lint
class QaVerifierService {
  static final RegExp _anchorRegex = RegExp(r'<!--\s*@b\d+\s*-->');
  static final RegExp _cjkRegex = RegExp(r'[\u4e00-\u9fff]');
  static final RegExp _hangulRegex = RegExp(r'[\uac00-\ud7af]');
  static final RegExp _urlRegex = RegExp(r'https?://[^\s)\]>"]+');
  static final RegExp _numberRegex = RegExp(r'\b\d+(?:[.,]\d+)?%?');
  static final RegExp _viCalqueRegex = RegExp(
    r'\b(một cách|bởi vì|sự việc|việc mà|đã từng là|bị được)\b',
    caseSensitive: false,
  );

  /// Evaluates a single translated chunk during the translation loop so
  /// serious defects (empty output or heavy script leakage) can trigger auto-retry.
  static List<QaIssue> checkChunk({
    required int chunkIndex,
    required String sourceChunk,
    required String translatedChunk,
    required String sourceLanguage,
    required String targetLanguage,
    List<List<String>> glossaryPairs = const [],
  }) {
    final issues = <QaIssue>[];
    final cleanSrc = _stripAnchors(sourceChunk).trim();
    final cleanTgt = _stripAnchors(translatedChunk).trim();

    if (cleanSrc.isEmpty) return issues;

    // 1. Completeness & ratio
    if (cleanTgt.isEmpty) {
      issues.add(QaIssue(
        chunkIndex: chunkIndex,
        gate: 'completeness',
        severity: QaSeverity.error,
        message: 'Empty translation output.',
      ));
      return issues;
    }

    final ratio = cleanTgt.length / cleanSrc.length;
    final srcIsCjk = _cjkRegex.hasMatch(cleanSrc);
    final minRatio = srcIsCjk ? 0.55 : (sourceLanguage == 'Tiếng Việt' ? 0.42 : 0.45);
    final maxRatio = srcIsCjk ? 5.0 : 3.2;

    if (cleanSrc.length >= 60 && ratio < minRatio) {
      issues.add(QaIssue(
        chunkIndex: chunkIndex,
        gate: 'completeness',
        severity: QaSeverity.warning,
        message: 'Translated output unusually short (char ratio=${ratio.toStringAsFixed(2)}).',
      ));
    } else if (cleanSrc.length >= 60 && ratio > maxRatio) {
      issues.add(QaIssue(
        chunkIndex: chunkIndex,
        gate: 'completeness',
        severity: QaSeverity.warning,
        message: 'Translated output unusually verbose/hallucinated (char ratio=${ratio.toStringAsFixed(2)}).',
      ));
    }

    // 2. Script leakage
    final allowCjkOut = targetLanguage == 'Tiếng Trung' || targetLanguage == 'Tiếng Nhật';
    if (!allowCjkOut) {
      final cjkMatches = _cjkRegex.allMatches(cleanTgt).length;
      if (cjkMatches >= 1) {
        issues.add(QaIssue(
          chunkIndex: chunkIndex,
          gate: 'script-leakage',
          severity: QaSeverity.error,
          message: 'Detected $cjkMatches untranslated CJK character(s) in $targetLanguage output.',
        ));
      }
    }

    if (targetLanguage != 'Tiếng Hàn') {
      final hangulCount = _hangulRegex.allMatches(cleanTgt).length;
      if (hangulCount >= 2) {
        issues.add(QaIssue(
          chunkIndex: chunkIndex,
          gate: 'script-leakage',
          severity: QaSeverity.error,
          message: 'Detected $hangulCount untranslated Hangul character(s).',
        ));
      }
    }

    // 3. Formal-data parity (URLs + distinctive numbers/years)
    for (final urlMatch in _urlRegex.allMatches(cleanSrc)) {
      final url = urlMatch.group(0)!;
      if (!cleanTgt.contains(url)) {
        issues.add(QaIssue(
          chunkIndex: chunkIndex,
          gate: 'formal-data',
          severity: QaSeverity.warning,
          message: 'Missing source URL in translation: $url',
        ));
      }
    }

    final srcNums = _numberRegex.allMatches(cleanSrc).map((m) => m.group(0)!).toSet();
    final tgtNums = _numberRegex.allMatches(cleanTgt).map((m) => m.group(0)!).toSet();
    for (final numStr in srcNums) {
      if (numStr.length >= 2 && !tgtNums.contains(numStr)) {
        final normalized = numStr.replaceAll(',', '.');
        final alt = numStr.replaceAll('.', ',');
        if (!tgtNums.contains(normalized) && !tgtNums.contains(alt) && !cleanTgt.contains(numStr)) {
          issues.add(QaIssue(
            chunkIndex: chunkIndex,
            gate: 'formal-data',
            severity: QaSeverity.warning,
            message: 'Number/statistic "$numStr" missing or altered in translation.',
          ));
          break; // at most 1 numeric parity warning per chunk to avoid noise
        }
      }
    }

    // 4. Glossary compliance
    final lowerSrc = cleanSrc.toLowerCase();
    final lowerTgt = cleanTgt.toLowerCase();
    for (final pair in glossaryPairs) {
      if (pair.length < 2) continue;
      final orig = pair[0];
      final expected = pair[1];
      if (_containsTerm(lowerSrc, orig) && !lowerTgt.contains(expected.toLowerCase())) {
        issues.add(QaIssue(
          chunkIndex: chunkIndex,
          gate: 'glossary-compliance',
          severity: QaSeverity.warning,
          message: 'Glossary term "$orig" -> expected "$expected" not found in chunk.',
        ));
      }
    }

    // 5. Vietnamese locale style lint
    if (targetLanguage == 'Tiếng Việt' && cleanTgt.length >= 200) {
      final calqueCount = _viCalqueRegex.allMatches(cleanTgt).length;
      final wordApprox = cleanTgt.split(RegExp(r'\s+')).length;
      if (wordApprox >= 60 && calqueCount >= 3 && (calqueCount / wordApprox) > 0.03) {
        issues.add(QaIssue(
          chunkIndex: chunkIndex,
          gate: 'locale-vi',
          severity: QaSeverity.warning,
          message: 'High Vietnamese translatorese density ($calqueCount calque phrases). Consider softening phrasing.',
        ));
      }
    }

    return issues;
  }

  /// Audits the entire translated book and computes a 0..100 QA score.
  static QaReport verifyBook({
    required List<String> rawChunks,
    required List<String?> translatedChunks,
    required String sourceLanguage,
    required String targetLanguage,
    required String glossaryCsv,
  }) {
    final pairs = _parseGlossaryPairs(glossaryCsv);
    final allIssues = <QaIssue>[];
    var checkedTerms = 0;
    var matchedTerms = 0;

    for (var i = 0; i < rawChunks.length; i++) {
      final src = rawChunks[i];
      final tgt = i < translatedChunks.length ? (translatedChunks[i] ?? '') : '';

      final chunkIssues = checkChunk(
        chunkIndex: i,
        sourceChunk: src,
        translatedChunk: tgt,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        glossaryPairs: pairs,
      );
      allIssues.addAll(chunkIssues);

      final cleanSrc = _stripAnchors(src).toLowerCase();
      final cleanTgt = _stripAnchors(tgt).toLowerCase();
      for (final pair in pairs) {
        if (_containsTerm(cleanSrc, pair[0])) {
          checkedTerms++;
          if (cleanTgt.contains(pair[1].toLowerCase())) {
            matchedTerms++;
          }
        }
      }
    }

    final errorCount = allIssues.where((e) => e.severity == QaSeverity.error).length;
    final warningCount = allIssues.where((e) => e.severity == QaSeverity.warning).length;

    var penalty = errorCount * 12 + warningCount * 3;
    if (penalty > 95) penalty = 95;
    final score = rawChunks.isEmpty ? 100 : (100 - penalty).clamp(5, 100);

    return QaReport(
      passed: errorCount == 0,
      score: score,
      totalChunks: rawChunks.length,
      errorCount: errorCount,
      warningCount: warningCount,
      glossaryTermsChecked: checkedTerms,
      glossaryTermsMatched: matchedTerms,
      issues: allIssues,
    );
  }

  static List<List<String>> _parseGlossaryPairs(String glossaryCsv) {
    if (glossaryCsv.trim().isEmpty) return const [];
    try {
      final rows = const CsvToListConverter().convert(
        glossaryCsv,
        eol: '\n',
        shouldParseNumbers: false,
      );
      final out = <List<String>>[];
      for (final row in rows) {
        if (row.length < 2) continue;
        final orig = row[0].toString().trim();
        final tgt = row[1].toString().trim();
        if (orig.isEmpty || tgt.isEmpty) continue;
        final lower = orig.toLowerCase();
        if (lower == 'original' || lower == 'term' || lower == 'từ gốc') continue;
        out.add([orig, tgt]);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static bool _containsTerm(String lowerText, String term) {
    final t = term.toLowerCase().trim();
    if (t.isEmpty) return false;
    if (RegExp(r'^[a-z0-9\s\-\x27]+$').hasMatch(t)) {
      return RegExp(r'\b' + RegExp.escape(t) + r'\b').hasMatch(lowerText);
    }
    return lowerText.contains(t);
  }

  static String _stripAnchors(String text) =>
      text.replaceAll(_anchorRegex, '').trim();
}
