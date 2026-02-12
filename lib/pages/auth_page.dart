import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/pages/get_started_page.dart';
import 'package:namer_app/pages/main_shell.dart';
import 'package:namer_app/pages/login_or_register_page.dart';

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  Future<bool> checkIfUserExists(String userId) async {
    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: userId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return FutureBuilder<bool>(
              future: checkIfUserExists(FirebaseAuth.instance.currentUser!.uid),
              builder: (context, AsyncSnapshot<bool> userExistsSnapshot) {
                if (userExistsSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (userExistsSnapshot.hasData &&
                    userExistsSnapshot.data == true) {
                  return const MainShell(initialIndex: 1);
                } else {
                  return GetStartedPage();
                }
              },
            );
          } else {
            return LoginOrRegisterPage();
          }
        },
      ),
    );
  }
}
