import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/ui/calorie_card.dart';

/// Which card finishes you've unlocked, and which one you're using.
///
/// Stored on `users/{uid}`: `card_design`, `best_streak` and
/// `card_unlocks` (designs earned once and kept, e.g. 'sunset').
class CardDesignService {
  CardDesignService._();

  static DocumentReference<Map<String, dynamic>> _user(String uid) =>
      BalanceService.db.collection('users').doc(uid);

  /// The streak (in days) that unlocks [design], or null if it isn't
  /// unlocked by a streak.
  static int? streakNeeded(CardDesign design) {
    switch (design.id) {
      case 'emerald':
        return 7;
      case 'metal':
        return 30;
      default:
        return null;
    }
  }

  /// Your longest streak so far, from `users/{uid}`.
  static int bestStreak(Map<String, dynamic>? user) =>
      (BalanceService.number(user?['best_streak']) ?? 0).round();

  /// How far your longest streak is towards unlocking [design]: 0 to 1, or
  /// null if it isn't unlocked by a streak.
  static double? unlockProgress(CardDesign design, Map<String, dynamic>? user) {
    final needed = streakNeeded(design);
    if (needed == null) return null;
    return (bestStreak(user) / needed).clamp(0.0, 1.0).toDouble();
  }

  /// Days of streak still to go before [design] unlocks (0 once it's
  /// reached), or null if it isn't unlocked by a streak.
  static int? daysToUnlock(CardDesign design, Map<String, dynamic>? user) {
    final needed = streakNeeded(design);
    if (needed == null) return null;
    final left = needed - bestStreak(user);
    return left > 0 ? left : 0;
  }

  /// Whether Premium is active, from the `premium_until` date the server
  /// keeps on `users/{uid}` (readable by friends, so they see your design).
  static bool hasPremium(Map<String, dynamic>? user, {DateTime? now}) {
    final until = user?['premium_until'];
    return until is Timestamp &&
        until.toDate().isAfter(now ?? BalanceService.now());
  }

  static bool isUnlocked(CardDesign design, Map<String, dynamic>? user) {
    if (design.premium) return hasPremium(user);
    final best = bestStreak(user);
    final unlocks = user?['card_unlocks'];
    final earned = unlocks is List && unlocks.contains(design.id);
    final needed = streakNeeded(design);
    if (needed != null) return best >= needed;
    switch (design.id) {
      case 'sunset':
        return earned;
      default:
        return true;
    }
  }

  /// The design someone is using. Falls back to Midnight if it isn't
  /// unlocked, e.g. a Premium design after Premium has ended.
  static CardDesign designOf(Map<String, dynamic>? user) {
    final chosen = CardDesign.byId(user?['card_design']);
    return isUnlocked(chosen, user) ? chosen : CardDesign.midnight;
  }

  static Stream<CardDesign> watch(String uid) =>
      _user(uid).snapshots().map((s) => designOf(s.data()));

  static Future<void> choose(String uid, CardDesign design) =>
      _user(uid).set({'card_design': design.id}, SetOptions(merge: true));

  /// Remembers your longest streak (it unlocks designs).
  static Future<void> recordStreak(String uid, int streak) async {
    if (streak <= 0) return;
    final ref = _user(uid);
    await BalanceService.db.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      final best = (BalanceService.number(snap.data()?['best_streak']) ?? 0);
      if (streak > best) {
        tx.set(ref, {'best_streak': streak}, SetOptions(merge: true));
      }
    });
  }
}
