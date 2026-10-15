import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:namer_app/services/premium_service.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:url_launcher/url_launcher.dart';

/// Premium in the Android app, bought through Google Play (Google doesn't
/// allow Android apps to sell subscriptions through Stripe). Our server
/// checks every purchase with Google and writes it to `billing/{uid}`, the
/// same place as Stripe, so [Premium] works the same either way.
///
/// The products are set up in Play Console as subscriptions with these
/// ids, each with one auto-renewing base plan.
class PlayBilling {
  PlayBilling._();

  static const package = 'com.thecaloriecard.app';

  /// Our plan name → the Play product ids it may have (the first that
  /// exists in Play Console is used).
  static const products = {
    'monthly': ['monthly', 'premium_monthly'],
    'yearly': ['yearly', 'premium_yearly'],
  };

  /// Google Play billing is used here (the Android app).
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// What's happening with a purchase, for the Premium page to show
  /// ("pending", an error, or done). Null when there's nothing to say.
  static final ValueNotifier<PlayNote?> note = ValueNotifier(null);

  static StreamSubscription<List<PurchaseDetails>>? _sub;
  static String? _uid;
  static Map<String, ProductDetails> _plans = {};

  /// Starts listening for purchases (called once the app shell is up, so a
  /// purchase that finished while the app was closed is picked up too).
  static void start(String uid) {
    if (!supported) return;
    if (_uid != uid) _plans = {};
    _uid = uid;
    try {
      _sub ??= InAppPurchase.instance.purchaseStream.listen(
        _onPurchases,
        onError: (_) {},
      );
    } catch (_) {
      // Google Play billing not available on this device: nothing to do.
    }
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
    _uid = null;
    _plans = {};
    note.value = null;
  }

  /// The plans with Google's prices, in the person's own currency, by plan
  /// name ('monthly', 'yearly'). Empty if Google Play isn't available.
  static Future<Map<String, ProductDetails>> plans() async {
    if (!supported) return const {};
    if (_plans.isNotEmpty) return _plans;
    try {
      final iap = InAppPurchase.instance;
      if (!await iap.isAvailable()) return const {};
      final r = await iap.queryProductDetails(
          {for (final ids in products.values) ...ids});
      final found = <String, ProductDetails>{};
      for (final e in products.entries) {
        for (final id in e.value) {
          for (final d in r.productDetails) {
            if (d.id == id) found.putIfAbsent(e.key, () => d);
          }
        }
      }
      return _plans = found;
    } catch (_) {
      return const {};
    }
  }

  /// Opens Google Play's payment sheet for [plan]. The result arrives later
  /// (see [note] and [Premium.notifier]).
  static Future<void> buy(String plan) async {
    final uid = _uid;
    if (uid == null) throw const PremiumException('Please sign in again.');
    final details = (await plans())[plan];
    if (details == null) {
      throw const PremiumException(
          "Couldn't reach Google Play. Check you're signed in to the Play "
          'Store and try again.');
    }
    note.value = null;
    final started = await InAppPurchase.instance.buyNonConsumable(
      // The account id lets our server check the purchase is this
      // account's (Google passes it back with the purchase).
      purchaseParam:
          PurchaseParam(productDetails: details, applicationUserName: uid),
    );
    if (!started) {
      throw const PremiumException(
          "Google Play couldn't start the payment. Try again?");
    }
  }

  /// "Restore purchases": asks Google Play for this phone's subscriptions
  /// and checks them again (a new phone, or a reinstall).
  static Future<void> restore() async {
    if (!supported) return;
    note.value = const PlayNote('Checking Google Play…');
    await InAppPurchase.instance.restorePurchases(applicationUserName: _uid);
    // Nothing to restore: no events arrive, so clear the message shortly.
    Timer(const Duration(seconds: 8), () {
      if (note.value?.text == 'Checking Google Play…') {
        note.value = const PlayNote(
            "No Premium subscription found on this phone's Google account.");
      }
    });
  }

  /// Google Play's own page to change plan, update payment or cancel.
  static Future<void> manage({String? productId}) async {
    final uri = Uri.https('play.google.com', '/store/account/subscriptions', {
      if (productId != null && productId.isNotEmpty) 'sku': productId,
      'package': package,
    });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) throw const PremiumException("Couldn't open Google Play.");
  }

  static Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.pending:
          note.value = const PlayNote(
              'Payment pending. Premium starts as soon as Google Play '
              'confirms it.');
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verify(p, restored: p.status == PurchaseStatus.restored);
          continue; // completed in _verify once the server has it
        case PurchaseStatus.error:
          note.value = const PlayNote(
              "The payment didn't go through, so nothing was charged. "
              'Try again?',
              error: true);
        case PurchaseStatus.canceled:
          note.value = null;
      }
      if (p.pendingCompletePurchase) {
        try {
          await InAppPurchase.instance.completePurchase(p);
        } catch (_) {}
      }
    }
  }

  /// Sends a purchase to our server, which checks it with Google and turns
  /// on Premium. Only then is it marked complete with Google; if our server
  /// can't be reached, Google hands it to us again next time.
  static Future<void> _verify(PurchaseDetails p, {required bool restored}) async {
    try {
      final r = await ProxyClient.post('/billing/play/verify', {
        'productId': p.productID,
        'purchaseToken': p.verificationData.serverVerificationData,
      }).timeout(const Duration(seconds: 60));
      Map? j;
      try {
        final d = json.decode(r.body);
        if (d is Map) j = d;
      } catch (_) {}
      if (r.statusCode == 200) {
        if (p.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(p);
        }
        note.value = j?['subscribed'] == true
            ? PlayNote(restored
                ? 'Your Premium subscription is back.'
                : 'Premium is yours! 💜 Thank you.')
            : null;
        return;
      }
      // A purchase our server won't accept (another account's): still
      // complete it with Google, or it's offered again forever.
      if (r.statusCode == 400 || r.statusCode == 403) {
        if (p.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(p);
        }
      }
      note.value = PlayNote(
          (j?['error'] as String?) ??
              "We couldn't confirm your purchase yet. It'll be checked "
                  'again automatically.',
          error: true);
    } catch (_) {
      note.value = const PlayNote(
          "We couldn't confirm your purchase yet. It'll be checked again "
          'automatically, so you won\'t be charged twice.',
          error: true);
    }
  }
}

/// A message about a Google Play purchase.
@immutable
class PlayNote {
  final String text;
  final bool error;
  const PlayNote(this.text, {this.error = false});
}
