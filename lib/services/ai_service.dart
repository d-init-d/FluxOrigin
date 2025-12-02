import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;

class AIService {
  static const String _baseUrl = 'http://127.0.0.1:11434/api/chat';

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

  Future<String> generateGlossary(String sample, String modelName, String sourceLanguage, String genre) async {
    // Prompt khác nhau tùy theo ngôn ngữ nguồn và thể loại
    String promptContent;
    if (sourceLanguage == 'Tiếng Trung') {
      // Kiểm tra thể loại: Kiếm Hiệp/Ngôn Tình vs Khoa học/Kỹ thuật/Hiện đại
      bool isWuxia = genre == 'KIEMHIEP' || genre == 'NGONTINH';
      
      if (isWuxia) {
        // === PROMPT CHO KIẾM HIỆP / NGÔN TÌNH (GIỮ NGUYÊN CŨ) ===
        promptContent = """NHIỆM VỤ: Phân tích văn bản Tiếng Trung và trích xuất các Tên Riêng (Nhân vật, Địa danh, Môn phái, Chiêu thức) để tạo từ điển Hán Việt.

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
        // === PROMPT CHO KHOA HỌC / KỸ THUẬT / HIỆN ĐẠI (MỚI) ===
        promptContent = """NHIỆM VỤ: Trích xuất thuật ngữ chuyên ngành (Technical Terms) và Tên riêng từ văn bản Tiếng Trung.

QUY TẮC QUAN TRỌNG:
1. ĐẦU RA CSV: `Từ gốc,Tiếng Việt`. Không thêm STT, không thêm giải thích.
2. THUẬT NGỮ CÔNG NGHỆ/KHOA HỌC:
   - GIỮ NGUYÊN các từ viết tắt tiếng Anh (LLM, LoRA, AI, GPU, PC, API, CPU, RAM, VRAM...). KHÔNG phiên âm (Ví dụ: Không dịch LoRA thành La Lạp).
   - Các thuật ngữ kỹ thuật nên dịch sang tiếng Việt hiện đại (Ví dụ: "微调" -> "Tinh chỉnh", "显存" -> "VRAM/Bộ nhớ đồ họa", "模型" -> "Mô hình").
3. KHÔNG dùng từ Hán Việt cổ trang (Không dịch "Teacher" là "Sư phụ" trong bối cảnh trường học hiện đại, dùng "Giáo viên").
4. Định nghĩa (Definition) nếu có hãy để ở cột 3.

Văn bản:
$sample""";
      }
    } else if (sourceLanguage == 'Tiếng Anh') {
      promptContent = """TASK: Extract Technical Terms and Proper Nouns from the English text below.

STRICT OUTPUT FORMAT (CSV - EXACTLY 2 COLUMNS):
Original Term,Vietnamese Translation

RULES:
1. Output ONLY 2 columns: `Original Term,Vietnamese Translation`. NO Definition column. NO extra columns.
2. Keep English acronyms and technical terms as-is (Blockchain, AI, Node, API, CPU, GPU, LLM...).
3. Translate descriptive terms naturally (e.g., "Decentralization" -> "Phi tập trung").
4. Keep Western names as-is (e.g., "Satoshi Nakamoto" -> "Satoshi Nakamoto").
5. Do NOT add Header row. Do NOT add numbering. Do NOT explain anything.

EXAMPLE OUTPUT:
Blockchain,Blockchain
Decentralization,Phi tập trung
Smart Contract,Hợp đồng thông minh
Satoshi Nakamoto,Satoshi Nakamoto

Text:
$sample""";
    } else {
      promptContent = """Analyze the text and list important Proper Nouns (Names, Places, Organizations). Output CSV with two columns: Original Term, Vietnamese Translation.

Example format:
Term1,Translation1
Term2,Translation2

Do NOT add Header. Do NOT explain anything.

Text:
$sample""";
    }

    final response = await chatCompletion(modelName: modelName, messages: [
      {
        "role": "user",
        "content": promptContent
      }
    ], options: {
      "num_predict": 3000
    });

    final List<String> lines = response.split('\n');
    final StringBuffer cleanBuffer = StringBuffer();

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final lower = trimmed.toLowerCase();
      if (lower.startsWith("sure") ||
          lower.startsWith("here") ||
          lower.startsWith("certainly") ||
          lower.startsWith("okay") ||
          lower.startsWith("note") ||
          lower.startsWith("of course") ||
          lower.contains("i can help") ||
          lower.contains("ai language model")) {
        continue;
      }

      if (trimmed.endsWith(':') &&
          !trimmed.contains(',') &&
          !trimmed.contains('-')) {
        continue;
      }

      String? original;
      String? vietnamese;
      String? definition;

      if (trimmed.contains(',')) {
        final parts = trimmed.split(',');
        if (parts.length >= 2) {
          original = parts[0].trim();
          vietnamese = parts[1].trim();
          if (parts.length > 2) definition = parts.sublist(2).join(',').trim();
        }
      } else if (trimmed.contains(':')) {
        final parts = trimmed.split(':');
        if (parts.length >= 2) {
          original = parts[0].trim();
          vietnamese = parts[1].trim();
          if (parts.length > 2) definition = parts.sublist(2).join(':').trim();
        }
      } else if (trimmed.contains('-')) {
        final parts = trimmed.split('-');
        if (parts.length >= 2) {
          original = parts[0].trim();
          vietnamese = parts[1].trim();
          if (parts.length > 2) definition = parts.sublist(2).join('-').trim();
        }
      }

      if (original != null &&
          vietnamese != null &&
          original.isNotEmpty &&
          vietnamese.isNotEmpty) {
        if (vietnamese.length > 100) continue;
        cleanBuffer.writeln(
            '"$original","$vietnamese"${definition != null ? ',"$definition"' : ''}');
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
\"$previousContext\"

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

    final contentOnly = text.replaceAll(
        RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');

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
    final punctOnlyPattern = RegExp(r'^[\s.,;:!?\-"' "'" r'()\[\]{}]+' + r'$');
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
      clean = clean.replaceAll(RegExp(r'\s+[,.:;]+\s*' + r'$', multiLine: true), '');
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
    try {
      final String finalModel = modelName.toLowerCase().replaceAll('-', ':');

      // LAYER 1: Strict Model Parameters to prevent hallucinations
      final Map<String, dynamic> defaultOptions = {
        "temperature": 0.2,      // Low creativity, high accuracy - kills hallucinations
        "num_predict": 2048,     // Prevents cut-off sentences
        "repeat_penalty": 1.2,   // Prevents loops like "rừngispereming" or ",,,"
      };

      // Merge caller options with defaults (caller options take precedence)
      final Map<String, dynamic> mergedOptions = {
        ...defaultOptions,
        if (options != null) ...options,
      };

      final body = {
        "model": finalModel,
        "messages": messages,
        "stream": false,
        "options": mergedOptions,
      };

      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        return json['message']['content'] ?? "";
      } else {
        throw Exception(
            "Ollama API Error: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      throw Exception("Failed to connect to Ollama: $e");
    }
  }

  Future<List<String>> getInstalledModels() async {
    try {
      final response =
          await http.get(Uri.parse('http://127.0.0.1:11434/api/tags'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> models = data['models'];
        return models.map<String>((m) => m['name'] as String).toList();
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  Future<bool> pullModel(
      String modelName, Function(double progress) onProgress) async {
    try {
      final request =
          http.Request('POST', Uri.parse('http://127.0.0.1:11434/api/pull'));
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
      final String finalModel = modelName.toLowerCase().replaceAll('-', ':');

      final body = {
        "model": finalModel,
        "messages": [],
      };

      await http.post(
        Uri.parse(_baseUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );
    } catch (e) {
      // Silent failure
    }
  }

  /// Delete a model from Ollama
  Future<bool> deleteModel(String modelName) async {
    try {
      final response = await http.delete(
        Uri.parse('http://127.0.0.1:11434/api/delete'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"name": modelName}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
