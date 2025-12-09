import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:window_manager/window_manager.dart';
import '../theme/app_theme.dart';

class TitleBar extends StatelessWidget {
  final bool isDark;

  const TitleBar({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (details) {
        windowManager.startDragging();
      },
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSidebar : AppColors.lightSidebar,
          border: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0xFF2A2A2A) : AppColors.lightBorder,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // Left: App icon and title
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    FaIcon(
                      FontAwesomeIcons.layerGroup,
                      size: 12,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.8)
                          : AppColors.lightPrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'FluxOrigin',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color:
                            isDark ? Colors.grey[400] : AppColors.lightPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Right: Window controls
            _WindowButton(
              isDark: isDark,
              icon: Icons.remove,
              onPressed: () => windowManager.minimize(),
            ),
            _WindowButton(
              isDark: isDark,
              icon: Icons.crop_square,
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
            ),
            _WindowButton(
              isDark: isDark,
              icon: Icons.close,
              isClose: true,
              onPressed: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final bool isDark;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;

  const _WindowButton({
    required this.isDark,
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: double.infinity,
          alignment: Alignment.center,
          color: _isHovered
              ? (widget.isClose
                  ? const Color(0xFFC42B1C)
                  : (widget.isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.1)))
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 18,
            color: _isHovered && widget.isClose
                ? Colors.white
                : (widget.isDark ? Colors.grey[400] : AppColors.lightPrimary),
          ),
        ),
      ),
    );
  }
}

