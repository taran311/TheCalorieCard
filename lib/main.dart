import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/pages/auth_page.dart';
import 'package:namer_app/pages/email_action_page.dart';
import 'package:namer_app/services/app_update.dart';
import 'package:namer_app/services/auth_services.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/services/session_hint.dart';
import 'package:namer_app/services/web_platform.dart' as web;
import 'package:namer_app/ui/adaptive_frame.dart';
import 'package:namer_app/ui/gift_claim.dart';
import 'package:namer_app/ui/theme_controller.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ?facebook=1 shows Facebook sign-in before it's live (for testing).
  // Read first: a gift link below tidies the address bar.
  AuthService.readUrlFlags();
  // These don't depend on each other, so start them together rather than
  // one after another (a quicker start).
  await Future.wait([
    _startFirebase(),
    ThemeController.instance.load(),
    // A gift link (?gift=…): remembered until they're signed in to claim it.
    PendingGift.captureFromUrl(),
    // Was this device signed in? Then a refresh waits for the session
    // rather than flashing the sign-in page.
    SessionHint.load(),
  ]);
  // Just refreshed to a new version (?refresh=…): tidy the address bar.
  final query = Uri.base.queryParameters;
  if (query.length == 1 && query.containsKey('refresh')) web.clearUrlQuery();
  runApp(const MyApp());
  // Moves to a newer deploy quietly, when nothing would be lost.
  AppUpdate.start();
}

/// Starts Firebase. On Android it has usually started already, from
/// google-services.json: if that copy's settings differ slightly from
/// [DefaultFirebaseOptions], Firebase reports "duplicate-app". That's
/// harmless (the app is running), so carry on rather than stop on the
/// opening screen.
Future<void> _startFirebase() async {
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
}

/// Read once at start-up (the page clears it from the address bar).
final EmailAction? _emailAction = EmailAction.current;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CategoryService()),
      ],
      // Rebuilds with the new colours when light/dark changes.
      child: ListenableBuilder(
        listenable: ThemeController.instance,
        builder: (context, _) => MaterialApp(
          title: 'The Calorie Card',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          // Lets mouse and trackpad users drag sideways lists (inbox,
          // suggestion chips, recents) on the web, not just touch.
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            dragDevices: PointerDeviceKind.values.toSet(),
          ),
          // Phones: full screen. Signed-out pages on big screens: framed
          // next to a brand panel. Signed in on big screens: the shell's
          // desktop layout takes over.
          builder: (context, child) =>
              AdaptiveFrame(child: child ?? const SizedBox.shrink()),
          // Lets a waiting update load quietly only when nothing is open.
          navigatorObservers: [AppUpdate.rootWatch],
          // A link from one of our emails (verify, reset password…) is
          // handled first, then carries on into the app.
          home: _emailAction == null
              ? const AuthPage()
              : EmailActionPage(action: _emailAction!),
        ),
      ),
    );
  }
}
