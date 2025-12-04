import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../theme/config_provider.dart';
import '../widgets/upload_dictionary_modal.dart';
import '../../utils/app_strings.dart';

class DictionaryScreen extends StatefulWidget {
  final bool isDark;

  const DictionaryScreen({super.key, required this.isDark});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  bool _showModal = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _dictionaries = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDictionaries());
  }

  Future<void> _loadDictionaries() async {
    setState(() => _isLoading = true);

    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    final dictionaryDir = configProvider.dictionaryDir;

    if (dictionaryDir.isEmpty) {
      setState(() {
        _dictionaries = [];
        _isLoading = false;
      });
      return;
    }

    final dir = Directory(dictionaryDir);
    if (!await dir.exists()) {
      setState(() {
        _dictionaries = [];
        _isLoading = false;
      });
      return;
    }

    final List<Map<String, dynamic>> dicts = [];

    try {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.csv')) {
          final file = entity;
          final stat = await file.stat();
          final fileName = file.path.split(Platform.pathSeparator).last;
          
          // Count lines (approximate entry count)
          int lineCount = 0;
          try {
            final content = await file.readAsString();
            lineCount = content.split('\n').where((l) => l.trim().isNotEmpty).length;
          } catch (_) {}

          // Format file size
          final sizeBytes = stat.size;
          String fileSize;
          if (sizeBytes >= 1024 * 1024) {
            fileSize = '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
          } else {
            fileSize = '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
          }

          dicts.add({
            'name': fileName,
            'entries': lineCount,
            'fileSize': fileSize,
            'path': file.path,
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading dictionaries: $e');
    }

    setState(() {
      _dictionaries = dicts;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<ConfigProvider>().appLanguage;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadDictionaries,
          child: Container(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.get(lang, 'dictionary_title'),
                          style: GoogleFonts.merriweather(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: widget.isDark
                                ? Colors.white
                                : AppColors.lightPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppStrings.get(lang, 'dictionary_subtitle'),
                          style: TextStyle(
                            fontSize: 14,
                            color: widget.isDark
                                ? Colors.grey[400]
                                : AppColors.lightPrimary.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _loadDictionaries,
                          icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
                          tooltip: AppStrings.get(lang, 'refresh_tooltip'),
                          style: IconButton.styleFrom(
                            backgroundColor: widget.isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : AppColors.lightPrimary.withValues(alpha: 0.1),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => setState(() => _showModal = true),
                          icon: const FaIcon(FontAwesomeIcons.plus, size: 14),
                          label: Text(AppStrings.get(lang, 'add_new')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                widget.isDark ? Colors.white : AppColors.lightPrimary,
                            foregroundColor:
                                widget.isDark ? Colors.black : Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Table
                Expanded(
                  child: Container(
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
                        // Table header
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? Colors.black.withValues(alpha: 0.2)
                                : Colors.grey[50]?.withValues(alpha: 0.5),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                            ),
                            border: Border(
                              bottom: BorderSide(
                                color: widget.isDark
                                    ? AppColors.darkBorder
                                    : Colors.grey[100]!,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  AppStrings.get(lang, 'dictionary_name'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: widget.isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[500],
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  AppStrings.get(lang, 'dictionary_size'),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: widget.isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[500],
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  AppStrings.get(lang, 'dictionary_entries'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: widget.isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[500],
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 48),
                            ],
                          ),
                        ),

                        // Table content
                        Expanded(
                          child: _buildContent(),
                        ),

                        // Footer
                        Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: widget.isDark
                                    ? AppColors.darkBorder
                                    : Colors.grey[100]!,
                                style: BorderStyle.solid,
                              ),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'Hiển thị ${_dictionaries.length} từ điển',
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: widget.isDark
                                    ? Colors.grey[600]
                                    : Colors.grey[400],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(),
        ),

        // Modal
        if (_showModal)
          UploadDictionaryModal(
            isDark: widget.isDark,
            onClose: () {
              setState(() => _showModal = false);
              _loadDictionaries(); // Refresh after adding
            },
          ),
      ],
    );
  }

  Widget _buildContent() {
    final lang = context.watch<ConfigProvider>().appLanguage;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_dictionaries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(
              FontAwesomeIcons.folderOpen,
              size: 48,
              color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.get(lang, 'no_dictionaries'),
              style: TextStyle(
                fontSize: 16,
                color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.get(lang, 'no_dictionaries_subtitle'),
              style: TextStyle(
                fontSize: 14,
                color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _dictionaries.length,
      itemBuilder: (context, index) => _DictRow(
        dict: _dictionaries[index],
        isDark: widget.isDark,
        isLast: index == _dictionaries.length - 1,
      ),
    );
  }
}


class _DictRow extends StatefulWidget {
  final Map<String, dynamic> dict;
  final bool isDark;
  final bool isLast;

  const _DictRow({
    required this.dict,
    required this.isDark,
    required this.isLast,
  });

  @override
  State<_DictRow> createState() => _DictRowState();
}

class _DictRowState extends State<_DictRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _isHovered
              ? (widget.isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey[50])
              : Colors.transparent,
          border: widget.isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: widget.isDark
                        ? const Color(0xFF2A2A2A)
                        : Colors.grey[50]!,
                  ),
                ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : AppColors.lightPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: FaIcon(
                        FontAwesomeIcons.book,
                        size: 12,
                        color: widget.isDark
                            ? Colors.white
                            : AppColors.lightPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.dict['name'],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color:
                            widget.isDark ? Colors.white : AppColors.lightPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                widget.dict['fileSize'],
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                widget.dict['entries'].toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: IconButton(
                onPressed: () {},
                icon: FaIcon(
                  FontAwesomeIcons.ellipsisVertical,
                  size: 16,
                  color: widget.isDark ? Colors.grey[400] : Colors.grey[400],
                ),
                style: IconButton.styleFrom(
                  backgroundColor: _isHovered
                      ? (widget.isDark
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.grey[200])
                      : Colors.transparent,
                  shape: const CircleBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
