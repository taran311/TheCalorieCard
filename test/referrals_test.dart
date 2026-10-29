import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/premium_service.dart';
import 'package:namer_app/services/referrals.dart';

void main() {
  group('Refer a friend', () {
    test('reads the server summary, hiding expired invites', () {
      final s = ReferralStatus.fromJson({
        'invitedBy': {'name': 'Taz', 'days': 1, 'status': 'pending'},
        'friends': [
          {'name': 'Sam', 'days': 3, 'status': 'rewarded'},
          {'name': 'Jo', 'days': 2, 'status': 'pending'},
          {'name': 'Old', 'days': 0, 'status': 'expired'},
        ],
        'earned': 1,
        'bonusUntil': '2026-11-28T12:00:00.000Z',
        'rewardDays': 30,
        'daysNeeded': 3,
      });
      expect(s.invitedBy!.name, 'Taz');
      expect(s.invitedBy!.pending, isTrue);
      expect(s.friends.map((f) => f.name), ['Sam', 'Jo']);
      expect(s.friends.first.rewarded, isTrue);
      expect(s.earned, 1);
      expect(s.bonusUntil!.toUtc(), DateTime.utc(2026, 11, 28, 12));
      expect(s.rewardLabel, 'a month');
    });

    test('copes with an empty or odd reply', () {
      final s = ReferralStatus.fromJson({'friends': 'nope'});
      expect(s.invitedBy, isNull);
      expect(s.friends, isEmpty);
      expect(s.bonusUntil, isNull);
      expect(s.daysNeeded, 3);
    });

    test('free time from friends is Premium after the trial ends', () {
      final now = DateTime.now();
      final e = Entitlement.fromMap({
        'trial_ends_at': Timestamp.fromDate(now.subtract(const Duration(days: 2))),
        'bonus_until': Timestamp.fromDate(now.add(const Duration(days: 20))),
      });
      expect(e.isPremium, isTrue);
      expect(e.inBonus, isTrue);
      expect(e.subscribed, isFalse);
      expect(e.trialEnded, isFalse, reason: 'no "trial ended" while free');
      expect(e.bonusCoversTrial, isTrue);
    });

    test('a bonus inside the trial changes nothing about the trial', () {
      final now = DateTime.now();
      final e = Entitlement.fromMap({
        'trial_ends_at': Timestamp.fromDate(now.add(const Duration(days: 10))),
        'bonus_until': Timestamp.fromDate(now.add(const Duration(days: 5))),
      });
      expect(e.inTrial, isTrue);
      expect(e.bonusCoversTrial, isFalse);
    });

    test('an expired bonus is the free plan', () {
      final now = DateTime.now();
      final e = Entitlement.fromMap({
        'trial_ends_at': Timestamp.fromDate(now.subtract(const Duration(days: 40))),
        'bonus_until': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
      });
      expect(e.isPremium, isFalse);
      expect(e.trialEnded, isTrue);
    });
  });
}
