import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/recipe.dart';
import '../../parser/quantity.dart';
import '../../providers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// One ingredient line at [factor] servings, optionally converted to [system].
String displayIngredient(IngredientLine i, double factor, UnitSystem? system) {
  if (i.isSection || i.quantity == null) return i.raw;
  var q = i.quantity! * factor;
  var max = i.quantityMax == null ? null : i.quantityMax! * factor;
  var unit = i.unit;
  String? unitText = i.unitRaw;
  if (system != null) {
    final c = convertQuantity(q, max, unit, system);
    if (c != null) {
      q = c.quantity;
      max = c.quantityMax;
      unit = c.unit;
      unitText = unitLabel(c.unit, max ?? q);
    }
  }
  if (factor != 1 && unit != null && unitText == i.unitRaw) unitText = unitLabel(unit, max ?? q);
  return [formatRange(q, max), ?unitText, i.item, if (i.note != null) '(${i.note})'].join(' ');
}

String recipeAsText(Recipe r) => [
      r.title,
      if (r.yieldText != null) r.yieldText!,
      '',
      'Ingredients',
      for (final i in r.ingredients) i.isSection ? '\n${i.item}' : '- ${i.raw}',
      '',
      'Steps',
      for (var k = 0; k < r.steps.length; k++) '${k + 1}. ${r.steps[k].text}',
      if (r.notes.isNotEmpty) ...['', 'Notes', r.notes],
      '',
      'Source: ${attribution(r.source)}${r.source.url != null ? ' ${r.source.url}' : ''}',
    ].join('\n');

class DetailScreen extends ConsumerStatefulWidget {
  const DetailScreen({super.key, required this.recipeId});
  final String recipeId;
  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  double? _servings;
  bool _convert = false;

  Future<void> _editNotes(Recipe r) async {
    final c = TextEditingController(text: r.notes);
    final notes = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notes'),
        content: TextField(controller: c, autofocus: true, minLines: 3, maxLines: 10, decoration: const InputDecoration(hintText: 'Swaps, oven quirks, who loved it…')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (notes != null) await ref.read(recipesProvider.notifier).save(r.copy()..notes = notes.trim());
  }

  Future<void> _editTags(Recipe r) async {
    final c = TextEditingController(text: r.tags.join(', '));
    final tags = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tags'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'dinner, vegetarian, quick')),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save'))],
      ),
    );
    if (tags != null) {
      await ref.read(recipesProvider.notifier).save(r.copy()..tags = tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toSet().toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(recipeProvider(widget.recipeId));
    if (r == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Recipe not found')));
    final text = Theme.of(context).textTheme;
    final base = r.servings;
    final servings = _servings ?? base;
    final factor = base == null || servings == null || base == 0 ? 1.0 : servings / base;
    final units = ref.watch(settingsProvider).units;
    final time = minutesLabel(r);
    return Scaffold(
      appBar: AppBar(actions: [
        IconButton(
          icon: Icon(r.wantToCook ? Icons.bookmark : Icons.bookmark_border),
          tooltip: 'Want to cook',
          onPressed: () => ref.read(recipesProvider.notifier).save(r.copy()..wantToCook = !r.wantToCook),
        ),
        IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit', onPressed: () => context.push('/recipe/${r.id}/review')),
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'share') await SharePlus.instance.share(ShareParams(text: recipeAsText(r), subject: r.title));
            if (v == 'delete') {
              await ref.read(recipesProvider.notifier).delete(r);
              if (context.mounted) context.pop();
            }
          },
          itemBuilder: (_) => const [PopupMenuItem(value: 'share', child: Text('Share as text')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
        ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Row(children: [
          RecipeThumb(r, size: 72),
          const SizedBox(width: 12),
          Expanded(child: Text(r.title.isEmpty ? 'Untitled recipe' : r.title, style: text.headlineSmall)),
        ]),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(sourceIcon(r.source)),
            title: Text(attribution(r.source)),
            subtitle: Text(r.source.url != null ? 'Open original' : (r.source.kind == 'scan' ? '${r.source.pageCount} page${r.source.pageCount == 1 ? '' : 's'} scanned' : 'Added by you')),
            trailing: r.source.url != null ? const Icon(Icons.open_in_new) : null,
            onTap: r.source.url == null ? null : () => launchUrl(Uri.parse(r.source.url!), mode: LaunchMode.externalApplication),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (time != null) Chip(avatar: const Icon(Icons.schedule, size: 16), label: Text(time)),
          if (servings != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton.outlined(icon: const Icon(Icons.remove), tooltip: 'Fewer servings', onPressed: servings <= 1 ? null : () => setState(() => _servings = servings - 1)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('${formatQuantity(servings)} servings')),
              IconButton.outlined(icon: const Icon(Icons.add), tooltip: 'More servings', onPressed: () => setState(() => _servings = servings + 1)),
            ]),
          FilterChip(
            label: Text(units == UnitSystem.metric ? 'Show metric' : 'Show US'),
            selected: _convert,
            onSelected: (v) => setState(() => _convert = v),
          ),
        ]),
        if (r.lowConfidenceCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${r.lowConfidenceCount} highlighted line${r.lowConfidenceCount == 1 ? '' : 's'} may be misread.', style: text.bodySmall),
          ),
        const SizedBox(height: 12),
        Text('Ingredients', style: text.titleMedium),
        for (final i in r.ingredients)
          Container(
            color: confidenceColor(i.confidence),
            padding: EdgeInsets.only(top: i.isSection ? 12 : 4, bottom: 4),
            child: Text(
              i.isSection ? i.item : '•  ${displayIngredient(i, factor, _convert ? units : null)}',
              style: i.isSection ? text.labelLarge : text.bodyLarge,
            ),
          ),
        const SizedBox(height: 16),
        Text('Steps', style: text.titleMedium),
        for (var k = 0; k < r.steps.length; k++)
          Container(
            color: confidenceColor(r.steps[k].confidence),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 12, child: Text('${k + 1}', style: const TextStyle(fontSize: 12))),
              const SizedBox(width: 10),
              Expanded(child: Text(r.steps[k].text, style: text.bodyLarge)),
            ]),
          ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Notes'),
          subtitle: Text(r.notes.isEmpty ? 'Add your notes' : r.notes),
          trailing: const Icon(Icons.edit_note),
          onTap: () => _editNotes(r),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tags'),
          subtitle: Text(r.tags.isEmpty ? 'Add tags' : r.tags.join(', ')),
          trailing: const Icon(Icons.sell_outlined),
          onTap: () => _editTags(r),
        ),
      ]),
    );
  }
}
