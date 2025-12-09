import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../theme/config_provider.dart';
import '../../utils/app_strings.dart';

class FileUploadZone extends StatefulWidget {
  final bool isDark;
  final String? title;
  final String? subtitle;
  final IconData icon;
  final bool enabled;

  final Function(String)? onFileSelected;

  const FileUploadZone({
    super.key,
    required this.isDark,
    this.title,
    this.subtitle,
    this.icon = FontAwesomeIcons.cloudArrowUp,
    this.onFileSelected,
    this.enabled = true,
  });

  @override
  State<FileUploadZone> createState() => _FileUploadZoneState();
}

class _FileUploadZoneState extends State<FileUploadZone> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<ConfigProvider>().appLanguage;
    final displayTitle = widget.title ?? AppStrings.get(lang, 'drag_drop_file');
    final displaySubtitle = widget.subtitle ?? AppStrings.get(lang, 'supported_formats');
    
    return DropTarget(
      onDragEntered: (details) {
        if (widget.enabled) setState(() => _isDragging = true);
      },
      onDragExited: (details) {
        setState(() => _isDragging = false);
      },
      onDragDone: (details) {
        setState(() => _isDragging = false);
        if (!widget.enabled) return;
        if (details.files.isNotEmpty) {
          final file = details.files.first;
          final ext = path.extension(file.path).toLowerCase();
          if (ext == '.txt' || ext == '.epub') {
            widget.onFileSelected?.call(file.path);
          } else {
            // Optional: Show error for unsupported file type
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppStrings.get(lang, 'unsupported_format_error')),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }
      },
      child: MouseRegion(
        onEnter: (_) {
          if (widget.enabled) setState(() => _isHovered = true);
        },
        onExit: (_) => setState(() => _isHovered = false),
        child: Opacity(
          opacity: widget.enabled ? 1.0 : 0.5,
          child: Container(
          decoration: BoxDecoration(
            color: _isDragging
                ? (widget.isDark
                    ? AppColors.darkSurface.withValues(alpha: 0.8)
                    : Colors.blue.withValues(alpha: 0.1))
                : (widget.isDark
                    ? AppColors.darkSurface.withValues(alpha: 0.5)
                    : Colors.white),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isDragging
                  ? AppColors.lightPrimary
                  : (_isHovered
                      ? (widget.isDark
                          ? Colors.grey[500]!
                          : AppColors.lightPrimary.withValues(alpha: 0.5))
                      : (widget.isDark
                          ? const Color(0xFF444444)
                          : Colors.grey[300]!)),
              width: 2,
              strokeAlign: BorderSide.strokeAlignInside,
              style: _isDragging ? BorderStyle.solid : BorderStyle.solid,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedScale(
                    scale: _isHovered || _isDragging ? 1.1 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: widget.isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : AppColors.lightPrimary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Center(
                        child: FaIcon(
                          widget.icon,
                          size: 28,
                          color: widget.isDark
                              ? Colors.white.withValues(alpha: 0.9)
                              : AppColors.lightPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isDragging ? AppStrings.get(lang, 'drop_file_here') : displayTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: widget.isDark
                          ? Colors.grey[200]
                          : AppColors.lightPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    displaySubtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.isDark
                          ? Colors.grey[500]
                          : AppColors.lightPrimary.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: widget.enabled
                        ? () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['txt', 'epub'],
                            );
                            if (result != null && result.files.single.path != null) {
                              widget.onFileSelected?.call(result.files.single.path!);
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : AppColors.lightPrimary.withValues(alpha: 0.1),
                      foregroundColor:
                          widget.isDark ? Colors.white : AppColors.lightPrimary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      AppStrings.get(lang, 'choose_file'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

