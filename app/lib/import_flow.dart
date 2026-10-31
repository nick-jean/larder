import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models/recipe.dart';
import 'providers.dart';

/// Saves a parsed draft as a recipe waiting for review and opens the review screen.
Future<void> saveDraftForReview(
  BuildContext context,
  WidgetRef ref,
  RecipeDraft draft,
  RecipeSource source, {
  String? thumbnailUrl,
  List<String>? imageKeys,
}) async {
  final recipe = Recipe.fromDraft(draft, id: newId(), source: source, now: DateTime.now(), thumbnailUrl: thumbnailUrl, imageKeys: imageKeys);
  final saved = await ref.read(recipesProvider.notifier).save(recipe);
  if (context.mounted) context.pushReplacement('/recipe/${saved.id}/review');
}
