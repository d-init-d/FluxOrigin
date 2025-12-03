import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

class ConfigProvider extends ChangeNotifier {
  static const String _projectPathKey = 'project_path';
  static const String _selectedModelKey = 'selected_model';
  static const String _appLanguageKey = 'app_language';

  String _projectPath = '';
  String _selectedModel = 'qwen2.5:7b'; // Default model
  String _appLanguage = 'vi'; // Default language
  bool _isLoading = true;

  String get projectPath => _projectPath;
  String get selectedModel => _selectedModel;
  String get appLanguage => _appLanguage;
  bool get isLoading => _isLoading;

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
    _appLanguage = prefs.getString(_appLanguageKey) ?? 'vi';

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

  Future<void> setAppLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appLanguageKey, lang);

    _appLanguage = lang;
    notifyListeners();
  }
}
