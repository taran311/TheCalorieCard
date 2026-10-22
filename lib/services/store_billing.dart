import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:namer_app/services/premium_service.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:url_launcher/url_launcher.dart';

/// Premium in the phone apps, bought through the phone's own store: Google
/// Play on Android, the App Store on iPhone (neither allows apps to sell
/// subscriptions through Stripe). Our server checks every purchase with
/// Google or Apple and writes it to `billing/{uid}`, the same place as
/// Stripe, so [Premium] works the same wherever someone paid.
///
/// The products are set up in Play Console and App Store Connect as
/// auto-renewing subscriptions with these ids.
class StoreBilling {
  StoreBilling._();

  static const package = 'com.thecaloriecard.app';

  /// Our plan name → the store product ids it may have (the first that
  /// exists in the store is used).
  static const products = {
    'monthly': ['monthly', 'premium_monthly'],
    'yearly': ['yearly', 'premium_yearly'],
  };

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get _ios =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// The phone's store is used here (the Android or iPhone app).
  static bool get supported => _android || _ios;

  /// Which store, as `billing/{uid}.store` names it: 'play' or 'apple'.
  static String? get store => _android ? 'play' : _ios ? 'apple' : null;

  /// "Google Play" or "the App Store", for sentences.
  static String get storeName => _ios ? 'the App Store' : 'Google Play';

  /// The store's name for [store] ('play' or 'apple'), wherever this runs.
  static String nameOf(String? store) =>
      store == 'apple' ? 'the App Store' : 'Google Play';

  /// Where a subscription from [store] is changed or cancelled, in words.
  static String manageWhere(String? store) => store == 'apple'
      ? 'in Settings on your iPhone: tap your name, then Subscriptions'
      : 'in the Play Store on your Android phone: Profile → Payments and '
          'subscriptions';

  /// What's happening with a purchase, for the Premium page to show
  /// ("pending", an error, or done). Null when there's nothing to say.
  static final ValueNotifier<StoreNote?> note = ValueNotifier(null);

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
      // The store isn't available on this device: nothing to do.
    }
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
    _uid = null;
    _plans = {};
    note.value = null;
  }

  /// The plans with the store's prices, in the person's own currency, by
  /// plan name ('monthly', 'yearly'). Empty if the store isn't available.
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

  /// Opens the store's payment sheet for [plan]. The result arrives later
  /// (see [note] and [Premium.notifier]).
  static Future<void> buy(String plan) async {
    final uid = _uid;
    if (uid == null) throw const PremiumException('Please sign in again.');
    final details = (await plans())[plan];
    if (details == null) {
      throw PremiumException(_ios
          ? "Couldn't reach the App Store. Check you're signed in to the "
              'App Store and try again.'
          : "Couldn't reach Google Play. Check you're signed in to the Play "
              'Store and try again.');
    }
    note.value = null;
    final started = await InAppPurchase.instance.buyNonConsumable(
      // On Android the account id lets our server check the purchase is
      // this account's (Google passes it back). Apple only takes a UUID
      // there, so on iPhone the server links the purchase to the account
      // that first sends it instead.
      purchaseParam: PurchaseParam(
          productDetails: details, applicationUserName: _ios ? null : uid),
    );
    if (!started) {
      throw PremiumException(
          "${_ios ? 'The App Store' : 'Google Play'} couldn't start the "
          'payment. Try again?');
    }
  }

  static String get _checking =>
      _ios ? 'Checking the App Store…' : 'Checking Google Play…';

  /// "Restore purchases": asks the store for this account's subscriptions
  /// and checks them again (a new phone, or a reinstall).
  static Future<void> restore() async {
    if (!supported) return;
    note.value = StoreNote(_checking);
    await InAppPurchase.instance
        .restorePurchases(applicationUserName: _ios ? null : _uid);
    // Nothing to restore: no events arrive, so clear the message shortly.
    Timer(const Duration(seconds: 8), () {
      if (note.value?.text == _checking) {
        note.value = StoreNote(_ios
            ? 'No Premium subscription found on this Apple ID.'
            : "No Premium subscription found on this phone's Google "
                'account.');
      }
    });
  }

  /// The store's own page to change plan, update payment or cancel.
  static Future<void> manage({String? productId}) async {
    final uri = _ios
        ? Uri.https('apps.apple.com', '/account/subscriptions')
        : Uri.https('play.google.com', '/store/account/subscriptions', {
            if (productId != null && productId.isNotEmpty) 'sku': productId,
            'package': package,
          });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw PremiumException(
          "Couldn't open ${_ios ? 'the App Store' : 'Google Play'}.");
    }
  }

  static Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.pending:
          note.value = StoreNote(
              'Payment pending. Premium starts as soon as '
              '${_ios ? 'the App Store' : 'Google Play'} confirms it.');
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verify(p, restored: p.status == PurchaseStatus.restored);
          continue; // completed in _verify once the server has it
        case PurchaseStatus.error:
          note.value = const StoreNote(
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

  /// Sends a purchase to our server, which checks it with Google or Apple
  /// and turns on Premium. Only then is it marked complete with the store;
  /// if our server can't be reached, the store hands it to us again next
  /// time.
  static Future<void> _verify(PurchaseDetails p, {required bool restored}) async {
    try {
      final proof = p.verificationData.serverVerificationData;
      final r = await (_ios
              ? ProxyClient.post('/billing/apple/verify', {
                  'productId': p.productID,
                  // StoreKit 2's signed transaction (a JWS).
                  'signedTransaction': proof,
                })
              : ProxyClient.post('/billing/play/verify', {
                  'productId': p.productID,
                  'purchaseToken': proof,
                }))
          .timeout(const Duration(seconds: 60));
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
            ? StoreNote(restored
                ? 'Your Premium subscription is back.'
                : 'Premium is yours! 💜 Thank you.')
            : null;
        return;
      }
      // A purchase our server won't accept (another account's): still
      // complete it with the store, or it's offered again forever.
      if (r.statusCode == 400 || r.statusCode == 403) {
        if (p.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(p);
        }
      }
      note.value = StoreNote(
          (j?['error'] as String?) ??
              "We couldn't confirm your purchase yet. It'll be checked "
                  'again automatically.',
          error: true);
    } catch (_) {
      note.value = const StoreNote(
          "We couldn't confirm your purchase yet. It'll be checked again "
          'automatically, so you won\'t be charged twice.',
          error: true);
    }
  }
}

/// A message about a store purchase.
@immutable
class StoreNote {
  final String text;
  final bool error;
  const StoreNote(this.text, {this.error = false});
}
