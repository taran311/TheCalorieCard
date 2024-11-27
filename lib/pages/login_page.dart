import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/components/my_button.dart';
import 'package:namer_app/components/my_text_field.dart';
import 'package:namer_app/pages/home_page.dart';

class LoginPage extends StatefulWidget {
  final Function()? onTap;
  LoginPage({super.key, required this.onTap});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();

  final passwordController = TextEditingController();

  Future<void> signUserIn(BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) {
        return Center(child: CircularProgressIndicator());
      },
    );

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text,
        password: passwordController.text,
      );

      if (context.mounted) {
        Navigator.pop(context);
      }

      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomePage()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
      }

      if (e.code == 'invalid-email') {
        if (context.mounted) {
          showErrorDialog('Incorrect Email!');
        }
      } else if (e.code == 'invalid-credential') {
        if (context.mounted) {
          showErrorDialog('Incorrect Password!');
        }
      } else if (e.code == 'channel-error') {
        if (context.mounted) {
          showErrorDialog('Incorrect Email/Password!');
        }
      } else {
        // General error handling
        if (context.mounted) {
          showErrorDialog('An unknown error occurred: ${e.message}');
        }
      }
    }
  }

  void showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.amber[900],
          title: Text(
            error,
            style: TextStyle(color: Colors.white),
          ),
        );
      },
    );
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

                SizedBox(height: 25),

                //welcome back
                Text(
                  'Spend your Calories wisely!',
                  style: TextStyle(color: Colors.white),
                ),

                SizedBox(height: 25),

                //username
                MyTextField(
                  controller: emailController,
                  hintText: 'Username',
                  obscureText: false,
                ),

                SizedBox(height: 10),

                //password
                MyTextField(
                  controller: passwordController,
                  hintText: 'Password',
                  obscureText: true,
                ),

                SizedBox(height: 10),

                //forgot password
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('Forgot Password?',
                          style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),

                SizedBox(height: 25),

                //sign in button
                MyButton(
                    onTap: () async {
                      await signUserIn(context);
                    },
                    text: 'Sign In'),

                const SizedBox(height: 35),

                // Padding(
                //   padding: const EdgeInsets.symmetric(horizontal: 25.0),
                //   child: Row(
                //     children: [
                //       Expanded(
                //         child: Divider(thickness: 0.5, color: Colors.black),
                //       ),
                //       Padding(
                //           padding: EdgeInsets.symmetric(horizontal: 10.0),
                //           child: Text('or continue with')),
                //       Expanded(
                //         child: Divider(thickness: 0.5, color: Colors.black),
                //       )
                //     ],
                //   ),
                // ),

                // const SizedBox(height: 35),

                // Row(
                //   mainAxisAlignment: MainAxisAlignment.center,
                //   children: [
                //     GestureDetector(
                //       onTap: () => {AuthService().signInWithGoogle()},
                //       child: Container(
                //           padding: EdgeInsets.all(20),
                //           decoration: BoxDecoration(
                //               border: Border.all(color: Colors.white),
                //               borderRadius: BorderRadius.circular(16),
                //               color: Colors.grey[200]),
                //           child:
                //               Image.asset('lib/images/google.png', height: 52)),
                //     ),
                //   ],
                // ),

                // SizedBox(height: 42),

                //register
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Not a member?',
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: widget.onTap,
                      child: Text(
                        'Register now',
                        style: TextStyle(
                          color: Colors.blue[900],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
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
