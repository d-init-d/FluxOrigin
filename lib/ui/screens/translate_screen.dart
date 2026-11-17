import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../controllers/translation_controller.dart';
import '../../services/ai_service.dart';
import '../../services/dev_logger.dart';
import '../../services/epub_pipeline_service.dart';
import '../../services/qa_verifier_service.dart';
import '../../utils/app_strings.dart';
import '../../utils/desktop_helpers.dart';
import '../theme/app_theme.dart';
import '../theme/config_provider.dart';
import '../widgets/file_upload_zone.dart';
import '../widgets/language_selector.dart';
import '../widgets/ollama_connection_dialog.dart';

enum TranslationState { idle, fileSelected, processing, finished }

class TranslateScreen extends StatefulWidget {
  final bool isDark;
  final bool isActive;

  const TranslateScreen({
    super.key,
    required this.isDark,
    this.isActive = true,
  });

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  String _sourceLang = 'Tiếng Anh';
  String _targetLang = 'Tiếng Việt';
  String _selectedGenre = 'AUTO';
  bool _useCustomDict = true;

  TranslationState _currentState = TranslationState.idle;
  String? _selectedFilePath;
  String? _selectedDictionaryPath;
  String? _translatedContent;
  List<int>? _translatedEpubBytes;
  QaReport? _qaReport;
  String? _workspacePath;

  final TranslationController _controller = TranslationController();
  double _progress = 0.0;
  String _statusMessage = "";
  DateTime? _runStartedAt;

  String _currentSourceChunk = "";
  String _currentTranslatedChunk = "";
  int _currentChunkIndex = 0;
  int _totalChunks = 0;

  bool _hasExistingProgress = false;
  double _existingProgressPercent = 0.0;

  static const List<String> _allLanguages = [
    'Tiếng Anh',
    'Tiếng Trung',
    'Tiếng Việt',
    'Tiếng Nhật',
    'Tiếng Hàn',
    'Tiếng Pháp',
    'Tiếng Đức',
    'Tiếng Tây Ban Nha',
  ];

  static const List<(String, String)> _genreOptions = [
    ('AUTO', 'genre_auto'),
    ('KIEMHIEP', 'genre_kiemhiep'),
    ('TIEN_HIEP', 'genre_tienhiep'),
    ('NGONTINH', 'genre_ngontinh'),
    ('FANTASY', 'genre_fantasy'),
    ('KINHDOANH', 'genre_kinhdoanh'),
    ('KHOAHOC', 'genre_khoahoc'),
    ('KYTHUAT', 'genre_kythuat'),
    ('PHAPLY', 'genre_phaply'),
    ('KHAC', 'genre_khac'),
  ];

  void _swapLanguages() {
    setState(() {
      final temp = _sourceLang;
      _sourceLang = _targetLang;
      _targetLang = temp;
    });
  }

  void _reset() {
    setState(() {
      _currentState = TranslationState.idle;
      _selectedFilePath = null;
      _translatedContent = null;
      _translatedEpubBytes = null;
      _qaReport = null;
      _workspacePath = null;
      _progress = 0.0;
      _statusMessage = "";
      _hasExistingProgress = false;
      _existingProgressPercent = 0.0;
      _runStartedAt = null;
    });
  }

  void _onFileSelected(String filePath) async {
    setState(() {
      _selectedFilePath = filePath;
      _currentState = TranslationState.fileSelected;
    });
    await _checkExistingProgress();
  }

  Future<void> _checkExistingProgress() async {
    final configProvider = context.read<ConfigProvider>();
    if (!configProvider.isConfigured || _selectedFilePath == null) {
      setState(() {
        _hasExistingProgress = false;
        _existingProgressPercent = 0.0;
      });
      return;
    }

    final progress = await _controller.getProgressPercentage(
      _selectedFilePath!,
      configProvider.dictionaryDir,
    );

    if (mounted) {
      setState(() {
        _hasExistingProgress = progress != null;
        _existingProgressPercent = progress ?? 0.0;
      });
    }
  }

  Future<void> _deleteProgress() async {
    final configProvider = context.read<ConfigProvider>();
    if (!configProvider.isConfigured || _selectedFilePath == null) return;

    await _controller.deleteProgress(
      _selectedFilePath!,
      configProvider.dictionaryDir,
    );

    if (mounted) {
      setState(() {
        _hasExistingProgress = false;
        _existingProgressPercent = 0.0;
      });
    }
  }

  Future<void> _startTranslation({bool resume = false}) async {
    final configProvider = context.read<ConfigProvider>();
    final lang = configProvider.appLanguage;

    if (!configProvider.isConfigured) {
      _showSnack(AppStrings.get(lang, 'please_configure_project'),
          isError: true);
      return;
    }

    if (_selectedFilePath == null) return;

    // Pre-flight connection check across Ollama / LM Studio / BYOK
    final aiService = AIService();
    aiService.setBaseUrl(configProvider.currentAiUrl);
    aiService.setProviderType(configProvider.effectiveAiServiceType);
    aiService.setApiKey(configProvider.activeApiKey);

    final (connected, _, _) = await aiService.checkConnection();
    if (!connected) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => OllamaConnectionDialog(
            isDark: widget.isDark,
            lang: lang,
          ),
        );
      }
      return;
    }

    setState(() {
      _currentState = TranslationState.processing;
      _progress = resume ? _existingProgressPercent : 0.0;
      _statusMessage = resume
          ? AppStrings.get(lang, 'resuming')
          : AppStrings.get(lang, 'initializing');
      _currentSourceChunk = "";
      _currentTranslatedChunk = "";
      _currentChunkIndex = 0;
      _totalChunks = 0;
      _runStartedAt = DateTime.now();
      _qaReport = null;
      _translatedEpubBytes = null;
      _workspacePath = null;
    });

    // Apply full AI & D-Transcreate config
    _controller.setAIUrl(configProvider.currentAiUrl);
    _controller.setAIProviderType(configProvider.effectiveAiServiceType);
    _controller.setAIApiKey(configProvider.activeApiKey);
    _controller.setTemperature(configProvider.temperature);
    _controller.setChunkSize(configProvider.targetChunkSize);
    _controller.setDeepMode(configProvider.dTranscreateDeepMode);

    final bool allowInternet = !_useCustomDict;

    try {
      final result = await _controller.processFile(
        filePath: _selectedFilePath!,
        dictionaryDir: configProvider.dictionaryDir,
        modelName: configProvider.selectedModel,
        sourceLanguage: _sourceLang,
        targetLanguage: _targetLang,
        allowInternet: allowInternet,
        resume: resume,
        appLanguage: lang,
        userGlossaryPath: _useCustomDict ? _selectedDictionaryPath : null,
        genreOverride: _selectedGenre,
        preserveEpubLayout: configProvider.preserveEpubLayout,
        onUpdate: (status, progress) {
          if (mounted) {
            setState(() {
              _statusMessage = status;
              _progress = progress;
            });
          }
        },
        onChunkUpdate: (currentIndex, total, sourceChunk, translatedChunk) {
          if (mounted) {
            setState(() {
              _currentChunkIndex = currentIndex;
              _totalChunks = total;
              _currentSourceChunk = sourceChunk;
              _currentTranslatedChunk = translatedChunk;
            });
          }
        },
      );

      if (mounted) {
        if (result == null) {
          await _checkExistingProgress();
          setState(() {
            _currentState = TranslationState.fileSelected;
          });
        } else {
          setState(() {
            _translatedContent = result;
            _translatedEpubBytes = _controller.lastTranslatedEpubBytes;
            _qaReport = _controller.lastQaReport;
            _workspacePath = _controller.lastWorkspacePath;
            _currentState = TranslationState.finished;
            _progress = 1.0;
            _hasExistingProgress = false;
            _existingProgressPercent = 0.0;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        await _checkExistingProgress();
        if (!mounted) return;

        final lang = context.read<ConfigProvider>().appLanguage;
        setState(() {
          _currentState = TranslationState.fileSelected;
          _statusMessage = "${AppStrings.get(lang, 'error_prefix')}$e";
        });

        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('failed to connect') ||
            errorStr.contains('connection') ||
            errorStr.contains('api key') ||
            errorStr.contains('socket')) {
          showDialog(
            context: context,
            builder: (ctx) => OllamaConnectionDialog(
              isDark: widget.isDark,
              lang: lang,
            ),
          );
        } else {
          _showSnack('${AppStrings.get(lang, 'error_prefix')}$e',
              isError: true);
        }
      }
    }
  }

  void _requestPause() {
    _controller.requestPause();
    final lang = context.read<ConfigProvider>().appLanguage;
    setState(() {
      _statusMessage = AppStrings.get(lang, 'pausing');
    });
  }

  Future<void> _saveTextOrMarkdown(String ext) async {
    if (_translatedContent == null || _selectedFilePath == null) return;
    final lang = context.read<ConfigProvider>().appLanguage;
    final fileName = path.basenameWithoutExtension(_selectedFilePath!);
    final defaultName = '${fileName}_translated.$ext';

    final outputFile = await FilePicker.platform.saveFile(
      dialogTitle: AppStrings.get(lang, 'save_result_dialog_title'),
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: [ext],
    );

    if (outputFile != null) {
      try {
        await File(outputFile).writeAsString(_translatedContent!, flush: true);
        _showSnack('${AppStrings.get(lang, 'file_saved_at')}$outputFile');
      } catch (e) {
        _showSnack('${AppStrings.get(lang, 'error_saving_file')}$e',
            isError: true);
      }
    }
  }

  Future<void> _saveEpub() async {
    if (_translatedContent == null || _selectedFilePath == null) return;
    final lang = context.read<ConfigProvider>().appLanguage;
    final fileName = path.basenameWithoutExtension(_selectedFilePath!);
    final defaultName = '${fileName}_translated.epub';

    final outputFile = await FilePicker.platform.saveFile(
      dialogTitle: AppStrings.get(lang, 'save_result_dialog_title'),
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: ['epub'],
    );

    if (outputFile != null) {
      try {
        final bytes = (_translatedEpubBytes != null &&
                _translatedEpubBytes!.isNotEmpty)
            ? _translatedEpubBytes!
            : EpubPipelineService.buildCleanEpubFromText(
                title: fileName,
                content: _translatedContent!,
                targetLanguageName: _targetLang,
              );
        await File(outputFile).writeAsBytes(bytes, flush: true);
        _showSnack('${AppStrings.get(lang, 'file_saved_at')}$outputFile');
      } catch (e) {
        _showSnack('${AppStrings.get(lang, 'error_saving_file')}$e',
            isError: true);
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: TextStyle(
            color: widget.isDark ? Colors.white : AppColors.lightPrimary,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: (isError ? Colors.red : Colors.green).withValues(alpha: 0.5),
          ),
        ),
        backgroundColor: widget.isDark ? AppColors.darkSurface : Colors.white,
        margin: const EdgeInsets.all(16),
        elevation: 6,
      ),
    );
  }

  void _showQaDialog() {
    if (_qaReport == null) return;
    final report = _qaReport!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            FaIcon(
              report.passed
                  ? FontAwesomeIcons.circleCheck
                  : FontAwesomeIcons.triangleExclamation,
              size: 18,
              color: report.passed ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 10),
            Text(
              'D-Transcreate QA: ${report.score}/100',
              style: GoogleFonts.merriweather(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: widget.isDark ? Colors.white : AppColors.lightPrimary,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 560,
          height: 360,
          child: SingleChildScrollView(
            child: SelectableText(
              report.toMarkdown(),
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'Consolas',
                height: 1.5,
                color: widget.isDark ? Colors.grey[300] : Colors.grey[800],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _reportContent() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'd.init.d.contact@gmail.com',
      query: Uri.encodeFull(
        'subject=Report Inappropriate Content - FluxOrigin&body=I found inappropriate content generated by the AI in file...\n\nPlease describe the issue below:\n',
      ),
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    }
  }

  String _formatEta() {
    if (_runStartedAt == null || _currentChunkIndex <= 1 || _totalChunks <= 1) {
      return '';
    }
    final completed = _currentChunkIndex - 1;
    final elapsedSec = DateTime.now().difference(_runStartedAt!).inSeconds;
    if (elapsedSec <= 0 || completed <= 0) return '';
    final remaining = _totalChunks - completed;
    final estSec = ((elapsedSec / completed) * remaining).round();
    if (estSec >= 60) {
      return ' · ~${(estSec / 60).ceil()}m left';
    }
    return ' · ~${estSec}s left';
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<ConfigProvider>().appLanguage;
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Language & Domain Control Row (compact, faithfully aligned)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 176,
                child: LanguageSelector(
                  value: _sourceLang,
                  isDark: widget.isDark,
                  onChange: (l) {
                    setState(() {
                      if (l == _targetLang) {
                        _targetLang = _sourceLang;
                      }
                      _sourceLang = l;
                    });
                  },
                  availableLanguages: _allLanguages,
                ),
              ),
              IconButton(
                onPressed: _swapLanguages,
                icon: FaIcon(
                  FontAwesomeIcons.rightLeft,
                  size: 14,
                  color: widget.isDark ? Colors.white : AppColors.lightPrimary,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: widget.isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : AppColors.lightPrimary.withValues(alpha: 0.1),
                  shape: const CircleBorder(),
                ),
              ),
              SizedBox(
                width: 176,
                child: LanguageSelector(
                  value: _targetLang,
                  isDark: widget.isDark,
                  onChange: (l) => setState(() => _targetLang = l),
                  availableLanguages: _allLanguages,
                  disabledLanguage: _sourceLang,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: widget.isDark
                        ? const Color(0xFF444444)
                        : AppColors.lightBorder,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedGenre,
                    dropdownColor:
                        widget.isDark ? AppColors.darkSurface : Colors.white,
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          widget.isDark ? Colors.grey[200] : AppColors.lightPrimary,
                    ),
                    items: _genreOptions
                        .map((g) => DropdownMenuItem<String>(
                              value: g.$1,
                              child: Text(AppStrings.get(lang, g.$2)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedGenre = v);
                    },
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Dictionary + File Upload Zone
          Expanded(
            child: _buildSpecializedMode(),
          ),
        ],
      ),
    );
  }

  Widget _buildStateContent() {
    switch (_currentState) {
      case TranslationState.idle:
        return FileUploadZone(
          isDark: widget.isDark,
          onFileSelected: _onFileSelected,
          enabled: widget.isActive,
        ).animate().fadeIn();

      case TranslationState.fileSelected:
        return _buildFileSelectedView();

      case TranslationState.processing:
        return _buildProcessingView();

      case TranslationState.finished:
        return _buildFinishedView();
    }
  }

  Widget _buildFileSelectedView() {
    final String fileName = _selectedFilePath != null
        ? path.basename(_selectedFilePath!)
        : "Unknown File";

    final lang = context.watch<ConfigProvider>().appLanguage;
    final int progressPercent = (_existingProgressPercent * 100).toInt();

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: widget.isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isDark ? const Color(0xFF444444) : Colors.grey[300]!,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.isDark
                      ? const Color(0xFF555555)
                      : Colors.grey[300]!,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: FaIcon(
                        fileName.toLowerCase().endsWith('.epub')
                            ? FontAwesomeIcons.bookOpen
                            : (fileName.toLowerCase().endsWith('.pdf')
                                ? FontAwesomeIcons.filePdf
                                : FontAwesomeIcons.fileLines),
                        size: 22,
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
                          fileName,
                          style: TextStyle(
                            fontFamily: 'Merriweather',
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: widget.isDark
                                ? Colors.white
                                : AppColors.lightPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_hasExistingProgress)
                          Text(
                            '${AppStrings.get(lang, 'progress')}$progressPercent%',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.isDark
                                  ? Colors.green[300]
                                  : Colors.green[700],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_hasExistingProgress)
                    IconButton(
                      onPressed: _deleteProgress,
                      icon: FaIcon(
                        FontAwesomeIcons.trash,
                        size: 14,
                        color: Colors.red[400],
                      ),
                      tooltip:
                          AppStrings.get(lang, 'delete_progress_tooltip'),
                    ),
                  IconButton(
                    onPressed: _reset,
                    icon: FaIcon(
                      FontAwesomeIcons.xmark,
                      size: 16,
                      color:
                          widget.isDark ? Colors.grey[400] : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    _startTranslation(resume: _hasExistingProgress),
                icon: _hasExistingProgress
                    ? const FaIcon(FontAwesomeIcons.play, size: 14)
                    : const SizedBox.shrink(),
                label: Text(
                  _hasExistingProgress
                      ? '${AppStrings.get(lang, 'continue_translation')} - $progressPercent%'
                      : AppStrings.get(lang, 'start_translation'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      widget.isDark ? Colors.white : AppColors.lightPrimary,
                  foregroundColor: widget.isDark ? Colors.black : Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (_hasExistingProgress) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  await _deleteProgress();
                  _startTranslation(resume: false);
                },
                child: Text(
                  AppStrings.get(lang, 'restart_from_beginning'),
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
            ],
          ],
        ),
      ).animate().scale(duration: 200.ms, curve: Curves.easeOut),
    );
  }

  Widget _buildProcessingView() {
    final lang = context.watch<ConfigProvider>().appLanguage;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 620),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: widget.isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isDark ? const Color(0xFF444444) : Colors.grey[300]!,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.get(lang, 'processing'),
                        style: TextStyle(
                          fontFamily: 'Merriweather',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: widget.isDark
                              ? Colors.white
                              : AppColors.lightPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _statusMessage,
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.isDark
                              ? Colors.grey[400]
                              : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : AppColors.lightPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${(_progress * 100).toStringAsFixed(0)}%",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color:
                          widget.isDark ? Colors.white : AppColors.lightPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              backgroundColor: widget.isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey[200],
              color: widget.isDark ? Colors.white : AppColors.lightPrimary,
            ),
            const SizedBox(height: 14),
            if (_totalChunks > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "${AppStrings.get(lang, 'chunk_progress')} $_currentChunkIndex / $_totalChunks${_formatEta()}",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.isDark ? Colors.blue[200] : Colors.blue[700],
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _buildTextPanel(
                      title: AppStrings.get(lang, 'source_text_panel'),
                      content: _currentSourceChunk,
                      icon: FontAwesomeIcons.fileLines,
                      iconColor: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextPanel(
                      title: AppStrings.get(lang, 'translated_text_panel'),
                      content: _currentTranslatedChunk,
                      icon: FontAwesomeIcons.language,
                      iconColor: Colors.green,
                      isTranslating: _currentTranslatedChunk ==
                          AppStrings.get(lang, 'processing'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _requestPause,
                  icon: const FaIcon(FontAwesomeIcons.pause, size: 14),
                  label: Text(AppStrings.get(lang, 'pause')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.withValues(alpha: 0.15),
                    foregroundColor: Colors.orange,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: Colors.orange.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: () {
                    _controller.requestPause();
                    _reset();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  child: Text(AppStrings.get(lang, 'cancel_action')),
                ),
              ],
            ),
          ],
        ),
      ).animate().fadeIn(),
    );
  }

  Widget _buildTextPanel({
    required String title,
    required String content,
    required FaIconData icon,
    required Color iconColor,
    bool isTranslating = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.black.withValues(alpha: 0.3)
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isDark ? const Color(0xFF333333) : Colors.grey[300]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                FaIcon(icon, size: 14, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.isDark ? Colors.white70 : Colors.grey[700],
                  ),
                ),
                if (isTranslating) ...[
                  const Spacer(),
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: iconColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: content.isEmpty
                ? Center(
                    child: Text(
                      AppStrings.get(
                          context.read<ConfigProvider>().appLanguage,
                          'waiting_data'),
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: widget.isDark
                            ? Colors.grey[600]
                            : Colors.grey[400],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      content,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: widget.isDark
                            ? Colors.grey[300]
                            : Colors.grey[800],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinishedView() {
    final lang = context.watch<ConfigProvider>().appLanguage;
    final hasLayoutEpub =
        _translatedEpubBytes != null && _translatedEpubBytes!.isNotEmpty;

    return Center(
      child: Container(
        width: 540,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: widget.isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isDark ? const Color(0xFF444444) : Colors.grey[300]!,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: FaIcon(
                  FontAwesomeIcons.check,
                  size: 34,
                  color: Colors.green,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              AppStrings.get(lang, 'translation_success'),
              style: TextStyle(
                fontFamily: 'Merriweather',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: widget.isDark ? Colors.white : AppColors.lightPrimary,
              ),
            ),
            if (_qaReport != null) ...[
              const SizedBox(height: 10),
              ActionChip(
                avatar: FaIcon(
                  _qaReport!.passed
                      ? FontAwesomeIcons.shieldHalved
                      : FontAwesomeIcons.triangleExclamation,
                  size: 13,
                  color: _qaReport!.passed ? Colors.green : Colors.orange,
                ),
                label: Text(
                  '${AppStrings.get(lang, 'qa_score_label')}: ${_qaReport!.score}/100 (${_qaReport!.warningCount} warn)',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: _showQaDialog,
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: hasLayoutEpub
                    ? _saveEpub
                    : () => _saveTextOrMarkdown('txt'),
                icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 16),
                label: Text(
                  hasLayoutEpub
                      ? AppStrings.get(lang, 'save_epub')
                      : AppStrings.get(lang, 'save_result'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      widget.isDark ? Colors.white : AppColors.lightPrimary,
                  foregroundColor: widget.isDark ? Colors.black : Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!hasLayoutEpub)
                  OutlinedButton.icon(
                    onPressed: _saveEpub,
                    icon: const FaIcon(FontAwesomeIcons.book, size: 12),
                    label: Text(AppStrings.get(lang, 'save_epub'),
                        style: const TextStyle(fontSize: 12)),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _saveTextOrMarkdown('txt'),
                    icon: const FaIcon(FontAwesomeIcons.fileLines, size: 12),
                    label: Text(AppStrings.get(lang, 'save_result'),
                        style: const TextStyle(fontSize: 12)),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _saveTextOrMarkdown('md'),
                  icon: const FaIcon(FontAwesomeIcons.markdown, size: 12),
                  label: Text(AppStrings.get(lang, 'save_md'),
                      style: const TextStyle(fontSize: 12)),
                ),
                if (_workspacePath != null)
                  OutlinedButton.icon(
                    onPressed: () => revealInDesktopExplorer(_workspacePath!),
                    icon: const FaIcon(FontAwesomeIcons.folderOpen, size: 12),
                    label: Text(AppStrings.get(lang, 'reveal_in_finder'),
                        style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _reportContent,
              icon: Icon(Icons.flag_outlined, size: 15, color: Colors.grey[500]),
              label: Text(
                AppStrings.get(lang, 'report_inappropriate_content'),
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),
            TextButton(
              onPressed: _reset,
              child: Text(
                AppStrings.get(lang, 'translate_another'),
                style: TextStyle(
                  color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      ).animate().scale(duration: 200.ms, curve: Curves.easeOut),
    );
  }

  Widget _buildSpecializedMode() {
    final lang = context.watch<ConfigProvider>().appLanguage;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                FaIcon(
                  FontAwesomeIcons.bookBookmark,
                  size: 16,
                  color: widget.isDark ? Colors.white : AppColors.lightPrimary,
                ),
                const SizedBox(width: 8),
                Text(
                  AppStrings.get(lang, 'local_dictionary'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color:
                        widget.isDark ? Colors.white : AppColors.lightPrimary,
                  ),
                ),
              ],
            ),
            Switch(
              value: _useCustomDict,
              onChanged: (value) => setState(() => _useCustomDict = value),
              activeTrackColor: const Color(0xFF043222),
              activeThumbColor: Colors.white,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _useCustomDict
                ? (widget.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey[50])
                : (widget.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFE8E6DF)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isDark
                  ? const Color(0xFF444444)
                  : AppColors.lightBorder,
            ),
          ),
          child: _useCustomDict
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        FaIcon(
                          FontAwesomeIcons.upload,
                          size: 18,
                          color: widget.isDark
                              ? Colors.white
                              : AppColors.lightPrimary,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedDictionaryPath != null
                                    ? path.basename(_selectedDictionaryPath!)
                                    : AppStrings.get(
                                        lang, 'upload_dictionary_placeholder'),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: widget.isDark
                                      ? Colors.grey[200]
                                      : Colors.grey[800],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _selectedDictionaryPath != null
                                    ? AppStrings.get(lang, 'selected')
                                    : '.CSV',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: widget.isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () async {
                            try {
                              final result =
                                  await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['csv'],
                              );
                              if (result != null &&
                                  result.files.single.path != null) {
                                setState(() {
                                  _selectedDictionaryPath =
                                      result.files.single.path;
                                });
                              }
                            } catch (e) {
                              DevLogger().warning(
                                  'TranslateScreen', 'Error picking dictionary',
                                  details: e.toString());
                              if (mounted) {
                                _showSnack(
                                    '${AppStrings.get(lang, 'error_picking_file')}$e',
                                    isError: true);
                              }
                            }
                          },
                          child: Text(
                            _selectedDictionaryPath != null
                                ? AppStrings.get(lang, 'change_file')
                                : AppStrings.get(lang, 'choose_file'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.get(lang, 'local_mode_hint'),
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color:
                            widget.isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: widget.isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: FaIcon(
                          FontAwesomeIcons.wandMagicSparkles,
                          size: 18,
                          color: widget.isDark
                              ? Colors.white
                              : AppColors.lightAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.get(lang, 'ai_auto_mode'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: widget.isDark
                                  ? Colors.white
                                  : AppColors.lightPrimary,
                            ),
                          ),
                          Text(
                            AppStrings.get(lang, 'ai_auto_hint'),
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.isDark
                                  ? Colors.grey[400]
                                  : AppColors.lightPrimary
                                      .withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ).animate().fadeIn(),
        const SizedBox(height: 16),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildStateContent(),
          ),
        ),
      ],
    ).animate().fadeIn();
  }
}
