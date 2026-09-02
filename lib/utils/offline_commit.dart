import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Whether a batch reached the server before we stopped waiting for it.
enum CommitOutcome { synced, queuedOffline }

/// Commits [batch] without blocking indefinitely when there's no signal.
///
/// Firestore applies a batch write to the local cache synchronously the
/// moment `commit()` is called — any other local listener (this device's
/// own dashboard, a StreamBuilder on the same document, etc.) sees the
/// change immediately, offline or not. But the Future `commit()` returns
/// only resolves once the *server* acknowledges the write, which while
/// genuinely offline can simply never happen until connectivity returns.
/// A screen that does `await batch.commit()` before navigating or
/// re-enabling its UI ends up stuck for as long as the JO has no signal,
/// which looks and feels exactly like a failure even though the data was
/// captured correctly.
///
/// This races the real commit against [timeout]. If the ack doesn't
/// arrive in time we treat the write as safely queued — it already is —
/// and let the caller move on. The original commit keeps retrying in the
/// background and will reach Firestore automatically once a connection
/// returns, using whatever client-side timestamps were already baked
/// into the payload. Any failure that surfaces *after* we've stopped
/// waiting is swallowed here on purpose: by then there's no UI left
/// waiting for an answer, so there's nothing useful to do with it beyond
/// letting Firestore's own retry logic keep handling it.
Future<CommitOutcome> commitAllowingOffline(
  WriteBatch batch, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  final commitFuture = batch.commit();
  try {
    await commitFuture.timeout(timeout);
    return CommitOutcome.synced;
  } on TimeoutException {
    unawaited(commitFuture.catchError((_) {}));
    return CommitOutcome.queuedOffline;
  }
}
