import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/app_theme.dart';

class FileUploadZone extends StatefulWidget {
  final bool isDark;
  final String title;
  final String subtitle;
  final IconData icon;

  const FileUploadZone({
    super.key,
    required this.isDark,
    this.title = 'Kéo thả tài liệu vào đây',
    this.subtitle = 'Hỗ trợ .TXT, .EPUB',
    this.icon = FontAwesomeIcons.cloudArrowUp,
  });

  @override
  State<FileUploadZone> createState() => _FileUploadZoneState();
}

class _FileUploadZoneState extends State<FileUploadZone> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        decoration: BoxDecoration(
          color: widget.isDark
              ? AppColors.darkSurface.withOpacity(0.5)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered
                ? (widget.isDark
                    ? Colors.grey[500]!
                    : AppColors.lightPrimary.withOpacity(0.5))
                : (widget.isDark ? const Color(0xFF444444) : Colors.grey[300]!),
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: _isHovered ? 1.1 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? Colors.white.withOpacity(0.1)
                          : AppColors.lightPrimary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Center(
                      child: FaIcon(
                        widget.icon,
                        size: 28,
                        color: widget.isDark
                            ? Colors.white.withOpacity(0.9)
                            : AppColors.lightPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.title,
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
                  widget.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.isDark
                        ? Colors.grey[500]
                        : AppColors.lightPrimary.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['txt', 'epub'],
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isDark
                        ? Colors.white.withOpacity(0.1)
                        : AppColors.lightPrimary.withOpacity(0.1),
                    foregroundColor:
                        widget.isDark ? Colors.white : AppColors.lightPrimary,
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text(
                    'Chọn file',
                    style: TextStyle(
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
    );
  }
}
