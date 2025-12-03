import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import '../theme/app_theme.dart';
import '../widgets/language_selector.dart';
import '../widgets/file_upload_zone.dart';
import '../../controllers/translation_controller.dart';
import '../theme/config_provider.dart';
import '../../utils/app_strings.dart';

enum TranslationState { idle, fileSelected, processing, finished }

class TranslateScreen extends StatefulWidget {
  final bool isDark;

  const TranslateScreen({super.key, required this.isDark});

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  String _sourceLang = 'Tiếng Anh';
  String _targetLang = 'Tiếng Việt';
  bool _useCustomDict = true;

  // State Machine
  TranslationState _currentState = TranslationState.idle;
  String? _selectedFilePath;
  String? _selectedDictionaryPath;
  String? _translatedContent;

  // Processing State
  final TranslationController _controller = TranslationController();
  double _progress = 0.0;
  String _statusMessage = "";

  // Resume state
  bool _hasExistingProgress = false;
  double _existingProgressPercent = 0.0;

  final List<String> _allLanguages = ['Tiếng Anh', 'Tiếng Trung', 'Tiếng Việt'];

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
      _progress = 0.0;
      _statusMessage = "";
      _hasExistingProgress = false;
      _existingProgressPercent = 0.0;
    });
  }

  void _onFileSelected(String filePath) async {
    setState(() {
      _selectedFilePath = filePath;
      _currentState = TranslationState.fileSelected;
    });
    // Check for existing progress
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

    if (!configProvider.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.get(context.read<ConfigProvider>().appLanguage,
                'please_configure_project'),
            style: const TextStyle(color: AppColors.lightPrimary),
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
          ),
          backgroundColor: widget.isDark ? AppColors.darkSurface : Colors.white,
          margin: const EdgeInsets.all(16),
          elevation: 6,
        ),
      );
      return;
    }

    if (_selectedFilePath == null) return;

    setState(() {
      _currentState = TranslationState.processing;
      _progress = resume ? _existingProgressPercent : 0.0;
      _statusMessage = resume
          ? AppStrings.get(configProvider.appLanguage, 'resuming')
          : AppStrings.get(configProvider.appLanguage, 'initializing');
    });

    // Switch ON = Local Mode (Offline) -> allowInternet: false
    // Switch OFF = Internet Mode (Online) -> allowInternet: true
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
        onUpdate: (status, progress) {
          if (mounted) {
            setState(() {
              _statusMessage = status;
              _progress = progress;
            });
          }
        },
      );

      if (mounted) {
        // result is null if paused
        if (result == null) {
          // Paused - go back to file selected state
          await _checkExistingProgress();
          setState(() {
            _currentState = TranslationState.fileSelected;
          });
        } else {
          // Completed
          setState(() {
            _translatedContent = result;
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
        setState(() {
          _currentState = TranslationState.fileSelected; // Go back to selected
          _statusMessage =
              "${AppStrings.get(context.read<ConfigProvider>().appLanguage, 'error_prefix')}$e";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "${AppStrings.get(context.read<ConfigProvider>().appLanguage, 'error_prefix')}$e",
              style: const TextStyle(color: AppColors.lightPrimary),
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
            ),
            backgroundColor:
                widget.isDark ? AppColors.darkSurface : Colors.white,
            margin: const EdgeInsets.all(16),
            elevation: 6,
          ),
        );
      }
    }
  }

  void _requestPause() {
    _controller.requestPause();
    setState(() {
      _statusMessage =
          AppStrings.get(context.read<ConfigProvider>().appLanguage, 'pausing');
    });
  }

  Future<void> _saveResult() async {
    if (_translatedContent == null || _selectedFilePath == null) return;

    final String fileName = path.basenameWithoutExtension(_selectedFilePath!);
    // Output is ALWAYS .txt regardless of input format
    final String defaultName = "${fileName}_translated.txt";

    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: AppStrings.get(context.read<ConfigProvider>().appLanguage,
          'save_result_dialog_title'),
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: ['txt'], // Output is always TXT
    );

    if (outputFile != null) {
      try {
        final File file = File(outputFile);
        await file.writeAsString(_translatedContent!);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${AppStrings.get(context.read<ConfigProvider>().appLanguage, 'file_saved_at')}$outputFile',
                style: const TextStyle(color: AppColors.lightPrimary),
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.green.withOpacity(0.5)),
              ),
              backgroundColor:
                  widget.isDark ? AppColors.darkSurface : Colors.white,
              margin: const EdgeInsets.all(16),
              elevation: 6,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${AppStrings.get(context.read<ConfigProvider>().appLanguage, 'error_saving_file')}$e',
                style: const TextStyle(color: AppColors.lightPrimary),
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.red.withOpacity(0.5)),
              ),
              backgroundColor:
                  widget.isDark ? AppColors.darkSurface : Colors.white,
              margin: const EdgeInsets.all(16),
              elevation: 6,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Language Control
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 192,
                child: LanguageSelector(
                  value: _sourceLang,
                  isDark: widget.isDark,
                  onChange: (lang) {
                    setState(() {
                      if (lang == _targetLang) {
                        _targetLang = _sourceLang;
                      }
                      _sourceLang = lang;
                    });
                  },
                  availableLanguages: _allLanguages,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: IconButton(
                  onPressed: _swapLanguages,
                  icon: FaIcon(
                    FontAwesomeIcons.rightLeft,
                    size: 16,
                    color:
                        widget.isDark ? Colors.white : AppColors.lightPrimary,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: widget.isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : AppColors.lightPrimary.withValues(alpha: 0.1),
                    shape: const CircleBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 192,
                child: LanguageSelector(
                  value: _targetLang,
                  isDark: widget.isDark,
                  onChange: (lang) => setState(() => _targetLang = lang),
                  availableLanguages: _allLanguages,
                  disabledLanguage: _sourceLang,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Specialized Mode Content (Dictionary + File Upload)
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
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: widget.isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isDark ? const Color(0xFF444444) : Colors.grey[300]!,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // File Card
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
                        FontAwesomeIcons.fileLines,
                        size: 24,
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
                            fontSize: 16,
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
                  // Delete progress button (only show if progress exists)
                  if (_hasExistingProgress)
                    IconButton(
                      onPressed: _deleteProgress,
                      icon: FaIcon(
                        FontAwesomeIcons.trash,
                        size: 14,
                        color: Colors.red[400],
                      ),
                      tooltip: AppStrings.get(lang, 'delete_progress_tooltip'),
                      style: IconButton.styleFrom(
                        backgroundColor: widget.isDark
                            ? Colors.red.withValues(alpha: 0.1)
                            : Colors.red.withValues(alpha: 0.1),
                        shape: const CircleBorder(),
                      ),
                    ),
                  IconButton(
                    onPressed: _reset,
                    icon: FaIcon(
                      FontAwesomeIcons.xmark,
                      size: 16,
                      color:
                          widget.isDark ? Colors.grey[400] : Colors.grey[500],
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: widget.isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.grey[200],
                      shape: const CircleBorder(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Start/Resume Button
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
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      widget.isDark ? Colors.white : AppColors.lightPrimary,
                  foregroundColor: widget.isDark ? Colors.black : Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            // Start Fresh button (only show if progress exists)
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
        width: 500,
        padding: const EdgeInsets.all(32),
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
            Text(
              AppStrings.get(lang, 'processing'),
              style: TextStyle(
                fontFamily: 'Merriweather',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: widget.isDark ? Colors.white : AppColors.lightPrimary,
              ),
            ),
            const SizedBox(height: 24),
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              backgroundColor: widget.isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey[200],
              color: widget.isDark ? Colors.white : AppColors.lightPrimary,
            ),
            const SizedBox(height: 16),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: widget.isDark ? Colors.grey[300] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "${(_progress * 100).toStringAsFixed(0)}%",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: widget.isDark ? Colors.white70 : AppColors.lightPrimary,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Pause Button
                ElevatedButton.icon(
                  onPressed: _requestPause,
                  icon: const FaIcon(FontAwesomeIcons.pause, size: 14),
                  label: Text(AppStrings.get(lang, 'pause')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isDark
                        ? Colors.orange.withValues(alpha: 0.2)
                        : Colors.orange.withValues(alpha: 0.1),
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
                // Cancel Button
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

  Widget _buildFinishedView() {
    final lang = context.watch<ConfigProvider>().appLanguage;
    return Center(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(32),
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
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: FaIcon(
                  FontAwesomeIcons.check,
                  size: 40,
                  color: Colors.green,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              AppStrings.get(lang, 'translation_success'),
              style: TextStyle(
                fontFamily: 'Merriweather',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: widget.isDark ? Colors.white : AppColors.lightPrimary,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _saveResult,
                icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 18),
                label: Text(
                  AppStrings.get(lang, 'save_result'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
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
            const SizedBox(height: 16),
            TextButton(
              onPressed: _reset,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
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
        // Dictionary header with toggle
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

        const SizedBox(height: 16),

        // Conditional: Upload (Local/Offline) or AI Auto (Online) box
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
              color: _useCustomDict
                  ? (widget.isDark
                      ? const Color(0xFF444444)
                      : Colors.grey[300]!)
                  : (widget.isDark
                      ? const Color(0xFF444444)
                      : AppColors.lightBorder),
              style: _useCustomDict ? BorderStyle.solid : BorderStyle.solid,
            ),
          ),
          child: _useCustomDict
              // Switch ON: Local Mode (Offline) - Show File Picker
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
                            mainAxisAlignment: MainAxisAlignment.center,
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
                              debugPrint("Error picking dictionary: $e");
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '${AppStrings.get(lang, 'error_picking_file')}$e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: widget.isDark
                                  ? Colors.grey[500]!
                                  : Colors.grey[300]!,
                            ),
                            backgroundColor: widget.isDark
                                ? Colors.transparent
                                : Colors.white,
                          ),
                          child: Text(
                            _selectedDictionaryPath != null
                                ? AppStrings.get(lang, 'change_file')
                                : AppStrings.get(lang, 'choose_file'),
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.isDark
                                  ? Colors.grey[300]
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Hint text for Local Mode
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
              // Switch OFF: Internet Mode (Online) - Show AI Auto status
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
                        mainAxisAlignment: MainAxisAlignment.center,
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
                                      .withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ).animate().fadeIn(),

        const SizedBox(height: 16),

        // Main upload zone
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
