import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

enum AIProvider { ollama, lmStudio }

class ConfigProvider extends ChangeNotifier {
  static const String _projectPathKey = 'project_path';
  static const String _selectedModelKey = 'selected_model';
  static const String _ollamaUrlKey = 'ollama_url';
  static const String _lmStudioUrlKey = 'lm_studio_url';
  static const String _aiProviderKey = 'ai_provider';
  static const String _appLanguageKey = 'app_language';
  static const String _defaultOllamaUrl = 'http://localhost:11434';
  static const String _defaultLmStudioUrl = 'http://localhost:1234';

  String _projectPath = '';
  String _selectedModel = 'qwen2.5:7b'; // Default model
  String _ollamaUrl = _defaultOllamaUrl;
  String _lmStudioUrl = _defaultLmStudioUrl;
  AIProvider _aiProvider = AIProvider.ollama;
  String _appLanguage = 'vi'; // Default language
  bool _isLoading = true;

  String get projectPath => _projectPath;
  String get selectedModel => _selectedModel;
  String get ollamaUrl => _ollamaUrl;
  String get lmStudioUrl => _lmStudioUrl;
  AIProvider get aiProvider => _aiProvider;
  String get appLanguage => _appLanguage;
  bool get isLoading => _isLoading;

  /// Get the current AI URL based on selected provider
  String get currentAiUrl =>
      _aiProvider == AIProvider.ollama ? _ollamaUrl : _lmStudioUrl;

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

    // Load AI provider
    final providerStr = prefs.getString(_aiProviderKey) ?? 'ollama';
    _aiProvider =
        providerStr == 'lmStudio' ? AIProvider.lmStudio : AIProvider.ollama;

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
    // Normalize URL: remove trailing slash if present
    String normalizedUrl = url.trim();
    if (normalizedUrl.endsWith('/')) {
      normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 1);
    }
    await prefs.setString(_ollamaUrlKey, normalizedUrl);

    _ollamaUrl = normalizedUrl;
    notifyListeners();
  }

  Future<void> setLmStudioUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    // Normalize URL: remove trailing slash if present
    String normalizedUrl = url.trim();
    if (normalizedUrl.endsWith('/')) {
      normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 1);
    }
    await prefs.setString(_lmStudioUrlKey, normalizedUrl);

    _lmStudioUrl = normalizedUrl;
    notifyListeners();
  }

  Future<void> setAIProvider(AIProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aiProviderKey,
        provider == AIProvider.lmStudio ? 'lmStudio' : 'ollama');

    _aiProvider = provider;
    notifyListeners();
  }

  Future<void> setAppLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appLanguageKey, lang);

    _appLanguage = lang;
    notifyListeners();
  }
}
