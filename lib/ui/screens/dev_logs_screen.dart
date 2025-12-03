import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../../services/dev_logger.dart';

class DevLogsScreen extends StatefulWidget {
  final bool isDark;

  const DevLogsScreen({super.key, required this.isDark});

  @override
  State<DevLogsScreen> createState() => _DevLogsScreenState();
}

class _DevLogsScreenState extends State<DevLogsScreen> {
  final DevLogger _logger = DevLogger();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  LogLevel? _selectedLevel;
  String _searchQuery = '';
  bool _autoScroll = true;
  String? _expandedLogId;

  @override
  void initState() {
    super.initState();
    _logger.addListener(_onLogsChanged);
  }

  @override
  void dispose() {
    _logger.removeListener(_onLogsChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogsChanged() {
    if (mounted) {
      setState(() {});
      if (_autoScroll && _scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
  }

  List<LogEntry> get _filteredLogs {
    List<LogEntry> logs = _logger.logs;

    if (_selectedLevel != null) {
      logs = logs.where((log) => log.level == _selectedLevel).toList();
    }

    if (_searchQuery.isNotEmpty) {
      logs = logs
          .where((log) =>
              log.message.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              log.category.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (log.details
                      ?.toLowerCase()
                      .contains(_searchQuery.toLowerCase()) ??
                  false))
          .toList();
    }

    return logs;
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
      case LogLevel.request:
        return Colors.purple;
      case LogLevel.response:
        return Colors.teal;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                'Dev Logs',
                style: GoogleFonts.merriweather(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : AppColors.lightPrimary,
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange.withOpacity(0.5)),
                ),
                child: Text(
                  'DEV ONLY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
              const Spacer(),
              // Log count
              Text(
                '${_filteredLogs.length} / ${_logger.logs.length} logs',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Controls Row
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.isDark ? AppColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.isDark
                    ? AppColors.darkBorder
                    : AppColors.lightBorder,
              ),
            ),
            child: Column(
              children: [
                // Search and Filter Row
                Row(
                  children: [
                    // Search Box
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(
                          fontSize: 14,
                          color: widget.isDark ? Colors.white : Colors.black,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Tìm kiếm logs...',
                          hintStyle: TextStyle(
                            color: widget.isDark
                                ? Colors.grey[600]
                                : Colors.grey[400],
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            size: 18,
                            color: widget.isDark
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          filled: true,
                          fillColor: widget.isDark
                              ? Colors.black.withOpacity(0.2)
                              : AppColors.lightPaper,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() => _searchQuery = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Level Filter Dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: widget.isDark
                            ? Colors.black.withOpacity(0.2)
                            : AppColors.lightPaper,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<LogLevel?>(
                          value: _selectedLevel,
                          hint: Text(
                            'Tất cả levels',
                            style: TextStyle(
                              fontSize: 14,
                              color: widget.isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                          dropdownColor: widget.isDark
                              ? AppColors.darkSurface
                              : Colors.white,
                          items: [
                            DropdownMenuItem<LogLevel?>(
                              value: null,
                              child: Text(
                                'Tất cả levels',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: widget.isDark
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                            ),
                            ...LogLevel.values.map((level) => DropdownMenuItem(
                                  value: level,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: _getLevelColor(level),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        level.name.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: widget.isDark
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedLevel = value);
                          },
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Action Buttons Row
                Row(
                  children: [
                    // Auto-scroll toggle
                    _ActionButton(
                      icon: _autoScroll
                          ? FontAwesomeIcons.lock
                          : FontAwesomeIcons.lockOpen,
                      label: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
                      isActive: _autoScroll,
                      isDark: widget.isDark,
                      onTap: () => setState(() => _autoScroll = !_autoScroll),
                    ),
                    const SizedBox(width: 8),

                    // Toggle logging
                    _ActionButton(
                      icon: _logger.isEnabled
                          ? FontAwesomeIcons.play
                          : FontAwesomeIcons.pause,
                      label: _logger.isEnabled ? 'Logging ON' : 'Logging OFF',
                      isActive: _logger.isEnabled,
                      isDark: widget.isDark,
                      onTap: () {
                        _logger.setEnabled(!_logger.isEnabled);
                        setState(() {});
                      },
                    ),

                    const Spacer(),

                    // Copy all logs
                    _ActionButton(
                      icon: FontAwesomeIcons.copy,
                      label: 'Copy All',
                      isDark: widget.isDark,
                      onTap: () => _copyAllLogs(),
                    ),
                    const SizedBox(width: 8),

                    // Clear logs
                    _ActionButton(
                      icon: FontAwesomeIcons.trash,
                      label: 'Clear',
                      isDark: widget.isDark,
                      isDestructive: true,
                      onTap: () {
                        _logger.clear();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Logs List
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: widget.isDark
                    ? const Color(0xFF1E1E1E)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.isDark
                      ? AppColors.darkBorder
                      : AppColors.lightBorder,
                ),
              ),
              child: _filteredLogs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FaIcon(
                            FontAwesomeIcons.scroll,
                            size: 48,
                            color: widget.isDark
                                ? Colors.grey[700]
                                : Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _logger.logs.isEmpty
                                ? 'Chưa có logs nào'
                                : 'Không tìm thấy logs phù hợp',
                            style: TextStyle(
                              fontSize: 16,
                              color: widget.isDark
                                  ? Colors.grey[500]
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _filteredLogs.length,
                      padding: const EdgeInsets.all(8),
                      itemBuilder: (context, index) {
                        final log = _filteredLogs[index];
                        final logId = '${log.timestamp.microsecondsSinceEpoch}';
                        final isExpanded = _expandedLogId == logId;

                        return _LogEntryCard(
                          log: log,
                          isDark: widget.isDark,
                          isExpanded: isExpanded,
                          levelColor: _getLevelColor(log.level),
                          onTap: () {
                            setState(() {
                              _expandedLogId = isExpanded ? null : logId;
                            });
                          },
                          onCopy: () => _copyLog(log),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  void _copyLog(LogEntry log) {
    final text = '''
[${log.timestamp.toString()}] [${log.levelName}] [${log.category}]
${log.message}
${log.details != null ? '\nDetails:\n${log.details}' : ''}
'''
        .trim();

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Đã copy log!'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _copyAllLogs() {
    final buffer = StringBuffer();
    for (final log in _filteredLogs) {
      buffer.writeln(
          '[${log.timestamp.toString()}] [${log.levelName}] [${log.category}] ${log.message}');
      if (log.details != null) {
        buffer.writeln('  Details: ${log.details}');
      }
      buffer.writeln();
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã copy ${_filteredLogs.length} logs!'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final bool isActive;
  final bool isDestructive;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isDark,
    this.isActive = false,
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive
        ? Colors.red
        : isActive
            ? Colors.green
            : (isDark ? Colors.grey[400] : Colors.grey[600]);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withOpacity(0.2)
              : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: color!.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, size: 12, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogEntryCard extends StatelessWidget {
  final LogEntry log;
  final bool isDark;
  final bool isExpanded;
  final Color levelColor;
  final VoidCallback onTap;
  final VoidCallback onCopy;

  const _LogEntryCard({
    required this.log,
    required this.isDark,
    required this.isExpanded,
    required this.levelColor,
    required this.onTap,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isExpanded
              ? levelColor.withOpacity(0.5)
              : (isDark
                  ? const Color(0xFF3C3C3C)
                  : Colors.grey.withOpacity(0.2)),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  // Level Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: levelColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      log.levelName,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Consolas',
                        color: levelColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Category
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.blue.withOpacity(0.1)
                          : Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      log.category,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'Consolas',
                        color: isDark ? Colors.blue[300] : Colors.blue[700],
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Timestamp
                  Text(
                    _formatTimestamp(log.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'Consolas',
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),

                  if (log.details != null) ...[
                    const SizedBox(width: 8),
                    FaIcon(
                      isExpanded
                          ? FontAwesomeIcons.chevronUp
                          : FontAwesomeIcons.chevronDown,
                      size: 10,
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 6),

              // Message
              SelectableText(
                log.message,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Consolas',
                  color: isDark ? Colors.grey[300] : Colors.grey[800],
                ),
              ),

              // Expanded Details
              if (isExpanded && log.details != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.black.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Details',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                          InkWell(
                            onTap: onCopy,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: FaIcon(
                                FontAwesomeIcons.copy,
                                size: 12,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        log.details!,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Consolas',
                          color: isDark ? Colors.grey[400] : Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
  }
}
