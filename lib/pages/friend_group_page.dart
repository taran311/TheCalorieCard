import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/pages/achievements_page.dart';
import 'package:namer_app/pages/home_page.dart';
import 'package:namer_app/pages/messages_page.dart';

class FriendGroupPage extends StatefulWidget {
  final String groupId;
  final String groupName;

  const FriendGroupPage({
    Key? key,
    required this.groupId,
    required this.groupName,
  }) : super(key: key);

  @override
  State<FriendGroupPage> createState() => _FriendGroupPageState();
}

class _FriendGroupPageState extends State<FriendGroupPage> {
  String _truncateName(String email) {
    final username = email.split('@').first;
    if (username.length <= 15) {
      return username;
    }
    return '${username.substring(0, 15)}...';
  }

  Future<void> _startGroupChat(List<String> memberIds) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      // Use group ID as conversation ID
      final conversationId = 'group_${widget.groupId}';

      // Check if conversation already exists
      final conversationDoc = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) {
        // Create new group conversation
        Map<String, int> unreadCount = {};
        for (final memberId in memberIds) {
          unreadCount[memberId] = 0;
        }

        await FirebaseFirestore.instance
            .collection('conversations')
            .doc(conversationId)
            .set({
          'participant_ids': memberIds,
          'conversation_name': widget.groupName,
          'is_group': true,
          'group_id': widget.groupId,
          'created_at': FieldValue.serverTimestamp(),
          'last_message': '',
          'last_message_time': FieldValue.serverTimestamp(),
          'unread_count': unreadCount,
        });
      }

      // Navigate to chat
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailPage(
              conversationId: conversationId,
              conversationName: widget.groupName,
              isGroup: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting chat: $e')),
        );
      }
    }
  }

  Future<void> _startChatWithMember(String memberId, String memberEmail) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      // Create a sorted list to ensure consistent conversation ID
      final participantIds = [currentUserId, memberId]..sort();
      final conversationId = '${participantIds[0]}_${participantIds[1]}';

      // Check if conversation already exists
      final conversationDoc = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) {
        // Create new conversation
        await FirebaseFirestore.instance
            .collection('conversations')
            .doc(conversationId)
            .set({
          'participant_ids': participantIds,
          'conversation_name': memberEmail.split('@')[0],
          'is_group': false,
          'created_at': FieldValue.serverTimestamp(),
          'last_message': '',
          'last_message_time': FieldValue.serverTimestamp(),
          'unread_count': {
            currentUserId: 0,
            memberId: 0,
          },
        });
      }

      // Navigate to chat
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailPage(
              conversationId: conversationId,
              conversationName: memberEmail.split('@')[0],
              isGroup: false,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting chat: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(8, topPadding + 8, 8, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).maybePop();
                    },
                    icon: const Icon(Icons.arrow_back),
                    color: Colors.white,
                    splashRadius: 20,
                    tooltip: 'Back',
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        widget.groupName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('friend_groups')
                        .doc(widget.groupId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const SizedBox(width: 48);
                      }

                      final groupData =
                          snapshot.data!.data() as Map<String, dynamic>?;
                      final memberIds =
                          (groupData?['members'] as List?)?.cast<String>() ??
                              [];

                      return IconButton(
                        onPressed: memberIds.isEmpty
                            ? null
                            : () => _startGroupChat(memberIds),
                        icon: const Icon(Icons.chat_bubble_outline),
                        color: Colors.white,
                        splashRadius: 20,
                        tooltip: 'Group Chat',
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('friend_groups')
                    .doc(widget.groupId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const Center(child: Text('Group not found'));
                  }

                  final groupData =
                      snapshot.data!.data() as Map<String, dynamic>;
                  final memberIds =
                      (groupData['members'] as List?)?.cast<String>() ?? [];

                  if (memberIds.isEmpty) {
                    return const Center(
                        child: Text('No members in this group'));
                  }

                  return Column(
                    children: [
                      Expanded(
                        child: StreamBuilder<List<Map<String, dynamic>>>(
                          stream: _getMemberConsumptionStream(memberIds),
                          builder: (context, consumptionSnapshot) {
                            if (!consumptionSnapshot.hasData) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }

                            var members = consumptionSnapshot.data!;

                            return ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: members.length,
                              itemBuilder: (context, index) {
                                final memberData = members[index];
                                final memberId = memberData['userId'] as String;
                                final memberEmail =
                                    memberData['email'] as String;
                                final calories =
                                    memberData['consumed_calories'] as double;
                                final protein =
                                    memberData['consumed_protein'] as double;
                                final carbs =
                                    memberData['consumed_carbs'] as double;
                                final fats =
                                    memberData['consumed_fats'] as double;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            // Avatar
                                            Container(
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    const Color(0xFF6366F1),
                                                    const Color(0xFF8B5CF6),
                                                  ],
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  memberEmail
                                                      .substring(0, 1)
                                                      .toUpperCase(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    _truncateName(memberEmail),
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(0xFF1F2937),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Today\'s Consumption',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          Colors.grey.shade600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        // Nutrition Info
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade50,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: Colors.grey.shade200,
                                              width: 1,
                                            ),
                                          ),
                                          child: Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              _buildNutritionChip(
                                                '${calories.toStringAsFixed(0)} cal',
                                                Colors.orange.shade600,
                                              ),
                                              _buildNutritionChip(
                                                '${protein.toStringAsFixed(0)}g protein',
                                                Colors.red.shade600,
                                              ),
                                              _buildNutritionChip(
                                                '${carbs.toStringAsFixed(0)}g carbs',
                                                Colors.blue.shade600,
                                              ),
                                              _buildNutritionChip(
                                                '${fats.toStringAsFixed(0)}g fat',
                                                Colors.green.shade600,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        // Action Icons Row (horizontal like bottom nav)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 8),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              top: BorderSide(
                                                color: Colors.grey.shade200,
                                                width: 1,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceEvenly,
                                            children: [
                                              IconButton(
                                                onPressed: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => HomePage(
                                                        readOnly: true,
                                                        hideNav: true,
                                                        userIdOverride:
                                                            memberId,
                                                        showBanner: true,
                                                        bannerTitle:
                                                            memberEmail,
                                                      ),
                                                    ),
                                                  );
                                                },
                                                icon: const Icon(
                                                  Icons.credit_card,
                                                  color: Color(0xFF6366F1),
                                                  size: 24,
                                                ),
                                                tooltip: 'View Card',
                                              ),
                                              IconButton(
                                                onPressed: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          AchievementsPage(
                                                        userIdOverride:
                                                            memberId,
                                                        titleOverride:
                                                            '$memberEmail\'s Achievements',
                                                      ),
                                                    ),
                                                  );
                                                },
                                                icon: const Icon(
                                                  Icons.emoji_events,
                                                  color: Color(0xFFF59E0B),
                                                  size: 24,
                                                ),
                                                tooltip: 'Achievements',
                                              ),
                                              IconButton(
                                                onPressed: () {
                                                  _startChatWithMember(
                                                      memberId, memberEmail);
                                                },
                                                icon: const Icon(
                                                  Icons.chat_bubble_outline,
                                                  color: Color(0xFF10B981),
                                                  size: 24,
                                                ),
                                                tooltip: 'Chat',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Stream<List<Map<String, dynamic>>> _getMemberConsumptionStream(
      List<String> memberIds) {
    if (memberIds.isEmpty) {
      return Stream.value([]);
    }

    // Listen to all user_food changes for all members
    return FirebaseFirestore.instance
        .collection('user_food')
        .where('user_id', whereIn: memberIds)
        .snapshots()
        .asyncMap((snapshot) async {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Group food items by user
      Map<String, List<QueryDocumentSnapshot>> userFoodMap = {};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final userId = data['user_id'] as String?;

        if (userId != null) {
          // Extract date from time_added or created_at
          DateTime? docDate;
          final timeAdded = data['time_added'];
          final createdAt = data['created_at'];

          if (timeAdded is Timestamp) {
            docDate = timeAdded.toDate();
          } else if (timeAdded is DateTime) {
            docDate = timeAdded;
          } else if (createdAt is Timestamp) {
            docDate = createdAt.toDate();
          } else if (createdAt is DateTime) {
            docDate = createdAt;
          }

          // Only include items from today
          if (docDate != null &&
              !docDate.isBefore(startOfDay) &&
              docDate.isBefore(endOfDay)) {
            userFoodMap.putIfAbsent(userId, () => []).add(doc);
          }
        }
      }

      // Build member data list
      final List<Map<String, dynamic>> memberData = [];

      for (final memberId in memberIds) {
        try {
          // Fetch user email
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(memberId)
              .get();

          final email = userDoc.data()?['email'] ?? 'Unknown';

          // Calculate consumed values from today's food items
          double consumedCalories = 0;
          double consumedProtein = 0;
          double consumedCarbs = 0;
          double consumedFats = 0;

          final userFoodDocs = userFoodMap[memberId] ?? [];
          for (final doc in userFoodDocs) {
            final data = doc.data() as Map<String, dynamic>;
            consumedCalories +=
                (data['food_calories'] as num?)?.toDouble() ?? 0;
            consumedProtein += (data['food_protein'] as num?)?.toDouble() ?? 0;
            consumedCarbs += (data['food_carbs'] as num?)?.toDouble() ?? 0;
            consumedFats += (data['food_fat'] as num?)?.toDouble() ?? 0;
          }

          memberData.add({
            'userId': memberId,
            'email': email,
            'consumed_calories': consumedCalories,
            'consumed_protein': consumedProtein,
            'consumed_carbs': consumedCarbs,
            'consumed_fats': consumedFats,
          });
        } catch (e) {
          // Error fetching member data
        }
      }

      return memberData;
    });
  }

  Widget _buildNutritionChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color.withOpacity(0.9),
        ),
      ),
    );
  }
}
