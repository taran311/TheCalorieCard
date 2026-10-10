// Premium: who has it, and the Premium-only card design.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/card_design_service.dart';
import 'package:namer_app/services/premium_service.dart';
import 'package:namer_app/ui/calorie_card.dart';

void main() {
  final now = DateTime.now();
  Timestamp days(int n) => Timestamp.fromDate(now.add(Duration(days: n)));

  group('Entitlement', () {
    test('not loaded yet: nothing is locked', () {
      expect(Entitlement.unknown.isPremium, isTrue);
      expect(Entitlement.unknown.trialEnded, isFalse);
    });

    test('in the free trial', () {
      final e = Entitlement.fromMap({'trial_ends_at': days(10)});
      expect(e.isPremium, isTrue);
      expect(e.inTrial, isTrue);
      expect(e.subscribed, isFalse);
      expect(e.trialDaysLeft, inInclusiveRange(10, 11));
    });

    test('trial over and no plan: free', () {
      final e = Entitlement.fromMap({'trial_ends_at': days(-1)});
      expect(e.isPremium, isFalse);
      expect(e.trialEnded, isTrue);
      expect(e.trialDaysLeft, 0);
    });

    test('subscribed, including while a payment is being retried', () {
      for (final status in ['active', 'trialing', 'past_due']) {
        final e = Entitlement.fromMap({
          'status': status,
          'current_period_end': days(20),
          'trial_ends_at': days(-5),
        });
        expect(e.isPremium, isTrue, reason: status);
        expect(e.trialEnded, isFalse, reason: status);
      }
    });

    test('cancelled subscriptions end', () {
      final e = Entitlement.fromMap({
        'status': 'canceled',
        'current_period_end': days(20),
        'trial_ends_at': days(-40),
      });
      expect(e.isPremium, isFalse);
    });
  });

  group('Aurora card design', () {
    test('only while Premium', () {
      final premium = {'premium_until': days(3), 'card_design': 'aurora'};
      expect(CardDesignService.isUnlocked(CardDesign.aurora, premium), isTrue);
      expect(CardDesignService.designOf(premium).id, 'aurora');
    });

    test('goes back to Midnight when Premium ends', () {
      final lapsed = {'premium_until': days(-1), 'card_design': 'aurora'};
      expect(CardDesignService.isUnlocked(CardDesign.aurora, lapsed), isFalse);
      expect(CardDesignService.designOf(lapsed).id, 'midnight');
      expect(CardDesignService.designOf({'card_design': 'aurora'}).id,
          'midnight');
    });

    test('other designs are unaffected', () {
      expect(
          CardDesignService.isUnlocked(
              CardDesign.midnight, {'premium_until': days(-1)}),
          isTrue);
    });
  });
}
