import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../widgets/language_selector.dart';
import '../widgets/file_upload_zone.dart';

class TranslateScreen extends StatefulWidget {
  final bool isDark;

  const TranslateScreen({super.key, required this.isDark});

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  String _mode = 'document'; // 'document' or 'specialized'
  String _sourceLang = 'Tiếng Anh';
  String _targetLang = 'Tiếng Việt';
  bool _useCustomDict = true;

  final List<String> _allLanguages = ['Tiếng Anh', 'Tiếng Trung', 'Tiếng Việt'];

  void _swapLanguages() {
    setState(() {
      final temp = _sourceLang;
      _sourceLang = _targetLang;
      _targetLang = temp;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Mode Toggle
          Center(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: widget.isDark
                    ? Colors.white.withOpacity(0.1)
                    : const Color(0xFFE8E4D9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ModeButton(
                    icon: FontAwesomeIcons.file,
                    label: 'Tài liệu',
                    isActive: _mode == 'document',
                    isDark: widget.isDark,
                    onTap: () => setState(() => _mode = 'document'),
                  ),
                  _ModeButton(
                    icon: FontAwesomeIcons.briefcase,
                    label: 'Chuyên ngành',
                    isActive: _mode == 'specialized',
                    isDark: widget.isDark,
                    onTap: () => setState(() => _mode = 'specialized'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Language Control
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 192,
                child: LanguageSelector(
                  value: _sourceLang,
                  isDark: widget.isDark,
                  onChange: (lang) => setState(() => _sourceLang = lang),
                  availableLanguages: _allLanguages,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: IconButton(
                  onPressed: _swapLanguages,
                  icon: FaIcon(
                    FontAwesomeIcons.rightLeft,
                    size: 16,
                    color:
                        widget.isDark ? Colors.white : AppColors.lightPrimary,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: widget.isDark
                        ? Colors.white.withOpacity(0.1)
                        : AppColors.lightPrimary.withOpacity(0.1),
                    shape: const CircleBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 192,
                child: LanguageSelector(
                  value: _targetLang,
                  isDark: widget.isDark,
                  onChange: (lang) => setState(() => _targetLang = lang),
                  availableLanguages: _allLanguages,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Content based on mode
          Expanded(
            child: _mode == 'document'
                ? FileUploadZone(isDark: widget.isDark).animate().fadeIn()
                : _buildSpecializedMode(),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecializedMode() {
    return Column(
      children: [
        // Dictionary header with toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                FaIcon(
                  FontAwesomeIcons.bookBookmark,
                  size: 16,
                  color: widget.isDark ? Colors.white : AppColors.lightPrimary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Từ điển chuyên ngành',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color:
                        widget.isDark ? Colors.white : AppColors.lightPrimary,
                  ),
                ),
              ],
            ),
            Switch(
              value: _useCustomDict,
              onChanged: (value) => setState(() => _useCustomDict = value),
              activeTrackColor: const Color(0xFF043222),
              activeThumbColor: Colors.white,
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Conditional: Upload or AI box
        Container(
          height: 80,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _useCustomDict
                ? (widget.isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey[50])
                : (widget.isDark
                    ? Colors.white.withOpacity(0.05)
                    : const Color(0xFFE8E6DF)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _useCustomDict
                  ? (widget.isDark
                      ? const Color(0xFF444444)
                      : Colors.grey[300]!)
                  : (widget.isDark
                      ? const Color(0xFF444444)
                      : AppColors.lightBorder),
              style: _useCustomDict ? BorderStyle.solid : BorderStyle.solid,
            ),
          ),
          child: _useCustomDict
              ? Row(
                  children: [
                    FaIcon(
                      FontAwesomeIcons.upload,
                      size: 18,
                      color:
                          widget.isDark ? Colors.white : AppColors.lightPrimary,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Tải lên từ điển của bạn',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: widget.isDark
                                  ? Colors.grey[200]
                                  : Colors.grey[800],
                            ),
                          ),
                          Text(
                            '.CSV',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['csv'],
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: widget.isDark
                              ? Colors.grey[500]!
                              : Colors.grey[300]!,
                        ),
                        backgroundColor:
                            widget.isDark ? Colors.transparent : Colors.white,
                      ),
                      child: Text(
                        'Chọn file',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.isDark
                              ? Colors.grey[300]
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: widget.isDark
                            ? Colors.white.withOpacity(0.1)
                            : const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: FaIcon(
                          FontAwesomeIcons.wandMagicSparkles,
                          size: 18,
                          color: widget.isDark
                              ? Colors.white
                              : AppColors.lightAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'AI Tự động tạo từ điển',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: widget.isDark
                                  ? Colors.white
                                  : AppColors.lightPrimary,
                            ),
                          ),
                          Text(
                            'Hệ thống sẽ tự động phân tích tài liệu và trích xuất thuật ngữ chuyên ngành.',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.isDark
                                  ? Colors.grey[400]
                                  : AppColors.lightPrimary.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ).animate().fadeIn(),

        const SizedBox(height: 16),

        // Main upload zone
        Expanded(
          child: FileUploadZone(isDark: widget.isDark),
        ),
      ],
    ).animate().fadeIn();
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark ? Colors.white : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(
              icon,
              size: 12,
              color: isActive
                  ? (isDark ? Colors.black : AppColors.lightPrimary)
                  : (isDark
                      ? Colors.grey[400]
                      : AppColors.lightPrimary.withOpacity(0.6)),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isActive
                    ? (isDark ? Colors.black : AppColors.lightPrimary)
                    : (isDark
                        ? Colors.grey[400]
                        : AppColors.lightPrimary.withOpacity(0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
