import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../import_flow.dart';
import '../../models/import_result.dart';
import '../../models/recipe.dart';
import '../../parser/links.dart';
import '../../parser/text.dart';
import '../../providers.dart';
import '../../scan/ocr_service.dart';

class AddLinkScreen extends ConsumerStatefulWidget {
  const AddLinkScreen({super.key, this.initialUrl});
  final String? initialUrl;
  @override
  ConsumerState<AddLinkScreen> createState() => _AddLinkScreenState();
}

class _AddLinkScreenState extends ConsumerState<AddLinkScreen> {
  late final _url = TextEditingController(text: widget.initialUrl ?? '');
  final _caption = TextEditingController();
  bool _busy = false;
  String? _error;
  ClassifiedLink? _link;
  ImportResult? _result;
  RecipeDraft? _base; // from the server and pasted captions
  RecipeDraft? _draft; // _base plus everything read from screenshots
  final List<String> _screenshots = [];
  final List<InputLine> _ocrLines = [];
  bool _saved = false;

  /// All screenshots are structured together so a recipe split across several isn't cut off.
  void _recompute() => _draft = _ocrLines.isEmpty ? _base : mergeDrafts(_base, structureLines(_ocrLines, 'ocr', newId: newId));

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) WidgetsBinding.instance.addPostFrameCallback((_) => _import());
  }

  @override
  void dispose() {
    _url.dispose();
    _caption.dispose();
    if (!_saved) discardImages(_screenshots);
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final url = data?.text == null ? null : firstUrl(data!.text!);
    if (url != null) {
      _url.text = url;
      _import();
    } else {
      setState(() => _error = 'No link on the clipboard. Copy the link from the app\'s Share menu first.');
    }
  }

  Future<void> _import() async {
    final link = classifyLink(_url.text);
    if (link == null) {
      setState(() => _error = 'That doesn\'t look like a link.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _link = link;
      _result = null;
      _base = null;
      discardImages(_screenshots);
      _screenshots.clear();
      _ocrLines.clear();
      _recompute();
    });
    final api = ref.read(apiProvider);
    try {
      final result = await api.importLink(link.canonicalUrl);
      setState(() {
        _result = result;
        _base = result.draft;
        _recompute();
      });
    } catch (e) {
      // Offline, not signed in, or no server: keep the link and creator, and ask for the caption.
      setState(() => _result = ImportResult(
            needsUserText: true,
            message: api.configured
                ? 'Couldn\'t reach Larder ($e). Paste the caption or add a screenshot; we\'ll keep the link.'
                : 'Paste the caption or add a screenshot. We\'ll keep the link and creator.',
          ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _useCaption() {
    final text = _caption.text.trim();
    if (text.isEmpty) return;
    final d = structureText(text, 'pasted_text', newId: newId);
    setState(() {
      _base = mergeDrafts(_base, d);
      _recompute();
    });
    if (!hasRecipe(d)) setState(() => _error = 'Couldn\'t find ingredients or steps in that text. You can still save and edit it.');
  }

  Future<void> _addScreenshot() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _busy = true);
    final ocr = OcrService();
    try {
      final path = await keepImage(picked.path);
      _screenshots.add(path);
      final lines = await ocr.recognize(path, _screenshots.length - 1);
      setState(() {
        _ocrLines.addAll(lines);
        _recompute();
      });
    } catch (e) {
      setState(() => _error = 'Couldn\'t read that image: $e');
    } finally {
      await ocr.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    final link = _link!;
    final receipt = _result?.receipt;
    final draft = _draft ?? RecipeDraft(title: receipt?.captionSnippet ?? '');
    _saved = true; // set first: saving navigates away, which disposes this screen
    try {
      await saveDraftForReview(
        context,
        ref,
        draft,
        RecipeSource(
          kind: link.platform,
          url: receipt?.canonicalUrl ?? link.canonicalUrl,
          creatorHandle: receipt?.creatorHandle ?? link.creatorHandle,
          creatorName: receipt?.creatorName,
          retrievedAt: DateTime.now().toUtc().toIso8601String(),
        ),
        thumbnailUrl: receipt?.thumbnailUrl,
        imageKeys: _screenshots,
      );
    } catch (_) {
      _saved = false;
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final draft = _draft;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Paste a link')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Link',
              hintText: 'https://www.tiktok.com/@creator/video/…',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(icon: const Icon(Icons.content_paste), tooltip: 'Paste', onPressed: _busy ? null : _paste),
            ),
            onSubmitted: (_) => _import(),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _import, child: const Text('Import')),
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (result != null) ...[
            const SizedBox(height: 16),
            if (result.receipt != null || _link != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(result.receipt?.creatorName ?? result.receipt?.creatorHandle ?? _link?.creatorHandle ?? _link!.platform),
                  subtitle: Text(result.receipt?.captionSnippet ?? _link!.canonicalUrl, maxLines: 3, overflow: TextOverflow.ellipsis),
                ),
              ),
            for (final l in result.layers.where((l) => l.status != 'skipped'))
              ListTile(
                dense: true,
                leading: Icon(switch (l.status) { 'ok' => Icons.check_circle, 'error' => Icons.error_outline, _ => Icons.remove_circle_outline },
                    color: l.status == 'ok' ? Colors.green : null),
                title: Text(l.label),
                subtitle: l.detail == null ? null : Text(l.detail!),
              ),
            if (result.message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(result.message!, style: text.bodyLarge)),
            if (hasRecipe(draft))
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(
                  title: Text(draft!.title.isEmpty ? 'Recipe found' : draft.title),
                  subtitle: Text('${draft.ingredients.where((i) => !i.isSection).length} ingredients · ${draft.steps.length} steps'
                      '${draft.lowConfidenceCount > 0 ? ' · ${draft.lowConfidenceCount} to check' : ''}'),
                ),
              ),
            if (!hasRecipe(draft) || draft!.steps.isEmpty || !draft.ingredients.any((i) => !i.isSection)) ...[
              const SizedBox(height: 8),
              Text(hasRecipe(draft) ? 'Missing part of the recipe? Add the caption or a screenshot.' : 'Add the recipe text', style: text.titleSmall),
              const SizedBox(height: 8),
              TextField(controller: _caption, minLines: 3, maxLines: 8, decoration: const InputDecoration(hintText: 'Paste the caption here', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _useCaption, icon: const Icon(Icons.text_snippet_outlined), label: const Text('Use caption'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _addScreenshot, icon: const Icon(Icons.screenshot), label: const Text('Add screenshot'))),
              ]),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy || _link == null ? null : _review, child: Text(hasRecipe(draft) ? 'Review recipe' : 'Save link and fill in later')),
          ],
        ],
      ),
    );
  }
}
