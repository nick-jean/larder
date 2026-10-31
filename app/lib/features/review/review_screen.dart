import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/recipe.dart';
import '../../parser/confidence.dart';
import '../../parser/ingredient.dart';
import '../../providers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Review & edit: highlights what the parser wasn't sure about, lets the user fix, split, merge,
/// move and reorder lines (with undo), and gates saving until checked or explicitly accepted.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.recipeId});
  final String recipeId;
  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

IngredientLine ingredientFromText(String text, String id, String provenance) {
  final p = parseIngredientLine(text);
  return IngredientLine(
    id: id,
    raw: p.raw,
    isSection: p.isSection,
    quantity: p.quantity,
    quantityMax: p.quantityMax,
    unit: p.unit,
    unitRaw: p.unitRaw,
    item: p.item,
    note: p.note,
    confidence: Confidence.high,
    provenance: provenance,
  );
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  Recipe? _r;
  final List<Map<String, dynamic>> _undo = [];
  late final _title = TextEditingController();
  Box? _focusBox;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _change(void Function(Recipe r) fn) {
    _undo.add(_r!.toJson());
    if (_undo.length > 50) _undo.removeAt(0);
    setState(() => fn(_r!));
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() {
      _r = Recipe.fromJson(_undo.removeLast());
      _title.text = _r!.title;
    });
  }

  Future<String?> _editText(String title, String initial, {String? hint}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, minLines: 1, maxLines: 6, decoration: InputDecoration(helperText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Done')),
        ],
      ),
    );
  }

  Future<void> _editIngredient(int i) async {
    final line = _r!.ingredients[i];
    final text = await _editText('Edit ingredient', line.raw, hint: 'Put each ingredient on its own line to split it.');
    if (text == null) return;
    final parts = text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    _change((r) => r.ingredients.replaceRange(i, i + 1, [
          for (var k = 0; k < parts.length; k++)
            ingredientFromText(parts[k], k == 0 ? line.id : newId(), line.provenance)..box = line.box,
        ]));
  }

  Future<void> _editStep(int i) async {
    final step = _r!.steps[i];
    final text = await _editText('Edit step', step.text, hint: 'Put a blank line between steps to split it.');
    if (text == null) return;
    final parts = text.split(RegExp(r'\n\s*\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    _change((r) => r.steps.replaceRange(i, i + 1, [
          for (var k = 0; k < parts.length; k++)
            StepLine(id: k == 0 ? step.id : newId(), text: parts[k], provenance: step.provenance, box: step.box),
        ]));
  }

  void _ingredientAction(int i, String action) {
    final line = _r!.ingredients[i];
    switch (action) {
      case 'ok':
        _change((r) => r.ingredients[i].confidence = Confidence.high);
      case 'section':
        _change((r) => r.ingredients[i] = IngredientLine(id: line.id, raw: line.raw, isSection: !line.isSection, item: line.isSection ? line.item : line.raw.replaceFirst(RegExp(r':\s*$'), ''), provenance: line.provenance)
          ..quantity = line.isSection ? parseIngredientLine(line.raw).quantity : null);
      case 'merge':
        if (i + 1 >= _r!.ingredients.length) return;
        _change((r) {
          final next = r.ingredients.removeAt(i + 1);
          r.ingredients[i] = ingredientFromText('${line.raw} ${next.raw}', line.id, line.provenance)..box = line.box;
        });
      case 'toStep':
        _change((r) {
          r.ingredients.removeAt(i);
          r.steps.insert(0, StepLine(id: line.id, text: line.raw, provenance: line.provenance, box: line.box));
        });
      case 'delete':
        _change((r) => r.ingredients.removeAt(i));
    }
  }

  void _stepAction(int i, String action) {
    final step = _r!.steps[i];
    switch (action) {
      case 'ok':
        _change((r) => r.steps[i]
          ..confidence = Confidence.high
          ..seam = false);
      case 'merge':
        if (i + 1 >= _r!.steps.length) return;
        _change((r) {
          final next = r.steps.removeAt(i + 1);
          r.steps[i].text = '${step.text} ${next.text}';
          r.steps[i].confidence = minConfidence([step.confidence, next.confidence]);
        });
      case 'toIngredient':
        _change((r) {
          r.steps.removeAt(i);
          r.ingredients.add(ingredientFromText(step.text, step.id, step.provenance)..box = step.box);
        });
      case 'delete':
        _change((r) => r.steps.removeAt(i));
    }
  }

  Future<void> _save() async {
    final r = _r!..title = _title.text.trim();
    final unchecked = r.lowConfidenceCount;
    if (unchecked > 0) {
      final accept = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$unchecked thing${unchecked == 1 ? '' : 's'} still unchecked'),
          content: const Text('Highlighted lines may be misread. Save anyway? They stay highlighted so you can fix them later.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep checking')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Accept as is')),
          ],
        ),
      );
      if (accept != true) return;
    }
    r.status = 'saved';
    final saved = await ref.read(recipesProvider.notifier).save(r);
    if (mounted) context.pushReplacement('/recipe/${saved.id}');
  }

  Widget _lineMenu(List<(String, String)> items, void Function(String) onSelected) => PopupMenuButton<String>(
        onSelected: onSelected,
        itemBuilder: (_) => [for (final (v, label) in items) PopupMenuItem(value: v, child: Text(label))],
      );

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(recipeProvider(widget.recipeId));
    if (_r == null && stored != null) {
      _r = stored.copy();
      _title.text = _r!.title;
    }
    final r = _r;
    if (r == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Recipe not found')));
    final text = Theme.of(context).textTheme;
    final unchecked = r.lowConfidenceCount;
    return Scaffold(
      appBar: AppBar(
        title: Text(unchecked > 0 ? 'Check $unchecked thing${unchecked == 1 ? '' : 's'}' : 'Review'),
        actions: [
          IconButton(icon: const Icon(Icons.undo), tooltip: 'Undo', onPressed: _undo.isEmpty ? null : _undoLast),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Discard',
            onPressed: () async {
              await ref.read(recipesProvider.notifier).delete(r);
              if (context.mounted) context.pop();
            },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: FilledButton(onPressed: _save, child: const Text('Save recipe')))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SourceBadge(r.source),
        if (r.imageKeys.isNotEmpty) _SourcePhotos(paths: r.imageKeys, focus: _focusBox),
        const SizedBox(height: 8),
        Container(
          color: confidenceColor(r.titleConfidence),
          child: TextField(
            controller: _title,
            style: text.titleLarge,
            decoration: const InputDecoration(labelText: 'Title'),
            onChanged: (_) => r.titleConfidence = Confidence.high,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _NumberField('Servings', r.servings?.round(), r.servingsConfidence, (v) => _change((x) => x
            ..servings = v?.toDouble()
            ..servingsConfidence = Confidence.high)),
          _NumberField('Prep min', r.prepMinutes, r.timesConfidence, (v) => _change((x) => x.prepMinutes = v)),
          _NumberField('Cook min', r.cookMinutes, r.timesConfidence, (v) => _change((x) => x.cookMinutes = v)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text('Ingredients', style: text.titleMedium)),
          TextButton.icon(
            onPressed: () async {
              final t = await _editText('Add ingredient', '');
              if (t != null && t.trim().isNotEmpty) _change((x) => x.ingredients.add(ingredientFromText(t, newId(), 'manual')));
            },
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ]),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) => _change((x) => x.ingredients.insert(to, x.ingredients.removeAt(from))),
          children: [
            for (var i = 0; i < r.ingredients.length; i++)
              Container(
                key: ValueKey(r.ingredients[i].id),
                color: confidenceColor(r.ingredients[i].confidence),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 4),
                  leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator)),
                  title: Text(r.ingredients[i].isSection ? r.ingredients[i].item.toUpperCase() : r.ingredients[i].raw,
                      style: r.ingredients[i].isSection ? text.labelLarge : null),
                  subtitle: r.ingredients[i].alternatives.isEmpty
                      ? null
                      : Wrap(spacing: 4, children: [
                          for (final alt in r.ingredients[i].alternatives)
                            ActionChip(
                              label: Text(alt),
                              onPressed: () => _change((x) => x.ingredients[i] = ingredientFromText(alt, x.ingredients[i].id, x.ingredients[i].provenance)),
                            ),
                        ]),
                  onTap: () {
                    setState(() => _focusBox = r.ingredients[i].box);
                    _editIngredient(i);
                  },
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    ConfidenceDot(r.ingredients[i].confidence),
                    _lineMenu([
                      if (r.ingredients[i].confidence != Confidence.high) ('ok', 'Looks right'),
                      ('section', r.ingredients[i].isSection ? 'Not a section' : 'Make section heading'),
                      ('merge', 'Merge with next'),
                      ('toStep', 'Move to steps'),
                      ('delete', 'Delete'),
                    ], (a) => _ingredientAction(i, a)),
                  ]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text('Steps', style: text.titleMedium)),
          TextButton.icon(
            onPressed: () async {
              final t = await _editText('Add step', '');
              if (t != null && t.trim().isNotEmpty) _change((x) => x.steps.add(StepLine(id: newId(), text: t.trim())));
            },
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ]),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) => _change((x) => x.steps.insert(to, x.steps.removeAt(from))),
          children: [
            for (var i = 0; i < r.steps.length; i++)
              Container(
                key: ValueKey(r.steps[i].id),
                color: confidenceColor(r.steps[i].seam ? minConfidence([r.steps[i].confidence, Confidence.medium]) : r.steps[i].confidence),
                child: ListTile(
                  contentPadding: const EdgeInsets.only(left: 4),
                  leading: ReorderableDragStartListener(index: i, child: CircleAvatar(radius: 14, child: Text('${i + 1}'))),
                  title: Text(r.steps[i].text),
                  subtitle: r.steps[i].seam ? const Text('Continues across pages. Check nothing is missing.') : null,
                  onTap: () {
                    setState(() => _focusBox = r.steps[i].box);
                    _editStep(i);
                  },
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    ConfidenceDot(r.steps[i].seam ? Confidence.medium : r.steps[i].confidence),
                    _lineMenu([
                      if (r.steps[i].confidence != Confidence.high || r.steps[i].seam) ('ok', 'Looks right'),
                      ('merge', 'Merge with next'),
                      ('toIngredient', 'Move to ingredients'),
                      ('delete', 'Delete'),
                    ], (a) => _stepAction(i, a)),
                  ]),
                ),
              ),
          ],
        ),
        if (r.ingredients.isEmpty && r.steps.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('Nothing was found yet. Add ingredients and steps, or save the link and fill it in later.')),
      ]),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField(this.label, this.value, this.confidence, this.onChanged);
  final String label;
  final int? value;
  final Confidence confidence;
  final void Function(int?) onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 100,
        child: Container(
          color: confidenceColor(confidence),
          child: TextFormField(
            key: ValueKey('$label$value'),
            initialValue: value?.toString() ?? '',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label),
            onFieldSubmitted: (v) => onChanged(int.tryParse(v.trim())),
          ),
        ),
      );
}

/// Source photos with the selected line's region outlined, so the user can compare against the original.
class _SourcePhotos extends StatelessWidget {
  const _SourcePhotos({required this.paths, this.focus});
  final List<String> paths;
  final Box? focus;

  @override
  Widget build(BuildContext context) {
    final page = (focus?.page ?? 0).clamp(0, paths.length - 1);
    final file = File(paths[page]);
    if (!file.existsSync()) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('Source photo${paths.length > 1 ? ' (page ${page + 1} of ${paths.length})' : ''}'),
        initiallyExpanded: focus != null,
        children: [
          LayoutBuilder(
            builder: (context, c) => Stack(children: [
              Image.file(file, width: c.maxWidth, fit: BoxFit.fitWidth),
              if (focus != null)
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: FractionalOffset(
                      focus!.w >= 1 ? 0 : focus!.x / (1 - focus!.w),
                      focus!.h >= 1 ? 0 : focus!.y / (1 - focus!.h),
                    ),
                    widthFactor: focus!.w.clamp(0.01, 1),
                    heightFactor: focus!.h.clamp(0.01, 1),
                    child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: Colors.deepOrange, width: 2))),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}
