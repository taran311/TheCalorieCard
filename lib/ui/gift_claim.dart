import 'package:flutter/material.dart';
import 'package:namer_app/services/premium_service.dart';
import 'package:namer_app/services/web_platform.dart' as web;
import 'package:namer_app/ui/responsive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A gift link (thecaloriecard.com/?gift=CC-XXXX-XXXX) waiting to be
/// claimed. It's remembered on this device as the app opens, so someone
/// new can sign up and verify their email first, then claim it.
class PendingGift {
  PendingGift._();

  static const _key = 'pending_gift_code';

  /// The gift link the app was opened with, for sharing.
  static String linkFor(String code) =>
      'https://thecaloriecard.com/?gift=${Uri.encodeQueryComponent(code)}';

  /// Saves `?gift=…` from the address bar (and tidies the address bar).
  static Future<void> captureFromUrl() async {
    try {
      final code = Uri.base.queryParameters['gift']?.trim() ?? '';
      if (code.isEmpty || code.length > 40) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, code);
      web.clearUrlQuery();
    } catch (_) {}
  }

  static Future<String?> peek() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_key);
      return code == null || code.isEmpty ? null : code;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}

bool _offering = false;

/// If a gift link is waiting, offers it: "You've been gifted lifetime
/// Premium" with a Claim button. Call once the signed-in app is showing.
Future<void> offerPendingGift(BuildContext context) async {
  if (_offering) return;
  final code = await PendingGift.peek();
  if (code == null || !context.mounted) return;
  if (Premium.current.loaded && Premium.current.lifetime) {
    await PendingGift.clear();
    return;
  }
  _offering = true;
  try {
    final claimed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _GiftSheet(code: code),
    );
    if (claimed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(seconds: 6),
        content: Text('Lifetime Premium is yours! 💜 Your Aurora card '
            'appears in a few seconds.'),
      ));
    }
  } finally {
    _offering = false;
  }
}

class _GiftSheet extends StatefulWidget {
  final String code;
  const _GiftSheet({required this.code});

  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  bool _busy = false;
  String? _error;

  /// The code can't be used (used, cancelled or not real): no retry.
  bool _final = false;

  Future<void> _claim() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await GiftCodes.redeem(widget.code);
      await PendingGift.clear();
      if (!mounted) return;
      if (r.stillPaying) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 8),
          content: Text('Your paid plan is still running: cancel it under '
              "Premium → Manage subscription so you're not charged."),
        ));
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      final message = e is PremiumException
          ? e.message
          : 'Something went wrong. Try again?';
      // Used, cancelled or not a real code: don't offer it again. A
      // connection problem keeps it for next time.
      final isFinal = !message.startsWith("Couldn't reach");
      if (isFinal) await PendingGift.clear();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = message;
        _final = isFinal;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('🎁',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 52)),
            const SizedBox(height: 8),
            Text(
              "You've been gifted lifetime Premium",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Everything in Premium, for good, including the Aurora card. '
              'Nothing to pay and no card details.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14.5, height: 1.4, color: AppColors.gray700),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppText.red600, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy || _final ? null : _claim,
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_error == null ? 'Claim it' : 'Try again',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: Text(_final ? 'Close' : 'Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
