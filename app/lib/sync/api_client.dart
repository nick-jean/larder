import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/import_result.dart';
import '../models/recipe.dart';
import '../parser/text.dart';

/// Base URL of the Larder API, e.g. --dart-define=LARDER_API=https://larder.vercel.app
const apiBaseUrl = String.fromEnvironment('LARDER_API');

/// Local dev only: with AUTH_DEV_BYPASS=1 on the server, sends `Bearer dev:<uid>` instead of a Firebase token.
const devUid = String.fromEnvironment('LARDER_DEV_UID');

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

class SyncResult {
  SyncResult(this.cursor, this.recipes, this.conflictIds);
  final String cursor;
  final List<Recipe> recipes;
  final List<String> conflictIds;
}

class ApiClient {
  ApiClient({required this.tokenProvider, http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? apiBaseUrl;

  final Future<String?> Function() tokenProvider;
  final http.Client _client;
  final String baseUrl;

  bool get configured => baseUrl.isNotEmpty;

  /// Bearer tokens only go over HTTPS; plain HTTP is allowed for local dev servers in debug builds.
  static bool isSecure(Uri uri) =>
      uri.scheme == 'https' ||
      (kDebugMode && uri.scheme == 'http' && const {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host));

  Future<String?> _token() async => (kDebugMode && devUid.isNotEmpty) ? 'dev:$devUid' : await tokenProvider();

  Future<Map<String, dynamic>> _send(String method, String path, [Object? body]) async {
    if (!configured) throw ApiException(0, 'Larder server not configured');
    final uri = Uri.parse('$baseUrl/api/v1$path');
    if (!isSecure(uri)) throw ApiException(0, 'Refusing to send credentials to a non-HTTPS API');
    final token = await _token();
    if (token == null) throw ApiException(401, 'Sign in to import links');
    final headers = {'authorization': 'Bearer $token', 'content-type': 'application/json'};
    // No redirects: the bearer token must only reach the validated host.
    final req = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll(headers);
    if (method != 'GET') req.body = jsonEncode(body ?? {});
    final res = await http.Response.fromStream(await _client.send(req));
    if (res.statusCode >= 300 && res.statusCode < 400) throw ApiException(res.statusCode, 'Unexpected redirect from the Larder server');
    final data = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) throw ApiException(res.statusCode, data['error'] as String? ?? 'Request failed (${res.statusCode})');
    return data;
  }

  Future<ImportResult> importLink(String url) async => ImportResult.fromJson(await _send('POST', '/imports/link', {'url': url}));

  /// Optional server structuring of pasted text or OCR lines; `ai: true` is the opt-in AI tidy-up.
  Future<RecipeDraft?> importText({String? text, List<InputLine>? lines, String provenance = 'pasted_text', bool ai = false}) async {
    final data = await _send('POST', '/imports/text', {
      'text': ?text,
      if (lines != null)
        'lines': [for (final l in lines) {'text': l.text, 'confidence': l.confidence, if (l.box != null) 'box': l.box!.toJson()}],
      'provenance': provenance,
      'ai': ai,
    });
    final d = data['draft'];
    return d == null ? null : RecipeDraft.fromJson(d as Map<String, dynamic>);
  }

  Future<SyncResult> sync({required String? cursor, required List<Recipe> recipes}) async {
    final data = await _send('POST', '/sync', {'cursor': cursor, 'recipes': [for (final r in recipes) r.toJson()]});
    return SyncResult(
      data['cursor'] as String,
      [for (final r in (data['recipes'] as List)) Recipe.fromJson(r as Map<String, dynamic>)],
      [for (final c in (data['conflicts'] as List)) (c as Map<String, dynamic>)['id'] as String],
    );
  }

  Future<Map<String, dynamic>> me() => _send('GET', '/me');
}
