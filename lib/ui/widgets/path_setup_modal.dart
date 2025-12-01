import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import '../theme/app_theme.dart';
import '../theme/config_provider.dart';

class PathSetupModal extends StatefulWidget {
  final bool isDark;
  final VoidCallback? onClose;
  final bool isDismissible;

  const PathSetupModal({
    super.key,
    required this.isDark,
    this.onClose,
    this.isDismissible = true,
  });

  @override
  State<PathSetupModal> createState() => _PathSetupModalState();
}

class _PathSetupModalState extends State<PathSetupModal> {
  final TextEditingController _projectController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<ConfigProvider>();
    _projectController.text = config.projectPath;
  }

  @override
  void dispose() {
    _projectController.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      setState(() {
        _projectController.text = selectedDirectory;
      });
    }
  }

  Future<void> _saveConfig() async {
    final projectPath = _projectController.text;
    if (projectPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn thư mục dự án')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Create subdirectories
      final inputDir = Directory(path.join(projectPath, 'input'));
      final outputDir = Directory(path.join(projectPath, 'output'));
      final dictionaryDir = Directory(path.join(projectPath, 'dictionary'));

      if (!await inputDir.exists()) await inputDir.create(recursive: true);
      if (!await outputDir.exists()) await outputDir.create(recursive: true);
      if (!await dictionaryDir.exists())
        await dictionaryDir.create(recursive: true);

      await context.read<ConfigProvider>().setProjectPath(projectPath);

      if (mounted) {
        setState(() => _isLoading = false);
        if (widget.onClose != null) {
          widget.onClose!();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tạo thư mục: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
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
                            'Cấu hình Dự án',
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
                        if (widget.isDismissible && widget.onClose != null)
                          IconButton(
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
                          'Hệ thống sẽ tự động tạo các thư mục con (input, output, dictionary) bên trong thư mục này.',
                          style: TextStyle(
                            fontSize: 13,
                            color: widget.isDark
                                ? Colors.grey[400]
                                : Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildPathInput(
                          'Thư mục Dự án (Project Folder)',
                          'Chọn thư mục gốc cho dự án',
                          _projectController,
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
                        if (widget.isDismissible && widget.onClose != null) ...[
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
                              'Hủy',
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
                        ],
                        ElevatedButton(
                          onPressed: _isLoading ? null : _saveConfig,
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
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text(
                                  'Lưu & Tạo thư mục',
                                  style: TextStyle(
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
            ),
          ).animate().scale(
                begin: const Offset(0.95, 0.95),
                end: const Offset(1, 1),
                duration: const Duration(milliseconds: 200),
              ),
        ),
      ),
    );
  }

  Widget _buildPathInput(
      String label, String hint, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: widget.isDark ? Colors.grey[300] : Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(
                    color: widget.isDark ? Colors.grey[500] : Colors.grey[400],
                  ),
                  filled: true,
                  fillColor: widget.isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: widget.isDark
                          ? const Color(0xFF444444)
                          : Colors.grey[300]!,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: widget.isDark
                          ? const Color(0xFF444444)
                          : Colors.grey[300]!,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: widget.isDark
                          ? Colors.white.withValues(alpha: 0.5)
                          : AppColors.lightPrimary.withValues(alpha: 0.5),
                    ),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: widget.isDark ? Colors.white : AppColors.lightPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _pickDirectory,
              icon: FaIcon(
                FontAwesomeIcons.folderOpen,
                size: 18,
                color: widget.isDark ? Colors.white : AppColors.lightPrimary,
              ),
              style: IconButton.styleFrom(
                backgroundColor: widget.isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : AppColors.lightPrimary.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
