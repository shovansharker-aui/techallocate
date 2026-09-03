import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../utils/water_plant.dart';
import 'reload_trigger.dart';

/// Bump this string every time you ship a web build you want already-
/// open tabs/PWAs to pick up automatically. There's no server push
/// available on this project's Firebase plan, so this works by mutual
/// announcement instead: whichever open session has the newest build
/// writes its own version here, and every other open session notices
/// the mismatch on its next check and reloads itself — which loads the
/// new build, which re-announces its version, and so on. In practice
/// this means: after deploying, open the site once yourself, and every
/// other already-open tab/PWA converges onto the new version within one
/// polling interval (a few minutes) — nothing updates until at least
/// one session has actually loaded the new build and announced it.
const String kAppBuildVersion = '2026-09-03.1';

/// Reuses the same already-writable Firestore document as the Water
/// Plant "Switching" toggle (see water_plant.dart) rather than a new
/// collection or document — this project's Firestore rules reject
/// writes to locations they don't already recognize (that's what broke
/// the chart-mode toggle originally), and this doc is proven to accept
/// arbitrary extra fields.
class AppVersionService {
  Timer? _timer;

  Future<void> start() async {
    if (!kIsWeb) return; // this mechanism only makes sense for web/PWA
    await _checkOnce();
    _timer = Timer.periodic(const Duration(minutes: 3), (_) => _checkOnce());
  }

  Future<void> _checkOnce() async {
    try {
      final snap = await waterPlantSettingsRef.get();
      final remote = snap.data()?['appVersion'] as String?;

      if (remote == null || remote == kAppBuildVersion) {
        // Nobody's announced a version yet, or we already match —
        // either way, (re-)announce so this stays the shared baseline.
        await waterPlantSettingsRef.set({'appVersion': kAppBuildVersion}, SetOptions(merge: true));
        return;
      }

      // kAppBuildVersion is always 'YYYY-MM-DD.N', so plain string
      // comparison sorts oldest-to-newest correctly — no separate
      // "parse and compare dates" step needed.
      if (kAppBuildVersion.compareTo(remote) > 0) {
        // This session is running a NEWER build than what's on record —
        // don't reload ourselves, announce so everyone else does.
        await waterPlantSettingsRef.set({'appVersion': kAppBuildVersion}, SetOptions(merge: true));
      } else {
        // Someone else's session already announced a newer build than
        // this one — reload to pick it up.
        triggerReload();
      }
    } catch (_) {
      // Best-effort; a failed check just tries again next tick.
    }
  }
}

final appVersionService = AppVersionService();
