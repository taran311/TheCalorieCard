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

  static bool isUnlocked(CardDesign design, Map<String, dynamic>? user) {
    final best = (BalanceService.number(user?['best_streak']) ?? 0).round();
    final unlocks = user?['card_unlocks'];
    final earned = unlocks is List && unlocks.contains(design.id);
    switch (design.id) {
      case 'emerald':
        return best >= 7;
      case 'metal':
        return best >= 30;
      case 'sunset':
        return earned;
      default:
        return true;
    }
  }

  /// The design someone is using (falls back to Midnight if they've
  /// somehow picked one that isn't unlocked).
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
