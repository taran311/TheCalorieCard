import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/components/my_button.dart';
import 'package:namer_app/components/my_text_field.dart';

class RegisterPage extends StatefulWidget {
  final Function()? onTap;

  RegisterPage({super.key, required this.onTap});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  bool isLoading = false;

  Future<void> signUserUp() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      await showErrorDialog("Email and Password cannot be empty");
      return;
    }

    if (passwordController.text != confirmPasswordController.text) {
      await showErrorDialog("Passwords don't match");
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      if (mounted) {
        setState(() {
          isLoading = false;
        });
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        await showErrorDialog(getErrorMessage(e.code));
      }
    }
  }

  Future<void> showErrorDialog(String message) async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.amber[900],
          title: Text(
            message,
            style: TextStyle(color: Colors.white),
          ),
        );
      },
    );
  }

  String getErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already in use.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password is too weak.';
      default:
        return 'An unknown error occurred.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.credit_card, size: 70),
                    SizedBox(width: 10),
                    Text('TheCalorieCard', style: TextStyle(fontSize: 35)),
                  ],
                ),
                SizedBox(height: 50),
                Text(
                  'Let\'s create an account for you!',
                  style: TextStyle(color: Colors.white),
                ),
                SizedBox(height: 25),
                MyTextField(
                  controller: emailController,
                  hintText: 'Email',
                  obscureText: false,
                ),
                SizedBox(height: 10),
                MyTextField(
                  controller: passwordController,
                  hintText: 'Password',
                  obscureText: true,
                ),
                SizedBox(height: 10),
                MyTextField(
                  controller: confirmPasswordController,
                  hintText: 'Confirm Password',
                  obscureText: true,
                ),
                SizedBox(height: 25),
                isLoading
                    ? CircularProgressIndicator(color: Colors.white)
                    : MyButton(
                        onTap: () async {
                          await signUserUp();
                        },
                        text: 'Sign Up',
                      ),
                SizedBox(height: 50),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account?',
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: widget.onTap,
                      child: Text(
                        'Login now',
                        style: TextStyle(
                          color: Colors.blue[900],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
