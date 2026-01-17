import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/pages/login_or_register_page.dart';
import 'package:namer_app/pages/user_settings_page.dart';
import 'package:namer_app/pages/home_page.dart';
import 'package:namer_app/pages/recipes_page.dart';

class MenuPage extends StatelessWidget {
  final bool hideNav;

  const MenuPage({Key? key, this.hideNav = false}) : super(key: key);

  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const LoginOrRegisterPage(),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.indigo.shade50,
              Colors.blue.shade50,
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Edit Profile
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(Icons.edit, color: Color(0xFF6366F1)),
                title: const Text(
                  'Edit Profile',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserSettingsPage(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Logout
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Logout',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () async {
                  await _logout(context);
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: hideNav
          ? null
          : Container(
              color: Colors.white,
              height: 56,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right:
                              BorderSide(color: Colors.grey.shade200, width: 1),
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.person,
                            size: 24, color: Color(0xFF6366F1)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const HomePage()),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                                color: Colors.grey.shade200, width: 1),
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.credit_card, size: 24),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RecipesPage()),
                        );
                      },
                      child: Container(
                        child: const Center(
                          child: Icon(Icons.restaurant, size: 24),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
