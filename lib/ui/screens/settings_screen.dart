import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../theme/config_provider.dart';
import '../widgets/path_setup_modal.dart';
import '../../services/ai_service.dart';

class SettingsScreen extends StatefulWidget {
  final bool isDark;

  const SettingsScreen({super.key, required this.isDark});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedModel = 'Qwen2.5-7B';
  bool _isModelDropdownOpen = false;

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
  Map<String, bool> _downloadingStates = {};

  @override
  void initState() {
    super.initState();
    _checkInstalledModels();
  }

  Future<void> _checkInstalledModels() async {
    final models = await _aiService.getInstalledModels();
    if (mounted) {
      setState(() {
        _installedModels = models;
      });
    }
  }

  String _getOllamaModelName(String uiName) {
    return uiName.toLowerCase().replaceFirst('-', ':');
  }

  Future<void> _downloadModel(String uiName) async {
    setState(() {
      _downloadingStates[uiName] = true;
    });

    final ollamaName = _getOllamaModelName(uiName);
    final success = await _aiService.pullModel(ollamaName, (progress) {
      // Optional: Handle progress update if needed
    });

    if (mounted) {
      setState(() {
        _downloadingStates[uiName] = false;
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 768),
          child: ListView(
            children: [
              Text(
                'Cài đặt',
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
                title: 'GIAO DIỆN',
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
                      title: 'Chế độ tối (Dark Mode)',
                      subtitle: 'Sử dụng giao diện tối để bảo vệ mắt',
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
                      title: 'Font chữ hiển thị',
                      subtitle: 'Tùy chỉnh font chữ cho phần đọc',
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
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // AI Section
              _SectionHeader(
                icon: FontAwesomeIcons.brain,
                title: 'CẤU HÌNH AI',
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
                child: _SettingRow(
                  title: 'Mô hình dịch thuật',
                  subtitle: 'Chọn mô hình ngôn ngữ chính',
                  isDark: widget.isDark,
                  trailing: GestureDetector(
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
                            _selectedModel,
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
                            color:
                                widget.isDark ? Colors.grey : Colors.grey[600],
                          ),
                        ],
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
                      final isSelected = model == _selectedModel;
                      final ollamaName = _getOllamaModelName(model);
                      final isInstalled = _installedModels.contains(ollamaName);
                      final isDownloading = _downloadingStates[model] == true;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedModel = model;
                            _isModelDropdownOpen = false;
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
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
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

              const SizedBox(height: 32),

              // Data Section
              _SectionHeader(
                icon: FontAwesomeIcons.database,
                title: 'DỮ LIỆU',
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
                child: InkWell(
                  onTap: () {},
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : AppColors.lightPrimary
                                    .withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: FaIcon(
                              FontAwesomeIcons.cloudArrowDown,
                              size: 16,
                              color: widget.isDark
                                  ? Colors.white
                                  : AppColors.lightPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quản lý gói ngôn ngữ Offline',
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
                                'Đã tải: Tiếng Anh, Tiếng Việt (120MB)',
                                style: TextStyle(
                                  fontSize: 14,
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
                          FontAwesomeIcons.chevronRight,
                          size: 14,
                          color: Colors.grey[400],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.isDark,
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
                        : AppColors.lightPrimary.withOpacity(0.6),
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
