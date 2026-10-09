import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/pages/auth_page.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/ui/adaptive_frame.dart';
import 'package:namer_app/ui/responsive.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
      child: MaterialApp(
        title: 'The Calorie Card',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            primary: AppColors.primary,
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: AppColors.canvas,
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
          ),
          // Sheets and dialogs shouldn't stretch across a whole monitor.
          bottomSheetTheme: const BottomSheetThemeData(
            constraints: BoxConstraints(maxWidth: 640),
          ),
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
          ),
        ),
        // Phones: full screen. Signed-out pages on big screens: framed next
        // to a brand panel. Signed in on big screens: the shell's desktop
        // layout takes over.
        builder: (context, child) =>
            AdaptiveFrame(child: child ?? const SizedBox.shrink()),
        home: const AuthPage(),
      ),
    );
  }
}
