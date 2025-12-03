import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error, request, response }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String category;
  final String message;
  final String? details;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.details,
  });

  String get levelIcon {
    switch (level) {
      case LogLevel.debug:
        return '🔧';
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
      case LogLevel.request:
        return '📤';
      case LogLevel.response:
        return '📥';
    }
  }

  String get levelName {
    switch (level) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
      case LogLevel.request:
        return 'REQ';
      case LogLevel.response:
        return 'RES';
    }
  }
}

/// Singleton logger for development debugging
class DevLogger extends ChangeNotifier {
  static final DevLogger _instance = DevLogger._internal();
  factory DevLogger() => _instance;
  DevLogger._internal();

  final List<LogEntry> _logs = [];
  static const int _maxLogs = 1000;
  bool _isEnabled = true;

  List<LogEntry> get logs => List.unmodifiable(_logs);
  bool get isEnabled => _isEnabled;

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    notifyListeners();
  }

  void _addLog(LogLevel level, String category, String message,
      {String? details}) {
    if (!_isEnabled) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: message,
      details: details,
    );

    _logs.insert(0, entry); // Add to beginning for newest first

    // Trim old logs
    if (_logs.length > _maxLogs) {
      _logs.removeRange(_maxLogs, _logs.length);
    }

    notifyListeners();

    // Also print to console in debug mode
    if (kDebugMode) {
      debugPrint('[${entry.levelName}] [$category] $message');
      if (details != null) {
        debugPrint('  Details: $details');
      }
    }
  }

  void debug(String category, String message, {String? details}) {
    _addLog(LogLevel.debug, category, message, details: details);
  }

  void info(String category, String message, {String? details}) {
    _addLog(LogLevel.info, category, message, details: details);
  }

  void warning(String category, String message, {String? details}) {
    _addLog(LogLevel.warning, category, message, details: details);
  }

  void error(String category, String message, {String? details}) {
    _addLog(LogLevel.error, category, message, details: details);
  }

  void request(String category, String message, {String? details}) {
    _addLog(LogLevel.request, category, message, details: details);
  }

  void response(String category, String message, {String? details}) {
    _addLog(LogLevel.response, category, message, details: details);
  }

  void clear() {
    _logs.clear();
    notifyListeners();
  }

  /// Filter logs by level
  List<LogEntry> filterByLevel(LogLevel level) {
    return _logs.where((log) => log.level == level).toList();
  }

  /// Filter logs by category
  List<LogEntry> filterByCategory(String category) {
    return _logs
        .where((log) =>
            log.category.toLowerCase().contains(category.toLowerCase()))
        .toList();
  }

  /// Search logs
  List<LogEntry> search(String query) {
    final lowerQuery = query.toLowerCase();
    return _logs
        .where((log) =>
            log.message.toLowerCase().contains(lowerQuery) ||
            log.category.toLowerCase().contains(lowerQuery) ||
            (log.details?.toLowerCase().contains(lowerQuery) ?? false))
        .toList();
  }
}
