import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../parser/quantity.dart';
import '../../providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _status;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn({bool create = false}) async {
    try {
      await ref.read(authProvider).signInWithEmail(_email.text.trim(), _password.text, create: create);
      final moved = await ref.read(storeProvider).reassignOwner(ref.read(settingsProvider).guestId, ref.read(authProvider).uid!);
      final msg = await ref.read(recipesProvider.notifier).sync();
      setState(() => _status = '${moved > 0 ? 'Added $moved recipes to your account. ' : ''}$msg');
    } catch (e) {
      setState(() => _status = 'Sign-in failed: $e');
    }
  }

  Future<void> _export() async {
    final recipes = ref.read(recipesProvider).value ?? [];
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'larder-export.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'recipes': [for (final r in recipes) r.toJson()],
    }));
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Larder recipes'));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final auth = ref.watch(authProvider);
    final count = ref.watch(recipesProvider).value?.length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: auth,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          Text('Account', style: Theme.of(context).textTheme.titleMedium),
          if (!auth.available)
            const ListTile(contentPadding: EdgeInsets.zero, title: Text('Guest mode'), subtitle: Text('Recipes are saved on this device. Accounts aren\'t set up in this build.'))
          else if (auth.signedIn) ...[
            ListTile(contentPadding: EdgeInsets.zero, title: Text(auth.email ?? 'Signed in'), subtitle: const Text('Recipes back up and sync across your devices.')),
            Row(children: [
              OutlinedButton(
                onPressed: () async {
                  final msg = await ref.read(recipesProvider.notifier).sync();
                  setState(() => _status = msg);
                },
                child: const Text('Sync now'),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: auth.signOut, child: const Text('Sign out')),
            ]),
          ] else ...[
            TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton(onPressed: _signIn, child: const Text('Sign in')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => _signIn(create: true), child: const Text('Create account')),
            ]),
          ],
          if (_status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_status!)),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Offer to import copied links'),
            subtitle: const Text('When you open Larder, check the clipboard for a recipe link. Never in the background.'),
            value: settings.clipboardBanner,
            onChanged: (v) => ref.read(settingsProvider.notifier).update(settings.copyWith(clipboardBanner: v)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Units'),
            trailing: SegmentedButton<UnitSystem>(
              segments: const [ButtonSegment(value: UnitSystem.us, label: Text('US')), ButtonSegment(value: UnitSystem.metric, label: Text('Metric'))],
              selected: {settings.units},
              onSelectionChanged: (s) => ref.read(settingsProvider.notifier).update(settings.copyWith(units: s.first)),
            ),
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.ios_share),
            title: const Text('Export all recipes'),
            subtitle: Text('$count recipes as JSON, with sources and notes'),
            onTap: count == 0 ? null : _export,
          ),
        ]),
      ),
    );
  }
}
