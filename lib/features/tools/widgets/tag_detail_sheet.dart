import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/tag_category.dart';
import '../../../core/services/tag_service.dart';
import '../../../core/services/wiki_service.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/utils/responsive.dart';

/// Detail sheet for a single tag — shows the Danbooru wiki description,
/// other_names chips, and tappable [[wiki_link]] spans that re-open the
/// sheet for the linked tag (so users can navigate the tag graph).
///
/// Wiki content is © Danbooru contributors, CC-BY-SA-4.0.
/// See Tags/LICENSE-WIKI.txt.
class TagDetailSheet extends StatefulWidget {
  final DanbooruTag tag;

  const TagDetailSheet({super.key, required this.tag});

  /// Show as a modal bottom sheet (mobile) or right-side panel (desktop).
  static Future<void> show(BuildContext context, DanbooruTag tag) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TagDetailSheet(tag: tag),
    );
  }

  @override
  State<TagDetailSheet> createState() => _TagDetailSheetState();
}

class _TagDetailSheetState extends State<TagDetailSheet> {
  late Future<WikiEntry?> _entryFuture;

  @override
  void initState() {
    super.initState();
    _entryFuture = _load();
  }

  Future<WikiEntry?> _load() async {
    final wiki = context.read<WikiService>();
    await wiki.ensureLoaded();
    return wiki.lookup(widget.tag.tag);
  }

  Color _categoryColor(String? category) => TagCategories.colorFor(category ?? '');

  Future<void> _openLinkedTag(String tagName) async {
    final tagService = context.read<TagService>();
    final wiki = context.read<WikiService>();
    final navigator = Navigator.of(context);
    // Capture before any await — navigator.context survives this sheet's pop.
    final navigatorContext = navigator.context;

    final libraryHit = tagService.tags
        .where((t) => t.tag.toLowerCase() == tagName.toLowerCase())
        .firstOrNull;

    // Make sure the wiki asset is loaded before we decide whether we have an
    // entry. ensureLoaded() is a no-op once loaded.
    await wiki.ensureLoaded();
    final wikiHit = wiki.lookup(tagName);

    // If we have neither a library entry nor a wiki entry, the in-app sheet
    // would render an empty state — better to open the source page directly.
    if (libraryHit == null && wikiHit == null) {
      final slug = tagName.replaceAll(' ', '_');
      await launchUrl(
        Uri.parse('https://danbooru.donmai.us/wiki_pages/$slug'),
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    final target = libraryHit ?? DanbooruTag(tag: tagName, count: 0);
    navigator.pop();
    // ignore: use_build_context_synchronously
    Future.microtask(() => TagDetailSheet.show(navigatorContext, target));
  }

  Future<void> _openOnDanbooru() async {
    final slug = widget.tag.tag.replaceAll(' ', '_');
    final uri = Uri.parse('https://danbooru.donmai.us/wiki_pages/$slug');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final tag = widget.tag;
    final color = _categoryColor(tag.typeName);
    final mobile = isMobile(context);

    return DraggableScrollableSheet(
      // Open higher on mobile — there's less vertical room to spare.
      initialChildSize: mobile ? 0.85 : 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: t.surfaceHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              _grabber(t),
              _header(t, tag, color, mobile),
              Divider(height: 1, color: t.textMinimal),
              Expanded(
                child: FutureBuilder<WikiEntry?>(
                  future: _entryFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          ),
                        ),
                      );
                    }
                    final entry = snapshot.data;
                    return SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (entry?.otherNames.isNotEmpty ?? false) ...[
                            _otherNamesChips(entry!.otherNames, t, color, mobile),
                            const SizedBox(height: 16),
                          ],
                          if (entry == null || entry.description.isEmpty)
                            _emptyState(t)
                          else
                            _markdown(entry.description, t, color, mobile),
                          const SizedBox(height: 24),
                          _footer(t),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _grabber(VisionTokens t) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(top: 8, bottom: 4),
        decoration: BoxDecoration(
          color: t.textDisabled,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _header(VisionTokens t, DanbooruTag tag, Color color, bool mobile) {
    // On mobile, slightly smaller title font + wrap up to 2 lines for long
    // copyright/character tags; on desktop keep the larger one-line look.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tag.tag,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: TextStyle(
                    color: color,
                    fontSize: t.fontSize(16),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        tag.typeName.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontSize: t.fontSize(8),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    if (tag.count > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        NumberFormat.compact().format(tag.count),
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: t.fontSize(10),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.open_in_new, size: mobile ? 22 : 18, color: t.textDisabled),
            tooltip: 'View on Danbooru',
            onPressed: _openOnDanbooru,
          ),
          IconButton(
            icon: Icon(Icons.close, size: mobile ? 22 : 18, color: t.textDisabled),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _otherNamesChips(List<String> names, VisionTokens t, Color color, bool mobile) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: names.map((n) {
        return ConstrainedBox(
          // Cap chip width so a freakishly long alias can't blow out the row.
          constraints: const BoxConstraints(maxWidth: 240),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: mobile ? 6 : 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              n,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: t.fontSize(10),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _emptyState(VisionTokens t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.description_outlined, size: 32, color: t.textDisabled),
            const SizedBox(height: 8),
            Text(
              'No wiki description for this tag.',
              style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(11)),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _openOnDanbooru,
              child: Text(
                'Check on Danbooru',
                style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _markdown(String body, VisionTokens t, Color color, bool mobile) {
    return MarkdownBody(
      data: body,
      // Selectable text on mobile blocks single-tap on inline spans — long-press
      // to select wins the gesture race against tap, so links become hard to
      // hit. Desktop keeps selection.
      selectable: !mobile,
      onTapLink: (text, href, title) {
        if (href == null) return;
        launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
      },
      extensionSet: md.ExtensionSet(
        md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        [_WikiLinkSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
      ),
      builders: {
        'wikilink': _WikiLinkBuilder(color: color, onTap: _openLinkedTag, mobile: mobile),
      },
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(color: t.textPrimary, fontSize: t.fontSize(11), height: 1.5),
        h1: TextStyle(color: t.textPrimary, fontSize: t.headerSize(15), fontWeight: FontWeight.bold),
        h2: TextStyle(color: t.textPrimary, fontSize: t.headerSize(14), fontWeight: FontWeight.bold),
        h3: TextStyle(color: t.textPrimary, fontSize: t.headerSize(13), fontWeight: FontWeight.bold),
        h4: TextStyle(color: t.textPrimary, fontSize: t.headerSize(12), fontWeight: FontWeight.bold),
        h5: TextStyle(color: t.textSecondary, fontSize: t.headerSize(11), fontWeight: FontWeight.bold),
        h6: TextStyle(color: t.textSecondary, fontSize: t.headerSize(10), fontWeight: FontWeight.bold),
        em: TextStyle(color: t.textSecondary, fontStyle: FontStyle.italic),
        strong: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold),
        code: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: t.fontSize(10),
          backgroundColor: color.withValues(alpha: 0.08),
        ),
        codeblockDecoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(4),
        ),
        blockquote: TextStyle(color: t.textSecondary, fontStyle: FontStyle.italic),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: color.withValues(alpha: 0.4), width: 3)),
        ),
        listBullet: TextStyle(color: color.withValues(alpha: 0.6), fontSize: t.fontSize(11)),
        a: TextStyle(color: color, decoration: TextDecoration.underline),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.textMinimal, width: 1)),
        ),
      ),
    );
  }

  Widget _footer(VisionTokens t) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Tag descriptions © Danbooru contributors, CC-BY-SA-4.0',
        style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8)),
      ),
    );
  }
}

// --- Custom inline syntax for [[target|label]] ---------------------------

class _WikiLinkSyntax extends md.InlineSyntax {
  // Match [[target|label]] where target may contain spaces but neither | nor ]
  _WikiLinkSyntax() : super(r'\[\[([^\[\]|]+?)\|([^\[\]]*?)\]\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final target = match.group(1) ?? '';
    final label = (match.group(2) ?? '').isEmpty ? target : match.group(2)!;
    final el = md.Element.text('wikilink', label);
    el.attributes['target'] = target;
    parser.addNode(el);
    return true;
  }
}

class _WikiLinkBuilder extends MarkdownElementBuilder {
  final Color color;
  final void Function(String) onTap;
  final bool mobile;

  _WikiLinkBuilder({required this.color, required this.onTap, required this.mobile});

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final target = element.attributes['target'] ?? '';
    final label = element.textContent;
    final child = Text(
      label,
      style: (preferredStyle ?? const TextStyle()).copyWith(
        color: color,
        decoration: TextDecoration.underline,
        decorationColor: color.withValues(alpha: 0.5),
      ),
    );
    // On mobile, pad the hit area vertically so single-line links get a
    // realistic touch target without disrupting line wrapping. Padding here
    // expands the GestureDetector, not the visible underline.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(target),
      child: mobile
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: child,
            )
          : child,
    );
  }
}
