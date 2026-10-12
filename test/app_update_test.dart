import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/app_update.dart';

void main() {
  test('local and test builds never ask to refresh', () {
    // Tests run without --dart-define=BUILD_ID.
    expect(AppUpdate.buildId, isEmpty);
    expect(AppUpdate.isNewer('abc123'), isFalse);
    expect(AppUpdate.isNewer(null), isFalse);
  });

  group('quiet updates', () {
    final now = DateTime(2026, 10, 12, 18, 0);
    bool quiet({
      bool available = true,
      Duration away = const Duration(minutes: 20),
      bool nothingOpen = true,
      int pendingSaves = 0,
    }) =>
        AppUpdate.shouldReloadQuietly(
          available: available,
          hiddenAt: now.subtract(away),
          now: now,
          nothingOpen: nothingOpen,
          pendingSaves: pendingSaves,
        );

    test('reload after a while away with nothing open', () {
      expect(quiet(), isTrue);
    });

    test('never while a page, sheet or dialog is open', () {
      // e.g. halfway through making a recipe
      expect(quiet(nothingOpen: false), isFalse);
    });

    test('never with saves still on their way', () {
      expect(quiet(pendingSaves: 1), isFalse);
    });

    test('not after a quick look away', () {
      expect(quiet(away: const Duration(minutes: 2)), isFalse);
    });

    test('nothing to do without an update', () {
      expect(quiet(available: false), isFalse);
      expect(
          AppUpdate.shouldReloadQuietly(
            available: true,
            hiddenAt: null,
            now: now,
            nothingOpen: true,
            pendingSaves: 0,
          ),
          isFalse);
    });
  });
}
