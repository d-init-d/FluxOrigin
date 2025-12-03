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
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSidebar : AppColors.lightSidebar,
        border: Border(
          right: BorderSide(
            color: isDark ? const Color(0xFF2A2A2A) : AppColors.lightBorder,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // App Branding Header
          Padding(
            // Sửa thành: chỉ padding Trên, Dưới và Trái (16px bằng với menu)
            padding: const EdgeInsets.only(top: 24.0, bottom: 24.0, left: 16.0),
            child: Align(
              alignment: Alignment.centerLeft, // Bắt buộc căn trái
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.merriweather(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF000000),
                  ),
                  children: [
                    const TextSpan(text: 'Flux'),
                    TextSpan(
                      text: 'Origin',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF182b14),
                      ),
                    ),
                  ],
                ),
              ),
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
                    icon: FontAwesomeIcons.clockRotateLeft,
                    label: AppStrings.get(lang, 'sidebar_history'),
                    isActive: selectedIndex == 1,
                    onTap: () => onItemTap(1),
                    isDark: isDark,
                  ),
                  SidebarItem(
                    icon: FontAwesomeIcons.bookOpenReader,
                    label: AppStrings.get(lang, 'sidebar_dictionary'),
                    isActive: selectedIndex == 2,
                    onTap: () => onItemTap(2),
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),

          // Settings at bottom
          Container(
            padding: const EdgeInsets.only(top: 16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.grey.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SidebarItem(
                icon: FontAwesomeIcons.gear,
                label: AppStrings.get(lang, 'sidebar_settings'),
                isActive: selectedIndex == 3,
                onTap: () => onItemTap(3),
                isDark: isDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
