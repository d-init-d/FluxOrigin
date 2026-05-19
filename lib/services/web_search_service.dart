import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'dev_logger.dart';

class WebSearchService {
  /// Tra cứu định nghĩa thuật ngữ.
  /// Ưu tiên 1: Wikipedia API
  /// Ưu tiên 2: DuckDuckGo (Scraping)
  Future<String?> lookupTerm(String term, String langCode) async {
    if (term.trim().isEmpty) return null;

    // 1. Wikipedia Lookup
    try {
      final wikiDefinition = await _lookupWikipedia(term, langCode);
      if (wikiDefinition != null && wikiDefinition.isNotEmpty) {
        return wikiDefinition;
      }
    } catch (e) {
      DevLogger().warning('WebSearchService', "Wikipedia lookup failed for '$term' ($langCode)", details: e.toString());
    }

    // 2. DuckDuckGo Lookup (Fallback)
    try {
      final ddgDefinition = await _lookupDuckDuckGo(term);
      if (ddgDefinition != null && ddgDefinition.isNotEmpty) {
        return ddgDefinition;
      }
    } catch (e) {
      DevLogger().warning('WebSearchService', "DuckDuckGo lookup failed for '$term'", details: e.toString());
    }

    return null;
  }

  Future<String?> _lookupWikipedia(String term, String langCode) async {
    // Encode term for URL (e.g., spaces to %20)
    final encodedTerm = Uri.encodeComponent(term);
    final url = Uri.parse(
        'https://$langCode.wikipedia.org/api/rest_v1/page/summary/$encodedTerm');

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data != null && data['extract'] != null) {
        return data['extract'].toString();
      }
    }
    return null;
  }

  Future<String?> _lookupDuckDuckGo(String term) async {
    final url = Uri.parse('https://html.duckduckgo.com/html/');

    final response = await http.post(
      url,
      body: {'q': '$term definition'},
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    );

    if (response.statusCode == 200) {
      final document = html_parser.parse(response.body);
      // DuckDuckGo HTML version usually has results in .result__snippet
      // We take the first result's snippet
      final element = document.querySelector('.result__snippet');
      if (element != null) {
        return element.text.trim();
      }
    }
    return null;
  }
}
