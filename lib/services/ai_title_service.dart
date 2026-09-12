import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/ai_config.dart';

/// Free-tier Gemini endpoint (generativelanguage.googleapis.com) -- no
/// billing account required for the key from
/// https://aistudio.google.com/apikey, unlike Vertex AI / Firebase AI
/// Logic which need the project on a paid plan.
///
/// Uses the "-latest" alias (rather than pinning e.g. "gemini-2.5-flash")
/// so this keeps working as Google retires older dated models --
/// pinning to "gemini-2.0-flash" during development already broke once
/// that way (404 "no longer available") before this ever shipped.
const _endpoint = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-lite-latest:generateContent';

/// Turns an "Others" task's free-text remarks into a short title (a few
/// words, no trailing punctuation) for display in place of "No machine"
/// on the admin panel and archived tasks.
///
/// Best-effort only: returns null (never throws) if no API key is
/// configured, the remarks are blank, the request fails, or the response
/// doesn't parse -- callers should just skip setting a title in that
/// case and keep the existing machine-name fallback.
Future<String?> summarizeOthersTaskTitle(String remarks) async {
  final trimmed = remarks.trim();
  if (geminiApiKey.isEmpty || trimmed.isEmpty) return null;

  try {
    final response = await http
        .post(
          Uri.parse('$_endpoint?key=$geminiApiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {
                    'text': 'Summarize this maintenance-task note into a short title of 6 words or '
                        'fewer. Plain text only: no quotes, no markdown, no trailing period.\n\n'
                        'Note: $trimmed',
                  },
                ],
              },
            ],
            'generationConfig': {'maxOutputTokens': 20, 'temperature': 0.2},
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      debugPrint('AI title request failed: ${response.statusCode} ${response.body}');
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return null;
    final parts = (candidates.first as Map<String, dynamic>)['content']?['parts'] as List?;
    if (parts == null || parts.isEmpty) return null;
    var title = (parts.first as Map<String, dynamic>)['text']?.toString().trim();
    if (title == null || title.isEmpty) return null;

    title = title.replaceAll('"', '').replaceAll('\n', ' ').trim();
    if (title.length > 60) title = title.substring(0, 60).trim();
    return title;
  } catch (e) {
    debugPrint('AI title request errored: $e');
    return null;
  }
}
