import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../import_flow.dart';
import '../../models/recipe.dart';
import '../../parser/links.dart';
import '../../parser/text.dart';
import '../../providers.dart';

class PasteTextScreen extends ConsumerStatefulWidget {
  const PasteTextScreen({super.key});
  @override
  ConsumerState<PasteTextScreen> createState() => _PasteTextScreenState();
}

class _PasteTextScreenState extends ConsumerState<PasteTextScreen> {
  final _text = TextEditingController();
  bool _ai = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    RecipeDraft draft = structureText(text, 'pasted_text', newId: newId);
    if (_ai) {
      try {
        draft = await ref.read(apiProvider).importText(text: text, ai: true) ?? draft;
      } catch (e) {
        setState(() => _error = 'AI tidy-up unavailable ($e). Using the on-device parser.');
      }
    }
    final url = firstUrl(text);
    final link = url == null ? null : classifyLink(url);
    if (!mounted) return;
    await saveDraftForReview(
      context,
      ref,
      draft,
      RecipeSource(kind: link?.platform ?? 'manual', url: link?.canonicalUrl, creatorHandle: link?.creatorHandle),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Paste or type a recipe')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _text,
          minLines: 10,
          maxLines: 24,
          decoration: const InputDecoration(hintText: 'Title\nIngredients…\nSteps…', border: OutlineInputBorder()),
        ),
        if (api.configured)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _ai,
            onChanged: (v) => setState(() => _ai = v),
            title: const Text('Tidy up with AI'),
            subtitle: const Text('Sends this text to Larder\'s server. Uses one import from your monthly allowance. Quantities are never invented.'),
          ),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _continue, child: const Text('Review recipe')),
      ]),
    );
  }
}
