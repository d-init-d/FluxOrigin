import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/ai_service.dart';

enum AIProvider { ollama, lmStudio, byok }

class ConfigProvider extends ChangeNotifier {
  static const String _projectPathKey = 'project_path';
  static const String _selectedModelKey = 'selected_model';
  static const String _ollamaUrlKey = 'ollama_url';
  static const String _lmStudioUrlKey = 'lm_studio_url';
  static const String _aiProviderKey = 'ai_provider';
  static const String _appLanguageKey = 'app_language';
  static const String _byokPresetKey = 'byok_preset';
  static const String _byokUrlPrefix = 'byok_url_';
  static const String _byokApiKeyPrefix = 'byok_key_';
  static const String _temperatureKey = 'ai_temperature';
  static const String _chunkSizeKey = 'target_chunk_size';
  static const String _deepModeKey = 'd_transcreate_deep_mode';
  static const String _preserveEpubLayoutKey = 'preserve_epub_layout';

  static const String _defaultOllamaUrl = 'http://localhost:11434';
  static const String _defaultLmStudioUrl = 'http://localhost:1234';

  String _projectPath = '';
  String _selectedModel = 'qwen2.5:7b';
  String _ollamaUrl = _defaultOllamaUrl;
  String _lmStudioUrl = _defaultLmStudioUrl;
  AIProvider _aiProvider = AIProvider.ollama;
  ByokPreset _byokPreset = ByokPreset.gemini;
  final Map<ByokPreset, String> _byokUrls = {
    for (final entry in AIService.byokPresets.entries)
      entry.key: entry.value.defaultBaseUrl,
  };
  final Map<ByokPreset, String> _byokApiKeys = {};

  double _temperature = 0.2;
  int _targetChunkSize = 1200;
  bool _dTranscreateDeepMode = true;
  bool _preserveEpubLayout = true;

  String _appLanguage = 'vi';
  bool _isLoading = true;
  bool _ollamaConnected = true;

  String get projectPath => _projectPath;
  String get selectedModel => _selectedModel;
  String get ollamaUrl => _ollamaUrl;
  String get lmStudioUrl => _lmStudioUrl;
  AIProvider get aiProvider => _aiProvider;
  ByokPreset get byokPreset => _byokPreset;
  String get byokUrl =>
      _byokUrls[_byokPreset] ??
      AIService.byokPresets[_byokPreset]!.defaultBaseUrl;
  String get byokApiKey => _byokApiKeys[_byokPreset] ?? '';
  double get temperature => _temperature;
  int get targetChunkSize => _targetChunkSize;
  bool get dTranscreateDeepMode => _dTranscreateDeepMode;
  bool get preserveEpubLayout => _preserveEpubLayout;
  String get appLanguage => _appLanguage;
  bool get isLoading => _isLoading;
  bool get ollamaConnected => _ollamaConnected;

  String get currentAiUrl {
    switch (_aiProvider) {
      case AIProvider.ollama:
        return _ollamaUrl;
      case AIProvider.lmStudio:
        return _lmStudioUrl;
      case AIProvider.byok:
        return byokUrl;
    }
  }

  AIProviderType get effectiveAiServiceType {
    switch (_aiProvider) {
      case AIProvider.ollama:
        return AIProviderType.ollama;
      case AIProvider.lmStudio:
        return AIProviderType.lmStudio;
      case AIProvider.byok:
        return AIService.byokPresets[_byokPreset]?.providerType ??
            AIProviderType.openAiCompatible;
    }
  }

  String get activeApiKey => _aiProvider == AIProvider.byok ? byokApiKey : '';

  String get activeProviderShortLabel {
    switch (_aiProvider) {
      case AIProvider.ollama:
        return 'Ollama';
      case AIProvider.lmStudio:
        return 'LM Studio';
      case AIProvider.byok:
        return AIService.byokPresets[_byokPreset]?.label ?? 'BYOK';
    }
  }

  bool get isConfigured => _projectPath.isNotEmpty;

  String get dictionaryDir =>
      _projectPath.isEmpty ? '' : path.join(_projectPath, 'dictionary');

  ConfigProvider() {
    loadConfig();
  }

  Future<void> loadConfig() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    _projectPath = prefs.getString(_projectPathKey) ?? '';
    _selectedModel = prefs.getString(_selectedModelKey) ?? 'qwen2.5:7b';
    _ollamaUrl = prefs.getString(_ollamaUrlKey) ?? _defaultOllamaUrl;
    _lmStudioUrl = prefs.getString(_lmStudioUrlKey) ?? _defaultLmStudioUrl;
    _appLanguage = prefs.getString(_appLanguageKey) ?? 'vi';
    _temperature = prefs.getDouble(_temperatureKey) ?? 0.2;
    _targetChunkSize = prefs.getInt(_chunkSizeKey) ?? 1200;
    _dTranscreateDeepMode = prefs.getBool(_deepModeKey) ?? true;
    _preserveEpubLayout = prefs.getBool(_preserveEpubLayoutKey) ?? true;

    final providerStr = prefs.getString(_aiProviderKey) ?? 'ollama';
    if (providerStr == 'lmStudio') {
      _aiProvider = AIProvider.lmStudio;
    } else if (providerStr == 'byok') {
      _aiProvider = AIProvider.byok;
    } else {
      _aiProvider = AIProvider.ollama;
    }

    final presetName = prefs.getString(_byokPresetKey) ?? ByokPreset.gemini.name;
    _byokPreset = ByokPreset.values.firstWhere(
      (p) => p.name == presetName,
      orElse: () => ByokPreset.gemini,
    );

    for (final preset in ByokPreset.values) {
      final savedUrl = prefs.getString('$_byokUrlPrefix${preset.name}');
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        _byokUrls[preset] = savedUrl.trim();
      }
      final savedKey = prefs.getString('$_byokApiKeyPrefix${preset.name}');
      if (savedKey != null && savedKey.isNotEmpty) {
        _byokApiKeys[preset] = savedKey;
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> setProjectPath(String projectPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_projectPathKey, projectPath);
    _projectPath = projectPath;
    notifyListeners();
  }

  Future<void> setSelectedModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedModelKey, model);
    _selectedModel = model;
    notifyListeners();
  }

  Future<void> setOllamaUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    String normalizedUrl = _stripTrailingSlash(url);
    await prefs.setString(_ollamaUrlKey, normalizedUrl);
    _ollamaUrl = normalizedUrl;
    notifyListeners();
  }

  Future<void> setLmStudioUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    String normalizedUrl = _stripTrailingSlash(url);
    await prefs.setString(_lmStudioUrlKey, normalizedUrl);
    _lmStudioUrl = normalizedUrl;
    notifyListeners();
  }

  Future<void> setAIProvider(AIProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aiProviderKey, provider.name);
    _aiProvider = provider;
    notifyListeners();
    await checkOllamaHealth();
  }

  Future<void> setByokPreset(ByokPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_byokPresetKey, preset.name);
    _byokPreset = preset;

    // Auto-select recommended model if current model looks like a local Ollama tag
    final spec = AIService.byokPresets[preset];
    if (spec != null && spec.suggestedModels.isNotEmpty) {
      if (_selectedModel.contains(':') || _selectedModel.isEmpty) {
        _selectedModel = spec.suggestedModels.first;
        await prefs.setString(_selectedModelKey, _selectedModel);
      }
    }
    notifyListeners();
    await checkOllamaHealth();
  }

  Future<void> setByokUrl(String url, {ByokPreset? forPreset}) async {
    final preset = forPreset ?? _byokPreset;
    final normalized = _stripTrailingSlash(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_byokUrlPrefix${preset.name}', normalized);
    _byokUrls[preset] = normalized;
    notifyListeners();
  }

  Future<void> setByokApiKey(String rawKeys, {ByokPreset? forPreset}) async {
    final preset = forPreset ?? _byokPreset;
    final trimmed = rawKeys.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_byokApiKeyPrefix${preset.name}', trimmed);
    _byokApiKeys[preset] = trimmed;
    notifyListeners();
  }

  Future<void> setTemperature(double value) async {
    final clamped = value.clamp(0.0, 1.2);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_temperatureKey, clamped);
    _temperature = clamped;
    notifyListeners();
  }

  Future<void> setTargetChunkSize(int chars) async {
    final clamped = chars.clamp(500, 4000);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_chunkSizeKey, clamped);
    _targetChunkSize = clamped;
    notifyListeners();
  }

  Future<void> setDTranscreateDeepMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_deepModeKey, enabled);
    _dTranscreateDeepMode = enabled;
    notifyListeners();
  }

  Future<void> setPreserveEpubLayout(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_preserveEpubLayoutKey, enabled);
    _preserveEpubLayout = enabled;
    notifyListeners();
  }

  Future<void> setAppLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appLanguageKey, lang);
    _appLanguage = lang;
    notifyListeners();
  }

  /// Stealth Mode: Silently verifies active AI provider (Ollama, LM Studio, or BYOK key).
  Future<void> checkOllamaHealth() async {
    try {
      final service = AIService();
      final (ok, _, _) = await service.checkConnection(
        url: currentAiUrl,
        providerType: effectiveAiServiceType,
        apiKey: activeApiKey,
      );
      _ollamaConnected = ok;
    } catch (_) {
      _ollamaConnected = false;
    }
    notifyListeners();
  }

  static String _stripTrailingSlash(String url) {
    var normalized = url.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}
