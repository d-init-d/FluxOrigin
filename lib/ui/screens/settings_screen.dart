import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../theme/config_provider.dart';
import '../widgets/path_setup_modal.dart';
import '../../services/ai_service.dart';
import '../../utils/app_strings.dart';

class SettingsScreen extends StatefulWidget {
  final bool isDark;

  const SettingsScreen({super.key, required this.isDark});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  // String _selectedModel = 'Qwen2.5-7B'; // Removed local state
  bool _isModelDropdownOpen = false;
  bool _isLanguageDropdownOpen = false;

  final List<String> _models = [
    'Qwen2.5-0.5B',
    'Qwen2.5-1B',
    'Qwen2.5-3B',
    'Qwen2.5-7B',
    'Qwen3-8B',
    'Qwen3-14B',
    'Qwen3-30B-A3B',
  ];

  final AIService _aiService = AIService();
  List<String> _installedModels = [];
  final Map<String, double?> _downloadProgress = {};
  bool _isLoadingModels = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInstalledModels();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkInstalledModels();
    }
  }

  Future<void> _checkInstalledModels() async {
    if (!mounted) return;

    setState(() {
      _isLoadingModels = true;
    });

    try {
      final models = await _aiService.getInstalledModels();
      if (mounted) {
        setState(() {
          _installedModels = models;
        });
      }
    } catch (e) {
      debugPrint('Error checking installed models: $e');
      // Optionally show a snackbar or just fail silently
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingModels = false;
        });
      }
    }
  }

  String _getOllamaModelName(String uiName) {
    return uiName.toLowerCase().replaceFirst('-', ':');
  }

  Future<void> _downloadModel(String uiName) async {
    setState(() {
      _downloadProgress[uiName] = 0.0;
    });

    final ollamaName = _getOllamaModelName(uiName);
    final success = await _aiService.pullModel(ollamaName, (progress) {
      if (mounted) {
        setState(() {
          _downloadProgress[uiName] = progress;
        });
      }
    });

    if (mounted) {
      setState(() {
        _downloadProgress[uiName] = null;
      });

      if (success) {
        await _checkInstalledModels();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(AppStrings.get(
                        context.read<ConfigProvider>().appLanguage,
                        'download_success')
                    .replaceFirst('model', 'model $uiName'))),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(AppStrings.get(
                        context.read<ConfigProvider>().appLanguage,
                        'download_fail')
                    .replaceFirst('model', 'model $uiName'))),
          );
        }
      }
    }
  }

  void _showManageModelsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _ManageModelsDialog(
        isDark: widget.isDark,
        installedModels: _installedModels,
        aiService: _aiService,
        onModelsChanged: _checkInstalledModels,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<ConfigProvider>().appLanguage;
    return Container(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 768),
          child: ListView(
            children: [
              Text(
                AppStrings.get(lang, 'settings_title'),
                style: GoogleFonts.merriweather(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : AppColors.lightPrimary,
                ),
              ),

              const SizedBox(height: 32),

              // Appearance Section
              _SectionHeader(
                icon: FontAwesomeIcons.palette,
                title: AppStrings.get(lang, 'appearance_section'),
                isDark: widget.isDark,
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: widget.isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
                child: Column(
                  children: [
                    _SettingRow(
                      title: AppStrings.get(lang, 'dark_mode'),
                      subtitle: AppStrings.get(lang, 'dark_mode_subtitle'),
                      isDark: widget.isDark,
                      trailing: Consumer<ThemeNotifier>(
                        builder: (context, themeNotifier, _) => Switch(
                          value: widget.isDark,
                          onChanged: (_) => themeNotifier.toggleTheme(),
                          activeThumbColor: widget.isDark
                              ? Colors.white.withValues(alpha: 0.9)
                              : const Color(0xFF3E4C59),
                        ),
                      ),
                      showBorder: true,
                    ),
                    _SettingRow(
                      title: AppStrings.get(lang, 'display_font'),
                      subtitle: AppStrings.get(lang, 'display_font_subtitle'),
                      isDark: widget.isDark,
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: widget.isDark
                              ? Colors.black.withValues(alpha: 0.2)
                              : AppColors.lightPaper,
                          border: Border.all(
                            color: widget.isDark
                                ? const Color(0xFF444444)
                                : AppColors.lightBorder,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Merriweather (Mặc định)',
                          style: TextStyle(
                            fontSize: 14,
                            color: widget.isDark
                                ? Colors.grey[300]
                                : AppColors.lightPrimary,
                          ),
                        ),
                      ),
                      showBorder: true,
                    ),
                    _SettingRow(
                      title: AppStrings.get(lang, 'language'),
                      subtitle: AppStrings.get(lang, 'language_subtitle'),
                      isDark: widget.isDark,
                      trailing: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => setState(() => _isLanguageDropdownOpen =
                              !_isLanguageDropdownOpen),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            constraints: const BoxConstraints(minWidth: 120),
                            decoration: BoxDecoration(
                              color: widget.isDark
                                  ? Colors.black.withValues(alpha: 0.2)
                                  : AppColors.lightPaper,
                              border: Border.all(
                                color: widget.isDark
                                    ? const Color(0xFF444444)
                                    : AppColors.lightBorder,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  lang == 'vi' ? 'Tiếng Việt' : 'English',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: widget.isDark
                                        ? Colors.grey[300]
                                        : AppColors.lightPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FaIcon(
                                  _isLanguageDropdownOpen
                                      ? FontAwesomeIcons.chevronUp
                                      : FontAwesomeIcons.chevronDown,
                                  size: 12,
                                  color: widget.isDark
                                      ? Colors.grey
                                      : Colors.grey[600],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLanguageDropdownOpen)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: widget.isDark ? AppColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: widget.isDark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                  child: Column(
                    children: ['vi', 'en'].map((l) {
                      final isSelected = lang == l;
                      return InkWell(
                        onTap: () {
                          context.read<ConfigProvider>().setAppLanguage(l);
                          setState(() {
                            _isLanguageDropdownOpen = false;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (widget.isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : AppColors.lightPrimary
                                        .withValues(alpha: 0.05))
                                : Colors.transparent,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l == 'vi' ? 'Tiếng Việt' : 'English',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? (widget.isDark
                                            ? Colors.white
                                            : AppColors.lightPrimary)
                                        : (widget.isDark
                                            ? Colors.grey[300]
                                            : Colors.grey[600]),
                                  ),
                                ),
                              ),
                              if (isSelected)
                                FaIcon(
                                  FontAwesomeIcons.check,
                                  size: 12,
                                  color: widget.isDark
                                      ? Colors.white
                                      : AppColors.lightPrimary,
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ).animate().fadeIn(),

              const SizedBox(height: 32),

              // AI Section
              _SectionHeader(
                icon: FontAwesomeIcons.brain,
                title: AppStrings.get(lang, 'ai_config_section'),
                isDark: widget.isDark,
                onRefresh: _checkInstalledModels,
                isLoading: _isLoadingModels,
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: widget.isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
                child: _SettingRow(
                  title: AppStrings.get(lang, 'translation_model'),
                  subtitle: AppStrings.get(lang, 'translation_model_subtitle'),
                  isDark: widget.isDark,
                  trailing: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => setState(
                          () => _isModelDropdownOpen = !_isModelDropdownOpen),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        constraints: const BoxConstraints(minWidth: 140),
                        decoration: BoxDecoration(
                          color: widget.isDark
                              ? Colors.black.withValues(alpha: 0.2)
                              : AppColors.lightPaper,
                          border: Border.all(
                            color: widget.isDark
                                ? const Color(0xFF444444)
                                : AppColors.lightBorder,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.watch<ConfigProvider>().selectedModel,
                              style: TextStyle(
                                fontSize: 14,
                                color: widget.isDark
                                    ? Colors.grey[300]
                                    : AppColors.lightPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            FaIcon(
                              _isModelDropdownOpen
                                  ? FontAwesomeIcons.chevronUp
                                  : FontAwesomeIcons.chevronDown,
                              size: 12,
                              color: widget.isDark
                                  ? Colors.grey
                                  : Colors.grey[600],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              if (_isModelDropdownOpen)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: widget.isDark ? AppColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: widget.isDark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                  child: Column(
                    children: _models.map((model) {
                      final configProvider = context.read<ConfigProvider>();
                      final isSelected = model == configProvider.selectedModel;
                      final ollamaName = _getOllamaModelName(model);
                      final isInstalled = _installedModels.contains(ollamaName);
                      final isDownloading = _downloadProgress[model] != null;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            // _selectedModel = model; // Removed local state update
                            context
                                .read<ConfigProvider>()
                                .setSelectedModel(model);
                            _isModelDropdownOpen = false;
                          });

                          // Silent preload: trigger model loading in background
                          _aiService.preloadModel(model);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (widget.isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : AppColors.lightPrimary
                                        .withValues(alpha: 0.05))
                                : Colors.transparent,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  model,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? (widget.isDark
                                            ? Colors.white
                                            : AppColors.lightPrimary)
                                        : (widget.isDark
                                            ? Colors.grey[300]
                                            : Colors.grey[600]),
                                  ),
                                ),
                              ),
                              if (isDownloading)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 16),
                                    child: LinearProgressIndicator(
                                      value: _downloadProgress[model],
                                      minHeight: 6,
                                      borderRadius: BorderRadius.circular(4),
                                      color: widget.isDark
                                          ? const Color(0xFF4CAF50)
                                          : AppColors.lightPrimary,
                                      backgroundColor: widget.isDark
                                          ? Colors.white.withValues(alpha: 0.1)
                                          : Colors.grey[200],
                                    ),
                                  ),
                                )
                              else if (!isInstalled)
                                IconButton(
                                  icon: FaIcon(
                                    FontAwesomeIcons.download,
                                    size: 14,
                                    color: widget.isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                  ),
                                  onPressed: () => _downloadModel(model),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                )
                              else if (isSelected)
                                FaIcon(
                                  FontAwesomeIcons.check,
                                  size: 12,
                                  color: widget.isDark
                                      ? Colors.white
                                      : AppColors.lightPrimary,
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ).animate().fadeIn(),

              const SizedBox(height: 16),

              // Manage Downloaded Models
              Container(
                decoration: BoxDecoration(
                  color: widget.isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
                child: InkWell(
                  onTap: () => _showManageModelsDialog(context),
                  borderRadius: BorderRadius.circular(12),
                  child: _SettingRow(
                    title: AppStrings.get(lang, 'manage_models'),
                    subtitle:
                        '${_installedModels.length} ${AppStrings.get(lang, 'manage_models_subtitle')}',
                    isDark: widget.isDark,
                    trailing: FaIcon(
                      FontAwesomeIcons.hardDrive,
                      size: 16,
                      color: widget.isDark
                          ? Colors.grey[400]
                          : AppColors.lightPrimary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Translation Configuration Section
              _SectionHeader(
                icon: FontAwesomeIcons.gears,
                title: AppStrings.get(lang, 'translation_config_section'),
                isDark: widget.isDark,
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: widget.isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
                child: Consumer<ConfigProvider>(
                  builder: (context, config, _) => InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => PathSetupModal(
                          isDark: widget.isDark,
                          onClose: () => Navigator.pop(context),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppStrings.get(lang, 'project_folder'),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: widget.isDark
                                        ? Colors.grey[200]
                                        : AppColors.lightPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  config.isConfigured
                                      ? config.projectPath
                                      : AppStrings.get(lang, 'not_configured'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: widget.isDark
                                        ? Colors.grey[500]
                                        : AppColors.lightPrimary
                                            .withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FaIcon(
                            FontAwesomeIcons.penToSquare,
                            size: 16,
                            color: widget.isDark
                                ? Colors.grey[400]
                                : AppColors.lightPrimary.withValues(alpha: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Footer Credit
              const SizedBox(height: 48),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  AppStrings.get(lang, 'footer_credit'),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Consolas',
                    color: widget.isDark
                        ? Colors.grey.withValues(alpha: 0.6)
                        : const Color(0xFF888888),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ).animate().fadeIn();
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isDark;
  final VoidCallback? onRefresh;
  final bool isLoading;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.isDark,
    this.onRefresh,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FaIcon(
          icon,
          size: 12,
          color: isDark
              ? Colors.white.withValues(alpha: 0.7)
              : AppColors.lightPrimary,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            color:
                isDark ? Colors.white.withOpacity(0.7) : AppColors.lightPrimary,
          ),
        ),
        if (onRefresh != null) ...[
          const SizedBox(width: 8),
          if (isLoading)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isDark ? Colors.white : AppColors.lightPrimary,
              ),
            )
          else
            InkWell(
              onTap: onRefresh,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: FaIcon(
                  FontAwesomeIcons.rotateRight,
                  size: 12,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.7)
                      : AppColors.lightPrimary,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isDark;
  final Widget trailing;
  final bool showBorder;

  const _SettingRow({
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.trailing,
    this.showBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: showBorder
            ? Border(
                bottom: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[200] : AppColors.lightPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? Colors.grey[500]
                        : AppColors.lightPrimary.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _ManageModelsDialog extends StatefulWidget {
  final bool isDark;
  final List<String> installedModels;
  final AIService aiService;
  final VoidCallback onModelsChanged;

  const _ManageModelsDialog({
    required this.isDark,
    required this.installedModels,
    required this.aiService,
    required this.onModelsChanged,
  });

  @override
  State<_ManageModelsDialog> createState() => _ManageModelsDialogState();
}

class _ManageModelsDialogState extends State<_ManageModelsDialog> {
  late List<String> _models;
  final Set<String> _deletingModels = {};

  @override
  void initState() {
    super.initState();
    _models = List.from(widget.installedModels);
  }

  Future<void> _deleteModel(String modelName) async {
    setState(() {
      _deletingModels.add(modelName);
    });

    final success = await widget.aiService.deleteModel(modelName);

    if (mounted) {
      setState(() {
        _deletingModels.remove(modelName);
        if (success) {
          _models.remove(modelName);
        }
      });

      if (success) {
        widget.onModelsChanged();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    '${AppStrings.get(context.read<ConfigProvider>().appLanguage, 'deleted_model')} $modelName')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    '${AppStrings.get(context.read<ConfigProvider>().appLanguage, 'delete_fail')} $modelName')),
          );
        }
      }
    }
  }

  void _confirmDelete(String modelName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          AppStrings.get(context.read<ConfigProvider>().appLanguage,
              'delete_model_confirm'),
          style: TextStyle(
            color: widget.isDark ? Colors.white : AppColors.lightPrimary,
          ),
        ),
        content: Text(
          '${AppStrings.get(context.read<ConfigProvider>().appLanguage, 'delete_model_question')} "$modelName"?',
          style: TextStyle(
            color: widget.isDark ? Colors.grey[300] : Colors.grey[700],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppStrings.get(
                  context.read<ConfigProvider>().appLanguage, 'cancel'),
              style: TextStyle(
                color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteModel(modelName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(AppStrings.get(
                context.read<ConfigProvider>().appLanguage, 'delete')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 500),
        decoration: BoxDecoration(
          color: widget.isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isDark ? const Color(0xFF444444) : Colors.grey[200]!,
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
                  FaIcon(
                    FontAwesomeIcons.hardDrive,
                    size: 18,
                    color:
                        widget.isDark ? Colors.white : AppColors.lightPrimary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Quản lý Model đã tải',
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
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: FaIcon(
                      FontAwesomeIcons.xmark,
                      size: 20,
                      color:
                          widget.isDark ? Colors.grey[400] : Colors.grey[500],
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
            Flexible(
              child: _models.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FaIcon(
                            FontAwesomeIcons.boxOpen,
                            size: 48,
                            color: widget.isDark
                                ? Colors.grey[600]
                                : Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Chưa có model nào được tải',
                            style: TextStyle(
                              fontSize: 14,
                              color: widget.isDark
                                  ? Colors.grey[500]
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _models.length,
                      itemBuilder: (context, index) {
                        final model = _models[index];
                        final isDeleting = _deletingModels.contains(model);

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: index < _models.length - 1
                                ? Border(
                                    bottom: BorderSide(
                                      color: widget.isDark
                                          ? AppColors.darkBorder
                                          : AppColors.lightBorder,
                                    ),
                                  )
                                : null,
                          ),
                          child: Row(
                            children: [
                              FaIcon(
                                FontAwesomeIcons.cube,
                                size: 14,
                                color: widget.isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  model,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: widget.isDark
                                        ? Colors.grey[200]
                                        : AppColors.lightPrimary,
                                  ),
                                ),
                              ),
                              if (isDeleting)
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: widget.isDark
                                        ? Colors.white
                                        : AppColors.lightPrimary,
                                  ),
                                )
                              else
                                IconButton(
                                  onPressed: () => _confirmDelete(model),
                                  icon: FaIcon(
                                    FontAwesomeIcons.trash,
                                    size: 14,
                                    color: Colors.red[400],
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: 'Xóa model',
                                ),
                            ],
                          ),
                        );
                      },
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
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          widget.isDark ? Colors.white : AppColors.lightPrimary,
                      foregroundColor:
                          widget.isDark ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Đóng',
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
        );
  }
}
