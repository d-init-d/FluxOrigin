import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../theme/config_provider.dart';
import '../../utils/app_strings.dart';

class LanguageSelector extends StatefulWidget {
  final String value;
  final bool isDark;
  final Function(String) onChange;
  final List<String> availableLanguages;
  final String? disabledLanguage;

  const LanguageSelector({
    super.key,
    required this.value,
    required this.isDark,
    required this.onChange,
    required this.availableLanguages,
    this.disabledLanguage,
  });

  @override
  State<LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends State<LanguageSelector> {
  bool _isOpen = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _toggleDropdown() {
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      setState(() => _isOpen = false);
    } else {
      _isOpen = false;
    }
  }

  OverlayEntry _createOverlayEntry() {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _removeOverlay,
        child: Stack(
          children: [
            Positioned(
              width: size.width,
              child: CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                offset: Offset(0, size.height + 8),
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 280),
                    decoration: BoxDecoration(
                      color:
                          widget.isDark ? AppColors.darkSurface : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: widget.isDark
                            ? const Color(0xFF444444)
                            : Colors.grey[200]!,
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.availableLanguages.map((lang) {
                          final isSelected = lang == widget.value;
                          final isDisabled = lang == widget.disabledLanguage;
                          return InkWell(
                            onTap: isDisabled
                                ? null
                                : () {
                                    widget.onChange(lang);
                                    _removeOverlay();
                                  },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (widget.isDark
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : AppColors.lightPrimary
                                            .withValues(alpha: 0.1))
                                    : Colors.transparent,
                              ),
                              child: _buildLanguageItem(lang, isSelected),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageItem(String lang, bool isSelected) {
    final appLang = context.read<ConfigProvider>().appLanguage;
    final isDisabled = lang == widget.disabledLanguage;

    return Opacity(
      opacity: isDisabled ? 0.45 : 1.0,
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: widget.isDark
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                _getLanguageCode(lang),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.grey[600],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _getLocalizedLanguageName(lang, appLang),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: isDisabled
                    ? Colors.grey
                    : (isSelected
                        ? (widget.isDark
                            ? Colors.white
                            : AppColors.lightPrimary)
                        : (widget.isDark ? Colors.white : Colors.grey[800])),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (isSelected)
            FaIcon(
              FontAwesomeIcons.check,
              size: 12,
              color: widget.isDark ? Colors.white : AppColors.lightPrimary,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLang = context.watch<ConfigProvider>().appLanguage;
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _toggleDropdown,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: widget.isDark ? AppColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.isDark
                    ? const Color(0xFF444444)
                    : AppColors.lightBorder,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : AppColors.lightPrimary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      _getLanguageCode(widget.value),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: widget.isDark
                            ? Colors.white.withValues(alpha: 0.8)
                            : AppColors.lightPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _getLocalizedLanguageName(widget.value, appLang),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: widget.isDark
                          ? Colors.grey[200]
                          : AppColors.lightPrimary,
                    ),
                  ),
                ),
                FaIcon(
                  _isOpen
                      ? FontAwesomeIcons.chevronUp
                      : FontAwesomeIcons.chevronDown,
                  size: 11,
                  color: widget.isDark ? Colors.grey : Colors.grey[600],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getLanguageCode(String lang) {
    switch (lang) {
      case 'Tiếng Anh':
        return 'EN';
      case 'Tiếng Trung':
        return 'CN';
      case 'Tiếng Việt':
        return 'VI';
      case 'Tiếng Nhật':
        return 'JA';
      case 'Tiếng Hàn':
        return 'KO';
      case 'Tiếng Pháp':
        return 'FR';
      case 'Tiếng Đức':
        return 'DE';
      case 'Tiếng Tây Ban Nha':
        return 'ES';
      default:
        return lang.length >= 2 ? lang.substring(0, 2).toUpperCase() : lang;
    }
  }

  String _getLocalizedLanguageName(String langCode, String currentAppLang) {
    switch (langCode) {
      case 'Tiếng Anh':
        return AppStrings.get(currentAppLang, 'lang_en');
      case 'Tiếng Việt':
        return AppStrings.get(currentAppLang, 'lang_vi');
      case 'Tiếng Trung':
        return AppStrings.get(currentAppLang, 'lang_cn');
      case 'Tiếng Nhật':
        return AppStrings.get(currentAppLang, 'lang_ja');
      case 'Tiếng Hàn':
        return AppStrings.get(currentAppLang, 'lang_ko');
      case 'Tiếng Pháp':
        return AppStrings.get(currentAppLang, 'lang_fr');
      case 'Tiếng Đức':
        return AppStrings.get(currentAppLang, 'lang_de');
      case 'Tiếng Tây Ban Nha':
        return AppStrings.get(currentAppLang, 'lang_es');
      default:
        return langCode;
    }
  }
}
