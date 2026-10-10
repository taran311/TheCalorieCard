import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/pages/auth_page.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/ui/adaptive_frame.dart';
import 'package:namer_app/ui/theme_controller.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await ThemeController.instance.load();
  runApp(const MyApp());
}

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
          home: const AuthPage(),
        ),
      ),
    );
  }
}
