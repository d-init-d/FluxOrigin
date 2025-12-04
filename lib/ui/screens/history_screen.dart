import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import '../theme/app_theme.dart';
import '../theme/config_provider.dart';
import '../../utils/app_strings.dart';

class HistoryItem {
  final String fileName;
  final DateTime date;
  final String status;

  const HistoryItem({
    required this.fileName,
    required this.date,
    required this.status,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      fileName: json['fileName'] ?? '',
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      status: json['status'] ?? 'unknown',
    );
  }

  String formattedDate(String lang) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return AppStrings.get(lang, 'yesterday');
    } else if (diff.inDays < 7) {
      return '${diff.inDays} ${AppStrings.get(lang, 'days_ago')}';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

class HistoryScreen extends StatefulWidget {
  final bool isDark;

  const HistoryScreen({super.key, required this.isDark});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}


class _HistoryScreenState extends State<HistoryScreen> {
  bool _isLoading = true;
  List<HistoryItem> _history = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistory());
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    final dictionaryDir = configProvider.dictionaryDir;

    if (dictionaryDir.isEmpty) {
      setState(() {
        _history = [];
        _isLoading = false;
      });
      return;
    }

    final historyPath = path.join(dictionaryDir, 'history_log.json');
    final historyFile = File(historyPath);

    if (!await historyFile.exists()) {
      setState(() {
        _history = [];
        _isLoading = false;
      });
      return;
    }

    try {
      final content = await historyFile.readAsString();
      final decoded = jsonDecode(content);
      
      if (decoded is List) {
        final items = decoded
            .map((e) => HistoryItem.fromJson(e as Map<String, dynamic>))
            .toList();
        
        // Sort by newest first
        items.sort((a, b) => b.date.compareTo(a.date));
        
        setState(() {
          _history = items;
          _isLoading = false;
        });
      } else {
        setState(() {
          _history = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
      setState(() {
        _history = [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<ConfigProvider>().appLanguage;
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.get(lang, 'history_title'),
                  style: GoogleFonts.merriweather(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: widget.isDark ? Colors.white : AppColors.lightPrimary,
                  ),
                ),
                IconButton(
                  onPressed: _loadHistory,
                  icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
                  tooltip: AppStrings.get(lang, 'refresh_tooltip'),
                  style: IconButton.styleFrom(
                    backgroundColor: widget.isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : AppColors.lightPrimary.withValues(alpha: 0.1),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Content
            Expanded(child: _buildContent()),
          ],
        ),
      ).animate().fadeIn(),
    );
  }

  Widget _buildContent() {
    final lang = context.watch<ConfigProvider>().appLanguage;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(
              FontAwesomeIcons.clockRotateLeft,
              size: 48,
              color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.get(lang, 'no_history'),
              style: TextStyle(
                fontSize: 16,
                color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.get(lang, 'no_history_subtitle'),
              style: TextStyle(
                fontSize: 14,
                color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _history.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _HistoryCard(
        isDark: widget.isDark,
        item: _history[index],
        lang: lang,
      ),
    );
  }
}


class _HistoryCard extends StatefulWidget {
  final bool isDark;
  final HistoryItem item;
  final String lang;

  const _HistoryCard({
    required this.isDark,
    required this.item,
    required this.lang,
  });

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: widget.isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isHovered
                ? (widget.isDark
                    ? Colors.white.withValues(alpha: 0.5)
                    : AppColors.lightPrimary.withValues(alpha: 0.5))
                : (widget.isDark
                    ? AppColors.darkBorder
                    : AppColors.lightBorder),
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: widget.isDark ? 0.3 : 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Icon (Left)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : AppColors.lightPrimary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: FaIcon(
                  widget.item.status == 'completed'
                      ? FontAwesomeIcons.circleCheck
                      : FontAwesomeIcons.fileLines,
                  size: 18,
                  color: widget.item.status == 'completed'
                      ? Colors.green
                      : (widget.isDark ? Colors.white : AppColors.lightPrimary),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Filename (Middle - Expanded)
            Expanded(
              child: Text(
                widget.item.fileName,
                style: GoogleFonts.merriweather(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : AppColors.lightPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(width: 16),

            // Date (Right)
            Text(
              widget.item.formattedDate(widget.lang),
              style: GoogleFonts.inter(
                fontSize: 13,
                color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
