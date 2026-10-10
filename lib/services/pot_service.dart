import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/achievement_service.dart';
import 'package:namer_app/services/balance_service.dart';

/// Moving part of the pot onto today's card (and undoing that).
///
/// Mirrors [BalanceService.spendPot] field for field (`pot`, `calories`,
/// `pot_spent`, `pot_spent_date`), so the daily reset and pot savings treat
/// a part move exactly like moving the whole pot.
class PotService {
  PotService._();

  /// What "Move to today's card" suggests: a treat-sized amount, or the
  /// whole pot if it's smaller.
  static const double suggestedMove = 250;

  static double suggestedAmount(double pot) =>
      pot <= 0 ? 0 : (pot < suggestedMove ? pot : suggestedMove);

  /// Moves up to [amount] kcal from this week's pot onto today's card.
  /// Returns how much was actually moved (never more than the pot holds).
  static Future<double> move(String userId, double amount) async {
    if (!amount.isFinite || amount <= 0) return 0;
    await BalanceService.ensureDailyReset(userId);
    final doc = await BalanceService.userDataDoc(userId);
    if (doc == null) return 0;
    final today = BalanceService.dateKey(BalanceService.now());
    final moved = await BalanceService.db.runTransaction<double>((tx) async {
      final snap = await tx.get(doc.reference);
      final data = snap.data() ?? const <String, dynamic>{};
      final pot = BalanceService.potFrom(data);
      if (pot <= 0) return 0;
      final take = amount > pot ? pot : amount;
      tx.update(doc.reference, {
        'pot': pot - take,
        'calories': FieldValue.increment(take),
        'pot_spent': _spentToday(data, today) + take,
        'pot_spent_date': today,
      });
      return take;
    });
    // "Treat Yourself" achievement.
    if (moved > 0) await AchievementService.bump(userId, 'pot_spends');
    return moved;
  }

  /// Puts [amount] moved earlier today back into the pot. Returns false
  /// (and changes nothing) if the day has moved on since, or that much
  /// isn't on today's card from the pot any more.
  static Future<bool> undoMove(String userId, double amount) async {
    if (!amount.isFinite || amount <= 0) return false;
    final doc = await BalanceService.userDataDoc(userId);
    if (doc == null) return false;
    final today = BalanceService.dateKey(BalanceService.now());
    return BalanceService.db.runTransaction<bool>((tx) async {
      final snap = await tx.get(doc.reference);
      final data = snap.data() ?? const <String, dynamic>{};
      if (data['pots_enabled'] != true ||
          data['balance_date'] != today ||
          data['pot_week'] != BalanceService.weekKey(BalanceService.now())) {
        return false;
      }
      final spent = _spentToday(data, today);
      if (spent + 0.001 < amount) return false;
      tx.update(doc.reference, {
        'pot': BalanceService.potFrom(data) + amount,
        'calories': FieldValue.increment(-amount),
        'pot_spent': spent - amount,
        'pot_spent_date': today,
      });
      return true;
    });
  }

  static double _spentToday(Map<String, dynamic> data, String today) =>
      data['pot_spent_date'] == today
          ? (BalanceService.number(data['pot_spent']) ?? 0)
          : 0;
}
