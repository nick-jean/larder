import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/recipe_store.dart';
import '../../models/recipe.dart';
import '../../parser/links.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';

const _filters = ['All', 'Needs review', 'Want to cook', 'TikTok', 'Instagram', 'Facebook', 'Web', 'Scanned'];

bool matchesFilter(Recipe r, String filter) => switch (filter) {
      'Needs review' => r.needsReview,
      'Want to cook' => r.wantToCook,
      'TikTok' => r.source.kind == 'tiktok',
      'Instagram' => r.source.kind == 'instagram',
      'Facebook' => r.source.kind == 'facebook',
      'Web' => r.source.kind == 'web',
      'Scanned' => r.source.kind == 'scan',
      _ => true,
    };

bool matchesQuery(Recipe r, String query) {
  final text = RecipeStore.searchText(r);
  return query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(text.contains);
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  String _query = '';
  String _filter = 'All';
  ClassifiedLink? _clipboardLink;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkClipboard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkClipboard();
  }

  /// Offers to import a link the user just copied. Only reads the clipboard while Larder is open, and
  /// only if the banner is on in Settings.
  Future<void> _checkClipboard() async {
    final settings = ref.read(settingsProvider);
    if (!settings.clipboardBanner) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final url = data?.text == null ? null : firstUrl(data!.text!);
    final link = url == null ? null : classifyLink(url);
    if (!mounted) return;
    final known = ref.read(recipesProvider).value?.any((r) => r.source.url == link?.canonicalUrl) ?? false;
    setState(() => _clipboardLink = (link == null || known || link.canonicalUrl == settings.dismissedClipboard) ? null : link);
  }

  void _dismissClipboard() {
    final link = _clipboardLink;
    setState(() => _clipboardLink = null);
    if (link != null) {
      final s = ref.read(settingsProvider);
      ref.read(settingsProvider.notifier).update(s.copyWith(dismissedClipboard: link.canonicalUrl));
    }
  }

  void _showAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _AddOption(Icons.link, 'Paste a link', 'TikTok, Instagram, Facebook or a recipe site', () => context.push('/add/link')),
          _AddOption(Icons.menu_book, 'Scan a cookbook page', 'One or more pages', () => context.push('/scan/cookbook')),
          _AddOption(Icons.edit_note, 'Snap a handwritten card', 'Family recipes and notes', () => context.push('/scan/handwritten')),
          _AddOption(Icons.screenshot, 'Add a screenshot', 'A caption or recipe on screen', () => context.push('/scan/screenshot')),
          _AddOption(Icons.content_paste, 'Paste or type text', 'Captions, emails, notes', () => context.push('/add/text')),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(recipesProvider).value ?? [];
    final review = all.where((r) => r.needsReview).toList();
    final shown = all.where((r) => matchesFilter(r, _filter) && matchesQuery(r, _query)).toList();
    final link = _clipboardLink;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Larder'),
        actions: [IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: () => context.push('/settings'))],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _showAddSheet, icon: const Icon(Icons.add), label: const Text('Add recipe')),
      body: RefreshIndicator(
        onRefresh: () async {
          final msg = await ref.read(recipesProvider.notifier).sync();
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            if (link != null) ...[
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.content_paste_go),
                  title: Text('Import the ${_platformName(link.platform)} link you copied?'),
                  subtitle: Text(link.creatorHandle ?? link.canonicalUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.close), tooltip: 'Dismiss', onPressed: _dismissClipboard),
                    FilledButton(
                      onPressed: () {
                        setState(() => _clipboardLink = null);
                        context.push(Uri(path: '/add/link', queryParameters: {'url': link.canonicalUrl}).toString());
                      },
                      child: const Text('Import'),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search recipes, ingredients, creators', border: OutlineInputBorder()),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final f in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(label: Text(f), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
                  ),
              ]),
            ),
            if (review.isNotEmpty && _filter == 'All' && _query.isEmpty) ...[
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text('${review.length} recipe${review.length == 1 ? '' : 's'} to check'),
                  subtitle: const Text('Confirm what Larder wasn\'t sure about'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => review.length == 1 ? context.push('/recipe/${review.first.id}/review') : setState(() => _filter = 'Needs review'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (all.isEmpty)
              const _EmptyState()
            else if (shown.isEmpty)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No recipes match.')))
            else
              for (final r in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RecipeCard(r, onTap: () => context.push(r.needsReview ? '/recipe/${r.id}/review' : '/recipe/${r.id}')),
                ),
          ],
        ),
      ),
    );
  }
}

String _platformName(String p) => switch (p) { 'tiktok' => 'TikTok', 'instagram' => 'Instagram', 'facebook' => 'Facebook', _ => 'recipe' };

class _AddOption extends StatelessWidget {
  const _AddOption(this.icon, this.title, this.subtitle, this.onTap);
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
        child: Column(children: [
          Icon(Icons.soup_kitchen_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text('Your recipes, all in one place', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('Copy a link from TikTok, Instagram, Facebook or a recipe site, or snap a cookbook page or a handwritten card.',
              textAlign: TextAlign.center),
        ]),
      );
}
