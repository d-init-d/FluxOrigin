import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

class ConfigProvider extends ChangeNotifier {
  static const String _projectPathKey = 'project_path';

  String _projectPath = '';
  bool _isLoading = true;

  String get projectPath => _projectPath;
  bool get isLoading => _isLoading;

  bool get isConfigured => _projectPath.isNotEmpty;

  String get inputDir =>
      _projectPath.isEmpty ? '' : path.join(_projectPath, 'input');
  String get outputDir =>
      _projectPath.isEmpty ? '' : path.join(_projectPath, 'output');
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

    _isLoading = false;
    notifyListeners();
  }

  Future<void> setProjectPath(String projectPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_projectPathKey, projectPath);

    _projectPath = projectPath;
    notifyListeners();
  }
}
