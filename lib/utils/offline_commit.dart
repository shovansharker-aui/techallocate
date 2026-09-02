import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Fires [batch] at Firestore without ever waiting for the server to
/// answer.
///
/// Firestore writes a batch into its local cache the instant `commit()`
/// is called — before this function even returns — so anything already
/// listening (the Task Running screen, an admin dashboard, etc.) sees
/// the change right away, online or not. The actual round trip to the
/// server can then take anywhere from instantly (good signal) to
/// indefinitely (no signal at all); since nobody using this app should
/// ever be stuck on a spinner waiting for the internet, nothing here
/// waits for it either — not even briefly. If it eventually fails for a
/// real reason, that's only logged, since by then whatever screen asked
/// for the write has already moved on and there's no useful way to
/// surface the error.
void commitAllowingOffline(WriteBatch batch) {
  batch.commit().catchError((Object error) {
    debugPrint('Firestore write did not reach the server: $error');
  });
}
