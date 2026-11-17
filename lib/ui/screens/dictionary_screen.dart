import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../services/d_transcreate_service.dart';
import '../../services/dev_logger.dart';
import '../../utils/app_strings.dart';
import '../theme/app_theme.dart';
import '../theme/config_provider.dart';
import '../widgets/upload_dictionary_modal.dart';

class DictionaryScreen extends StatefulWidget {
  final bool isDark;

  const DictionaryScreen({super.key, required this.isDark});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  bool _showModal = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _dictionaries = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDictionaries());
  }

  Future<void> _loadDictionaries() async {
    setState(() => _isLoading = true);

    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    final dictionaryDir = configProvider.dictionaryDir;

    if (dictionaryDir.isEmpty) {
      setState(() {
        _dictionaries = [];
        _isLoading = false;
      });
      return;
    }

    final dir = Directory(dictionaryDir);
    if (!await dir.exists()) {
      setState(() {
        _dictionaries = [];
        _isLoading = false;
      });
      return;
    }

    final List<Map<String, dynamic>> dicts = [];

    try {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.csv')) {
          final file = entity;
          final stat = await file.stat();
          final fileName = file.path.split(Platform.pathSeparator).last;

          int lineCount = 0;
          try {
            final content = await file.readAsString();
            lineCount =
                content.split('\n').where((l) => l.trim().isNotEmpty).length;
          } catch (e) {
            DevLogger().warning('DictionaryScreen',
                'Failed to count lines for ${file.path}: $e');
          }

          final sizeBytes = stat.size;
          final String fileSize = sizeBytes >= 1024 * 1024
              ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
              : '${(sizeBytes / 1024).toStringAsFixed(0)} KB';

          dicts.add({
            'name': fileName,
            'entries': lineCount,
            'fileSize': fileSize,
            'path': file.path,
          });
        }
      }
      dicts.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    } catch (e) {
      DevLogger().warning('DictionaryScreen', 'Error loading dictionaries',
          details: e.toString());
    }

    if (mounted) {
      setState(() {
        _dictionaries = dicts;
        _isLoading = false;
      });
    }
  }

  Future<void> _importDTranscreatePreset(String domain, String lang) async {
    final config = context.read<ConfigProvider>();
    if (!config.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.get(lang, 'please_configure_project')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await DTranscreateService().importPresetGlossaryToDirectory(
      dictionaryDir: config.dictionaryDir,
      domain: domain,
    );
    await _loadDictionaries();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.get(lang, 'dict_imported_msg')
              .replaceAll('{domain}', domain)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openEditor(Map<String, dynamic> dict) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _DictionaryEditorDialog(
        filePath: dict['path'] as String,
        fileName: dict['name'] as String,
        isDark: widget.isDark,
      ),
    );
    if (changed == true) {
      await _loadDictionaries();
    }
  }

  Future<void> _renameDictionary(Map<String, dynamic> dict, String lang) async {
    final currentPath = dict['path'] as String;
    final currentName = p.basenameWithoutExtension(currentPath);
    final controller = TextEditingController(text: currentName);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? AppColors.darkSurface : Colors.white,
        title: Text(AppStrings.get(lang, 'rename')),
        content: TextField(
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.get(lang, 'cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.get(lang, 'save')),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      final newName = controller.text
          .trim()
          .replaceAll(RegExp(r'[^\w\u00C0-\u024F\-\s]+'), '_');
      final newPath = p.join(p.dirname(currentPath), '$newName.csv');
      if (newPath != currentPath) {
        await File(currentPath).rename(newPath);
        await _loadDictionaries();
      }
    }
  }

  Future<void> _deleteDictionary(Map<String, dynamic> dict, String lang) async {
    final name = dict['name'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? AppColors.darkSurface : Colors.white,
        title: Text(AppStrings.get(lang, 'delete')),
        content: Text(AppStrings.get(lang, 'confirm_delete_dict')
            .replaceAll('{name}', name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.get(lang, 'cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.get(lang, 'delete')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await File(dict['path'] as String).delete();
      await _loadDictionaries();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<ConfigProvider>().appLanguage;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadDictionaries,
          child: Container(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.get(lang, 'dictionary_title'),
                            style: GoogleFonts.merriweather(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: widget.isDark
                                  ? Colors.white
                                  : AppColors.lightPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            AppStrings.get(lang, 'dictionary_subtitle'),
                            style: TextStyle(
                              fontSize: 13,
                              color: widget.isDark
                                  ? Colors.grey[400]
                                  : AppColors.lightPrimary
                                      .withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        PopupMenuButton<String>(
                          tooltip: AppStrings.get(lang, 'import_d_transcreate'),
                          onSelected: (domain) =>
                              _importDTranscreatePreset(domain, lang),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'all', child: Text('All Domains (VI)')),
                            PopupMenuItem(
                                value: 'fiction',
                                child: Text('Fiction / Literary (VI)')),
                            PopupMenuItem(
                                value: 'technical',
                                child: Text('Technical / Software (VI)')),
                            PopupMenuItem(
                                value: 'legal',
                                child: Text('Legal / Contracts (VI)')),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: widget.isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : AppColors.lightPrimary
                                      .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: widget.isDark
                                    ? AppColors.darkBorder
                                    : AppColors.lightBorder,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FaIcon(
                                  FontAwesomeIcons.wandMagicSparkles,
                                  size: 13,
                                  color: widget.isDark
                                      ? Colors.white
                                      : AppColors.lightPrimary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  AppStrings.get(lang, 'import_d_transcreate'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: widget.isDark
                                        ? Colors.white
                                        : AppColors.lightPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _loadDictionaries,
                          icon: const FaIcon(FontAwesomeIcons.arrowsRotate,
                              size: 14),
                          tooltip: AppStrings.get(lang, 'refresh_tooltip'),
                          style: IconButton.styleFrom(
                            backgroundColor: widget.isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : AppColors.lightPrimary.withValues(alpha: 0.1),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => setState(() => _showModal = true),
                          icon: const FaIcon(FontAwesomeIcons.plus, size: 14),
                          label: Text(AppStrings.get(lang, 'add_new')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.isDark
                                ? Colors.white
                                : AppColors.lightPrimary,
                            foregroundColor:
                                widget.isDark ? Colors.black : Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // Table
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color:
                          widget.isDark ? AppColors.darkSurface : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: widget.isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? Colors.black.withValues(alpha: 0.2)
                                : Colors.grey[50]?.withValues(alpha: 0.5),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                            ),
                            border: Border(
                              bottom: BorderSide(
                                color: widget.isDark
                                    ? AppColors.darkBorder
                                    : Colors.grey[100]!,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  AppStrings.get(lang, 'dictionary_name'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: widget.isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[500],
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  AppStrings.get(lang, 'dictionary_size'),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: widget.isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[500],
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  AppStrings.get(lang, 'dictionary_entries'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: widget.isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[500],
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 48),
                            ],
                          ),
                        ),
                        Expanded(child: _buildContent()),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: widget.isDark
                                    ? AppColors.darkBorder
                                    : Colors.grey[100]!,
                              ),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              AppStrings.get(lang, 'showing_dictionaries')
                                  .replaceAll('{count}',
                                      _dictionaries.length.toString()),
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: widget.isDark
                                    ? Colors.grey[600]
                                    : Colors.grey[500],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(),
        ),
        if (_showModal)
          UploadDictionaryModal(
            isDark: widget.isDark,
            onClose: () {
              setState(() => _showModal = false);
              _loadDictionaries();
            },
          ),
      ],
    );
  }

  Widget _buildContent() {
    final lang = context.watch<ConfigProvider>().appLanguage;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_dictionaries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(
              FontAwesomeIcons.folderOpen,
              size: 48,
              color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.get(lang, 'no_dictionaries'),
              style: TextStyle(
                fontSize: 16,
                color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.get(lang, 'no_dictionaries_subtitle'),
              style: TextStyle(
                fontSize: 14,
                color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _dictionaries.length,
      itemBuilder: (context, index) => _DictRow(
        dict: _dictionaries[index],
        isDark: widget.isDark,
        isLast: index == _dictionaries.length - 1,
        lang: lang,
        onEdit: () => _openEditor(_dictionaries[index]),
        onRename: () => _renameDictionary(_dictionaries[index], lang),
        onDelete: () => _deleteDictionary(_dictionaries[index], lang),
      ),
    );
  }
}

class _DictRow extends StatefulWidget {
  final Map<String, dynamic> dict;
  final bool isDark;
  final bool isLast;
  final String lang;
  final VoidCallback onEdit;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _DictRow({
    required this.dict,
    required this.isDark,
    required this.isLast,
    required this.lang,
    required this.onEdit,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_DictRow> createState() => _DictRowState();
}

class _DictRowState extends State<_DictRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onEdit,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isHovered
                ? (widget.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey[50])
                : Colors.transparent,
            border: widget.isLast
                ? null
                : Border(
                    bottom: BorderSide(
                      color: widget.isDark
                          ? const Color(0xFF2A2A2A)
                          : Colors.grey[100]!,
                    ),
                  ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: widget.isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : AppColors.lightPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: FaIcon(
                          FontAwesomeIcons.book,
                          size: 12,
                          color: widget.isDark
                              ? Colors.white
                              : AppColors.lightPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.dict['name'],
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: widget.isDark
                              ? Colors.white
                              : AppColors.lightPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  widget.dict['fileSize'],
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  widget.dict['entries'].toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                child: PopupMenuButton<String>(
                  icon: FaIcon(
                    FontAwesomeIcons.ellipsisVertical,
                    size: 15,
                    color: Colors.grey[500],
                  ),
                  onSelected: (action) {
                    if (action == 'edit') widget.onEdit();
                    if (action == 'rename') widget.onRename();
                    if (action == 'delete') widget.onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(AppStrings.get(widget.lang, 'edit_terms')),
                    ),
                    PopupMenuItem(
                      value: 'rename',
                      child: Text(AppStrings.get(widget.lang, 'rename')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        AppStrings.get(widget.lang, 'delete'),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DictionaryEditorDialog extends StatefulWidget {
  final String filePath;
  final String fileName;
  final bool isDark;

  const _DictionaryEditorDialog({
    required this.filePath,
    required this.fileName,
    required this.isDark,
  });

  @override
  State<_DictionaryEditorDialog> createState() =>
      _DictionaryEditorDialogState();
}

class _DictionaryEditorDialogState extends State<_DictionaryEditorDialog> {
  final List<List<TextEditingController>> _rowControllers = [];
  final TextEditingController _filterCtrl = TextEditingController();
  bool _loading = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadRows();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    for (final rc in _rowControllers) {
      for (final c in rc) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _loadRows() async {
    try {
      final raw = await File(widget.filePath).readAsString();
      final parsed = const CsvToListConverter()
          .convert(raw, eol: '\n', shouldParseNumbers: false);
      for (final row in parsed) {
        final orig = row.isNotEmpty ? row[0].toString() : '';
        final target = row.length > 1 ? row[1].toString() : '';
        final ctx = row.length > 2 ? row[2].toString() : '';
        if (orig.trim().isEmpty && target.trim().isEmpty) continue;
        _rowControllers.add([
          TextEditingController(text: orig),
          TextEditingController(text: target),
          TextEditingController(text: ctx),
        ]);
      }
    } catch (e) {
      DevLogger().warning('DictionaryScreen', 'Error reading CSV in editor',
          details: e.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  void _addRow() {
    setState(() {
      _rowControllers.insert(0, [
        TextEditingController(),
        TextEditingController(),
        TextEditingController(),
      ]);
    });
  }

  Future<void> _saveAndClose() async {
    final rows = <List<String>>[];
    for (final rc in _rowControllers) {
      final o = rc[0].text.trim();
      final t = rc[1].text.trim();
      final c = rc[2].text.trim();
      if (o.isNotEmpty || t.isNotEmpty) {
        rows.add(c.isEmpty ? [o, t] : [o, t, c]);
      }
    }
    await File(widget.filePath)
        .writeAsString(const ListToCsvConverter().convert(rows, eol: '\n'), flush: true);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = _filter.isEmpty
        ? _rowControllers
        : _rowControllers
            .where((rc) =>
                rc[0].text.toLowerCase().contains(_filter) ||
                rc[1].text.toLowerCase().contains(_filter) ||
                rc[2].text.toLowerCase().contains(_filter))
            .toList();

    return Dialog(
      backgroundColor: widget.isDark ? AppColors.darkSurface : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 780,
        height: 560,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.fileName,
                    style: GoogleFonts.merriweather(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color:
                          widget.isDark ? Colors.white : AppColors.lightPrimary,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _addRow,
                  icon: const FaIcon(FontAwesomeIcons.plus, size: 12),
                  label: const Text('Add Row'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => Navigator.pop(context, false),
                  icon: const FaIcon(FontAwesomeIcons.xmark, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _filterCtrl,
              onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Filter terms...',
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: visibleRows.length,
                      itemBuilder: (ctx, idx) {
                        final rc = visibleRows[idx];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: rc[0],
                                  decoration: const InputDecoration(
                                    hintText: 'Original',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: rc[1],
                                  decoration: const InputDecoration(
                                    hintText: 'Translation',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: rc[2],
                                  decoration: const InputDecoration(
                                    hintText: 'Context (optional)',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: FaIcon(FontAwesomeIcons.trash,
                                    size: 13, color: Colors.red[400]),
                                onPressed: () {
                                  setState(() => _rowControllers.remove(rc));
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saveAndClose,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        widget.isDark ? Colors.white : AppColors.lightPrimary,
                    foregroundColor: widget.isDark ? Colors.black : Colors.white,
                  ),
                  child: const Text('Save Changes'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
