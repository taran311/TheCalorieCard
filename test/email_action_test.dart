import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/pages/email_action_page.dart';

void main() {
  test('reads Firebase email links', () {
    final a = EmailAction.fromUri(Uri.parse(
        'https://thecaloriecard.com/?mode=verifyEmail&oobCode=abc123&apiKey=k&lang=en'));
    expect(a?.mode, 'verifyEmail');
    expect(a?.code, 'abc123');

    expect(
        EmailAction.fromUri(Uri.parse(
                'https://thecaloriecard.com/?mode=resetPassword&oobCode=x'))
            ?.mode,
        'resetPassword');
  });

  test('ignores everything else', () {
    expect(EmailAction.fromUri(Uri.parse('https://thecaloriecard.com/')),
        isNull);
    expect(
        EmailAction.fromUri(
            Uri.parse('https://thecaloriecard.com/?mode=verifyEmail')),
        isNull);
    expect(
        EmailAction.fromUri(
            Uri.parse('https://thecaloriecard.com/?mode=signIn&oobCode=x')),
        isNull);
    expect(
        EmailAction.fromUri(Uri.parse('https://thecaloriecard.com/?game=g1')),
        isNull);
  });
}
