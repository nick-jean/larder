import 'dart:io';

import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../parser/confidence.dart';
import 'theme.dart';

IconData sourceIcon(RecipeSource s) => switch (s.kind) {
      'tiktok' => Icons.music_note,
      'instagram' => Icons.camera_alt_outlined,
      'facebook' => Icons.facebook,
      'web' => Icons.language,
      'scan' => s.scanType == 'handwritten' ? Icons.edit_note : (s.scanType == 'screenshot' ? Icons.screenshot : Icons.menu_book),
      _ => Icons.keyboard,
    };

String attribution(RecipeSource s) {
  final who = s.creatorHandle ?? s.creatorName;
  return who == null ? s.label : '$who · ${s.label}';
}

String? minutesLabel(Recipe r) {
  final total = r.totalMinutes ?? ((r.prepMinutes ?? 0) + (r.cookMinutes ?? 0));
  if (total == 0) return null;
  return total >= 60 ? '${total ~/ 60} h${total % 60 == 0 ? '' : ' ${total % 60} min'}' : '$total min';
}

class SourceBadge extends StatelessWidget {
  const SourceBadge(this.source, {super.key});
  final RecipeSource source;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(sourceIcon(source), size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(child: Text(attribution(source), overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
        ],
      );
}

class RecipeThumb extends StatelessWidget {
  const RecipeThumb(this.recipe, {super.key, this.size = 64});
  final Recipe recipe;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget child = Icon(sourceIcon(recipe.source), color: scheme.primary);
    if (recipe.imageKeys.isNotEmpty && File(recipe.imageKeys.first).existsSync()) {
      child = Image.file(File(recipe.imageKeys.first), fit: BoxFit.cover, width: size, height: size);
    } else if (recipe.thumbnailUrl != null) {
      child = Image.network(recipe.thumbnailUrl!, fit: BoxFit.cover, width: size, height: size, errorBuilder: (_, _, _) => child);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(width: size, height: size, color: scheme.primaryContainer, alignment: Alignment.center, child: child),
    );
  }
}

class RecipeCard extends StatelessWidget {
  const RecipeCard(this.recipe, {super.key, required this.onTap});
  final Recipe recipe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = minutesLabel(recipe);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              RecipeThumb(recipe),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(recipe.title.isEmpty ? 'Untitled recipe' : recipe.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    SourceBadge(recipe.source),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, children: [
                      if (recipe.needsReview) const _Pill('Needs review', warn: true),
                      if (time != null) _Pill(time),
                      if (recipe.wantToCook) const _Pill('Want to cook'),
                      for (final t in recipe.tags.take(2)) _Pill(t),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.warn = false});
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: warn ? confidenceColor(Confidence.low) : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class ConfidenceDot extends StatelessWidget {
  const ConfidenceDot(this.confidence, {super.key});
  final Confidence confidence;

  @override
  Widget build(BuildContext context) => confidence == Confidence.high
      ? const SizedBox.shrink()
      : Tooltip(
          message: confidence == Confidence.low ? 'Larder isn\'t sure about this. Please check.' : 'Probably right. Worth a glance.',
          child: Icon(Icons.help_outline, size: 18, color: confidence == Confidence.low ? Colors.deepOrange : Colors.amber.shade800),
        );
}
