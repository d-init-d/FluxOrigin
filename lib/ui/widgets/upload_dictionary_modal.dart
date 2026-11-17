import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:csv/csv.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../services/dev_logger.dart';
import '../../utils/app_strings.dart';
import '../theme/app_theme.dart';
import '../theme/config_provider.dart';

class UploadDictionaryModal extends StatefulWidget {
  final bool isDark;
  final VoidCallback onClose;

  const UploadDictionaryModal({
    super.key,
    required this.isDark,
    required this.onClose,
  });

  @override
  State<UploadDictionaryModal> createState() => _UploadDictionaryModalState();
}

class _UploadDictionaryModalState extends State<UploadDictionaryModal> {
  final TextEditingController _nameController = TextEditingController();
  String? _selectedFile;
  bool _isDragging = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _setSelectedFile(String filePath) {
    final fileName = p.basenameWithoutExtension(filePath);
    setState(() {
      _selectedFile = filePath;
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = fileName;
      }
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'json'],
    );
    if (result != null && result.files.single.path != null) {
      _setSelectedFile(result.files.single.path!);
    }
  }

  void _handleDroppedFile(String filePath, String lang) {
    final ext = p.extension(filePath).toLowerCase();
    if (ext == '.csv' || ext == '.json') {
      _setSelectedFile(filePath);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppStrings.get(lang, 'unsupported_dict_format_error')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _handleUpload(String lang) async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.get(lang, 'error_missing_info')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orange,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    final config = context.read<ConfigProvider>();
    if (!config.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.get(lang, 'please_configure_project')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final srcFile = File(_selectedFile!);
      final rawContent = await srcFile.readAsString();
      final ext = p.extension(_selectedFile!).toLowerCase();

      String csvOut = rawContent;
      if (ext == '.json') {
        csvOut = _convertJsonDictionaryToCsv(rawContent);
      }

      final rawName = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : p.basenameWithoutExtension(_selectedFile!);
      final safeName =
          rawName.replaceAll(RegExp(r'[^\w\u00C0-\u024F\-\s]+'), '_').trim();
      final dictDir = Directory(config.dictionaryDir);
      if (!await dictDir.exists()) {
        await dictDir.create(recursive: true);
      }

      final targetFile = File(p.join(dictDir.path, '$safeName.csv'));
      await targetFile.writeAsString(csvOut, flush: true);

      DevLogger().info(
        'Dictionary',
        'Imported dictionary "$safeName.csv" from $_selectedFile',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.get(lang, 'dict_upload_success')
                  .replaceAll('{name}', '$safeName.csv'),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onClose();
      }
    } catch (e) {
      DevLogger().error('Dictionary', 'Failed to save uploaded dictionary',
          details: e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppStrings.get(lang, 'error_saving_file')}$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _convertJsonDictionaryToCsv(String rawJson) {
    final decoded = jsonDecode(rawJson);
    final rows = <List<String>>[];

    if (decoded is Map) {
      for (final entry in decoded.entries) {
        final key = entry.key.toString().trim();
        final val = entry.value.toString().trim();
        if (key.isNotEmpty && val.isNotEmpty) {
          rows.add([key, val]);
        }
      }
    } else if (decoded is List) {
      for (final item in decoded) {
        if (item is Map) {
          final orig = (item['original'] ??
                  item['term'] ??
                  item['source'] ??
                  item['key'] ??
                  '')
              .toString()
              .trim();
          final target = (item['target'] ??
                  item['translation'] ??
                  item['vietnamese'] ??
                  item['value'] ??
                  '')
              .toString()
              .trim();
          final def = (item['definition'] ?? item['context'] ?? '').toString().trim();
          if (orig.isNotEmpty && target.isNotEmpty) {
            rows.add(def.isEmpty ? [orig, target] : [orig, target, def]);
          }
        }
      }
    }

    return const ListToCsvConverter().convert(rows, eol: '\n');
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<ConfigProvider>().appLanguage;
    return DropTarget(
      onDragDone: (details) {
        if (details.files.isNotEmpty) {
          _handleDroppedFile(details.files.first.path, lang);
        }
      },
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          color: Colors.black.withValues(alpha: 0.5),
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                width: 500,
                margin: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: widget.isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.isDark
                        ? const Color(0xFF444444)
                        : Colors.grey[200]!,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: widget.isDark
                                ? const Color(0xFF444444)
                                : Colors.grey[200]!,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              AppStrings.get(lang, 'add_dict_title'),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Merriweather',
                                color: widget.isDark
                                    ? Colors.white
                                    : AppColors.lightPrimary,
                              ),
                            ),
                          ),
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: IconButton(
                              onPressed: widget.onClose,
                              icon: FaIcon(
                                FontAwesomeIcons.xmark,
                                size: 20,
                                color: widget.isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[500],
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: widget.isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.grey[100],
                                shape: const CircleBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Body
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.get(lang, 'dict_name_label'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: widget.isDark
                                  ? Colors.grey[300]
                                  : Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _nameController,
                            style: TextStyle(
                              fontSize: 14,
                              color: widget.isDark
                                  ? Colors.white
                                  : AppColors.lightPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: AppStrings.get(lang, 'dict_name_hint'),
                              hintStyle: TextStyle(
                                color: widget.isDark
                                    ? Colors.grey[600]
                                    : Colors.grey[400],
                              ),
                              filled: true,
                              fillColor: widget.isDark
                                  ? Colors.black.withValues(alpha: 0.2)
                                  : AppColors.lightPaper,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: widget.isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: widget.isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          DropTarget(
                            onDragEntered: (details) =>
                                setState(() => _isDragging = true),
                            onDragExited: (details) =>
                                setState(() => _isDragging = false),
                            onDragDone: (details) {
                              setState(() => _isDragging = false);
                              if (details.files.isNotEmpty) {
                                _handleDroppedFile(
                                    details.files.first.path, lang);
                              }
                            },
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _pickFile,
                                child: Container(
                                  height: 140,
                                  decoration: BoxDecoration(
                                    color: _isDragging
                                        ? (widget.isDark
                                            ? Colors.blue.withValues(alpha: 0.2)
                                            : Colors.blue
                                                .withValues(alpha: 0.1))
                                        : (widget.isDark
                                            ? Colors.white
                                                .withValues(alpha: 0.05)
                                            : Colors.grey[50]),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _isDragging
                                          ? AppColors.lightPrimary
                                          : (widget.isDark
                                              ? const Color(0xFF444444)
                                              : Colors.grey[300]!),
                                      width: 2,
                                      strokeAlign: BorderSide.strokeAlignInside,
                                    ),
                                  ),
                                  child: Center(
                                    child: _selectedFile != null
                                        ? _buildSelectedFileUI(lang)
                                        : _buildUploadPromptUI(lang),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Footer
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: widget.isDark
                                ? const Color(0xFF444444)
                                : Colors.grey[200]!,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: widget.onClose,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: widget.isDark
                                      ? const Color(0xFF444444)
                                      : Colors.grey[300]!,
                                ),
                              ),
                            ),
                            child: Text(
                              AppStrings.get(lang, 'cancel'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: widget.isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed:
                                _isSaving ? null : () => _handleUpload(lang),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.isDark
                                  ? Colors.white
                                  : AppColors.lightPrimary,
                              foregroundColor:
                                  widget.isDark ? Colors.black : Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Text(
                                    AppStrings.get(lang, 'upload_btn'),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().scale(
                    begin: const Offset(0.95, 0.95),
                    end: const Offset(1, 1),
                    duration: const Duration(milliseconds: 200),
                  ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUploadPromptUI(String lang) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FaIcon(
          FontAwesomeIcons.arrowUpFromBracket,
          size: 24,
          color: widget.isDark
              ? Colors.white.withValues(alpha: 0.7)
              : AppColors.lightPrimary.withValues(alpha: 0.7),
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            text: '${AppStrings.get(lang, 'drag_drop_or')} ',
            style: TextStyle(
              fontSize: 14,
              color: widget.isDark ? Colors.grey[200] : Colors.grey[700],
            ),
            children: [
              TextSpan(
                text: AppStrings.get(lang, 'browse_files'),
                style: TextStyle(
                  decoration: TextDecoration.underline,
                  color: widget.isDark ? Colors.white : AppColors.lightPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppStrings.get(lang, 'supported_dict_formats'),
          style: TextStyle(
            fontSize: 12,
            color: widget.isDark ? Colors.grey[500] : Colors.grey[400],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedFileUI(String lang) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FaIcon(
            FontAwesomeIcons.fileLines,
            size: 24,
            color: widget.isDark ? Colors.green[400] : Colors.green[600],
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.get(lang, 'file_selected'),
            style: TextStyle(
              fontSize: 12,
              color: widget.isDark ? Colors.grey[400] : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            p.basename(_selectedFile ?? ''),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: widget.isDark ? Colors.white : AppColors.lightPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
