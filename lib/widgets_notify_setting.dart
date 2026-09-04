import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'utils/app_colors.dart';
import 'utils/water_plant.dart';

/// Lets admin compose a short message that every JO/admin/Water Plant
/// account will see as a one-time pop-up the next time they open the
/// app — used for things like "please refresh your PWA for the new
/// History tab" that can't be pushed automatically. Shown under
/// Settings on both web and native Android.
class NotifySetting extends StatefulWidget {
  const NotifySetting({super.key});

  @override
  State<NotifySetting> createState() => _NotifySettingState();
}

class _NotifySettingState extends State<NotifySetting> {
  final _controller = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _isSending = true);
    try {
      await waterPlantSettingsRef.set({
        'notifyMessage': text,
        // A fresh id each send is what makes it show again even if the
        // wording happens to repeat — devices compare ids, not text.
        'notifyMessageId': DateTime.now().millisecondsSinceEpoch.toString(),
      }, SetOptions(merge: true));
      if (mounted) {
        _controller.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sent — everyone will see it next time they open the app.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send: $e'), duration: const Duration(seconds: 6)));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notify everyone', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Shows as a one-time pop-up the next time each person opens the app — useful for "please refresh" or other announcements that can\'t be pushed automatically.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. "Please reopen the app to get the newest update"',
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSending ? null : _send,
                icon: _isSending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.campaign_outlined),
                label: const Text('Send to everyone'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
