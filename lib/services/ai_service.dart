import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;
import 'dev_logger.dart';

enum AIProviderType { ollama, lmStudio }

class AIService {
  static const String _defaultBaseUrl = 'http://localhost:11434';
  String _baseUrl = _defaultBaseUrl;
  AIProviderType _providerType = AIProviderType.ollama;
  final DevLogger _logger = DevLogger();

  /// Set the base URL for AI API
  void setBaseUrl(String url) {
    // Normalize URL: remove trailing slash if present
    String normalizedUrl = url.trim();
    if (normalizedUrl.endsWith('/')) {
      normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 1);
    }
    _baseUrl = normalizedUrl;
    _logger.info('AIService', 'Base URL set to: $normalizedUrl');
  }

  /// Set the AI provider type
  void setProviderType(AIProviderType type) {
    _providerType = type;
    _logger.info('AIService',
        'Provider type set to: ${type == AIProviderType.ollama ? 'Ollama' : 'LM Studio'}');
  }

  /// Get the chat API endpoint based on provider
  String get _chatUrl {
    if (_providerType == AIProviderType.lmStudio) {
      return '$_baseUrl/v1/chat/completions';
    }
    return '$_baseUrl/api/chat';
  }

  /// Get the tags/models API endpoint based on provider
  String get _tagsUrl {
    if (_providerType == AIProviderType.lmStudio) {
      return '$_baseUrl/v1/models';
    }
    return '$_baseUrl/api/tags';
  }

  /// Get the pull API endpoint (Ollama only)
  String get _pullUrl => '$_baseUrl/api/pull';

  /// Get the delete API endpoint (Ollama only)
  String get _deleteUrl => '$_baseUrl/api/delete';

  /// Check connection to AI server
  /// Returns a tuple of (success, message)
  Future<(bool, String)> checkConnection(
      {String? url, AIProviderType? providerType}) async {
    final testUrl = url ?? _baseUrl;
    final provider = providerType ?? _providerType;
    String normalizedUrl = testUrl.trim();
    if (normalizedUrl.endsWith('/')) {
      normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 1);
    }

    final modelsEndpoint = provider == AIProviderType.lmStudio
        ? '$normalizedUrl/v1/models'
        : '$normalizedUrl/api/tags';

    try {
      final response = await http
          .get(Uri.parse(modelsEndpoint))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        if (provider == AIProviderType.lmStudio) {
          // LM Studio returns { data: [...] }
          final List<dynamic> models = data['data'] ?? [];
          return (
            true,
            'Kết nối LM Studio thành công! Đã tìm thấy ${models.length} model.'
          );
        } else {
          // Ollama returns { models: [...] }
          final List<dynamic> models = data['models'] ?? [];
          return (
            true,
            'Kết nối Ollama thành công! Đã tìm thấy ${models.length} model.'
          );
        }
      } else {
        return (false, 'Lỗi: Server trả về mã ${response.statusCode}');
      }
    } on http.ClientException catch (e) {
      return (false, 'Không thể kết nối: ${e.message}');
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        return (
          false,
          'Hết thời gian chờ. Kiểm tra lại URL hoặc server có đang chạy không.'
        );
      }
      return (
        false,
        'Lỗi kết nối: Không thể kết nối tới server. Hãy đảm bảo server đang chạy.'
      );
    }
  }

  static const Map<String, String> _prompts = {
    "KIEMHIEP":
        "Bạn là dịch giả kiếm hiệp lão luyện. Dùng từ Hán Việt (huynh, đệ, tại hạ...), văn phong hào hùng, cổ trang. Chiêu thức giữ nguyên âm Hán Việt.",
    "NGONTINH":
        "Bạn là dịch giả ngôn tình. Văn phong lãng mạn, nhẹ nhàng, ướt át. Xưng hô Anh - Em hoặc Chàng - Nàng tùy ngữ cảnh.",
    "KINHDOANH":
        "Bạn là chuyên gia kinh tế. Dịch văn phong trang trọng, chuyên nghiệp, dùng thuật ngữ chính xác.",
    "KHAC":
        "Bạn là một dịch giả chuyên nghiệp. Hãy dịch trôi chảy, tự nhiên, sát nghĩa gốc."
  };

  Future<String> detectGenre(String sample, String modelName) async {
    final response = await chatCompletion(
      modelName: modelName,
      messages: [
        {
          "role": "user",
          "content":
              "Bạn là một trợ lý phân loại văn học.\nHãy đọc đoạn văn bản mẫu dưới đây và xác định thể loại chính của nó.\nChỉ trả về DUY NHẤT một từ khóa trong danh sách sau: [KIEMHIEP, NGONTINH, KINHDOANH, KHOAHOC, KHAC].\nTuyệt đối không giải thích gì thêm.\n\nVăn bản mẫu:\n$sample"
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
    // Trường hợp đặc biệt: Tiếng Trung -> Tiếng Việt (Kiếm Hiệp/Ngôn Tình)
    if (sourceLang == 'Tiếng Trung' && targetLang == 'Tiếng Việt') {
      return _prompts[genre] ?? _prompts['KHAC']!;
    }

    // Các trường hợp khác: Prompt chung
    return "You are a professional translator translating from $sourceLang to $targetLang. Translate the text naturally and fluently while preserving the original meaning and tone.";
  }

  Future<String> generateGlossary(String sample, String modelName,
      String sourceLanguage, String genre) async {
    // Prompt khác nhau tùy theo ngôn ngữ nguồn và thể loại
    // Prompt khác nhau tùy theo ngôn ngữ nguồn và thể loại
    String promptContent;
    bool isWuxia = genre == 'KIEMHIEP' || genre == 'NGONTINH';

    if (sourceLanguage == 'Tiếng Trung' && isWuxia) {
      // === PROMPT CHO KIẾM HIỆP / NGÔN TÌNH (GIỮ NGUYÊN CŨ) ===
      promptContent =
          """NHIỆM VỤ: Phân tích văn bản Tiếng Trung và trích xuất các Tên Riêng (Nhân vật, Địa danh, Môn phái, Chiêu thức) để tạo từ điển Hán Việt.

QUY TẮC BẮT BUỘC (TUÂN THỦ TUYỆT ĐỐI):
1. ĐỊNH DẠNG OUTPUT: Chỉ trả về CSV 2 cột: `Từ gốc Trung,Hán Việt`. Không thêm STT, không thêm giải thích.
2. DỊCH HÁN VIỆT CHUẨN:
   - "长老" (Elder) PHẢI dịch là "Trưởng lão". (Cấm dịch là Lão Đế, Giả Li).
   - "宗" (Sect) PHẢI dịch là "Tông".
   - "师兄/师弟" PHẢI dịch là "Sư huynh/Sư đệ".
   - Tên người: Dịch nguyên theo âm Hán Việt (Ví dụ: 叶尘 -> Diệp Trần).
3. KHÔNG ĐƯỢC BỊA ĐẶT: Nếu không chắc chắn về âm Hán Việt, hãy bỏ qua từ đó.
4. KHÔNG dịch sang tiếng Anh.

Văn bản:
$sample""";
    } else {
      // === PROMPT MỚI CHO: TIẾNG ANH, KHOA HỌC, KỸ THUẬT, ĐỜI SỐNG, TIẾNG TRUNG (CHUYÊN NGÀNH) ===
      promptContent = """
NHIỆM VỤ: Trích xuất thuật ngữ chuyên ngành và Tên riêng để tạo từ điển.

YÊU CẦU ĐẦU RA NGHIÊM NGẶT:
1. CHỈ TRẢ VỀ CSV 2 CỘT: `Từ gốc,Nghĩa Tiếng Việt`.
2. TUYỆT ĐỐI KHÔNG có cột thứ 3 (Không giải thích, không định nghĩa).
3. KHÔNG có dòng tiêu đề (Header).
4. KHÔNG có dấu chấm câu thừa ở cuối dòng.
5. QUY TẮC DỊCH (Cột 2):
   - Thuật ngữ quốc tế (AI, CEO, MRI, LoRA...): GIỮ NGUYÊN tiếng Anh.
   - Thuật ngữ thường: Dịch sang tiếng Việt hiện đại.
   - KHÔNG dùng từ Hán Việt cổ cho văn bản khoa học.

Văn bản:
$sample
""";
    }

    final response = await chatCompletion(modelName: modelName, messages: [
      {"role": "user", "content": promptContent}
    ], options: {
      "num_predict": 3000
    });

    final List<String> lines = response.split('\n');
    final StringBuffer cleanBuffer = StringBuffer();

    for (final line in lines) {
      // 1. Xóa các dòng Header nếu AI lỡ sinh ra
      lines.removeWhere((line) {
        final lower = line.toLowerCase().trim();
        return lower.startsWith('original') ||
            lower.startsWith('term') ||
            lower.startsWith('từ gốc') ||
            lower.startsWith('----');
      });

      for (var i = 0; i < lines.length; i++) {
        String line = lines[i].trim();
        if (line.isEmpty) continue;

        // 2. Xử lý dấu phẩy cuối dòng nếu có (ví dụ: "Term,Viet,")
        if (line.endsWith(',')) {
          line = line.substring(0, line.length - 1).trim();
        }

        String? original;
        String? vietnamese;

        // 3. Ưu tiên dùng thư viện CSV để parse cho chuẩn
        try {
          List<List<dynamic>> rows = const CsvToListConverter()
              .convert(line, shouldParseNumbers: false);
          if (rows.isNotEmpty && rows[0].isNotEmpty) {
            final row = rows[0];
            if (row.length >= 2) {
              original = row[0].toString().trim();
              vietnamese = row[1].toString().trim();
            } else if (row.length == 1 && line.contains(',')) {
              // Fallback: CSV parser có thể fail nếu quote không đóng, thử split thủ công
              final parts = line.split(',');
              if (parts.length >= 2) {
                original = parts[0].trim();
                vietnamese = parts.sublist(1).join(',').trim();
              }
            }
          }
        } catch (e) {
          // Fallback nếu CSV parser lỗi
        }

        // 4. Nếu CSV parser không ra, thử split thủ công thông minh
        if (original == null || vietnamese == null) {
          if (line.contains(':')) {
            final parts = line.split(':');
            if (parts.length >= 2) {
              original = parts[0].trim();
              vietnamese = parts.sublist(1).join(':').trim();
            }
          } else if (line.contains('-')) {
            // Chỉ split bằng '-' nếu không phải là từ ghép (ví dụ: "Sino-Vietnamese")
            // Logic đơn giản: split ở dấu gạch ngang đầu tiên có khoảng trắng bao quanh hoặc là dấu gạch ngang duy nhất
            if (line.contains(' - ')) {
              final parts = line.split(' - ');
              if (parts.length >= 2) {
                original = parts[0].trim();
                vietnamese = parts.sublist(1).join(' - ').trim();
              }
            } else {
              final parts = line.split('-');
              if (parts.length >= 2) {
                original = parts[0].trim();
                vietnamese = parts.sublist(1).join('-').trim();
              }
            }
          }
        }

        if (original != null &&
            vietnamese != null &&
            original.isNotEmpty &&
            vietnamese.isNotEmpty) {
          if (vietnamese.length > 100) continue;
          cleanBuffer.writeln('"$original","$vietnamese"');
        }
      }
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
  }) async {
    final isSmallModel = modelName.toLowerCase().contains("0.5b") ||
        modelName.toLowerCase().contains("1.5b");

    // LAYER 3: Strict Constraints to prevent garbage output
    String constraints = "";
    if (targetLanguage == 'Tiếng Việt') {
      // Kiểm tra thể loại để áp dụng quy tắc phù hợp
      bool isWuxia = genre == 'KIEMHIEP' || genre == 'NGONTINH';

      if (isWuxia) {
        // === CONSTRAINTS CHO KIẾM HIỆP / NGÔN TÌNH ===
        constraints = """
CRITICAL OUTPUT RULES:
1. Translate to natural Vietnamese (Tiếng Việt).
2. **ABSOLUTELY FORBIDDEN:** Do not output ANY English words (e.g., 'cold', 'surrounding', 'kill', 'said'). Translate them ALL to Vietnamese context.
3. **PUNCTUATION:** Convert Chinese punctuation (「...」, ，, 。) to standard Vietnamese punctuation ("...", ,, .).
4. **TERMINOLOGY:** Use Sino-Vietnamese (Hán-Việt) for all Proper Nouns, Cultivation Ranks, and Sect Names based on the Glossary.
5. Never output the Chinese text again. Only the Vietnamese translation.
6. **NO TRANSLATOR NOTES:** Do not add footnotes or explanations.
""";
      } else {
        // === CONSTRAINTS CHO KHOA HỌC / KỸ THUẬT / HIỆN ĐẠI ===
        constraints = """
CRITICAL OUTPUT RULES:
1. **FULL SENTENCE TRANSLATION:** You MUST translate the complete sentence structure, verbs, prepositions, and connecting words into Vietnamese. DO NOT just list the technical terms.
   - Wrong: "Blockchain (Blockchain) (Decentralization)."
   - Right: "Cốt lõi của Blockchain (Blockchain) nằm ở sự phi tập trung (Decentralization)."
2. **TECHNICAL TERMS:** Keep English acronyms (Blockchain, AI, Node, CPU...) but translate the context around them naturally.
3. **NO CHINESE CHARACTERS:** Do not output Chinese text.
4. **PUNCTUATION:** Convert Chinese punctuation (「...」, ，, 。) to standard Vietnamese punctuation ("...", ,, .).
5. **MODERN STYLE:** Use modern Vietnamese vocabulary, NOT archaic Sino-Vietnamese (Hán-Việt cổ).
6. Never output the source text again. Only the Vietnamese translation.
7. **NO TRANSLATOR NOTES:** Do not add footnotes or explanations.
""";
      }
    }

    String contextInstruction = "";
    if (previousContext != null && previousContext.isNotEmpty) {
      contextInstruction = """
### CONTEXT FROM PREVIOUS SECTION:
The following is the ending of the previous translated section for continuity reference:
"$previousContext"

Use this context to maintain narrative flow, consistent pronouns, and proper subject references. Do NOT re-translate the context - only translate the new text below.

""";
    }

    String finalSystemPrompt;
    if (isSmallModel) {
      finalSystemPrompt =
          "You are a professional translator. Translate the following text into $targetLanguage. Output ONLY the translation. Do not repeat the input.\n$constraints";
      if (contextInstruction.isNotEmpty) {
        finalSystemPrompt += "\n$contextInstruction";
      }
    } else {
      if (targetLanguage == 'Tiếng Việt') {
        finalSystemPrompt =
            "$systemPrompt\n\n$constraints\n\n$contextInstruction### YÊU CẦU DỊCH THUẬT NÂNG CAO:\n1. Dịch CHI TIẾT từng câu, tuyệt đối KHÔNG được tóm tắt hay bỏ sót ý.\n2. Giữ nguyên sắc thái biểu cảm, các thán từ, mô tả nội tâm của nhân vật.\n3. Nếu gặp thơ ca hoặc câu đối, hãy dịch sao cho vần điệu hoặc giữ nguyên Hán Việt nếu cần.\n4. Văn phong phải trôi chảy, tự nhiên như người bản xứ viết.\n\nOUTPUT ONLY THE VIETNAMESE TRANSLATION. NO PREAMBLE.";
      } else {
        finalSystemPrompt =
            "$systemPrompt\n\n$contextInstruction\nOUTPUT ONLY THE TRANSLATION. NO PREAMBLE.";
      }
    }

    String formattedGlossary = "";
    try {
      final List<List<dynamic>> rows = const CsvToListConverter().convert(
        glossaryCsv,
        eol: '\n',
        shouldParseNumbers: false,
      );

      final StringBuffer buffer = StringBuffer();
      for (final row in rows) {
        if (row.length >= 2) {
          final original = row[0].toString().trim();
          final vietnamese = row[1].toString().trim();
          final definition = row.length > 2 ? row[2].toString().trim() : "";

          if (original.isNotEmpty && vietnamese.isNotEmpty) {
            if (isSmallModel) {
              buffer.write("$original: $vietnamese\n");
            } else {
              buffer.write("- Term: $original\n");
              buffer.write("  Vietnamese: $vietnamese\n");
              if (definition.isNotEmpty) {
                buffer.write("  Context/Definition: $definition\n");
              }
            }
          }
        }
      }
      formattedGlossary = buffer.toString().trim();
    } catch (e) {
      formattedGlossary = glossaryCsv;
    }

    if (formattedGlossary.isNotEmpty) {
      finalSystemPrompt += "\n\n### GLOSSARY:\n$formattedGlossary";
    }

    final rawResponse = await chatCompletion(modelName: modelName, messages: [
      {"role": "system", "content": finalSystemPrompt},
      {
        "role": "user",
        "content":
            "Translate the following text from $sourceLanguage into $targetLanguage:\n\n$chunk"
      }
    ], options: {
      "timeout": 28800000
    });

    final cleaned = _cleanResponse(rawResponse, sourceLanguage, targetLanguage);

    if (_isGarbageOutput(cleaned)) {
      return "";
    }

    return cleaned;
  }

  /// Checks if output is garbage (only punctuation, symbols, or very short)
  bool _isGarbageOutput(String text) {
    if (text.isEmpty) return true;

    final contentOnly =
        text.replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');

    if (contentOnly.isEmpty) return true;
    if (contentOnly.length < 3 && text.length > 10) return true;

    return false;
  }

  /// LAYER 2: Aggressive String Sanitization
  String _cleanResponse(String raw, String sourceLang, String targetLang) {
    if (targetLang == 'Tiếng Trung') {
      return raw.trim();
    }

    String clean = raw.trim();

    // Normalize Chinese quotes to standard quotes (áp dụng cho mọi ngôn ngữ nguồn)
    clean = clean.replaceAll('"', '"');
    clean = clean.replaceAll('"', '"');
    clean = clean.replaceAll('「', '"');
    clean = clean.replaceAll('」', '"');
    clean = clean.replaceAll('『', '"');
    clean = clean.replaceAll('』', '"');

    // Chỉ normalize dấu câu Trung Quốc nếu nguồn là Tiếng Trung
    if (sourceLang == 'Tiếng Trung') {
      clean = clean.replaceAll('。', '. ');
      clean = clean.replaceAll('，', ', ');
      clean = clean.replaceAll('、', ', ');
      clean = clean.replaceAll('：', ': ');
      clean = clean.replaceAll('？', '? ');
      clean = clean.replaceAll('！', '! ');
      clean = clean.replaceAll(''', "'");
      clean = clean.replaceAll(''', "'");
      clean = clean.replaceAll('（', '(');
      clean = clean.replaceAll('）', ')');
      clean = clean.replaceAll('《', '"');
      clean = clean.replaceAll('》', '"');
      clean = clean.replaceAll('…', '...');
      clean = clean.replaceAll('～', '~');
      clean = clean.replaceAll('·', ' ');
      clean = clean.replaceAll('—', '-');
      clean = clean.replaceAll('–', '-');
    }

    // Remove Hallucinated Symbol Sequences - filter out lines that are ONLY punctuation
    final lines = clean.split('\n');
    final cleanedLines = <String>[];
    final punctOnlyPattern = RegExp(r'^[\s.,;:!?\-"' "'" r'()\[\]{}]+' r'$');
    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) continue;
      if (punctOnlyPattern.hasMatch(trimmedLine)) {
        continue;
      }
      cleanedLines.add(line);
    }
    clean = cleanedLines.join('\n');

    // Standard cleaning (quotes)
    if (clean.startsWith('"') && clean.endsWith('"')) {
      clean = clean.substring(1, clean.length - 1);
    } else if (clean.startsWith("'") && clean.endsWith("'")) {
      clean = clean.substring(1, clean.length - 1);
    }

    // Strip prompt repetition
    final processedLines = clean.split('\n');
    if (processedLines.isNotEmpty) {
      final firstLine = processedLines.first.toLowerCase();
      if (firstLine.contains("dịch đoạn văn bản") ||
          firstLine.contains("translate the following")) {
        clean = processedLines.sublist(1).join('\n').trim();
      }
    }

    // Xóa ký tự Trung Quốc nếu đích là Tiếng Việt (bất kể ngôn ngữ nguồn)
    // Lý do: Model Qwen đôi khi bị ảo giác chèn tiếng Trung vào bản dịch Anh-Việt
    if (targetLang == 'Tiếng Việt') {
      // Remove parenthesized Chinese: (黑铁剑) or [黑铁剑] or （黑铁剑）
      clean = clean.replaceAll(RegExp(r'\([^)]*[\u4e00-\u9fa5]+[^)]*\)'), '');
      clean = clean.replaceAll(RegExp(r'\[[^\]]*[\u4e00-\u9fa5]+[^\]]*\]'), '');
      clean = clean.replaceAll(RegExp(r'（[^）]*[\u4e00-\u9fa5]+[^）]*）'), '');

      // Remove loose Chinese characters
      clean = clean.replaceAll(RegExp(r'[\u4e00-\u9fa5]+'), '');

      // Clean up hanging punctuation left after Chinese removal
      clean = clean.replaceAll(RegExp(r'(\s*[,.:;]\s*){2,}'), ' ');

      // Remove leading punctuation on lines
      clean = clean.replaceAll(RegExp(r'^\s*[,.:;]+\s*', multiLine: true), '');

      // Remove trailing orphan punctuation
      clean =
          clean.replaceAll(RegExp(r'\s+[,.:;]+\s*' r'$', multiLine: true), '');
    }

    // Final cleanup: Fix double/multiple spaces
    clean = clean.replaceAll(RegExp(r' {2,}'), ' ');

    return clean.trim();
  }

  /// LAYER 1: Strict Model Parameters in chatCompletion
  Future<String> chatCompletion(
      {required String modelName,
      required List<Map<String, String>> messages,
      Map<String, dynamic>? options}) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Model name is now directly from provider, no conversion needed
      final String finalModel = modelName.trim();

      if (finalModel.isEmpty) {
        _logger.error(
            'AIService', 'chatCompletion failed: Model name is required');
        throw Exception("Model name is required");
      }

      Map<String, dynamic> body;

      if (_providerType == AIProviderType.lmStudio) {
        // LM Studio uses OpenAI API format
        body = {
          "model": finalModel,
          "messages": messages,
          "stream": false,
          "temperature": options?['temperature'] ?? 0.2,
          "max_tokens": options?['num_predict'] ?? 2048,
        };
      } else {
        // Ollama API format
        // LAYER 1: Strict Model Parameters to prevent hallucinations
        final Map<String, dynamic> defaultOptions = {
          "temperature":
              0.2, // Low creativity, high accuracy - kills hallucinations
          "num_predict": 2048, // Prevents cut-off sentences
          "repeat_penalty":
              1.2, // Prevents loops like "rừngispereming" or ",,,"
        };

        // Merge caller options with defaults (caller options take precedence)
        final Map<String, dynamic> mergedOptions = {
          ...defaultOptions,
          if (options != null) ...options,
        };

        body = {
          "model": finalModel,
          "messages": messages,
          "stream": false,
          "options": mergedOptions,
        };
      }

      // Log request
      final lastMessage =
          messages.isNotEmpty ? messages.last['content'] ?? '' : '';
      final truncatedContent = lastMessage.length > 200
          ? '${lastMessage.substring(0, 200)}...'
          : lastMessage;
      _logger.request(
        'AIService',
        'POST $_chatUrl | Model: $finalModel | Messages: ${messages.length}',
        details:
            'Last message (truncated): $truncatedContent\n\nBody: ${jsonEncode(body)}',
      );

      // Get timeout from options, default to 5 minutes (300000ms)
      final int timeoutMs = options?['timeout'] ?? 300000;
      final response = await http.post(
        Uri.parse(_chatUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      ).timeout(
        Duration(milliseconds: timeoutMs),
        onTimeout: () {
          throw Exception(
              'AI request timed out after ${timeoutMs ~/ 1000} seconds. The model may still be loading. Please try again.');
        },
      );

      stopwatch.stop();

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));

        // Parse response based on provider
        String content;
        if (_providerType == AIProviderType.lmStudio) {
          // OpenAI format: { choices: [{ message: { content: "..." } }] }
          final choices = json['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            content = choices[0]['message']['content'] ?? "";
          } else {
            content = "";
          }
        } else {
          // Ollama format: { message: { content: "..." } }
          content = json['message']['content'] ?? "";
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
        _logger.error(
          'AIService',
          'API Error ${response.statusCode} | ${stopwatch.elapsedMilliseconds}ms',
          details: response.body,
        );
        final providerName =
            _providerType == AIProviderType.lmStudio ? 'LM Studio' : 'Ollama';
        throw Exception(
            "$providerName API Error: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      stopwatch.stop();
      _logger.error(
        'AIService',
        'chatCompletion failed | ${stopwatch.elapsedMilliseconds}ms',
        details: e.toString(),
      );
      final providerName =
          _providerType == AIProviderType.lmStudio ? 'LM Studio' : 'Ollama';
      throw Exception("Failed to connect to $providerName: $e");
    }
  }

  Future<List<String>> getInstalledModels() async {
    try {
      final response = await http.get(Uri.parse(_tagsUrl));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        if (_providerType == AIProviderType.lmStudio) {
          // LM Studio returns { data: [{ id: "model-name", ... }] }
          final List<dynamic> models = data['data'] ?? [];
          return models.map<String>((m) => m['id'] as String).toList();
        } else {
          // Ollama returns { models: [{ name: "model-name", ... }] }
          final List<dynamic> models = data['models'] ?? [];
          return models.map<String>((m) => m['name'] as String).toList();
        }
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  /// Check if current provider supports model management (pull/delete)
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
            } catch (e) {
              // Ignore parse errors for partial chunks
            }
          }
        }).asFuture();
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Preload a model into memory silently (fire-and-forget)
  Future<void> preloadModel(String modelName) async {
    try {
      // Model name is now directly from provider, no conversion needed
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
    } catch (e) {
      // Silent failure
    }
  }

  /// Delete a model from Ollama (not supported for LM Studio)
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
    } catch (e) {
      return false;
    }
  }
}
