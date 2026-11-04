import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/add/add_link_screen.dart';
import 'features/add/paste_text_screen.dart';
import 'features/detail/detail_screen.dart';
import 'features/home/home_screen.dart';
import 'features/review/review_screen.dart';
import 'features/scan/scan_screen.dart';
import 'features/settings/settings_screen.dart';
import 'ui/theme.dart';

final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
    GoRoute(path: '/add/link', builder: (_, s) => AddLinkScreen(initialUrl: s.uri.queryParameters['url'])),
    GoRoute(path: '/add/text', builder: (_, _) => const PasteTextScreen()),
    GoRoute(path: '/scan/:type', builder: (_, s) => ScanScreen(scanType: s.pathParameters['type']!)),
    GoRoute(path: '/recipe/:id', builder: (_, s) => DetailScreen(recipeId: s.pathParameters['id']!)),
    GoRoute(path: '/recipe/:id/review', builder: (_, s) => ReviewScreen(recipeId: s.pathParameters['id']!)),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
  ],
);

class LarderApp extends StatelessWidget {
  const LarderApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Larder',
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      );
}
