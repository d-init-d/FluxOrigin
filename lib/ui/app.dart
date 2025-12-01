import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'theme/config_provider.dart';
import 'widgets/path_setup_modal.dart';
import 'widgets/title_bar.dart';
import 'widgets/sidebar.dart';
import 'widgets/ollama_health_check.dart';
import 'screens/translate_screen.dart';
import 'screens/history_screen.dart';
import 'screens/dictionary_screen.dart';
import 'screens/settings_screen.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, child) {
        return MaterialApp(
          title: 'FluxOrigin',
          theme: themeNotifier.currentTheme,
          debugShowCheckedModeBanner: false,
          home: OllamaHealthCheck(
            child: Consumer<ConfigProvider>(
              builder: (context, configProvider, _) {
                if (configProvider.isLoading) {
                  return Scaffold(
                    backgroundColor: themeNotifier.isDark
                        ? AppColors.darkPaper
                        : AppColors.lightPaper,
                    body: const Center(child: CircularProgressIndicator()),
                  );
                }

                return Stack(
                  children: [
                    Scaffold(
                      backgroundColor: themeNotifier.isDark
                          ? AppColors.darkPaper
                          : AppColors.lightPaper,
                      body: Column(
                        children: [
                          // CRITICAL: Fixed height TitleBar - NO Expanded
                          SizedBox(
                            height: 32,
                            child: TitleBar(isDark: themeNotifier.isDark),
                          ),

                          // CRITICAL: Expanded Row for remaining vertical space
                          Expanded(
                            child: Row(
                              children: [
                                // CRITICAL: Fixed width Sidebar - NO Expanded
                                SizedBox(
                                  width: 250,
                                  child: Sidebar(
                                    isDark: themeNotifier.isDark,
                                    selectedIndex: _selectedIndex,
                                    onItemTap: (index) {
                                      setState(() => _selectedIndex = index);
                                    },
                                  ),
                                ),

                                // CRITICAL: Expanded content area - fills remaining horizontal space
                                Expanded(
                                  child: Container(
                                    color: themeNotifier.isDark
                                        ? AppColors.darkPaper
                                        : AppColors.lightPaper,
                                    child: IndexedStack(
                                      index: _selectedIndex,
                                      children: [
                                        TranslateScreen(
                                            isDark: themeNotifier.isDark),
                                        HistoryScreen(
                                            isDark: themeNotifier.isDark),
                                        DictionaryScreen(
                                            isDark: themeNotifier.isDark),
                                        SettingsScreen(
                                            isDark: themeNotifier.isDark),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!configProvider.isConfigured)
                      PathSetupModal(
                        isDark: themeNotifier.isDark,
                        isDismissible: false,
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
