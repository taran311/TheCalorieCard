import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/app_update.dart';

void main() {
  test('local and test builds never ask to refresh', () {
    // Tests run without --dart-define=BUILD_ID.
    expect(AppUpdate.buildId, isEmpty);
    expect(AppUpdate.isNewer('abc123'), isFalse);
    expect(AppUpdate.isNewer(null), isFalse);
  });
}
