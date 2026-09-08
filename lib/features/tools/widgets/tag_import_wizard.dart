import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/models/tag_category.dart';
import '../../../core/models/tag_source.dart';
import '../../../core/services/tag_list_parser.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/file_picker_helper.dart';
import '../../../core/utils/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/tag_library_notifier.dart';

/// Import flow for a user-supplied tag list: pick a file, sniff its shape on
/// a background isolate, let the user confirm/adjust the interpretation
/// (columns, category numbering, threshold, categories, spacing), preview a
/// few rows, then parse the whole thing and store it as a tag source.
class TagImportWizard {
  TagImportWizard._();

  static const List<String> extensions = ['csv', 'json', 'txt', 'gz'];

  /// Starts the flow. With [replace], the picked file updates that existing
  /// source in place (same id, keeps its enabled flag and position).
  static Future<void> start(BuildContext context, {TagSource? replace}) async {
    final notifier = context.read<TagLibraryNotifier>();
    final l = context.l;
    final navigator = Navigator.of(context);

    final picked = await pickCustomFiles(allowedExtensions: extensions, withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = await readPickedFileBytes(file);
    if (bytes == null) {
      if (context.mounted) showErrorSnackBar(context, l.tagImportFailed('no data'));
      return;
    }
    if (!context.mounted) return;

    // Sniff off the UI thread; a full e621 dump is tens of MB.
    var loadingOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    ).whenComplete(() => loadingOpen = false);

    TagListSniff sniff;
    try {
      sniff = await compute(_decodeAndSniff, bytes);
    } catch (e) {
      if (loadingOpen) navigator.pop();
      if (context.mounted) showErrorSnackBar(context, l.tagImportFailed(e.toString()));
      return;
    }
    if (loadingOpen) navigator.pop();
    if (!context.mounted) return;

    if (sniff.isEmpty) {
      showErrorSnackBar(context, l.tagImportEmpty);
      return;
    }

    await showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: notifier,
        child: _TagImportDialog(sniff: sniff, fileName: file.name, replace: replace),
      ),
    );
  }

  static TagListSniff _decodeAndSniff(Uint8List bytes) =>
      TagListParser.sniff(TagListParser.decodeBytes(bytes));

  static TagImportResult _parseJob((TagListSniff, TagImportOptions) job) =>
      TagListParser.parse(job.$1, job.$2);

  /// `foo.csv.gz` → `foo`, `e621_tags.json` → `e621_tags`.
  static String defaultName(String fileName) {
    var n = p.basename(fileName);
    for (final ext in ['.gz', '.csv', '.json', '.txt']) {
      if (n.toLowerCase().endsWith(ext)) n = n.substring(0, n.length - ext.length);
    }
    return n.isEmpty ? 'Tag list' : n;
  }
}

class _TagImportDialog extends StatefulWidget {
  final TagListSniff sniff;
  final String fileName;
  final TagSource? replace;

  const _TagImportDialog({required this.sniff, required this.fileName, this.replace});

  @override
  State<_TagImportDialog> createState() => _TagImportDialogState();
}

class _TagImportDialogState extends State<_TagImportDialog> {
  late final TextEditingController _name;
  late TagColumnMapping _mapping;
  late TagSiteProfile _profile;
  late Map<String, String?> _customMap;
  late int _minCount;
  late Set<String> _include;
  bool _spaces = true;
  bool _aliases = true;
  bool _importing = false;

  TagListSniff get sniff => widget.sniff;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.replace?.name ?? TagImportWizard.defaultName(widget.fileName));
    _mapping = sniff.mapping;
    _profile = sniff.guessedProfile;
    _customMap = {
      for (final v in sniff.categoryValues)
        v: TagImportOptions(sourceId: '', mapping: sniff.mapping, profile: _profile).resolveCategory(v),
    };
    _include = TagCategories.all.toSet();
    _minCount = _suggestMinCount();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Big lists get a starting threshold that keeps them under ~100k tags;
  /// the user can lower it, but autocomplete stays snappy by default.
  int _suggestMinCount() {
    if (!sniff.hasCounts || sniff.rows.length <= 100000) return 0;
    for (final t in TagListParser.countLadder) {
      if ((sniff.countHistogram[t] ?? 0) <= 100000) return t;
    }
    return TagListParser.countLadder.last;
  }

  TagImportOptions _options(String sourceId) => TagImportOptions(
        sourceId: sourceId,
        mapping: _mapping,
        profile: _profile,
        customCategoryMap: _profile == TagSiteProfile.custom ? _customMap : const {},
        minCount: _minCount,
        includeCategories: _include.length == TagCategories.all.length ? null : _include,
        includeAliases: _aliases,
        underscoresToSpaces: _spaces,
      );

  TagSource? _existingByName(TagLibraryNotifier notifier) {
    if (widget.replace != null) return widget.replace;
    return notifier.sources?.byName(_name.text);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final mobile = isMobile(context);
    final notifier = context.read<TagLibraryNotifier>();
    final existing = _existingByName(notifier);
    final canImport = _mapping.name != null && _name.text.trim().isNotEmpty && !_importing;
    final preview = TagListParser.parse(sniff.withRows(sniff.sampleRows), _options('preview')).tags;

    return AlertDialog(
      backgroundColor: t.surfaceHigh,
      title: Text(
        l.tagImportTitle,
        style: TextStyle(fontSize: t.titleSize(mobile ? 13 : 10), letterSpacing: 2, color: t.textSecondary, fontWeight: FontWeight.w900),
      ),
      content: SizedBox(
        width: mobile ? double.maxFinite : 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(12)),
                decoration: InputDecoration(
                  labelText: l.tagImportName,
                  labelStyle: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9), letterSpacing: 1),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${widget.fileName} · ${_formatLabel(l)} · ${l.tagImportRows(sniff.rows.length)}',
                style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8), letterSpacing: 0.5),
              ),
              if (existing != null && widget.replace == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    l.tagImportReplaceExisting(existing.name),
                    style: TextStyle(color: t.accentEdit, fontSize: t.fontSize(9)),
                  ),
                ),
              if (sniff.columns.length > 1) ...[
                _section(l.tagImportColumns, t),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _columnPicker(l.tagImportColName, _mapping.name, (v) => _mapping = _mapping.copyWith(name: () => v), t, l),
                    _columnPicker(l.tagImportColCategory, _mapping.category, (v) => _mapping = _mapping.copyWith(category: () => v), t, l),
                    _columnPicker(l.tagImportColCount, _mapping.count, (v) => _mapping = _mapping.copyWith(count: () => v), t, l),
                    _columnPicker(l.tagImportColAliases, _mapping.aliases, (v) => _mapping = _mapping.copyWith(aliases: () => v), t, l),
                  ],
                ),
              ],
              if (_mapping.category != null && sniff.hasNumericCategories) ...[
                _section(l.tagImportProfile, t),
                DropdownButton<TagSiteProfile>(
                  value: _profile,
                  isExpanded: true,
                  dropdownColor: t.background,
                  style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(10)),
                  items: [
                    for (final p in TagSiteProfile.values)
                      DropdownMenuItem(value: p, child: Text(_profileLabel(l, p), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _profile = v;
                      if (v != TagSiteProfile.custom) {
                        _customMap = {
                          for (final raw in sniff.categoryValues)
                            raw: TagImportOptions(sourceId: '', mapping: _mapping, profile: v).resolveCategory(raw),
                        };
                      }
                    });
                  },
                ),
                if (_profile == TagSiteProfile.custom) ...[
                  const SizedBox(height: 4),
                  Text(l.tagImportCustomMapHint, style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8))),
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    children: [
                      for (final raw in sniff.categoryValues) _customMapRow(raw, t, l),
                    ],
                  ),
                ],
              ],
              if (sniff.hasCounts && _mapping.count != null) ...[
                _section(l.tagImportMinCount, t),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final threshold in TagListParser.countLadder)
                      ChoiceChip(
                        label: Text(
                          threshold == 0 ? l.tagLibAll : '≥ ${NumberFormat.compact().format(threshold)}',
                          style: TextStyle(fontSize: t.fontSize(8), color: _minCount == threshold ? t.textPrimary : t.textDisabled),
                        ),
                        selected: _minCount == threshold,
                        selectedColor: t.accent.withValues(alpha: 0.25),
                        backgroundColor: t.surfaceMid,
                        side: BorderSide(color: t.borderSubtle),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _minCount = threshold),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l.tagImportWillImport(sniff.countHistogram[_minCount] ?? sniff.rows.length, sniff.rows.length),
                  style: TextStyle(color: t.accent, fontSize: t.fontSize(9), letterSpacing: 1),
                ),
              ],
              _section(l.tagImportCategories, t),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final cat in TagCategories.all)
                    FilterChip(
                      label: Text(
                        cat.toUpperCase(),
                        style: TextStyle(
                          fontSize: t.fontSize(8),
                          letterSpacing: 1,
                          color: TagCategories.colorFor(cat).withValues(alpha: _include.contains(cat) ? 1 : 0.4),
                        ),
                      ),
                      selected: _include.contains(cat),
                      showCheckmark: false,
                      selectedColor: TagCategories.colorFor(cat).withValues(alpha: 0.15),
                      backgroundColor: Colors.transparent,
                      side: BorderSide(color: TagCategories.colorFor(cat).withValues(alpha: _include.contains(cat) ? 0.5 : 0.15)),
                      visualDensity: VisualDensity.compact,
                      onSelected: (v) => setState(() => v ? _include.add(cat) : _include.remove(cat)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _toggle(l.tagImportSpaces, _spaces, (v) => setState(() => _spaces = v), t),
              if (_mapping.aliases != null)
                _toggle(l.tagImportAliases, _aliases, (v) => setState(() => _aliases = v), t),
              _section(l.tagImportPreview, t),
              if (preview.isEmpty)
                Text(l.tagImportEmpty, style: TextStyle(color: t.accentDanger, fontSize: t.fontSize(9)))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final tag in preview) _previewChip(tag, t),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.pop(context),
          child: Text(l.commonCancel, style: TextStyle(color: t.textDisabled, fontSize: t.buttonSize(9))),
        ),
        TextButton(
          onPressed: canImport ? () => _import(notifier, existing) : null,
          child: _importing
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: t.accent))
              : Text(l.tagImportButton, style: TextStyle(color: canImport ? t.accent : t.textDisabled, fontSize: t.buttonSize(9), fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _section(String label, VisionTokens t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8), letterSpacing: 2, fontWeight: FontWeight.bold),
        ),
      );

  Widget _columnPicker(String label, String? value, void Function(String?) onChanged, VisionTokens t, AppLocalizations l) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(7), letterSpacing: 1)),
          DropdownButton<String?>(
            value: value,
            isExpanded: true,
            isDense: true,
            dropdownColor: t.background,
            style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(10)),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(l.tagImportColNone, style: TextStyle(color: t.textDisabled))),
              for (final c in sniff.columns) DropdownMenuItem<String?>(value: c.key, child: Text(c.label, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => onChanged(v)),
          ),
        ],
      ),
    );
  }

  Widget _customMapRow(String raw, VisionTokens t, AppLocalizations l) {
    final current = _customMap[raw];
    return SizedBox(
      width: 160,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(raw, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(9), fontFamily: 'monospace')),
          ),
          Icon(Icons.arrow_right_alt, size: 12, color: t.textDisabled),
          Expanded(
            child: DropdownButton<String>(
              value: current ?? '_skip',
              isExpanded: true,
              isDense: true,
              dropdownColor: t.background,
              style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(9)),
              items: [
                for (final cat in TagCategories.all)
                  DropdownMenuItem(value: cat, child: Text(cat, style: TextStyle(color: TagCategories.colorFor(cat)))),
                DropdownMenuItem(value: '_skip', child: Text(l.tagImportSkipValue, style: TextStyle(color: t.textDisabled))),
              ],
              onChanged: (v) => setState(() => _customMap[raw] = v == '_skip' ? null : v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged, VisionTokens t) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(value ? Icons.check_box_outlined : Icons.check_box_outline_blank, size: 14, color: value ? t.accent : t.textDisabled),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(9))),
          ],
        ),
      ),
    );
  }

  Widget _previewChip(dynamic tag, VisionTokens t) {
    final color = TagCategories.colorFor(tag.typeName as String);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tag.tag as String, style: TextStyle(color: color, fontSize: t.fontSize(9), fontWeight: FontWeight.bold)),
          if ((tag.count as int) > 0) ...[
            const SizedBox(width: 4),
            Text(NumberFormat.compact().format(tag.count), style: TextStyle(color: color.withValues(alpha: 0.5), fontSize: t.fontSize(7))),
          ],
        ],
      ),
    );
  }

  String _formatLabel(AppLocalizations l) {
    switch (sniff.format) {
      case TagListFormat.csv:
        return sniff.hasHeader ? l.tagImportFormatCsvHeader : l.tagImportFormatCsv;
      case TagListFormat.jsonObjects:
        return l.tagImportFormatJsonObjects;
      case TagListFormat.jsonStrings:
        return l.tagImportFormatJsonStrings;
      case TagListFormat.jsonMap:
        return l.tagImportFormatJsonMap;
      case TagListFormat.plainText:
        return l.tagImportFormatText;
      case TagListFormat.unknown:
        return l.tagImportFormatUnknown;
    }
  }

  static String _profileLabel(AppLocalizations l, TagSiteProfile p) {
    switch (p) {
      case TagSiteProfile.danbooru:
        return l.tagImportProfileDanbooru;
      case TagSiteProfile.e621:
        return l.tagImportProfileE621;
      case TagSiteProfile.e621Merged:
        return l.tagImportProfileE621Merged;
      case TagSiteProfile.custom:
        return l.tagImportProfileCustom;
    }
  }

  Future<void> _import(TagLibraryNotifier notifier, TagSource? existing) async {
    final l = context.l;
    final name = _name.text.trim();
    final id = existing?.id ?? TagSource.makeId(name);
    setState(() => _importing = true);
    try {
      final result = await compute(TagImportWizard._parseJob, (sniff, _options(id)));
      final source = TagSource(
        id: id,
        name: name,
        originFileName: widget.fileName,
        profile: _profile.name,
        tagCount: result.tags.length,
        importedAt: DateTime.now(),
        enabled: existing?.enabled ?? true,
      );
      await notifier.importSource(source, result.tags);
      if (!mounted) return;
      Navigator.pop(context);
      final skipped = result.skippedBelowMin + result.skippedByCategory + result.skippedInvalid + result.skippedDuplicate;
      final msg = skipped == 0
          ? l.tagImportDone(result.imported, name)
          : '${l.tagImportDone(result.imported, name)} · ${l.tagImportSkippedSummary(result.skippedBelowMin, result.skippedByCategory, result.skippedInvalid, result.skippedDuplicate)}';
      showAppSnackBar(context, msg);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, l.tagImportFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}
