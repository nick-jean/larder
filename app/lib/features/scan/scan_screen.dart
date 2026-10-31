import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../import_flow.dart';
import '../../models/recipe.dart';
import '../../parser/text.dart';
import '../../providers.dart';
import '../../scan/ocr_service.dart';

const maxPages = 10;

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key, required this.scanType});
  final String scanType; // cookbook | handwritten | screenshot
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final List<String> _pages = [];
  bool _busy = false;
  String? _error;

  String get _title => switch (widget.scanType) {
        'handwritten' => 'Handwritten card',
        'screenshot' => 'Screenshot',
        _ => 'Cookbook page',
      };

  String get _tip => switch (widget.scanType) {
        'handwritten' => 'Lay the card flat in good light. Add the back if the recipe continues.',
        'screenshot' => 'Pick screenshots of the caption or recipe. Add more if it\'s split across several.',
        _ => 'Fill the frame with the page and avoid glare. Add the next page if the recipe continues.',
      };

  bool _saved = false;

  @override
  void dispose() {
    if (!_saved) discardImages(_pages);
    super.dispose();
  }

  Future<void> _add(ImageSource source) async {
    final picker = ImagePicker();
    final files = source == ImageSource.camera
        ? [?await picker.pickImage(source: source, imageQuality: 90)]
        : await picker.pickMultiImage(imageQuality: 90, limit: maxPages - _pages.length);
    for (final f in files.take(maxPages - _pages.length)) {
      final path = await keepImage(f.path);
      setState(() => _pages.add(path));
    }
  }

  Future<void> _read() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ocr = OcrService();
    try {
      final lines = <InputLine>[];
      for (var i = 0; i < _pages.length; i++) {
        lines.addAll(await ocr.recognize(_pages[i], i));
      }
      if (lines.isEmpty) {
        setState(() => _error = 'No text found. Try a sharper photo with more light.');
        return;
      }
      final draft = structureLines(lines, 'ocr', newId: newId);
      if (!mounted) return;
      _saved = true; // set first: saving navigates away, which disposes this screen
      try {
        await saveDraftForReview(
          context,
          ref,
          draft,
          RecipeSource(kind: 'scan', scanType: widget.scanType, pageCount: _pages.length),
          imageKeys: List.of(_pages),
        );
      } catch (_) {
        _saved = false;
        rethrow;
      }
    } catch (e) {
      setState(() => _error = 'Couldn\'t read the photos: $e');
    } finally {
      await ocr.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(_tip),
          const SizedBox(height: 12),
          Row(children: [
            if (widget.scanType != 'screenshot') ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || _pages.length >= maxPages ? null : () => _add(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(_pages.isEmpty ? 'Take photo' : 'Add page'),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || _pages.length >= maxPages ? null : () => _add(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('From photos'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (_pages.isNotEmpty)
            SizedBox(
              height: 180,
              child: ReorderableListView(
                scrollDirection: Axis.horizontal,
                onReorderItem: (from, to) => setState(() => _pages.insert(to, _pages.removeAt(from))),
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    Padding(
                      key: ValueKey(_pages[i]),
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(children: [
                        ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_pages[i]), height: 180, width: 130, fit: BoxFit.cover)),
                        Positioned(left: 4, top: 4, child: CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 12)))),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: IconButton.filledTonal(
                            iconSize: 16,
                            icon: const Icon(Icons.close),
                            tooltip: 'Remove page',
                            onPressed: () {
                              discardImages([_pages[i]]);
                              setState(() => _pages.removeAt(i));
                            },
                          ),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          if (_pages.length > 1) const Padding(padding: EdgeInsets.only(top: 4), child: Text('Long-press and drag to reorder pages.')),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 16),
          if (_busy) const Center(child: CircularProgressIndicator()),
          FilledButton(
            onPressed: _busy || _pages.isEmpty ? null : _read,
            child: Text(_pages.length > 1 ? 'Read ${_pages.length} pages' : 'Read recipe'),
          ),
          const SizedBox(height: 8),
          const Text('Text is read on your phone. Photos stay on this device.', textAlign: TextAlign.center),
        ]),
      );
}
