import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/ai_service.dart';
import '../../services/dev_logger.dart';
import '../../utils/app_strings.dart';
import '../theme/app_theme.dart';
import '../theme/config_provider.dart';
import '../widgets/path_setup_modal.dart';

class SettingsScreen extends StatefulWidget {
  final bool isDark;

  const SettingsScreen({super.key, required this.isDark});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _isModelDropdownOpen = false;
  bool _isLanguageDropdownOpen = false;
  bool _obscureApiKey = true;

  final AIService _aiService = AIService();
  final TextEditingController _ollamaUrlController = TextEditingController();
  final TextEditingController _lmStudioUrlController = TextEditingController();
  final TextEditingController _byokUrlController = TextEditingController();
  final TextEditingController _byokKeyController = TextEditingController();
  final TextEditingController _customModelController = TextEditingController();

  bool _isCheckingConnection = false;
  String? _connectionStatus;
  bool? _isConnectionSuccess;
  List<String> _installedModels = [];
  bool _isLoadingModels = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAIConfig();
    });
  }

  void _initAIConfig() {
    final config = context.read<ConfigProvider>();
    _ollamaUrlController.text = config.ollamaUrl;
    _lmStudioUrlController.text = config.lmStudioUrl;
    _byokUrlController.text = config.byokUrl;
    _byokKeyController.text = config.byokApiKey;
    _customModelController.text = config.selectedModel;

    _updateAIServiceConfig(config);
    _checkInstalledModels();
  }

  void _updateAIServiceConfig(ConfigProvider config) {
    _aiService.setBaseUrl(config.currentAiUrl);
    _aiService.setProviderType(config.effectiveAiServiceType);
    _aiService.setApiKey(config.activeApiKey);
    _aiService.setDefaultTemperature(config.temperature);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ollamaUrlController.dispose();
    _lmStudioUrlController.dispose();
    _byokUrlController.dispose();
    _byokKeyController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkInstalledModels();
    }
  }

  Future<void> _checkAIConnection(ConfigProvider config) async {
    if (!mounted) return;

    // Persist edited BYOK URL & Key immediately so checkConnection & translation stay synced
    if (config.aiProvider == AIProvider.byok) {
      await config.setByokUrl(_byokUrlController.text.trim());
      await config.setByokApiKey(_byokKeyController.text.trim());
    } else if (config.aiProvider == AIProvider.lmStudio) {
      await config.setLmStudioUrl(_lmStudioUrlController.text.trim());
    } else {
      await config.setOllamaUrl(_ollamaUrlController.text.trim());
    }

    setState(() {
      _isCheckingConnection = true;
      _connectionStatus = null;
      _isConnectionSuccess = null;
    });

    final url = config.currentAiUrl;
    final providerType = config.effectiveAiServiceType;
    final apiKey = config.activeApiKey;

    final (success, errorCode, modelCount) = await _aiService.checkConnection(
      url: url,
      providerType: providerType,
      apiKey: apiKey,
    );

    if (mounted) {
      final lang = config.appLanguage;
      String message;

      if (success) {
        final String key;
        if (config.aiProvider == AIProvider.byok) {
          key = 'byok_connection_success';
        } else if (config.aiProvider == AIProvider.lmStudio) {
          key = 'lmstudio_connection_success';
        } else {
          key = 'ollama_connection_success';
        }
        message = AppStrings.get(lang, key)
            .replaceAll('@count', modelCount.toString());
      } else {
        if (errorCode == 'error_missing_key') {
          message = AppStrings.get(lang, 'connection_error_missing_key');
        } else if (errorCode != null && errorCode.startsWith('error_status:')) {
          final statusCode = errorCode.split(':')[1];
          message = AppStrings.get(lang, 'connection_error_status')
              .replaceAll('@code', statusCode);
        } else if (errorCode == 'error_timeout') {
          message = AppStrings.get(lang, 'connection_error_timeout');
        } else if (errorCode == 'error_connect') {
          message = AppStrings.get(lang, 'connection_error_connect');
        } else {
          message = AppStrings.get(lang, 'connection_error_generic');
        }
      }

      setState(() {
        _isCheckingConnection = false;
        _connectionStatus = message;
        _isConnectionSuccess = success;
      });

      _updateAIServiceConfig(config);
      await config.checkOllamaHealth();
      if (success) {
        _checkInstalledModels();
      }
    }
  }

  Future<void> _switchAIProvider(AIProvider provider) async {
    final config = context.read<ConfigProvider>();
    await config.setAIProvider(provider);

    if (!mounted) return;
    setState(() {
      _connectionStatus = null;
      _isConnectionSuccess = null;
      _installedModels = [];
      _byokUrlController.text = config.byokUrl;
      _byokKeyController.text = config.byokApiKey;
      _customModelController.text = config.selectedModel;
    });

    _updateAIServiceConfig(config);
    _checkInstalledModels();
  }

  Future<void> _selectByokPreset(ByokPreset preset) async {
    final config = context.read<ConfigProvider>();
    await config.setByokPreset(preset);
    if (!mounted) return;
    setState(() {
      _connectionStatus = null;
      _isConnectionSuccess = null;
      _byokUrlController.text = config.byokUrl;
      _byokKeyController.text = config.byokApiKey;
      _customModelController.text = config.selectedModel;
    });
    _updateAIServiceConfig(config);
    _checkInstalledModels();
  }

  Future<void> _checkInstalledModels() async {
    if (!mounted) return;

    setState(() => _isLoadingModels = true);

    try {
      final config = context.read<ConfigProvider>();
      _updateAIServiceConfig(config);
      final models = await _aiService.getInstalledModels();
      if (mounted) {
        setState(() {
          _installedModels = models;
        });

        if (models.isNotEmpty && !models.contains(config.selectedModel)) {
          // For BYOK, keep suggested model if it matches API; otherwise pick first fetched
          await config.setSelectedModel(models.first);
          if (mounted) {
            _customModelController.text = models.first;
          }
        }
      }
    } catch (e) {
      DevLogger().warning('SettingsScreen', 'Error checking installed models',
          details: e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoadingModels = false);
      }
    }
  }

  Widget _buildProviderButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? (widget.isDark
                      ? AppColors.lightPrimary.withValues(alpha: 0.25)
                      : AppColors.lightPrimary.withValues(alpha: 0.1))
                  : (widget.isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : Colors.grey[100]),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? (widget.isDark ? Colors.white70 : AppColors.lightPrimary)
                    : (widget.isDark
                        ? const Color(0xFF444444)
                        : Colors.grey[300]!),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FaIcon(
                  icon,
                  size: 14,
                  color: isSelected
                      ? (widget.isDark ? Colors.white : AppColors.lightPrimary)
                      : (widget.isDark ? Colors.grey[400] : Colors.grey[600]),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? (widget.isDark
                              ? Colors.white
                              : AppColors.lightPrimary)
                          : (widget.isDark
                              ? Colors.grey[400]
                              : Colors.grey[600]),
                    ),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 6),
                  FaIcon(
                    FontAwesomeIcons.circleCheck,
                    size: 13,
                    color: widget.isDark ? Colors.green[400] : Colors.green,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showManageModelsDialog(BuildContext context) {
    final lang = context.read<ConfigProvider>().appLanguage;
    showDialog(
      context: context,
      builder: (context) => _ManageModelsDialog(
        isDark: widget.isDark,
        installedModels: _installedModels,
        aiService: _aiService,
        onModelsChanged: _checkInstalledModels,
        lang: lang,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigProvider>();
    final lang = config.appLanguage;
    final keyCount = AIService.parseApiKeys(_byokKeyController.text).length;

    return Container(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 780),
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

              const SizedBox(height: 28),

              // Appearance Section
              _SectionHeader(
                icon: FontAwesomeIcons.palette,
                title: AppStrings.get(lang, 'appearance_section'),
                isDark: widget.isDark,
              ),
              const SizedBox(height: 14),
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
                          activeTrackColor: AppColors.lightPrimary,
                          activeThumbColor: Colors.white,
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
                            horizontal: 14, vertical: 8),
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
                          'Merriweather (${AppStrings.get(lang, 'default_label')})',
                          style: TextStyle(
                            fontSize: 13,
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
                                horizontal: 14, vertical: 8),
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
                                    fontSize: 13,
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
                                  size: 11,
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
                          setState(() => _isLanguageDropdownOpen = false);
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

              const SizedBox(height: 28),

              // AI Provider & BYOK Section
              _SectionHeader(
                icon: FontAwesomeIcons.brain,
                title: AppStrings.get(lang, 'ai_config_section'),
                isDark: widget.isDark,
                onRefresh: _checkInstalledModels,
                isLoading: _isLoadingModels,
              ),
              const SizedBox(height: 14),

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
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Provider',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: widget.isDark
                              ? Colors.grey[200]
                              : AppColors.lightPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppStrings.get(lang, 'ai_provider_subtitle'),
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.isDark
                              ? Colors.grey[500]
                              : AppColors.lightPrimary.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildProviderButton(
                            label: 'Ollama',
                            icon: FontAwesomeIcons.server,
                            isSelected: config.aiProvider == AIProvider.ollama,
                            onTap: () => _switchAIProvider(AIProvider.ollama),
                          ),
                          const SizedBox(width: 10),
                          _buildProviderButton(
                            label: 'LM Studio',
                            icon: FontAwesomeIcons.desktop,
                            isSelected:
                                config.aiProvider == AIProvider.lmStudio,
                            onTap: () => _switchAIProvider(AIProvider.lmStudio),
                          ),
                          const SizedBox(width: 10),
                          _buildProviderButton(
                            label: 'BYOK (API Key)',
                            icon: FontAwesomeIcons.key,
                            isSelected: config.aiProvider == AIProvider.byok,
                            onTap: () => _switchAIProvider(AIProvider.byok),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Provider Connection Details Card (Ollama / LM Studio / BYOK)
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
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: config.aiProvider == AIProvider.byok
                      ? _buildByokConfigCard(config, lang, keyCount)
                      : _buildLocalUrlConfigCard(config, lang),
                ),
              ),

              const SizedBox(height: 14),

              // Model Selection & Custom Model Card
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
                      title: AppStrings.get(lang, 'translation_model'),
                      subtitle: _installedModels.isEmpty
                          ? AppStrings.get(lang, 'no_models_check_connection')
                          : AppStrings.get(lang, 'select_from_models')
                              .replaceAll('{count}',
                                  _installedModels.length.toString()),
                      isDark: widget.isDark,
                      showBorder: true,
                      trailing: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: _installedModels.isEmpty
                              ? null
                              : () => setState(() =>
                                  _isModelDropdownOpen = !_isModelDropdownOpen),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            constraints: const BoxConstraints(
                                minWidth: 140, maxWidth: 260),
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
                                Flexible(
                                  child: Text(
                                    config.selectedModel.isEmpty
                                        ? AppStrings.get(
                                            lang, 'no_model_available')
                                        : config.selectedModel,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: widget.isDark
                                          ? Colors.grey[200]
                                          : AppColors.lightPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FaIcon(
                                  _isModelDropdownOpen
                                      ? FontAwesomeIcons.chevronUp
                                      : FontAwesomeIcons.chevronDown,
                                  size: 11,
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
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.get(lang, 'custom_model_id'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: widget.isDark
                                  ? Colors.grey[300]
                                  : AppColors.lightPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _customModelController,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: widget.isDark
                                        ? Colors.grey[200]
                                        : AppColors.lightPrimary,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: AppStrings.get(
                                        lang, 'custom_model_hint'),
                                    hintStyle: TextStyle(
                                      fontSize: 12,
                                      color: widget.isDark
                                          ? Colors.grey[600]
                                          : Colors.grey[400],
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    filled: true,
                                    fillColor: widget.isDark
                                        ? Colors.black.withValues(alpha: 0.2)
                                        : AppColors.lightPaper,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(
                                        color: widget.isDark
                                            ? const Color(0xFF444444)
                                            : AppColors.lightBorder,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(
                                        color: widget.isDark
                                            ? const Color(0xFF444444)
                                            : AppColors.lightBorder,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton(
                                onPressed: () {
                                  final m = _customModelController.text.trim();
                                  if (m.isNotEmpty) {
                                    config.setSelectedModel(m);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Model: $m'),
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                },
                                child: Text(
                                    AppStrings.get(lang, 'apply_model_btn')),
                              ),
                            ],
                          ),
                          if (config.aiProvider == AIProvider.byok) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: (AIService
                                          .byokPresets[config.byokPreset]
                                          ?.suggestedModels ??
                                      const [])
                                  .map((m) {
                                final isCurrent = config.selectedModel == m;
                                return ActionChip(
                                  label: Text(
                                    m,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isCurrent
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isCurrent
                                          ? (widget.isDark
                                              ? Colors.black
                                              : Colors.white)
                                          : (widget.isDark
                                              ? Colors.grey[300]
                                              : AppColors.lightPrimary),
                                    ),
                                  ),
                                  backgroundColor: isCurrent
                                      ? (widget.isDark
                                          ? Colors.white
                                          : AppColors.lightPrimary)
                                      : (widget.isDark
                                          ? Colors.black.withValues(alpha: 0.2)
                                          : AppColors.lightPaper),
                                  onPressed: () {
                                    _customModelController.text = m;
                                    config.setSelectedModel(m);
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_isModelDropdownOpen && _installedModels.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(
                    color: widget.isDark ? AppColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: widget.isDark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: _installedModels.map((model) {
                        final isSelected = model == config.selectedModel;
                        return InkWell(
                          onTap: () {
                            config.setSelectedModel(model);
                            _customModelController.text = model;
                            setState(() => _isModelDropdownOpen = false);
                            _aiService.preloadModel(model);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
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
                                      fontSize: 13,
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
                  ),
                ).animate().fadeIn(),

              if (config.aiProvider == AIProvider.ollama) ...[
                const SizedBox(height: 14),
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
                      subtitle: AppStrings.get(lang, 'models_installed_count')
                          .replaceAll(
                              '{count}', _installedModels.length.toString()),
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
              ],

              const SizedBox(height: 28),

              // D-Transcreate Engine & Project Folder Section
              _SectionHeader(
                icon: FontAwesomeIcons.gears,
                title: AppStrings.get(lang, 'translation_config_section'),
                isDark: widget.isDark,
              ),
              const SizedBox(height: 14),
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
                      title: AppStrings.get(lang, 'd_transcreate_deep_mode'),
                      subtitle:
                          AppStrings.get(lang, 'd_transcreate_deep_mode_sub'),
                      isDark: widget.isDark,
                      showBorder: true,
                      trailing: Switch(
                        value: config.dTranscreateDeepMode,
                        onChanged: (v) => config.setDTranscreateDeepMode(v),
                        activeTrackColor: AppColors.lightPrimary,
                        activeThumbColor: Colors.white,
                      ),
                    ),
                    _SettingRow(
                      title: AppStrings.get(lang, 'preserve_epub_layout'),
                      subtitle:
                          AppStrings.get(lang, 'preserve_epub_layout_sub'),
                      isDark: widget.isDark,
                      showBorder: true,
                      trailing: Switch(
                        value: config.preserveEpubLayout,
                        onChanged: (v) => config.setPreserveEpubLayout(v),
                        activeTrackColor: AppColors.lightPrimary,
                        activeThumbColor: Colors.white,
                      ),
                    ),
                    _SettingRow(
                      title: AppStrings.get(lang, 'chunk_size_label'),
                      subtitle: AppStrings.get(lang, 'chunk_size_subtitle'),
                      isDark: widget.isDark,
                      showBorder: true,
                      trailing: Wrap(
                        spacing: 6,
                        children: [800, 1200, 1800, 2400].map((size) {
                          final active = config.targetChunkSize == size;
                          return ChoiceChip(
                            label: Text('$size'),
                            selected: active,
                            onSelected: (_) => config.setTargetChunkSize(size),
                            selectedColor: widget.isDark
                                ? Colors.white
                                : AppColors.lightPrimary,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: active
                                  ? (widget.isDark ? Colors.black : Colors.white)
                                  : (widget.isDark
                                      ? Colors.grey[300]
                                      : AppColors.lightPrimary),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    _SettingRow(
                      title: AppStrings.get(lang, 'temperature_label'),
                      subtitle: AppStrings.get(lang, 'temperature_subtitle'),
                      isDark: widget.isDark,
                      showBorder: true,
                      trailing: Wrap(
                        spacing: 6,
                        children: [0.1, 0.2, 0.3, 0.5].map((temp) {
                          final active =
                              (config.temperature - temp).abs() < 0.01;
                          return ChoiceChip(
                            label: Text(temp.toStringAsFixed(1)),
                            selected: active,
                            onSelected: (_) => config.setTemperature(temp),
                            selectedColor: widget.isDark
                                ? Colors.white
                                : AppColors.lightPrimary,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: active
                                  ? (widget.isDark ? Colors.black : Colors.white)
                                  : (widget.isDark
                                      ? Colors.grey[300]
                                      : AppColors.lightPrimary),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => PathSetupModal(
                            isDark: widget.isDark,
                            onClose: () => Navigator.pop(context),
                          ),
                        );
                      },
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
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
                                        : AppStrings.get(
                                            lang, 'not_configured'),
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
                                  : AppColors.lightPrimary
                                      .withValues(alpha: 0.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),
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

  Widget _buildLocalUrlConfigCard(ConfigProvider config, String lang) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          config.aiProvider == AIProvider.lmStudio
              ? 'URL LM Studio Server'
              : 'URL Ollama Server',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: widget.isDark ? Colors.grey[200] : AppColors.lightPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          config.aiProvider == AIProvider.lmStudio
              ? AppStrings.get(lang, 'lmstudio_url_subtitle')
              : AppStrings.get(lang, 'ollama_url_subtitle'),
          style: TextStyle(
            fontSize: 12,
            color: widget.isDark
                ? Colors.grey[500]
                : AppColors.lightPrimary.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: config.aiProvider == AIProvider.lmStudio
                    ? _lmStudioUrlController
                    : _ollamaUrlController,
                style: TextStyle(
                  fontSize: 14,
                  color:
                      widget.isDark ? Colors.grey[200] : AppColors.lightPrimary,
                ),
                decoration: InputDecoration(
                  hintText: config.aiProvider == AIProvider.lmStudio
                      ? 'http://localhost:1234'
                      : 'http://localhost:11434',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: widget.isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : AppColors.lightPaper,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: widget.isDark
                          ? const Color(0xFF444444)
                          : AppColors.lightBorder,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _isCheckingConnection
                  ? null
                  : () => _checkAIConnection(config),
              icon: _isCheckingConnection
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const FaIcon(FontAwesomeIcons.plug,
                      size: 13, color: Colors.white),
              label: Text(
                _isCheckingConnection
                    ? AppStrings.get(lang, 'checking_connection')
                    : AppStrings.get(lang, 'check_connection'),
                style: const TextStyle(fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.isDark
                    ? const Color(0xFF2E7D32)
                    : AppColors.lightPrimary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ],
        ),
        if (_connectionStatus != null) ...[
          const SizedBox(height: 12),
          _buildConnectionStatusBanner(),
        ],
        if (config.aiProvider == AIProvider.lmStudio) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const FaIcon(FontAwesomeIcons.circleInfo,
                    size: 14, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppStrings.get(lang, 'lmstudio_note'),
                    style: TextStyle(fontSize: 12, color: Colors.blue[600]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildByokConfigCard(
      ConfigProvider config, String lang, int keyCount) {
    final spec = AIService.byokPresets[config.byokPreset]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.get(lang, 'byok_preset_title'),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: widget.isDark ? Colors.grey[200] : AppColors.lightPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppStrings.get(lang, 'byok_preset_subtitle'),
          style: TextStyle(
            fontSize: 12,
            color: widget.isDark
                ? Colors.grey[500]
                : AppColors.lightPrimary.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ByokPreset.values.map((preset) {
            final pSpec = AIService.byokPresets[preset]!;
            final selected = config.byokPreset == preset;
            return ChoiceChip(
              label: Text(pSpec.label),
              selected: selected,
              onSelected: (_) => _selectByokPreset(preset),
              selectedColor:
                  widget.isDark ? Colors.white : AppColors.lightPrimary,
              backgroundColor: widget.isDark
                  ? Colors.black.withValues(alpha: 0.25)
                  : AppColors.lightPaper,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected
                    ? (widget.isDark ? Colors.black : Colors.white)
                    : (widget.isDark ? Colors.grey[300] : AppColors.lightPrimary),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          AppStrings.get(lang, 'byok_endpoint_url'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: widget.isDark ? Colors.grey[300] : AppColors.lightPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _byokUrlController,
          onChanged: (v) => config.setByokUrl(v),
          style: TextStyle(
            fontSize: 13,
            color: widget.isDark ? Colors.grey[200] : AppColors.lightPrimary,
          ),
          decoration: InputDecoration(
            hintText: spec.defaultBaseUrl,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: widget.isDark
                ? Colors.black.withValues(alpha: 0.2)
                : AppColors.lightPaper,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: widget.isDark
                    ? const Color(0xFF444444)
                    : AppColors.lightBorder,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                AppStrings.get(lang, 'byok_api_key_label'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color:
                      widget.isDark ? Colors.grey[300] : AppColors.lightPrimary,
                ),
              ),
            ),
            if (keyCount > 1)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  AppStrings.get(lang, 'byok_keys_active')
                      .replaceAll('{count}', keyCount.toString()),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _byokKeyController,
                obscureText: _obscureApiKey,
                maxLines: _obscureApiKey ? 1 : 3,
                onChanged: (v) {
                  setState(() {});
                  config.setByokApiKey(v);
                },
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Consolas',
                  color:
                      widget.isDark ? Colors.grey[200] : AppColors.lightPrimary,
                ),
                decoration: InputDecoration(
                  hintText: spec.keyPlaceholder,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: widget.isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : AppColors.lightPaper,
                  suffixIcon: IconButton(
                    icon: FaIcon(
                      _obscureApiKey
                          ? FontAwesomeIcons.eye
                          : FontAwesomeIcons.eyeSlash,
                      size: 14,
                    ),
                    onPressed: () =>
                        setState(() => _obscureApiKey = !_obscureApiKey),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: widget.isDark
                          ? const Color(0xFF444444)
                          : AppColors.lightBorder,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _isCheckingConnection
                  ? null
                  : () => _checkAIConnection(config),
              icon: _isCheckingConnection
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const FaIcon(FontAwesomeIcons.plug,
                      size: 13, color: Colors.white),
              label: Text(
                _isCheckingConnection
                    ? AppStrings.get(lang, 'checking_connection')
                    : AppStrings.get(lang, 'check_connection'),
                style: const TextStyle(fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.isDark
                    ? const Color(0xFF2E7D32)
                    : AppColors.lightPrimary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ],
        ),
        if (_connectionStatus != null) ...[
          const SizedBox(height: 12),
          _buildConnectionStatusBanner(),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (widget.isDark
                    ? Colors.white
                    : AppColors.lightPrimary)
                .withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              FaIcon(
                FontAwesomeIcons.shieldHalved,
                size: 13,
                color:
                    widget.isDark ? Colors.grey[400] : AppColors.lightPrimary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppStrings.get(lang, 'byok_note'),
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.isDark
                        ? Colors.grey[400]
                        : AppColors.lightPrimary.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionStatusBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (_isConnectionSuccess == true ? Colors.green : Colors.red)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: (_isConnectionSuccess == true ? Colors.green : Colors.red)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          FaIcon(
            _isConnectionSuccess == true
                ? FontAwesomeIcons.circleCheck
                : FontAwesomeIcons.circleXmark,
            size: 14,
            color: _isConnectionSuccess == true ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _connectionStatus!,
              style: TextStyle(
                fontSize: 13,
                color: _isConnectionSuccess == true ? Colors.green : Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
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
            color: isDark
                ? Colors.white.withValues(alpha: 0.7)
                : AppColors.lightPrimary,
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
                    fontSize: 12,
                    color: isDark
                        ? Colors.grey[500]
                        : AppColors.lightPrimary.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
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
  final String lang;

  const _ManageModelsDialog({
    required this.isDark,
    required this.installedModels,
    required this.aiService,
    required this.onModelsChanged,
    required this.lang,
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
    setState(() => _deletingModels.add(modelName));
    final success = await widget.aiService.deleteModel(modelName);
    if (!mounted) return;
    setState(() {
      _deletingModels.remove(modelName);
      if (success) _models.remove(modelName);
    });
    if (success) {
      widget.onModelsChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${AppStrings.get(widget.lang, 'deleted_model')} $modelName')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${AppStrings.get(widget.lang, 'delete_fail')} $modelName')),
      );
    }
  }

  void _confirmDelete(String modelName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          AppStrings.get(widget.lang, 'delete_model_confirm'),
          style: TextStyle(
            color: widget.isDark ? Colors.white : AppColors.lightPrimary,
          ),
        ),
        content: Text(
          '${AppStrings.get(widget.lang, 'delete_model_question')} "$modelName"?',
          style: TextStyle(
            color: widget.isDark ? Colors.grey[300] : Colors.grey[700],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.get(widget.lang, 'cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteModel(modelName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
            ),
            child: Text(AppStrings.get(widget.lang, 'delete')),
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
                      AppStrings.get(widget.lang, 'manage_models_title'),
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
                    icon: const FaIcon(FontAwesomeIcons.xmark, size: 18),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _models.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        AppStrings.get(widget.lang, 'no_models_installed'),
                        style: TextStyle(
                          color: widget.isDark
                              ? Colors.grey[500]
                              : Colors.grey[600],
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _models.length,
                      itemBuilder: (context, index) {
                        final model = _models[index];
                        final isDeleting = _deletingModels.contains(model);
                        return ListTile(
                          leading: const FaIcon(FontAwesomeIcons.cube, size: 14),
                          title: Text(model, style: const TextStyle(fontSize: 14)),
                          trailing: isDeleting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : IconButton(
                                  onPressed: () => _confirmDelete(model),
                                  icon: FaIcon(
                                    FontAwesomeIcons.trash,
                                    size: 14,
                                    color: Colors.red[400],
                                  ),
                                ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        widget.isDark ? Colors.white : AppColors.lightPrimary,
                    foregroundColor:
                        widget.isDark ? Colors.black : Colors.white,
                  ),
                  child: Text(AppStrings.get(widget.lang, 'close')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
