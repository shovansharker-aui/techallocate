import 'package:flutter/material.dart';

/// Used on screens that were PUSHED on top of another screen (so there is
/// always a previous screen to return to) where it's easy to land by
/// mistake and want a quick way out — e.g. "Assign a CF" or "My CF
/// Assignments" reached from the dashboard.
///
/// Confirms first, then pops back to whatever screen pushed this one.
///
/// This is the pushed-screen counterpart to [RootBackScope]. Don't use
/// RootBackScope here instead: RootBackScope assumes there is NO previous
/// screen and, on confirmation, closes/minimizes the whole app — using it
/// on a screen that actually has a parent route is what made back
/// navigation from these screens dead-end instead of returning to the
/// dashboard.
class ConfirmBackScope extends StatelessWidget {
  final Widget child;
  final String title;
  final String message;

  const ConfirmBackScope({
    super.key,
    required this.child,
    this.title = 'Go back to the dashboard?',
    this.message = "Anything you've selected on this page hasn't been saved.",
  });

  Future<void> _confirmLeave(BuildContext context) async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Go back'),
          ),
        ],
      ),
    );

    if (shouldLeave == true && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmLeave(context);
      },
      child: child,
    );
  }
}
