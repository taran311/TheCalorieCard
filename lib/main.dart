import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/pages/auth_page.dart';
import 'package:namer_app/pages/email_action_page.dart';
import 'package:namer_app/services/app_update.dart';
import 'package:namer_app/services/auth_services.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/services/web_platform.dart' as web;
import 'package:namer_app/ui/adaptive_frame.dart';
import 'package:namer_app/ui/gift_claim.dart';
import 'package:namer_app/ui/theme_controller.dart';
import 'package:namer_app/ui/update_banner.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await ThemeController.instance.load();
  // ?facebook=1 shows Facebook sign-in before it's live (for testing).
  AuthService.readUrlFlags();
  // A gift link (?gift=…): remembered until they're signed in to claim it.
  await PendingGift.captureFromUrl();
  // Just refreshed to a new version (?refresh=…): tidy the address bar.
  final query = Uri.base.queryParameters;
  if (query.length == 1 && query.containsKey('refresh')) web.clearUrlQuery();
  runApp(const MyApp());
  // "A new version is ready · Refresh" when a newer deploy is live.
  AppUpdate.start();
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
          builder: (context, child) => UpdateBanner(
              child: AdaptiveFrame(child: child ?? const SizedBox.shrink())),
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
