import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/models/tag_category.dart';
import '../../../core/models/tag_source.dart';
import '../../../core/services/tag_source_service.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../providers/tag_library_notifier.dart';
import 'tag_import_wizard.dart';

/// Manages imported tag lists: enable/disable, priority order (drag), rename,
/// update from a newer file, export, delete — plus the entry point to import
/// a new list. Opened from the Tag Library header.
class TagSourcesSheet extends StatelessWidget {
  const TagSourcesSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tRead.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const TagSourcesSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<TagLibraryNotifier>();
    final t = context.t;
    final l = context.l;
    final mobile = isMobile(context);
    final service = notifier.sources;
    final sources = service?.sources ?? const <TagSource>[];
    final bundledCount = notifier.tagService.bundledTags.length;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, mobile ? 16 : 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.tagSourcesTitle,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: t.titleSize(11),
                        letterSpacing: 3,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => TagImportWizard.start(context),
                    icon: Icon(Icons.upload_file, size: 14, color: t.accent),
                    label: Text(
                      l.tagSourcesImport,
                      style: TextStyle(color: t.accent, fontSize: t.buttonSize(9), letterSpacing: 1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l.tagSourcesDesc,
                style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(mobile ? 11 : 9)),
              ),
              const SizedBox(height: 12),
              _bundledRow(t, l, bundledCount),
              Divider(height: 16, color: t.textMinimal),
              if (sources.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      l.tagSourcesEmpty,
                      style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(10), letterSpacing: 1),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    itemCount: sources.length,
                    onReorder: notifier.reorderSources,
                    proxyDecorator: (child, index, animation) => Material(
                      color: t.surfaceMid,
                      borderRadius: BorderRadius.circular(4),
                      elevation: 4,
                      child: child,
                    ),
                    itemBuilder: (context, index) => _SourceRow(
                      key: ValueKey(sources[index].id),
                      index: index,
                      source: sources[index],
                      service: service!,
                      notifier: notifier,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bundledRow(VisionTokens t, dynamic l, int count) {
    return Row(
      children: [
        const SizedBox(width: 20),
        Icon(Icons.lock_outline, size: 14, color: t.textDisabled),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.tagSourcesBundled,
                style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(11), letterSpacing: 1),
              ),
              Text(
                l.tagSourcesTagCount(count),
                style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8), letterSpacing: 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  final int index;
  final TagSource source;
  final TagSourceService service;
  final TagLibraryNotifier notifier;

  const _SourceRow({
    super.key,
    required this.index,
    required this.source,
    required this.service,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final enabled = source.enabled;
    final fg = enabled ? t.textSecondary : t.textDisabled;
    final date = DateFormat.yMMMd().format(source.importedAt);
    final profile = _profileLabel(l, source.profile);
    final categories = _categorySummary(service.tagsOf(source.id));

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.textMinimal, width: 0.5)),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Icon(Icons.drag_handle, size: 16, color: t.textDisabled),
          ),
          const SizedBox(width: 4),
          Transform.scale(
            scale: 0.75,
            child: Switch(
              value: enabled,
              activeThumbColor: t.accent,
              onChanged: (v) => notifier.setSourceEnabled(source.id, v),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        source.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontSize: t.fontSize(11),
                          letterSpacing: 1,
                          fontWeight: enabled ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        border: Border.all(color: t.borderSubtle),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        source.badge,
                        style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(7), letterSpacing: 1),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${l.tagSourcesTagCount(source.tagCount)} · $profile · $date',
                  style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8), letterSpacing: 0.5),
                ),
                if (categories.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final e in categories)
                          Text(
                            '${e.key} ${NumberFormat.compact().format(e.value)}',
                            style: TextStyle(
                              color: TagCategories.colorFor(e.key).withValues(alpha: enabled ? 0.7 : 0.35),
                              fontSize: t.fontSize(7),
                              letterSpacing: 0.5,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 16, color: t.textDisabled),
            color: t.surfaceMid,
            onSelected: (action) => _onAction(context, action),
            itemBuilder: (_) => [
              _item('rename', Icons.drive_file_rename_outline, l.tagSourcesRename, t),
              _item('update', Icons.sync, l.tagSourcesUpdate, t),
              _item('export', Icons.download_outlined, l.tagSourcesExport, t),
              _item('delete', Icons.delete_outline, l.tagSourcesDelete, t, color: t.accentDanger),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _item(String value, IconData icon, String label, VisionTokens t, {Color? color}) {
    return PopupMenuItem<String>(
      value: value,
      height: 32,
      child: Row(
        children: [
          Icon(icon, size: 14, color: color ?? t.textSecondary),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color ?? t.textSecondary, fontSize: t.fontSize(10))),
        ],
      ),
    );
  }

  static String _profileLabel(dynamic l, String profile) {
    switch (TagSiteProfile.fromName(profile)) {
      case TagSiteProfile.danbooru:
        return 'Danbooru';
      case TagSiteProfile.e621:
        return 'e621';
      case TagSiteProfile.e621Merged:
        return 'Danbooru + e621';
      case TagSiteProfile.custom:
        return l.tagImportProfileCustom;
    }
  }

  static List<MapEntry<String, int>> _categorySummary(Iterable tags) {
    final counts = <String, int>{};
    for (final t in tags) {
      counts[t.typeName as String] = (counts[t.typeName as String] ?? 0) + 1;
    }
    final ordered = <MapEntry<String, int>>[];
    for (final c in TagCategories.all) {
      if (counts.containsKey(c)) ordered.add(MapEntry(c, counts[c]!));
    }
    return ordered;
  }

  Future<void> _onAction(BuildContext context, String action) async {
    switch (action) {
      case 'rename':
        await _rename(context);
      case 'update':
        await TagImportWizard.start(context, replace: source);
      case 'export':
        await _export(context);
      case 'delete':
        await _delete(context);
    }
  }

  Future<void> _rename(BuildContext context) async {
    final t = context.tRead;
    final l = context.l;
    final controller = TextEditingController(text: source.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surfaceHigh,
        title: Text(l.tagSourcesRenameTitle.toUpperCase(),
            style: TextStyle(fontSize: t.titleSize(10), letterSpacing: 2, color: t.textSecondary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(12)),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.commonCancel, style: TextStyle(color: t.textDisabled, fontSize: t.buttonSize(9))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l.commonRename, style: TextStyle(color: t.accent, fontSize: t.buttonSize(9))),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty && name.trim() != source.name) {
      await notifier.renameSource(source.id, name.trim());
    }
  }

  Future<void> _export(BuildContext context) async {
    final l = context.l;
    final bundle = service.bundle(source.id);
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(bundle.toJson()));
    final safeName = source.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: l.tagSourcesExport,
        fileName: '$safeName.json',
        bytes: bytes,
      );
      if (savePath == null) return;
      if (kIsWeb || !Platform.isAndroid) {
        await File(savePath).writeAsBytes(bytes);
      }
      if (context.mounted) showAppSnackBar(context, l.tagSourcesExported(source.name));
    } catch (e) {
      if (context.mounted) showErrorSnackBar(context, e.toString());
    }
  }

  Future<void> _delete(BuildContext context) async {
    final l = context.l;
    final confirmed = await showConfirmDialog(
      context,
      title: l.tagSourcesDelete,
      message: l.tagSourcesDeleteConfirm(source.name, source.tagCount),
      confirmLabel: l.commonDelete,
      confirmColor: context.tRead.accentDanger,
    );
    if (confirmed == true) await notifier.removeSource(source.id);
  }
}
