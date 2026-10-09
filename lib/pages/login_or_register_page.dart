import 'package:flutter/material.dart';
import 'package:namer_app/pages/login_page.dart';
import 'package:namer_app/pages/register_page.dart';

/// Sign-in and sign-up share this spot; the switch fades between them.
class LoginOrRegisterPage extends StatefulWidget {
  const LoginOrRegisterPage({super.key});

  @override
  State<LoginOrRegisterPage> createState() => _LoginOrRegisterPageState();
}

class _LoginOrRegisterPageState extends State<LoginOrRegisterPage> {
  bool showLoginPage = true;

  void togglePages() {
    setState(() {
      showLoginPage = !showLoginPage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: showLoginPage
          ? LoginPage(key: const ValueKey('signin'), onTap: togglePages)
          : RegisterPage(key: const ValueKey('signup'), onTap: togglePages),
    );
  }
}
