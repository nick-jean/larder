import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/recipe_store.dart';
import 'data/settings.dart';
import 'providers.dart';
import 'sync/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await RecipeStore.open();
  final settings = await Settings.load(store);
  final auth = AuthService();
  await auth.init();
  runApp(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        initialSettingsProvider.overrideWithValue(settings),
        authProvider.overrideWithValue(auth),
      ],
      child: const LarderApp(),
    ),
  );
}
