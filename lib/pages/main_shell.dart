import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:namer_app/pages/home_page.dart';
import 'package:namer_app/pages/menu_page.dart';
import 'package:namer_app/pages/messages_page.dart';
import 'package:namer_app/pages/recipes_page.dart';

class MainShell extends StatefulWidget {
  final int initialIndex;

  const MainShell({super.key, this.initialIndex = 1});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 3);
  }

  void _onTap(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      MenuPage(hideNav: true),
      const HomePage(hideNav: true),
      const RecipesPage(hideNav: true),
      const MessagesPage(hideNav: true),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        height: 56,
        child: Row(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('friend_requests')
                    .where('to_user_id',
                        isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                    .where('status', isEqualTo: 'pending')
                    .snapshots(),
                builder: (context, snapshot) {
                  final pendingCount = snapshot.data?.docs.length ?? 0;

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _onTap(0),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right:
                              BorderSide(color: Colors.grey.shade200, width: 1),
                        ),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Icon(
                              Icons.person,
                              size: 24,
                              color: _currentIndex == 0
                                  ? const Color(0xFF6366F1)
                                  : Colors.black,
                            ),
                          ),
                          if (pendingCount > 0)
                            Positioned(
                              right: 2,
                              top: 2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                child: Text(
                                  pendingCount.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onTap(1),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: Colors.grey.shade200, width: 1),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.credit_card,
                      size: 24,
                      color: _currentIndex == 1
                          ? const Color(0xFF6366F1)
                          : Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onTap(2),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: Colors.grey.shade200, width: 1),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.restaurant,
                      size: 24,
                      color: _currentIndex == 2
                          ? const Color(0xFF6366F1)
                          : Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('conversations')
                    .where('participant_ids',
                        arrayContains:
                            FirebaseAuth.instance.currentUser?.uid ?? '')
                    .snapshots(),
                builder: (context, snapshot) {
                  int unreadCount = 0;
                  if (snapshot.hasData) {
                    final currentUserId =
                        FirebaseAuth.instance.currentUser?.uid;
                    for (final doc in snapshot.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final unreadMap =
                          data['unread_count'] as Map<String, dynamic>?;
                      unreadCount += (unreadMap?[currentUserId] as int?) ?? 0;
                    }
                  }

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _onTap(3),
                    child: Stack(
                      children: [
                        Center(
                          child: Icon(
                            Icons.chat_bubble_outline,
                            size: 24,
                            color: _currentIndex == 3
                                ? const Color(0xFF6366F1)
                                : Colors.black,
                          ),
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            right: 2,
                            top: 2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              child: Text(
                                unreadCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
