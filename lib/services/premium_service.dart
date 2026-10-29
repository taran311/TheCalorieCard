import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:namer_app/services/referrals.dart';
import 'package:namer_app/services/store_billing.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:url_launcher/url_launcher.dart';

/// Prices shown in the app. They must match the prices set up in Stripe
/// (the server decides what's actually charged).
class PremiumPrices {
  PremiumPrices._();

  static const monthly = '£4.99';
  static const yearly = '£29.99';
  static const yearlyPerMonth = '£2.50';
  static const founder = '£19.99';
  static const yearlySaving = '50%';
  static const freeCoachPerDay = 5;
}

/// What someone has, from `billing/{uid}` (written only by the server).
@immutable
class Entitlement {
  /// False until the billing document has been read.
  final bool loaded;
  final String? status;
  final String? plan; // monthly, yearly or founder
  final DateTime? trialEndsAt;
  final DateTime? periodEnd;
  final bool cancelAtPeriodEnd;
  final bool founder;

  /// Premium for good, from a gift code (see [GiftCodes]).
  final bool lifetime;

  /// Free Premium from inviting friends (see [Referrals]) lasts until then.
  final DateTime? bonusUntil;

  /// Where the plan was bought: 'stripe' (the website), 'play' (Google
  /// Play, in the Android app) or 'apple' (the App Store, in the iPhone
  /// app). Null if they've never paid.
  final String? store;

  /// The Google Play product, for "Manage subscription".
  final String? playProductId;

  const Entitlement({
    this.loaded = false,
    this.status,
    this.plan,
    this.trialEndsAt,
    this.periodEnd,
    this.cancelAtPeriodEnd = false,
    this.founder = false,
    this.lifetime = false,
    this.bonusUntil,
    this.store,
    this.playProductId,
  });

  static const unknown = Entitlement();

  static DateTime? _date(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  // A document with no trial and no subscription yet (the trial is still
  // being started, or the server can't check billing) counts as not loaded,
  // so nothing locks while that's sorted out.
  factory Entitlement.fromMap(Map<String, dynamic>? d) => Entitlement(
        loaded: d != null &&
            (d['trial_ends_at'] != null ||
                d['status'] != null ||
                d['lifetime'] == true ||
                d['bonus_until'] != null),
        status: d?['status'] as String?,
        plan: d?['plan'] as String?,
        trialEndsAt: _date(d?['trial_ends_at']),
        periodEnd: _date(d?['current_period_end']),
        cancelAtPeriodEnd: d?['cancel_at_period_end'] == true,
        founder: d?['founder'] == true,
        lifetime: d?['lifetime'] == true,
        bonusUntil: _date(d?['bonus_until']),
        store: d?['store'] as String? ??
            (d?['stripe_subscription_id'] != null ? 'stripe' : null),
        playProductId: d?['play_product_id'] as String?,
      );

  static const _paid = {'active', 'trialing', 'past_due'};

  bool subscribedAt(DateTime now) => lifetime || payingAt(now);

  /// A subscription (Stripe, Google Play or the App Store) that's still
  /// running.
  bool payingAt(DateTime now) =>
      _paid.contains(status) && periodEnd != null && periodEnd!.isAfter(now);

  bool get paying => payingAt(DateTime.now());

  bool inTrialAt(DateTime now) =>
      !subscribedAt(now) && trialEndsAt != null && trialEndsAt!.isAfter(now);

  /// Free time from inviting friends, and no paid plan.
  bool inBonusAt(DateTime now) =>
      !subscribedAt(now) && bonusUntil != null && bonusUntil!.isAfter(now);

  bool get subscribed => subscribedAt(DateTime.now());
  bool get inTrial => inTrialAt(DateTime.now());
  bool get inBonus => inBonusAt(DateTime.now());

  /// Free time from friends runs on past the trial, so there's no "trial
  /// ending" to warn about.
  bool get bonusCoversTrial =>
      inBonus && (trialEndsAt == null || bonusUntil!.isAfter(trialEndsAt!));

  /// Premium right now. While we're still loading (or can't read billing),
  /// the app doesn't lock anything: the server has the final say.
  bool get isPremium => !loaded || subscribed || inTrial || inBonus;

  /// The trial ended and they didn't subscribe (or earn time by inviting
  /// friends).
  bool get trialEnded =>
      loaded &&
      !subscribed &&
      !inBonus &&
      trialEndsAt != null &&
      !trialEndsAt!.isAfter(DateTime.now());

  /// Whole days left in the trial (rounded up), or 0.
  int get trialDaysLeft {
    final end = trialEndsAt;
    if (end == null || !inTrial) return 0;
    final hours = end.difference(DateTime.now()).inHours;
    return (hours / 24).ceil().clamp(1, 999);
  }

  String get planLabel => lifetime ? 'Lifetime' : switch (plan) {
        'monthly' => 'Monthly',
        'founder' => 'Early supporter (yearly)',
        _ => 'Yearly',
      };
}

class PremiumException implements Exception {
  final String message;
  const PremiumException(this.message);

  @override
  String toString() => message;
}

/// Premium state for the signed-in user, and the Stripe hand-offs.
class Premium {
  Premium._();

  static final ValueNotifier<Entitlement> notifier =
      ValueNotifier(Entitlement.unknown);

  /// Whether Premium can be bought here: on the website with Stripe, in
  /// the Android app with Google Play and in the iPhone app with the App
  /// Store (neither allows apps to sell subscriptions any other way).
  /// Premium bought in one works in all of them.
  static bool get sellsHere => kIsWeb || StoreBilling.supported;

  /// Buying through the phone's store here (Google Play or the App
  /// Store), not Stripe.
  static bool get viaStore => StoreBilling.supported;

  /// The iPhone app: Apple doesn't allow gift codes to unlock Premium in
  /// the app, or pointing people to the website to pay (App Review 3.1.1).
  static bool get onIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Whether this plan can be changed or cancelled from here: a website
  /// plan on the website, a store plan in that store's app.
  static bool canManage(Entitlement e) => switch (e.store) {
        'play' || 'apple' => StoreBilling.store == e.store,
        _ => kIsWeb,
      };

  static Entitlement get current => notifier.value;
  static bool get isPremium => notifier.value.isPremium;

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  static String? _uid;

  /// Called once the app shell is on screen: starts the free trial if this
  /// account hasn't had one (new and existing users alike), then follows
  /// the billing document so changes from Stripe show straight away.
  static void start(String uid) {
    if (_uid == uid && _sub != null) return;
    _sub?.cancel();
    _uid = uid;
    notifier.value = Entitlement.unknown;
    StoreBilling.start(uid);
    // A new account's first friend, or a friend who's now logged enough
    // days: the free month lands in billing, which the listener below sees.
    Referrals.reset();
    Referrals.check();
    _sub = FirebaseFirestore.instance
        .collection('billing')
        .doc(uid)
        .snapshots()
        .listen(
      (snap) {
        final e = Entitlement.fromMap(snap.data());
        notifier.value = e;
        if (snap.data()?['trial_ends_at'] == null) _startTrial();
      },
      // No access (rules not set up yet) or offline: stay unlocked.
      onError: (_) {},
    );
  }

  static bool _trialRequested = false;

  static Future<void> _startTrial() async {
    if (_trialRequested) return;
    _trialRequested = true;
    try {
      await ProxyClient.post('/billing/start-trial', const {})
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      _trialRequested = false; // try again next time the document changes
    }
  }

  static void stop() {
    StoreBilling.stop();
    _sub?.cancel();
    _sub = null;
    _uid = null;
    _trialRequested = false;
    notifier.value = Entitlement.unknown;
  }

  /// Early-supporter places left (0 if none or unknown).
  static Future<int> foundersLeft() async {
    try {
      final r = await ProxyClient.get('/billing/offer')
          .timeout(const Duration(seconds: 30));
      final j = json.decode(r.body);
      final n = j is Map ? j['founderLeft'] : null;
      return n is num ? n.toInt() : 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<String> _url(String path, Map<String, dynamic> body) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw const PremiumException('Please sign in again.');
    }
    final http.Response r;
    try {
      r = await ProxyClient.post(path, body)
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      throw const PremiumException(
          "Couldn't reach the server. Check your connection and try again.");
    }
    Map? j;
    try {
      final d = json.decode(r.body);
      if (d is Map) j = d;
    } catch (_) {}
    final url = j?['url'];
    if (r.statusCode == 200 && url is String && url.startsWith('https://')) {
      return url;
    }
    throw PremiumException(
        (j?['error'] as String?) ?? 'Something went wrong. Try again?');
  }

  static Future<void> _open(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      webOnlyWindowName: '_self',
      mode: LaunchMode.externalApplication,
    );
    if (!ok) throw const PremiumException("Couldn't open the page.");
  }

  /// Buys [plan] (monthly, yearly or founder): the store's payment sheet
  /// in the phone apps, otherwise Stripe's payment page.
  static Future<void> checkout(String plan) async {
    if (viaStore) return StoreBilling.buy(plan);
    return _open(await _url('/billing/checkout', {'plan': plan}));
  }

  /// Change plan, update payment or cancel: the store's page for a plan
  /// bought there, otherwise Stripe's.
  static Future<void> manage() async {
    final e = current;
    if (e.store == 'play' || e.store == 'apple') {
      return StoreBilling.manage(productId: e.playProductId);
    }
    return _open(await _url('/billing/portal', const {}));
  }
}

/// A gift code as the Gift codes screen shows it.
class GiftCode {
  final String code;
  final String note;
  final DateTime? createdAt;
  final DateTime? redeemedAt;
  final String? redeemedName;
  final bool cancelled;

  const GiftCode({
    required this.code,
    required this.note,
    this.createdAt,
    this.redeemedAt,
    this.redeemedName,
    this.cancelled = false,
  });

  bool get used => redeemedAt != null || redeemedName != null;
  bool get open => !used && !cancelled;

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  factory GiftCode.fromJson(Map j) => GiftCode(
        code: '${j['code'] ?? ''}',
        note: '${j['note'] ?? ''}',
        createdAt: _date(j['createdAt']),
        redeemedAt: _date(j['redeemedAt']),
        redeemedName: j['redeemedName'] as String?,
        cancelled: j['cancelled'] == true,
      );
}

/// Lifetime Premium gift codes: redeeming one (anyone), and making and
/// managing them (admins only; the server checks).
class GiftCodes {
  GiftCodes._();

  static bool? _admin;

  static Future<Map> _call(Future<http.Response> Function() request) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw const PremiumException('Please sign in again.');
    }
    final http.Response r;
    try {
      r = await request().timeout(const Duration(seconds: 60));
    } catch (_) {
      throw const PremiumException(
          "Couldn't reach the server. Check your connection and try again.");
    }
    Map? j;
    try {
      final d = json.decode(r.body);
      if (d is Map) j = d;
    } catch (_) {}
    if (r.statusCode == 200 && j != null) return j;
    throw PremiumException(
        (j?['error'] as String?) ?? 'Something went wrong. Try again?');
  }

  /// Whether this account can make gift codes (asked once per session).
  static Future<bool> isAdmin() async {
    final known = _admin;
    if (known != null) return known;
    try {
      final j = await _call(() => ProxyClient.get('/gift/admin'));
      return _admin = j['admin'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Forgets the admin check (e.g. after signing out).
  static void reset() => _admin = null;

  /// Uses [code]. Returns whether they still have a paid Stripe plan
  /// running (which they'll want to cancel, now Premium is free).
  static Future<({bool stillPaying, bool already})> redeem(String code) async {
    final j = await _call(
        () => ProxyClient.post('/gift/redeem', {'code': code.trim()}));
    return (
      stillPaying: j['stillPaying'] == true,
      already: j['already'] == true,
    );
  }

  /// Makes a new code, e.g. "CC-7KQ2-M9XD". [note] is just for you.
  static Future<String> create({String note = ''}) async {
    final j = await _call(
        () => ProxyClient.post('/gift/create', {'note': note.trim()}));
    final code = j['code'];
    if (code is! String) {
      throw const PremiumException("Couldn't make a code. Try again.");
    }
    return code;
  }

  static Future<List<GiftCode>> list() async {
    final j = await _call(() => ProxyClient.get('/gift/list'));
    final codes = j['codes'];
    return [
      if (codes is List)
        for (final c in codes)
          if (c is Map) GiftCode.fromJson(c)
    ];
  }

  static Future<void> cancel(String code) async {
    await _call(() => ProxyClient.post('/gift/cancel', {'code': code}));
  }
}
