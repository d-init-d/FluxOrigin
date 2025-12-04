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
  final TextEditingController _ollamaUrlController = TextEditingController();
  final TextEditingController _lmStudioUrlController = TextEditingController();
  bool _isCheckingConnection = false;
  String? _connectionStatus;
  bool? _isConnectionSuccess;
  List<String> _installedModels = [];
  final Map<String, double?> _downloadProgress = {};
  bool _isLoadingModels = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Load URLs from config after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAIConfig();
    });
  }

  void _initAIConfig() {
    final config = context.read<ConfigProvider>();
    _ollamaUrlController.text = config.ollamaUrl;
    _lmStudioUrlController.text = config.lmStudioUrl;

    // Set AIService based on current provider
    _updateAIServiceConfig(config);
    _checkInstalledModels();
  }

  void _updateAIServiceConfig(ConfigProvider config) {
    if (config.aiProvider == AIProvider.lmStudio) {
      _aiService.setBaseUrl(config.lmStudioUrl);
      _aiService.setProviderType(AIProviderType.lmStudio);
    } else {
      _aiService.setBaseUrl(config.ollamaUrl);
      _aiService.setProviderType(AIProviderType.ollama);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ollamaUrlController.dispose();
    _lmStudioUrlController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkInstalledModels();
    }
  }

  Future<void> _checkAIConnection(AIProvider provider) async {
    if (!mounted) return;

    setState(() {
      _isCheckingConnection = true;
      _connectionStatus = null;
      _isConnectionSuccess = null;
    });

    final url = provider == AIProvider.lmStudio
        ? _lmStudioUrlController.text.trim()
        : _ollamaUrlController.text.trim();

    final providerType = provider == AIProvider.lmStudio
        ? AIProviderType.lmStudio
        : AIProviderType.ollama;

    final (success, message) =
        await _aiService.checkConnection(url: url, providerType: providerType);

    if (mounted) {
      setState(() {
        _isCheckingConnection = false;
        _connectionStatus = message;
        _isConnectionSuccess = success;
      });

      if (success) {
        final config = context.read<ConfigProvider>();
        // Save URL to config
        if (provider == AIProvider.lmStudio) {
          await config.setLmStudioUrl(url);
        } else {
          await config.setOllamaUrl(url);
        }

        // If this is the active provider, update AIService and refresh models
        if (config.aiProvider == provider) {
          _updateAIServiceConfig(config);
          _checkInstalledModels();
        }
      }
    }
  }

  Future<void> _switchAIProvider(AIProvider provider) async {
    final config = context.read<ConfigProvider>();
    await config.setAIProvider(provider);

    // Reset connection status when switching
    setState(() {
      _connectionStatus = null;
      _isConnectionSuccess = null;
      _installedModels = [];
    });

    // Update AIService config
    _updateAIServiceConfig(config);

    // Check models for the new provider
    _checkInstalledModels();
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

        // Auto-select first model if current selection is invalid
        final config = context.read<ConfigProvider>();
        if (models.isNotEmpty && !models.contains(config.selectedModel)) {
          config.setSelectedModel(models.first);
        }
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? (widget.isDark
                      ? AppColors.lightPrimary.withValues(alpha: 0.2)
                      : AppColors.lightPrimary.withValues(alpha: 0.1))
                  : (widget.isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : Colors.grey[100]),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? (widget.isDark
                        ? AppColors.lightPrimary
                        : AppColors.lightPrimary)
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
                  size: 16,
                  color: isSelected
                      ? (widget.isDark ? Colors.white : AppColors.lightPrimary)
                      : (widget.isDark ? Colors.grey[400] : Colors.grey[600]),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? (widget.isDark
                            ? Colors.white
                            : AppColors.lightPrimary)
                        : (widget.isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  FaIcon(
                    FontAwesomeIcons.circleCheck,
                    size: 14,
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
            SnackBar(content: Text('Tải model $uiName thành công!')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tải model $uiName thất bại.')),
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
                          'Merriweather (${AppStrings.get(lang, 'default_label')})',
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

              // AI Provider Selection
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
                          fontWeight: FontWeight.w500,
                          color: widget.isDark
                              ? Colors.grey[200]
                              : AppColors.lightPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Chọn nguồn AI để sử dụng cho dịch thuật',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.isDark
                              ? Colors.grey[500]
                              : AppColors.lightPrimary.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Consumer<ConfigProvider>(
                        builder: (context, config, _) => Row(
                          children: [
                            _buildProviderButton(
                              label: 'Ollama',
                              icon: FontAwesomeIcons.server,
                              isSelected:
                                  config.aiProvider == AIProvider.ollama,
                              onTap: () => _switchAIProvider(AIProvider.ollama),
                            ),
                            const SizedBox(width: 12),
                            _buildProviderButton(
                              label: 'LM Studio',
                              icon: FontAwesomeIcons.desktop,
                              isSelected:
                                  config.aiProvider == AIProvider.lmStudio,
                              onTap: () =>
                                  _switchAIProvider(AIProvider.lmStudio),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // AI URL Configuration - Shows based on selected provider
              Consumer<ConfigProvider>(
                builder: (context, config, _) => Container(
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
                          config.aiProvider == AIProvider.lmStudio
                              ? 'URL LM Studio Server'
                              : 'URL Ollama Server',
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
                          config.aiProvider == AIProvider.lmStudio
                              ? 'Địa chỉ kết nối tới LM Studio (mặc định: http://localhost:1234)'
                              : 'Địa chỉ kết nối tới Ollama (mặc định: http://localhost:11434)',
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
                                controller:
                                    config.aiProvider == AIProvider.lmStudio
                                        ? _lmStudioUrlController
                                        : _ollamaUrlController,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: widget.isDark
                                      ? Colors.grey[200]
                                      : AppColors.lightPrimary,
                                ),
                                decoration: InputDecoration(
                                  hintText:
                                      config.aiProvider == AIProvider.lmStudio
                                          ? 'http://localhost:1234'
                                          : 'http://localhost:11434',
                                  hintStyle: TextStyle(
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
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(
                                      color: widget.isDark
                                          ? Colors.white.withValues(alpha: 0.3)
                                          : AppColors.lightPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: _isCheckingConnection
                                  ? null
                                  : () => _checkAIConnection(config.aiProvider),
                              icon: _isCheckingConnection
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: widget.isDark
                                            ? Colors.white
                                            : AppColors.lightPrimary,
                                      ),
                                    )
                                  : FaIcon(
                                      FontAwesomeIcons.plug,
                                      size: 14,
                                      color: widget.isDark
                                          ? Colors.white
                                          : Colors.white,
                                    ),
                              label: Text(
                                _isCheckingConnection
                                    ? 'Đang kiểm tra...'
                                    : 'Kiểm tra kết nối',
                                style: const TextStyle(fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: widget.isDark
                                    ? const Color(0xFF4CAF50)
                                    : AppColors.lightPrimary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_connectionStatus != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _isConnectionSuccess == true
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _isConnectionSuccess == true
                                    ? Colors.green.withValues(alpha: 0.3)
                                    : Colors.red.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                FaIcon(
                                  _isConnectionSuccess == true
                                      ? FontAwesomeIcons.circleCheck
                                      : FontAwesomeIcons.circleXmark,
                                  size: 14,
                                  color: _isConnectionSuccess == true
                                      ? Colors.green
                                      : Colors.red,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _connectionStatus!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _isConnectionSuccess == true
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // Note for LM Studio users
                        if (config.aiProvider == AIProvider.lmStudio) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.blue.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                FaIcon(
                                  FontAwesomeIcons.circleInfo,
                                  size: 14,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'LM Studio: Hãy đảm bảo đã bật Local Server trong LM Studio và đã load model trước khi sử dụng.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Model Selection - Show installed models
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
                  title: 'Mô hình dịch thuật',
                  subtitle: _installedModels.isEmpty
                      ? 'Chưa có model nào. Hãy kiểm tra kết nối Ollama.'
                      : 'Chọn từ ${_installedModels.length} model đã cài đặt',
                  isDark: widget.isDark,
                  trailing: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _installedModels.isEmpty
                          ? null
                          : () => setState(() =>
                              _isModelDropdownOpen = !_isModelDropdownOpen),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        constraints:
                            const BoxConstraints(minWidth: 140, maxWidth: 250),
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
                                _installedModels.isEmpty
                                    ? 'Không có model'
                                    : context
                                        .watch<ConfigProvider>()
                                        .selectedModel,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _installedModels.isEmpty
                                      ? Colors.grey
                                      : (widget.isDark
                                          ? Colors.grey[300]
                                          : AppColors.lightPrimary),
                                ),
                                overflow: TextOverflow.ellipsis,
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

              if (_isModelDropdownOpen && _installedModels.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  constraints: const BoxConstraints(maxHeight: 300),
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
                        final configProvider = context.read<ConfigProvider>();
                        final isSelected =
                            model == configProvider.selectedModel;

                        return InkWell(
                          onTap: () {
                            setState(() {
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
                    title: 'Quản lý Model đã tải',
                    subtitle: '${_installedModels.length} model đã cài đặt',
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
                title: 'CẤU HÌNH DỊCH THUẬT',
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
                                  'Thư mục dự án',
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
                                      : 'Chưa cấu hình',
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
                  'FluxOrigin v1.0.0 - Made with ☕ by d-init-d',
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
            SnackBar(content: Text('Đã xóa model $modelName')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Xóa model $modelName thất bại')),
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
          'Xác nhận xóa',
          style: TextStyle(
            color: widget.isDark ? Colors.white : AppColors.lightPrimary,
          ),
        ),
        content: Text(
          'Bạn có chắc muốn xóa model "$modelName"?',
          style: TextStyle(
            color: widget.isDark ? Colors.grey[300] : Colors.grey[700],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Hủy',
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
            child: const Text('Xóa'),
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
