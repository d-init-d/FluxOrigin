import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../theme/app_theme.dart';
import '../theme/config_provider.dart';

class TitleBar extends StatelessWidget {
  final bool isDark;
  final VoidCallback? onProviderStatusTap;

  const TitleBar({
    super.key,
    required this.isDark,
    this.onProviderStatusTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isMac = Platform.isMacOS;
    final double barHeight = isMac ? 38 : 32;
    final config = Provider.of<ConfigProvider?>(context, listen: true);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (details) {
        windowManager.startDragging();
      },
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          windowManager.unmaximize();
        } else {
          windowManager.maximize();
        }
      },
      child: Container(
        height: barHeight,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSidebar : AppColors.lightSidebar,
          border: Border(
            bottom: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // Leave authentic breathing room for macOS native traffic-light buttons on left
            SizedBox(width: isMac ? 78 : 16),
            FaIcon(
              FontAwesomeIcons.layerGroup,
              size: 12,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.85)
                  : AppColors.lightPrimary,
            ),
            const SizedBox(width: 8),
            Text(
              'FluxOrigin',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[300] : AppColors.lightPrimary,
              ),
            ),
            const Spacer(),

            // Subtle AI / BYOK Status Pill preserving literary aesthetic
            if (config != null)
              Padding(
                padding: EdgeInsets.only(right: isMac ? 14 : 10),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onProviderStatusTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : AppColors.lightPrimary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: config.ollamaConnected
                                  ? Colors.green
                                  : Colors.orangeAccent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: Text(
                              '${config.activeProviderShortLabel} · ${config.selectedModel}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.grey[300]
                                    : AppColors.lightPrimary
                                        .withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Windows & Linux window controls (macOS uses native traffic lights)
            if (!isMac) ...[
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
