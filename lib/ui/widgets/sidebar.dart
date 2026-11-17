import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../theme/config_provider.dart';
import '../../utils/app_strings.dart';
import 'sidebar_item.dart';

class Sidebar extends StatelessWidget {
  final bool isDark;
  final int selectedIndex;
  final Function(int) onItemTap;

  const Sidebar({
    super.key,
    required this.isDark,
    required this.selectedIndex,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<ConfigProvider>().appLanguage;
    final ollamaConnected = context.watch<ConfigProvider>().ollamaConnected;
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSidebar : AppColors.lightSidebar,
        border: Border(
          right: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // App Branding Header (preserved serif editorial wordmark)
          Padding(
            padding: const EdgeInsets.only(top: 22.0, bottom: 20.0, left: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.merriweather(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF000000),
                      ),
                      children: [
                        const TextSpan(text: 'Flux'),
                        TextSpan(
                          text: 'Origin',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white
                                : AppColors.lightAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : AppColors.lightPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'v3.0 · D-Transcreate v1.1',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: isDark
                          ? Colors.grey[400]
                          : AppColors.lightPrimary.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Navigation Items
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  SidebarItem(
                    icon: FontAwesomeIcons.language,
                    label: AppStrings.get(lang, 'sidebar_translate'),
                    isActive: selectedIndex == 0,
                    onTap: () => onItemTap(0),
                    isDark: isDark,
                  ),
                  SidebarItem(
                    icon: FontAwesomeIcons.folderTree,
                    label: AppStrings.get(lang, 'sidebar_batch'),
                    isActive: selectedIndex == 1,
                    onTap: () => onItemTap(1),
                    isDark: isDark,
                  ),
                  SidebarItem(
                    icon: FontAwesomeIcons.clockRotateLeft,
                    label: AppStrings.get(lang, 'sidebar_history'),
                    isActive: selectedIndex == 2,
                    onTap: () => onItemTap(2),
                    isDark: isDark,
                  ),
                  SidebarItem(
                    icon: FontAwesomeIcons.bookOpenReader,
                    label: AppStrings.get(lang, 'sidebar_dictionary'),
                    isActive: selectedIndex == 3,
                    onTap: () => onItemTap(3),
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),

          // Settings and Dev Logs at bottom
          Container(
            padding: const EdgeInsets.only(top: 16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.12),
                  width: 1,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  SidebarItem(
                    icon: FontAwesomeIcons.gear,
                    label: AppStrings.get(lang, 'sidebar_settings'),
                    isActive: selectedIndex == 4,
                    onTap: () => onItemTap(4),
                    isDark: isDark,
                    showBadge: !ollamaConnected,
                  ),
                  SidebarItem(
                    icon: FontAwesomeIcons.bug,
                    label: 'Dev Logs',
                    isActive: selectedIndex == 5,
                    onTap: () => onItemTap(5),
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
