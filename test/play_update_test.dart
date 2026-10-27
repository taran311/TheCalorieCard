import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/play_update.dart';

void main() {
  final now = DateTime(2026, 10, 28, 9);

  group('PlayUpdate.shouldOffer', () {
    bool offer({
      bool available = true,
      int? days = 8,
      bool flexible = true,
      DateTime? snoozedAt,
    }) =>
        PlayUpdate.shouldOffer(
          available: available,
          stalenessDays: days,
          flexibleAllowed: flexible,
          snoozedAt: snoozedAt,
          now: now,
        );

    test('only once an update has waited a week', () {
      expect(offer(days: 8), isTrue);
      expect(offer(days: 7), isTrue);
      expect(offer(days: 6), isFalse, reason: 'auto-update usually gets it');
      expect(offer(days: null), isFalse);
    });

    test('not without an update, or if Play won\'t do it in the background',
        () {
      expect(offer(available: false), isFalse);
      expect(offer(flexible: false), isFalse);
    });

    test('"Later" hides it for a week', () {
      expect(offer(snoozedAt: now.subtract(const Duration(days: 2))), isFalse);
      expect(offer(snoozedAt: now.subtract(const Duration(days: 7))), isTrue);
    });
  });

  group('PlayUpdate.isTooOld', () {
    test('older than the minimum set on the server', () {
      expect(PlayUpdate.isTooOld(thisBuild: 19, minBuild: 20), isTrue);
      expect(PlayUpdate.isTooOld(thisBuild: 20, minBuild: 20), isFalse);
      expect(PlayUpdate.isTooOld(thisBuild: 25, minBuild: 20), isFalse);
    });

    test('never when no minimum is set or the build is unknown', () {
      expect(PlayUpdate.isTooOld(thisBuild: 3, minBuild: 0), isFalse);
      expect(PlayUpdate.isTooOld(thisBuild: null, minBuild: 20), isFalse);
    });
  });
}
