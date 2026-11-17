import 'dart:collection';
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;
import 'dev_logger.dart';
import 'd_transcreate_service.dart';

enum AIProviderType { ollama, lmStudio, openAiCompatible, anthropic }

enum ByokPreset { gemini, openai, anthropic, deepseek, openrouter, groq, custom }

class ByokPresetSpec {
  final ByokPreset preset;
  final String label;
  final AIProviderType providerType;
  final String defaultBaseUrl;
  final List<String> suggestedModels;
  final String keyPlaceholder;

  const ByokPresetSpec({
    required this.preset,
    required this.label,
    required this.providerType,
    required this.defaultBaseUrl,
    required this.suggestedModels,
    required this.keyPlaceholder,
  });
}

class AIService {
  static const String _defaultBaseUrl = 'http://localhost:11434';
  String _baseUrl = _defaultBaseUrl;
  AIProviderType _providerType = AIProviderType.ollama;
  List<String> _apiKeys = const [];
  int _keyCursor = 0;
  double _defaultTemperature = 0.2;
  final DevLogger _logger = DevLogger();

  static const Map<ByokPreset, ByokPresetSpec> byokPresets = {
    ByokPreset.gemini: ByokPresetSpec(
      preset: ByokPreset.gemini,
      label: 'Google Gemini',
      providerType: AIProviderType.openAiCompatible,
      defaultBaseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      suggestedModels: [
        'gemini-2.5-flash',
        'gemini-2.5-pro',
        'gemini-2.0-flash',
      ],
      keyPlaceholder: 'AIzaSy...',
    ),
    ByokPreset.openai: ByokPresetSpec(
      preset: ByokPreset.openai,
      label: 'OpenAI',
      providerType: AIProviderType.openAiCompatible,
      defaultBaseUrl: 'https://api.openai.com/v1',
      suggestedModels: [
        'gpt-4.1-mini',
        'gpt-4.1',
        'gpt-4o-mini',
      ],
      keyPlaceholder: 'sk-proj-...',
    ),
    ByokPreset.anthropic: ByokPresetSpec(
      preset: ByokPreset.anthropic,
      label: 'Anthropic Claude',
      providerType: AIProviderType.anthropic,
      defaultBaseUrl: 'https://api.anthropic.com',
      suggestedModels: [
        'claude-sonnet-4-20250514',
        'claude-3-7-sonnet-latest',
        'claude-3-5-haiku-latest',
      ],
      keyPlaceholder: 'sk-ant-...',
    ),
    ByokPreset.deepseek: ByokPresetSpec(
      preset: ByokPreset.deepseek,
      label: 'DeepSeek',
      providerType: AIProviderType.openAiCompatible,
      defaultBaseUrl: 'https://api.deepseek.com/v1',
      suggestedModels: ['deepseek-chat', 'deepseek-reasoner'],
      keyPlaceholder: 'sk-...',
    ),
    ByokPreset.openrouter: ByokPresetSpec(
      preset: ByokPreset.openrouter,
      label: 'OpenRouter',
      providerType: AIProviderType.openAiCompatible,
      defaultBaseUrl: 'https://openrouter.ai/api/v1',
      suggestedModels: [
        'google/gemini-2.5-flash',
        'anthropic/claude-sonnet-4',
        'openai/gpt-4.1-mini',
      ],
      keyPlaceholder: 'sk-or-v1-...',
    ),
    ByokPreset.groq: ByokPresetSpec(
      preset: ByokPreset.groq,
      label: 'Groq',
      providerType: AIProviderType.openAiCompatible,
      defaultBaseUrl: 'https://api.groq.com/openai/v1',
      suggestedModels: [
        'llama-3.3-70b-versatile',
        'qwen/qwen3-32b',
      ],
      keyPlaceholder: 'gsk_...',
    ),
    ByokPreset.custom: ByokPresetSpec(
      preset: ByokPreset.custom,
      label: 'Custom OpenAI API',
      providerType: AIProviderType.openAiCompatible,
      defaultBaseUrl: 'https://api.openai.com/v1',
      suggestedModels: ['gpt-4.1-mini'],
      keyPlaceholder: 'sk-... (one key per line for rotation)',
    ),
  };

  /// Set the base URL for AI API.
  void setBaseUrl(String url) {
    String normalizedUrl = _normalizeBaseUrl(url);
    _baseUrl = normalizedUrl;
    _logger.info('AIService', 'Base URL set to: $normalizedUrl');
  }

  /// Set the AI provider type.
  void setProviderType(AIProviderType type) {
    _providerType = type;
    _logger.info('AIService', 'Provider type set to: ${_providerLabel(type)}');
  }

  /// Set one or multiple BYOK API keys (comma, semicolon, or newline separated).
  void setApiKey(String rawKeys) {
    _apiKeys = parseApiKeys(rawKeys);
    _keyCursor = 0;
  }

  /// Set default generation temperature.
  void setDefaultTemperature(double temp) {
    _defaultTemperature = temp.clamp(0.0, 1.5);
  }

  int get apiKeyCount => _apiKeys.length;

  /// Parses single or multi-key string into a deduplicated list.
  static List<String> parseApiKeys(String raw) {
    final seen = <String>{};
    final keys = <String>[];
    for (final part in raw.split(RegExp(r'[\r\n,;]+'))) {
      final k = part.trim();
      if (k.isNotEmpty && seen.add(k)) {
        keys.add(k);
      }
    }
    return keys;
  }

  /// Masks an API key safely for DevLogger diagnostics.
  static String maskApiKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return '<none>';
    if (trimmed.length <= 10) return '***';
    return '${trimmed.substring(0, 4)}***${trimmed.substring(trimmed.length - 4)}';
  }

  static String _providerLabel(AIProviderType type) {
    switch (type) {
      case AIProviderType.ollama:
        return 'Ollama';
      case AIProviderType.lmStudio:
        return 'LM Studio';
      case AIProviderType.openAiCompatible:
        return 'BYOK OpenAI-Compatible';
      case AIProviderType.anthropic:
        return 'Anthropic Claude';
    }
  }

  static String _normalizeBaseUrl(String url) {
    var normalized = url.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static bool _hasVersionPathSuffix(String baseUrl) {
    final lower = baseUrl.toLowerCase();
    return lower.endsWith('/v1') ||
        lower.endsWith('/v1beta/openai') ||
        lower.endsWith('/v1beta') ||
        lower.endsWith('/v2') ||
        lower.endsWith('/v3') ||
        lower.endsWith('/v4') ||
        lower.endsWith('/openai') ||
        lower.endsWith('/api/v1');
  }

  static String buildOpenAiChatUrl(String baseUrl) {
    final norm = _normalizeBaseUrl(baseUrl);
    if (norm.toLowerCase().endsWith('/chat/completions')) return norm;
    if (_hasVersionPathSuffix(norm)) return '$norm/chat/completions';
    return '$norm/v1/chat/completions';
  }

  static String buildOpenAiModelsUrl(String baseUrl) {
    final norm = _normalizeBaseUrl(baseUrl);
    if (norm.toLowerCase().endsWith('/models')) return norm;
    if (_hasVersionPathSuffix(norm)) return '$norm/models';
    return '$norm/v1/models';
  }

  static String buildAnthropicMessagesUrl(String baseUrl) {
    final norm = _normalizeBaseUrl(baseUrl);
    if (norm.toLowerCase().endsWith('/messages')) return norm;
    if (norm.toLowerCase().endsWith('/v1')) return '$norm/messages';
    return '$norm/v1/messages';
  }

  static String buildAnthropicModelsUrl(String baseUrl) {
    final norm = _normalizeBaseUrl(baseUrl);
    if (norm.toLowerCase().endsWith('/models')) return norm;
    if (norm.toLowerCase().endsWith('/v1')) return '$norm/models';
    return '$norm/v1/models';
  }

  String get _chatUrl {
    switch (_providerType) {
      case AIProviderType.ollama:
        return '$_baseUrl/api/chat';
      case AIProviderType.lmStudio:
      case AIProviderType.openAiCompatible:
        return buildOpenAiChatUrl(_baseUrl);
      case AIProviderType.anthropic:
        return buildAnthropicMessagesUrl(_baseUrl);
    }
  }

  String get _tagsUrl {
    switch (_providerType) {
      case AIProviderType.ollama:
        return '$_baseUrl/api/tags';
      case AIProviderType.lmStudio:
      case AIProviderType.openAiCompatible:
        return buildOpenAiModelsUrl(_baseUrl);
      case AIProviderType.anthropic:
        return buildAnthropicModelsUrl(_baseUrl);
    }
  }

  String get _pullUrl => '$_baseUrl/api/pull';
  String get _deleteUrl => '$_baseUrl/api/delete';

  Map<String, String> _buildHeaders({
    required AIProviderType providerType,
    String? apiKey,
    String? baseUrl,
  }) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final key = apiKey?.trim() ?? '';
    if (providerType == AIProviderType.anthropic) {
      if (key.isNotEmpty) {
        headers['x-api-key'] = key;
      }
      headers['anthropic-version'] = '2023-06-01';
    } else if ((providerType == AIProviderType.openAiCompatible ||
            providerType == AIProviderType.lmStudio) &&
        key.isNotEmpty) {
      headers['Authorization'] = 'Bearer $key';
      if ((baseUrl ?? _baseUrl).toLowerCase().contains('openrouter.ai')) {
        headers['HTTP-Referer'] = 'https://github.com/d-init-d/FluxOrigin';
        headers['X-Title'] = 'FluxOrigin';
      }
    }
    return headers;
  }

  String? _nextKey(List<String> keys) {
    if (keys.isEmpty) return null;
    final selected = keys[_keyCursor % keys.length];
    _keyCursor = (_keyCursor + 1) % keys.length;
    return selected;
  }

  /// Check connection to AI server (supports Ollama, LM Studio, and BYOK endpoints).
  Future<(bool, String?, int)> checkConnection({
    String? url,
    AIProviderType? providerType,
    String? apiKey,
  }) async {
    final testUrl = _normalizeBaseUrl(url ?? _baseUrl);
    final provider = providerType ?? _providerType;
    final keys = apiKey != null ? parseApiKeys(apiKey) : _apiKeys;
    final activeKey = keys.isNotEmpty ? keys.first : '';

    if ((provider == AIProviderType.openAiCompatible ||
            provider == AIProviderType.anthropic) &&
        activeKey.isEmpty) {
      return (false, 'error_missing_key', 0);
    }

    String modelsEndpoint;
    switch (provider) {
      case AIProviderType.ollama:
        modelsEndpoint = '$testUrl/api/tags';
        break;
      case AIProviderType.lmStudio:
      case AIProviderType.openAiCompatible:
        modelsEndpoint = buildOpenAiModelsUrl(testUrl);
        break;
      case AIProviderType.anthropic:
        modelsEndpoint = buildAnthropicModelsUrl(testUrl);
        break;
    }

    try {
      final response = await http
          .get(
            Uri.parse(modelsEndpoint),
            headers: _buildHeaders(
              providerType: provider,
              apiKey: activeKey,
              baseUrl: testUrl,
            ),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        if (provider == AIProviderType.ollama) {
          final List<dynamic> models = data['models'] ?? [];
          return (true, null, models.length);
        } else {
          final List<dynamic> models = data['data'] ?? [];
          return (true, null, models.length);
        }
      } else {
        return (false, 'error_status:${response.statusCode}', 0);
      }
    } on http.ClientException {
      return (false, 'error_connect', 0);
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        return (false, 'error_timeout', 0);
      }
      return (false, 'error_generic', 0);
    }
  }

  static const Map<String, String> _prompts = {
    "KIEMHIEP":
        "Bạn là dịch giả kiếm hiệp lão luyện. Dùng từ Hán Việt chuẩn xác (huynh, đệ, tại hạ, tôn giả...), văn phong hào hùng, cổ trang. Chiêu thức và danh hiệu giữ nguyên âm Hán Việt.",
    "TIEN_HIEP":
        "Bạn là dịch giả tiên hiệp - huyền huyễn lão luyện. Giữ chuẩn hệ thống cảnh giới tu luyện, pháp bảo, tông môn bằng âm Hán Việt trang nhã, câu văn giàu nhịp điệu.",
    "NGONTINH":
        "Bạn là dịch giả ngôn tình giàu cảm xúc. Văn phong mượt mà, tự nhiên, xưng hô nhất quán theo quan hệ nhân vật.",
    "FANTASY":
        "Bạn là dịch giả văn học kỳ ảo và Light Novel. Giữ văn phong giàu hình ảnh, nhịp thoại sống động và nhất quán danh từ thế giới.",
    "KINHDOANH":
        "Bạn là chuyên gia kinh tế - quản trị. Dịch văn phong trang trọng, súc tích, dùng chuẩn thuật ngữ tài chính và doanh nghiệp.",
    "KHOAHOC":
        "Bạn là dịch giả khoa học - công nghệ. Dịch chính xác khái niệm khoa học, giữ chuẩn ký hiệu và viết hoa thuật ngữ chuyên ngành.",
    "KYTHUAT":
        "Bạn là kỹ sư phần mềm và dịch giả tài liệu kỹ thuật. Giữ nguyên từ khóa/acronym kỹ thuật chuẩn (API, CPU, GPU, LLM...) và diễn đạt câu tiếng Việt tự nhiên, rõ ràng.",
    "PHAPLY":
        "Bạn là chuyên gia dịch thuật pháp lý. Bảo toàn tuyệt đối hiệu lực ràng buộc (phải, có nghĩa vụ, không được), số điều khoản và thuật ngữ luật chuẩn mực.",
    "KHAC":
        "Bạn là một dịch giả chuyên nghiệp. Hãy dịch trôi chảy, tự nhiên, bám sát ý gốc và tránh lối dịch từng chữ.",
  };

  Future<String> detectGenre(String sample, String modelName) async {
    final response = await chatCompletion(
      modelName: modelName,
      messages: [
        {
          "role": "user",
          "content":
              "Bạn là trợ lý phân loại văn bản.\nHãy đọc đoạn văn bản mẫu dưới đây và xác định thể loại chính của nó.\nChỉ trả về DUY NHẤT một từ khóa trong danh sách sau: [KIEMHIEP, TIEN_HIEP, NGONTINH, FANTASY, KINHDOANH, KHOAHOC, KYTHUAT, PHAPLY, KHAC].\nTuyệt đối không giải thích gì thêm.\n\nVăn bản mẫu:\n$sample"
        }
      ],
    );

    final genre = response.trim().toUpperCase();
    if (_prompts.containsKey(genre)) {
      return genre;
    }
    for (final key in _prompts.keys) {
      if (genre.contains(key)) {
        return key;
      }
    }
    return "KHAC";
  }

  String getSystemPrompt(String genre, String sourceLang, String targetLang) {
    if (targetLang == 'Tiếng Việt' && _prompts.containsKey(genre)) {
      return _prompts[genre]!;
    }
    return "You are a professional literary and technical translator translating from $sourceLang to $targetLang (genre/domain: $genre). Translate faithfully, preserve voice, register, formatting anchors, and inline links without adding commentary.";
  }

  Future<String> generateGlossary(
    String sample,
    String modelName,
    String sourceLanguage,
    String genre, {
    String? candidateTermsBlock,
    String targetLanguage = 'Tiếng Việt',
  }) async {
    String promptContent;
    final bool isWuxia =
        genre == 'KIEMHIEP' || genre == 'TIEN_HIEP' || genre == 'NGONTINH';
    final candidatesSection = (candidateTermsBlock != null &&
            candidateTermsBlock.trim().isNotEmpty)
        ? "\n\nDANH SÁCH THỰC THỂ & THUẬT NGỮ XUẤT HIỆN XUYÊN SUỐT SÁCH (ưu tiên chuẩn hóa trước):\n$candidateTermsBlock"
        : "";

    if (sourceLanguage == 'Tiếng Trung' &&
        targetLanguage == 'Tiếng Việt' &&
        isWuxia) {
      promptContent = """NHIỆM VỤ: Phân tích văn bản Tiếng Trung và trích xuất các Tên Riêng (Nhân vật, Địa danh, Môn phái, Cảnh giới, Chiêu thức) để tạo từ điển Hán Việt.

QUY TẮC BẮT BUỘC (TUÂN THỦ TUYỆT ĐỐI):
1. ĐỊNH DẠNG OUTPUT: Chỉ trả về CSV 2 cột: `Từ gốc Trung,Hán Việt`. Không thêm STT, không thêm giải thích.
2. DỊCH HÁN VIỆT CHUẨN:
   - "长老" PHẢI dịch là "Trưởng lão".
   - "宗" PHẢI dịch là "Tông".
   - "师兄/师弟" PHẢI dịch là "Sư huynh/Sư đệ".
   - Tên người: Dịch nguyên theo âm Hán Việt (Ví dụ: 叶尘 -> Diệp Trần).
3. KHÔNG ĐƯỢC BỊA ĐẶT: Nếu không chắc chắn về âm Hán Việt, hãy bỏ qua từ đó.
4. KHÔNG dịch sang tiếng Anh.$candidatesSection

Văn bản:
$sample""";
    } else {
      promptContent = """TASK: Extract domain terminology, named entities, organizations, and recurring concepts from the text to build a consistent glossary.

STRICT OUTPUT RULES:
1. Return ONLY 2-column CSV lines: `OriginalTerm,TargetTranslation` (target language: $targetLanguage).
2. NO 3rd explanation column, NO CSV header row, NO markdown fences, NO trailing punctuation.
3. Preserve internationally established acronyms (API, AI, CPU, MRI, EBITDA...) when appropriate for $targetLanguage.
4. Ensure consistent proper noun spelling/transliteration across all sections.$candidatesSection

Text:
$sample""";
    }

    final response = await chatCompletion(modelName: modelName, messages: [
      {"role": "user", "content": promptContent}
    ], options: {
      "num_predict": 3000,
    });

    return parseGlossaryResponse(response);
  }

  /// Parses the raw AI glossary response into a clean CSV string.
  /// Single-pass parser with LinkedHashMap deduplication (first-occurrence wins).
  String parseGlossaryResponse(String response) {
    final StringBuffer cleanBuffer = StringBuffer();
    final List<String> lines =
        response.split('\n').where((l) => l.trim().isNotEmpty).toList();

    final filtered = lines.where((l) {
      final lower = l.toLowerCase().trim();
      return !(lower.startsWith('original') ||
          lower.startsWith('term') ||
          lower.startsWith('từ gốc') ||
          lower.startsWith('----') ||
          lower.startsWith('```'));
    }).toList();

    final LinkedHashMap<String, String> seen = LinkedHashMap<String, String>();

    for (var i = 0; i < filtered.length; i++) {
      final currentLine = filtered[i].trim();
      if (currentLine.isEmpty) continue;

      String? original;
      String? translated;

      final csvPattern = RegExp(r'"([^"]+)"\s*,\s*"([^"]+)"');
      final csvMatch = csvPattern.firstMatch(currentLine);
      if (csvMatch != null) {
        original = csvMatch.group(1)?.trim();
        translated = csvMatch.group(2)?.trim();
      }

      if (original == null || translated == null) {
        final commaParts = currentLine.split(',');
        if (commaParts.length >= 2) {
          original = commaParts[0].trim();
          translated = commaParts.sublist(1).join(',').trim();
        }
      }

      if (original == null || translated == null) {
        final colonParts = currentLine.split(':');
        if (colonParts.length >= 2) {
          original = colonParts[0].trim();
          translated = colonParts.sublist(1).join(':').trim();
        }
      }

      if (original == null || translated == null) {
        final dashParts = currentLine.split(' - ');
        if (dashParts.length >= 2) {
          original = dashParts[0].trim();
          translated = dashParts.sublist(1).join(' - ').trim();
        }
      }

      if (original == null || translated == null) {
        final hyphenParts = currentLine.split('-');
        if (hyphenParts.length >= 2) {
          original = hyphenParts[0].trim();
          translated = hyphenParts.sublist(1).join('-').trim();
        }
      }

      if (original == null ||
          translated == null ||
          original.isEmpty ||
          translated.isEmpty) {
        continue;
      }

      if (translated.length > 100) continue;

      if (!seen.containsKey(original)) {
        seen[original] = translated;
      }
    }

    for (final entry in seen.entries) {
      cleanBuffer.writeln('"${entry.key}","${entry.value}"');
    }

    return cleanBuffer.toString().trim();
  }

  Future<String> translateChunk(
    String chunk,
    String systemPrompt,
    String glossaryCsv,
    String modelName,
    String sourceLanguage,
    String targetLanguage, {
    String? previousContext,
    String? genre,
    String? styleGuide,
    bool sliceGlossary = true,
  }) async {
    final lowerModel = modelName.toLowerCase();
    final isSmallModel =
        lowerModel.contains('0.5b') || lowerModel.contains('1.5b');
    final hasAnchors = chunk.contains('<!-- @b');

    String constraints = "";
    if (targetLanguage == 'Tiếng Việt') {
      final bool isWuxia =
          genre == 'KIEMHIEP' || genre == 'TIEN_HIEP' || genre == 'NGONTINH';
      if (isWuxia) {
        constraints = """
CRITICAL OUTPUT RULES:
1. Translate faithfully into natural, idiomatic Vietnamese (Tiếng Việt).
2. ABSOLUTELY FORBIDDEN: Do not output leftover English words inside prose.
3. PUNCTUATION: Convert Chinese punctuation (「...」, ，, 。) to standard Vietnamese punctuation ("...", ,, .).
4. TERMINOLOGY: Use Sino-Vietnamese (Hán-Việt) strictly matching the Glossary for names, ranks, sects, and artifacts.
5. Never output untranslated Chinese characters. Output ONLY the Vietnamese translation.
6. NO TRANSLATOR NOTES unless clearly present in original footnote links.""";
      } else {
        constraints = """
CRITICAL OUTPUT RULES:
1. FULL SENTENCE TRANSLATION: Translate complete sentence structure, verbs, and nuance naturally into modern Vietnamese; avoid robotic passive calques ("bị/được") or "một cách" overuse.
2. TECHNICAL TERMS: Keep internationally established acronyms (AI, API, CPU, EBITDA...) in context where natural.
3. NO SOURCE SCRIPT LEAKAGE: Never output untranslated source sentences or Chinese characters.
4. PUNCTUATION: Normalize source punctuation to clean Vietnamese punctuation.
5. NO TRANSLATOR NOTES OR PREAMBLE.""";
      }
    }

    String anchorInstruction = "";
    if (hasAnchors) {
      anchorInstruction = """
### ANCHOR-LOCKED FORMAT PRESERVATION (MANDATORY):
The source contains HTML block anchors like `<!-- @b12 -->` and inline Markdown links `[label](href)` or images `![alt](src)`.
- Keep EVERY `<!-- @bN -->` marker on its own line immediately above its translated paragraph in exact order.
- Preserve every Markdown link target `(href)` and image target `(src)` intact while translating the visible `[label]` or `[alt]`.
""";
    }

    String contextInstruction = "";
    if (previousContext != null && previousContext.isNotEmpty) {
      contextInstruction = """
### CONTEXT FROM PREVIOUS SECTION:
"$previousContext"

Maintain continuity, pronoun registers, and character references from this context. Do NOT re-translate it — output ONLY the new section below.
""";
    }

    final styleSection =
        (styleGuide != null && styleGuide.trim().isNotEmpty && !isSmallModel)
            ? "\n\n$styleGuide"
            : "";

    String finalSystemPrompt;
    if (isSmallModel) {
      finalSystemPrompt =
          "You are a professional translator. Translate the following text into $targetLanguage. Output ONLY the translation. Do not repeat the input.\n$constraints\n$anchorInstruction\n$contextInstruction";
    } else if (targetLanguage == 'Tiếng Việt') {
      finalSystemPrompt =
          "$systemPrompt\n\n$constraints$styleSection\n\n$anchorInstruction$contextInstruction### YÊU CẦU DỊCH THUẬT NÂNG CAO:\n1. Dịch CHI TIẾT từng câu, tuyệt đối KHÔNG tóm tắt hay bỏ sót ý.\n2. Giữ nguyên sắc thái biểu cảm, thán từ và nhịp văn bản.\n3. Văn phong trôi chảy, chuẩn xuất bản tiếng Việt.\n\nOUTPUT ONLY THE VIETNAMESE TRANSLATION. NO PREAMBLE.";
    } else {
      finalSystemPrompt =
          "$systemPrompt$styleSection\n\n$anchorInstruction$contextInstruction\nOUTPUT ONLY THE $targetLanguage TRANSLATION. NO PREAMBLE.";
    }

    // D-Transcreate scoped glossary slicing for maximum adherence per token
    final activeGlossaryCsv = sliceGlossary
        ? DTranscreateService.sliceGlossaryForChunk(glossaryCsv, chunk)
        : glossaryCsv;

    String formattedGlossary = "";
    if (activeGlossaryCsv.isNotEmpty) {
      try {
        final List<List<dynamic>> rows = const CsvToListConverter().convert(
          activeGlossaryCsv,
          eol: '\n',
          shouldParseNumbers: false,
        );

        final StringBuffer buffer = StringBuffer();
        for (final row in rows) {
          if (row.length >= 2) {
            final original = row[0].toString().trim();
            final target = row[1].toString().trim();
            final definition = row.length > 2 ? row[2].toString().trim() : "";

            if (original.isNotEmpty && target.isNotEmpty) {
              if (isSmallModel) {
                buffer.write("$original: $target\n");
              } else {
                buffer.write("- Term: $original\n");
                buffer.write("  Target: $target\n");
                if (definition.isNotEmpty) {
                  buffer.write("  Context: $definition\n");
                }
              }
            }
          }
        }
        formattedGlossary = buffer.toString().trim();
      } catch (_) {
        formattedGlossary = activeGlossaryCsv;
      }
    }

    if (formattedGlossary.isNotEmpty) {
      finalSystemPrompt += "\n\n### GLOSSARY:\n$formattedGlossary";
    }

    final rawResponse = await chatCompletion(
      modelName: modelName,
      messages: [
        {"role": "system", "content": finalSystemPrompt},
        {
          "role": "user",
          "content":
              "Translate the following text from $sourceLanguage into $targetLanguage:\n\n$chunk"
        }
      ],
      options: {
        "timeout": 28800000,
        if (hasAnchors) "num_predict": 4096,
      },
    );

    final cleaned = _cleanResponse(rawResponse, sourceLanguage, targetLanguage);
    if (_isGarbageOutput(cleaned)) {
      return "";
    }
    return cleaned;
  }

  /// Public response cleanup helper (exposed for unit tests & UI post-processing).
  String cleanResponse(
    String raw,
    String targetLang, {
    String sourceLang = 'Tiếng Trung',
  }) {
    return _cleanResponse(raw, sourceLang, targetLang);
  }

  /// Checks if output is garbage (only punctuation, symbols, or very short).
  bool _isGarbageOutput(String text) {
    if (text.isEmpty) return true;
    final strippedAnchors =
        text.replaceAll(RegExp(r'<!--\s*@b\d+\s*-->'), '').trim();
    if (strippedAnchors.isEmpty) return true;

    final contentOnly = strippedAnchors.replaceAll(
        RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');

    if (contentOnly.isEmpty) return true;
    if (contentOnly.length < 3 && strippedAnchors.length > 10) return true;

    return false;
  }

  /// LAYER 2: String Sanitization (preserving anchors & Markdown links cleanly).
  String _cleanResponse(String raw, String sourceLang, String targetLang) {
    if (targetLang == 'Tiếng Trung') {
      return raw.trim();
    }

    String clean = raw.trim();

    // Strip markdown code-block wrappers if model wrapped output in ```...```
    final fenceMatch = RegExp(r'^```[a-zA-Z]*\s*\n([\s\S]*?)\n```$').firstMatch(clean);
    if (fenceMatch != null) {
      clean = fenceMatch.group(1)!.trim();
    }

    // Normalize smart & CJK quotation marks across languages
    clean = clean
        .replaceAll('\u201C', '"')
        .replaceAll('\u201D', '"')
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('「', '"')
        .replaceAll('」', '"')
        .replaceAll('『', '"')
        .replaceAll('』', '"')
        .replaceAll('\u3000', '');

    // Normalize Chinese punctuation cleanly
    if (sourceLang == 'Tiếng Trung') {
      clean = clean
          .replaceAll('。', '. ')
          .replaceAll('，', ', ')
          .replaceAll('、', ', ')
          .replaceAll('：', ': ')
          .replaceAll('？', '? ')
          .replaceAll('！', '! ')
          .replaceAll('（', '(')
          .replaceAll('）', ')')
          .replaceAll('《', '"')
          .replaceAll('》', '"')
          .replaceAll('…', '...')
          .replaceAll('～', '~')
          .replaceAll('·', ' ')
          .replaceAll('—', '-')
          .replaceAll('–', '-');
    }

    // Collapse mixed punctuation loops (e.g. ", . , . , ." -> ".") and long dot loops ("......" -> ".")
    clean = clean.replaceAllMapped(RegExp(r'\s+([.,;:?!])'), (m) => m.group(1)!);
    clean = clean.replaceAll(RegExp(r'(?:\s*[,.]){2,}\s*$'), '.');
    clean = clean.replaceAll(RegExp(r'\.{4,}\s*$'), '.');

    // Filter out lines that are strictly punctuation noise
    final lines = clean.split('\n');
    final cleanedLines = <String>[];
    final punctOnlyPattern = RegExp(r'^[\s.,;:!?\-"' "'" r'()\[\]{}]+' r'$');
    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) {
        if (cleanedLines.isNotEmpty && cleanedLines.last.isNotEmpty) {
          cleanedLines.add('');
        }
        continue;
      }
      if (punctOnlyPattern.hasMatch(trimmedLine)) continue;
      cleanedLines.add(trimmedLine);
    }
    clean = cleanedLines.join('\n').trim();

    // Strip outer wrapping quotes ONLY if string is a single unnested quoted block
    if (clean.length >= 2 &&
        clean.startsWith('"') &&
        clean.endsWith('"') &&
        clean.indexOf('"', 1) == clean.length - 1) {
      clean = clean.substring(1, clean.length - 1);
    } else if (clean.length >= 2 &&
        clean.startsWith("'") &&
        clean.endsWith("'") &&
        clean.indexOf("'", 1) == clean.length - 1) {
      clean = clean.substring(1, clean.length - 1);
    }

    // Strip prompt echo lines
    final processedLines = clean.split('\n');
    if (processedLines.isNotEmpty) {
      final firstLine = processedLines.first.toLowerCase();
      if (firstLine.contains("dịch đoạn văn bản") ||
          firstLine.contains("translate the following")) {
        clean = processedLines.sublist(1).join('\n').trim();
      }
    }

    if (targetLang == 'Tiếng Việt') {
      // Strip leaked parenthesized or loose Chinese characters
      clean = clean
          .replaceAll(RegExp(r'\s*\([^)]*[\u4e00-\u9fa5]+[^)]*\)'), '')
          .replaceAll(RegExp(r'\s*\[[^\]]*[\u4e00-\u9fa5]+[^\]]*\]'), '')
          .replaceAll(RegExp(r'\s*（[^）]*[\u4e00-\u9fa5]+[^）]*）'), '')
          .replaceAll(RegExp(r'[\u4e00-\u9fa5]+'), '');

      // Remove untranslated English martial/fantasy building suffixes after Vietnamese names
      if (sourceLang == 'Tiếng Trung') {
        clean = clean.replaceAllMapped(
          RegExp(
            r'\b([A-Z\u00C0-\u1EF9][A-Za-z\u00C0-\u1EF9]{1,}\s+[A-Z\u00C0-\u1EF9][A-Za-z\u00C0-\u1EF9]{1,})\s+(Hall|Sect|Pavilion|Palace)\b',
          ),
          (m) => m.group(1)!,
        );
      }

      // Fix punctuation artifacts left by CJK removal
      clean = clean
          .replaceAll(RegExp(r'(\s*[,.:;]\s*){2,}'), '. ')
          .replaceAll(RegExp(r'^\s*[,.:;]+\s*', multiLine: true), '')
          .replaceAll(RegExp(r'\s+[,:;]+\s*$', multiLine: true), '');
    }

    clean = clean.replaceAll(RegExp(r' {2,}'), ' ');
    return clean.trim();
  }

  /// LAYER 1: Multi-provider Chat Completion (Ollama, LM Studio, BYOK OpenAI-Compat, BYOK Anthropic)
  /// with automatic key rotation & backoff on rate limits (`429` / `503`).
  Future<String> chatCompletion({
    required String modelName,
    required List<Map<String, String>> messages,
    Map<String, dynamic>? options,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      final String finalModel = modelName.trim();
      if (finalModel.isEmpty) {
        _logger.error('AIService', 'chatCompletion failed: Model name is required');
        throw Exception("Model name is required");
      }

      final bool isCloudByok =
          _providerType == AIProviderType.openAiCompatible ||
          _providerType == AIProviderType.anthropic;

      if (isCloudByok && _apiKeys.isEmpty) {
        _logger.error('AIService', 'chatCompletion failed: API key is required for BYOK');
        throw Exception('API Key is required for BYOK provider. Check Settings -> BYOK.');
      }

      final double temperature =
          (options?['temperature'] as num?)?.toDouble() ?? _defaultTemperature;
      final int maxTokens = (options?['num_predict'] as int?) ?? 2048;

      Map<String, dynamic> buildRequestBody() {
        switch (_providerType) {
          case AIProviderType.anthropic:
            final systemParts = <String>[];
            final anthropicMsgs = <Map<String, String>>[];
            for (final msg in messages) {
              if ((msg['role'] ?? '') == 'system') {
                if ((msg['content'] ?? '').isNotEmpty) {
                  systemParts.add(msg['content']!);
                }
              } else {
                anthropicMsgs.add({
                  'role': msg['role'] == 'assistant' ? 'assistant' : 'user',
                  'content': msg['content'] ?? '',
                });
              }
            }
            return {
              'model': finalModel,
              'max_tokens': maxTokens,
              'temperature': temperature,
              if (systemParts.isNotEmpty) 'system': systemParts.join('\n\n'),
              'messages': anthropicMsgs,
            };

          case AIProviderType.lmStudio:
          case AIProviderType.openAiCompatible:
            return {
              'model': finalModel,
              'messages': messages,
              'stream': false,
              'temperature': temperature,
              'max_tokens': maxTokens,
            };

          case AIProviderType.ollama:
            final Map<String, dynamic> defaultOptions = {
              'temperature': temperature,
              'num_predict': maxTokens,
              'repeat_penalty': 1.2,
            };
            final Map<String, dynamic> mergedOptions = {
              ...defaultOptions,
              if (options != null) ...options,
            };
            mergedOptions.remove('timeout');
            return {
              'model': finalModel,
              'messages': messages,
              'stream': false,
              'options': mergedOptions,
            };
        }
      }

      final body = buildRequestBody();
      final lastMessage =
          messages.isNotEmpty ? messages.last['content'] ?? '' : '';
      final truncatedContent = lastMessage.length > 200
          ? '${lastMessage.substring(0, 200)}...'
          : lastMessage;

      final keysSnapshot = List<String>.from(_apiKeys);
      final int maxAttempts = isCloudByok
          ? (keysSnapshot.length > 1 ? keysSnapshot.length : 2)
          : 1;
      final int timeoutMs = options?['timeout'] ?? 300000;

      http.Response? response;
      String? usedKey;

      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        usedKey = _nextKey(keysSnapshot);
        final headers = _buildHeaders(
          providerType: _providerType,
          apiKey: usedKey,
          baseUrl: _baseUrl,
        );

        _logger.request(
          'AIService',
          'POST $_chatUrl | Model: $finalModel | Messages: ${messages.length} | Key: ${usedKey != null ? maskApiKey(usedKey) : 'local'}',
          details: 'Last message (truncated): $truncatedContent',
        );

        response = await http
            .post(
              Uri.parse(_chatUrl),
              headers: headers,
              body: jsonEncode(body),
            )
            .timeout(
              Duration(milliseconds: timeoutMs),
              onTimeout: () {
                throw Exception(
                    'AI request timed out after ${timeoutMs ~/ 1000} seconds. Please check connection or timeout.');
              },
            );

        if (response.statusCode == 200) {
          break;
        }

        final isRetryable = response.statusCode == 429 ||
            response.statusCode == 503 ||
            response.statusCode == 502;
        if (isRetryable && attempt + 1 < maxAttempts) {
          _logger.warning(
            'AIService',
            'Rate-limit / transient HTTP ${response.statusCode}; rotating key & retrying (${attempt + 2}/$maxAttempts)',
          );
          await Future.delayed(Duration(milliseconds: 900 * (attempt + 1)));
          continue;
        }
        break;
      }

      stopwatch.stop();

      if (response != null && response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        String content = '';

        switch (_providerType) {
          case AIProviderType.anthropic:
            final blocks = json['content'] as List?;
            if (blocks != null) {
              content = blocks
                  .whereType<Map>()
                  .where((b) => b['type'] == 'text')
                  .map((b) => b['text']?.toString() ?? '')
                  .join('\n');
            }
            break;
          case AIProviderType.lmStudio:
          case AIProviderType.openAiCompatible:
            final choices = json['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              content = choices[0]['message']?['content']?.toString() ?? '';
            }
            break;
          case AIProviderType.ollama:
            content = json['message']?['content']?.toString() ?? '';
            break;
        }

        final truncatedResponse =
            content.length > 300 ? '${content.substring(0, 300)}...' : content;

        _logger.response(
          'AIService',
          'OK 200 | ${stopwatch.elapsedMilliseconds}ms | ${content.length} chars',
          details: 'Response (truncated): $truncatedResponse',
        );

        return content;
      } else {
        final status = response?.statusCode ?? 0;
        final respBody = response?.body ?? '';
        _logger.error(
          'AIService',
          'API Error $status | ${stopwatch.elapsedMilliseconds}ms',
          details: respBody,
        );
        final providerName = _providerLabel(_providerType);
        throw Exception("$providerName API Error: $status - $respBody");
      }
    } catch (e) {
      stopwatch.stop();
      _logger.error(
        'AIService',
        'chatCompletion failed | ${stopwatch.elapsedMilliseconds}ms',
        details: e.toString(),
      );
      final providerName = _providerLabel(_providerType);
      throw Exception("Failed to connect to $providerName: $e");
    }
  }

  Future<List<String>> getInstalledModels() async {
    try {
      final activeKey = _apiKeys.isNotEmpty ? _apiKeys.first : '';
      if ((_providerType == AIProviderType.openAiCompatible ||
              _providerType == AIProviderType.anthropic) &&
          activeKey.isEmpty) {
        return [];
      }

      final response = await http
          .get(
            Uri.parse(_tagsUrl),
            headers: _buildHeaders(
              providerType: _providerType,
              apiKey: activeKey,
              baseUrl: _baseUrl,
            ),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(utf8.decode(response.bodyBytes));

        if (_providerType == AIProviderType.ollama) {
          final List<dynamic> models = data['models'] ?? [];
          return models
              .map<String>((m) => m['name']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
        } else {
          final List<dynamic> models = data['data'] ?? [];
          final ids = models
              .map<String>((m) => m['id']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .map((id) => id.startsWith('models/') ? id.substring(7) : id)
              .toList();
          ids.sort();
          return ids;
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Check if current provider supports model management (pull/delete — Ollama only).
  bool get supportsModelManagement => _providerType == AIProviderType.ollama;

  Future<bool> pullModel(
      String modelName, Function(double progress) onProgress) async {
    if (!supportsModelManagement) {
      _logger.warning('AIService',
          'Model management not supported for LM Studio. Please load models in LM Studio app.');
      return false;
    }

    try {
      final request = http.Request('POST', Uri.parse(_pullUrl));
      request.body = jsonEncode({"name": modelName, "stream": true});
      request.headers.addAll({"Content-Type": "application/json"});

      final response = await request.send();

      if (response.statusCode == 200) {
        await response.stream.transform(utf8.decoder).listen((chunk) {
          final lines =
              chunk.split('\n').where((line) => line.trim().isNotEmpty);
          for (final line in lines) {
            try {
              final data = jsonDecode(line);
              if (data.containsKey('completed') && data.containsKey('total')) {
                final completed = data['completed'];
                final total = data['total'];
                if (total > 0) {
                  onProgress(completed / total);
                }
              } else if (data['status'] == 'success') {
                onProgress(1.0);
              }
            } catch (_) {}
          }
        }).asFuture();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Preload a model into local memory silently (no-op for cloud BYOK APIs).
  Future<void> preloadModel(String modelName) async {
    if (_providerType == AIProviderType.openAiCompatible ||
        _providerType == AIProviderType.anthropic) {
      return;
    }
    try {
      final String finalModel = modelName.trim();
      if (finalModel.isEmpty) return;

      final body = {
        "model": finalModel,
        "messages": [],
      };

      await http.post(
        Uri.parse(_chatUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );
    } catch (_) {}
  }

  /// Delete a model from Ollama.
  Future<bool> deleteModel(String modelName) async {
    if (!supportsModelManagement) {
      _logger.warning('AIService',
          'Model management not supported for LM Studio. Please manage models in LM Studio app.');
      return false;
    }

    try {
      final response = await http.delete(
        Uri.parse(_deleteUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"name": modelName}),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
