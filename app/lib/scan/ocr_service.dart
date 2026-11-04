import 'dart:io';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/recipe.dart';
import '../parser/text.dart';

/// On-device OCR (Apple Vision / Google ML Kit via google_mlkit_text_recognition). Photos never leave the phone.
class OcrService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Lines in reading order with normalized boxes on [page], ready for `structureLines`.
  Future<List<InputLine>> recognize(String path, int page) async {
    final bytes = await File(path).readAsBytes();
    final image = await (await ui.instantiateImageCodec(bytes)).getNextFrame();
    final w = image.image.width.toDouble(), h = image.image.height.toDouble();
    final result = await _recognizer.processImage(InputImage.fromFilePath(path));
    final lines = [for (final b in result.blocks) ...b.lines]
      ..sort((a, b) => (a.boundingBox.top - b.boundingBox.top).abs() < 8
          ? a.boundingBox.left.compareTo(b.boundingBox.left)
          : a.boundingBox.top.compareTo(b.boundingBox.top));
    return [
      for (final l in lines)
        InputLine(
          l.text,
          confidence: l.confidence,
          box: Box(page: page, x: l.boundingBox.left / w, y: l.boundingBox.top / h, w: l.boundingBox.width / w, h: l.boundingBox.height / h),
        ),
    ];
  }

  Future<void> close() => _recognizer.close();
}

/// Copies a picked photo out of the picker's temp cache into app storage so the recipe keeps its source image.
Future<String> keepImage(String path) async {
  final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'scans'));
  await dir.create(recursive: true);
  final ext = p.extension(path).isEmpty ? '.jpg' : p.extension(path);
  return (await File(path).copy(p.join(dir.path, '${const Uuid().v4()}$ext'))).path;
}

/// Deletes kept photos that never made it into a saved recipe.
void discardImages(Iterable<String> paths) {
  for (final path in paths) {
    File(path).delete().ignore();
  }
}

/// Fills what [base] is missing (title, ingredients, steps, servings, times) from [extra].
RecipeDraft mergeDrafts(RecipeDraft? base, RecipeDraft extra) {
  if (base == null) return extra;
  final takeTitle = base.title.isEmpty && extra.title.isNotEmpty;
  return RecipeDraft(
    title: takeTitle ? extra.title : base.title,
    titleConfidence: takeTitle ? extra.titleConfidence : base.titleConfidence,
    servings: base.servings ?? extra.servings,
    yieldText: base.yieldText ?? extra.yieldText,
    servingsConfidence: base.servings != null ? base.servingsConfidence : extra.servingsConfidence,
    prepMinutes: base.prepMinutes ?? extra.prepMinutes,
    cookMinutes: base.cookMinutes ?? extra.cookMinutes,
    totalMinutes: base.totalMinutes ?? extra.totalMinutes,
    timesConfidence: base.timesConfidence,
    ingredients: base.ingredients.any((i) => !i.isSection) ? base.ingredients : extra.ingredients,
    steps: base.steps.isNotEmpty ? base.steps : extra.steps,
    foundIn: {...base.foundIn, ...extra.foundIn}.toList(),
  );
}

bool hasRecipe(RecipeDraft? d) => d != null && (d.ingredients.any((i) => !i.isSection) || d.steps.isNotEmpty);
