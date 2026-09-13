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

/// What the title should look like -- named subject + a short category
/// word, never the plant/room/area, plain Title Case with no punctuation.
/// A single instruction string alone let the model free-style word order
/// and pick up noise words (e.g. "Glass cleaning work view" for "view
/// glass cleaning work") -- these examples pin the exact style down far
/// more reliably than prose instructions on their own. Taken directly
/// from real JO remarks and the titles wanted for them.
const _systemInstruction = 'You generate a short title for a maintenance task from a technician\'s '
    'informal, often typo-ridden field notes. Rules:\n'
    '- 2-4 words, Title Case, no ending punctuation, no quotes.\n'
    '- Name ONLY the equipment/system plus a short category word (Repair, Task, '
    'Required, Work, Inspection) -- never the plant, building, area, or room it '
    'happened in.\n'
    '- Silently fix obvious typos and ignore filler words like "view", "running", '
    '"working" used as filler rather than the subject.\n'
    '- Never explain your answer -- output the title text only, nothing else.';

const _fewShotExamples = <(String remarks, String title)>[
  ('Softgel FBE control panel tray er pipe leakage hoyse (service area)', 'Air Pipe Repair'),
  ('view glass cleaning work', 'Glass Cleaning Work'),
  ('need welding', 'Welding Required'),
  ('gp annex light work', 'Light Repair'),
  ('light and inter lock workin', 'Light & Interlock Repair'),
  ('secondary change room access control working running', 'Access Control Repair'),
];

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
            'systemInstruction': {
              'parts': [
                {'text': _systemInstruction},
              ],
            },
            // Few-shot: each example is a fake prior exchange so the
            // model pattern-matches the exact style instead of only
            // reading it as a rule to interpret on its own.
            'contents': [
              for (final (exampleRemarks, exampleTitle) in _fewShotExamples) ...[
                {
                  'role': 'user',
                  'parts': [
                    {'text': exampleRemarks},
                  ],
                },
                {
                  'role': 'model',
                  'parts': [
                    {'text': exampleTitle},
                  ],
                },
              ],
              {
                'role': 'user',
                'parts': [
                  {'text': trimmed},
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

const _reasonSystemInstruction = 'You write a one-sentence reason for a machine breakdown, for an admin '
    'reviewing a maintenance log. You are given the technician\'s initial problem note and, if the job is '
    'finished, their completion remarks describing what was actually done. Rules:\n'
    '- One short plain sentence (under 15 words), normal sentence case, no ending period, no quotes.\n'
    '- State the actual problem and, if given, the fix -- e.g. "Air pipe leak, replaced gasket".\n'
    '- Silently fix obvious typos. Omit plant/building/room names.\n'
    '- If completion remarks are empty, describe only the initial problem.\n'
    '- Never explain your answer -- output the sentence only, nothing else.';

/// Turns a completed breakdown task's initial + completion remarks into
/// a one-line reason, for the Breakdown Trend chart's per-machine detail
/// popup (see widgets_breakdown_trend_chart.dart), which computes this
/// once per task and caches it on the task's own `reasonSummary` field
/// rather than re-calling this on every popup open.
///
/// Best-effort only, same contract as [summarizeOthersTaskTitle]: null
/// on any failure or missing key/input, never throws.
Future<String?> summarizeBreakdownReason(String initialRemarks, String completionRemarks) async {
  final initial = initialRemarks.trim();
  final completion = completionRemarks.trim();
  if (geminiApiKey.isEmpty || (initial.isEmpty && completion.isEmpty)) return null;

  final prompt = StringBuffer();
  prompt.writeln('Initial problem: ${initial.isEmpty ? '(none given)' : initial}');
  prompt.writeln('Completion remarks: ${completion.isEmpty ? '(job not yet finished)' : completion}');

  try {
    final response = await http
        .post(
          Uri.parse('$_endpoint?key=$geminiApiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'systemInstruction': {
              'parts': [
                {'text': _reasonSystemInstruction},
              ],
            },
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': prompt.toString()},
                ],
              },
            ],
            'generationConfig': {'maxOutputTokens': 40, 'temperature': 0.2},
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      debugPrint('AI reason request failed: ${response.statusCode} ${response.body}');
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return null;
    final parts = (candidates.first as Map<String, dynamic>)['content']?['parts'] as List?;
    if (parts == null || parts.isEmpty) return null;
    var reason = (parts.first as Map<String, dynamic>)['text']?.toString().trim();
    if (reason == null || reason.isEmpty) return null;

    reason = reason.replaceAll('"', '').replaceAll('\n', ' ').trim();
    if (reason.length > 120) reason = reason.substring(0, 120).trim();
    return reason;
  } catch (e) {
    debugPrint('AI reason request errored: $e');
    return null;
  }
}
