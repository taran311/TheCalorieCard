import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
                      // Group Balance Stats
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _getGroupDailyLogsStream(memberIds),
                        builder: (context, logsSnapshot) {
                          if (!logsSnapshot.hasData) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Card(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                ),
                              ),
                            );
                          }

                          final logs = logsSnapshot.data!;
                          double totalCaloriesBalance = 0;
                          double totalProteinBalance = 0;
                          double totalCarbsBalance = 0;
                          double totalFatsBalance = 0;

                          for (var data in logs) {
                            final balances =
                                data['balances'] as Map<String, dynamic>?;
                            if (balances != null) {
                              totalCaloriesBalance +=
                                  (balances['calories'] as num?)?.toDouble() ??
                                      0;
                              totalProteinBalance +=
                                  (balances['protein_balance'] as num?)
                                          ?.toDouble() ??
                                      0;
                              totalCarbsBalance +=
                                  (balances['carbs_balance'] as num?)
                                          ?.toDouble() ??
                                      0;
                              totalFatsBalance +=
                                  (balances['fats_balance'] as num?)
                                          ?.toDouble() ??
                                      0;
                            }
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Group Balance (Today)',
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        _buildBalanceItem(
                                          'Calories',
                                          totalCaloriesBalance,
                                          Colors.orange.shade600,
                                        ),
                                        _buildBalanceItem(
                                          'Protein',
                                          totalProteinBalance,
                                          Colors.red.shade600,
                                        ),
                                        _buildBalanceItem(
                                          'Carbs',
                                          totalCarbsBalance,
                                          Colors.blue.shade600,
                                        ),
                                        _buildBalanceItem(
                                          'Fats',
                                          totalFatsBalance,
                                          Colors.green.shade600,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: memberIds.length,
                          itemBuilder: (context, index) {
                            final memberId = memberIds[index];

                            return FutureBuilder<DocumentSnapshot>(
                              future: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(memberId)
                                  .get(),
                              builder: (context, userSnapshot) {
                                if (!userSnapshot.hasData) {
                                  return const SizedBox.shrink();
                                }

                                final memberEmail =
                                    userSnapshot.data?.get('email') ??
                                        'Unknown';

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          memberEmail,
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => HomePage(
                                                readOnly: true,
                                                hideNav: true,
                                                userIdOverride: memberId,
                                                showBanner: true,
                                                bannerTitle: memberEmail,
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.credit_card,
                                          color: Color(0xFF6366F1),
                                        ),
                                        tooltip: 'View card',
                                      ),
                                      IconButton(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => AchievementsPage(
                                                userIdOverride: memberId,
                                                titleOverride:
                                                    '$memberEmail\'s Achievements',
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.emoji_events,
                                          color: Color(0xFFF59E0B),
                                        ),
                                        tooltip: 'View achievements',
                                      ),
                                    ],
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

  static Stream<List<Map<String, dynamic>>> _getGroupDailyLogsStream(
      List<String> memberIds) {
    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    if (memberIds.isEmpty) {
      return Stream.value([]);
    }

    // Fetch all member daily logs or user_data and emit whenever any changes
    return Stream.periodic(const Duration(milliseconds: 500))
        .asyncExpand((_) async* {
      final List<Map<String, dynamic>> memberBalances = [];

      for (final memberId in memberIds) {
        try {
          // First try to get daily_logs
          final dailyLogDoc = await FirebaseFirestore.instance
              .collection('daily_logs')
              .doc('${memberId}_$dateKey')
              .get();

          if (dailyLogDoc.exists) {
            // Use balance from daily_logs if it exists
            memberBalances.add(dailyLogDoc.data() as Map<String, dynamic>);
          } else {
            // Fall back to user_data if no daily log exists yet
            final userDataSnapshot = await FirebaseFirestore.instance
                .collection('user_data')
                .where('user_id', isEqualTo: memberId)
                .limit(1)
                .get();

            if (userDataSnapshot.docs.isNotEmpty) {
              final userData = userDataSnapshot.docs.first.data();
              // Create a balance object from user_data
              memberBalances.add({
                'balances': {
                  'calories': userData['calories'],
                  'protein_balance': userData['protein_balance'],
                  'carbs_balance': userData['carbs_balance'],
                  'fats_balance': userData['fats_balance'],
                },
              });
            }
          }
        } catch (e) {
          print('Error fetching balance for $memberId: $e');
        }
      }

      yield memberBalances;
    });
  }

  static Widget _buildBalanceItem(String label, double value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value.toStringAsFixed(0),
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
