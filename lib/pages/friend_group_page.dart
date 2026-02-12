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
  String? _selectedChallengeType;

  final List<String> _challengeTypes = [
    'Lowest Calories Consumed',
    'Lowest Protein Consumed',
    'Lowest Carbs Consumed',
    'Lowest Fat Consumed',
    'Highest Calories Consumed',
    'Highest Protein Consumed',
    'Highest Carbs Consumed',
    'Highest Fat Consumed',
    'Log Streak',
  ];

  String _truncateName(String email) {
    final username = email.split('@').first;
    if (username.length <= 15) {
      return username;
    }
    return '${username.substring(0, 15)}...';
  }

  Future<void> _updateChallengeType(String? newType) async {
    if (newType == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('friend_groups')
          .doc(widget.groupId)
          .update({'challenge_type': newType});

      setState(() {
        _selectedChallengeType = newType;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating challenge type: $e')),
        );
      }
    }
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

                  // Sync challenge type from group data if it changed
                  final groupChallengeType =
                      groupData['challenge_type'] as String?;
                  if (groupChallengeType != _selectedChallengeType) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _selectedChallengeType = groupChallengeType;
                        });
                      }
                    });
                  }

                  if (memberIds.isEmpty) {
                    return const Center(
                        child: Text('No members in this group'));
                  }

                  return Column(
                    children: [
                      // Challenge Type Dropdown
                      Padding(
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
                                  'Challenge Type',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  value: _selectedChallengeType,
                                  hint: Text(
                                    'Select a challenge',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                  ),
                                  items: _challengeTypes.map((type) {
                                    return DropdownMenuItem(
                                      value: type,
                                      child: Text(
                                        type,
                                        style: TextStyle(fontSize: 14),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: _updateChallengeType,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Rankings Header
                      if (_selectedChallengeType != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Rankings',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF6366F1),
                            ),
                          ),
                        ),
                      if (_selectedChallengeType != null)
                        const SizedBox(height: 8),
                      Expanded(
                        child: StreamBuilder<List<Map<String, dynamic>>>(
                          stream: _getMemberConsumptionStream(memberIds),
                          builder: (context, consumptionSnapshot) {
                            if (!consumptionSnapshot.hasData) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }

                            var members = consumptionSnapshot.data!;

                            // Sort members based on challenge type
                            List<int> ranks = [];
                            if (_selectedChallengeType != null) {
                              members = _sortMembersByChallenge(
                                  members, _selectedChallengeType!);
                              // Calculate ranks with ties
                              ranks = _calculateRanksWithTies(
                                  members, _selectedChallengeType!);
                            }

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
                                final logStreak =
                                    memberData['log_streak'] as int? ?? 0;
                                final rank =
                                    ranks.isNotEmpty ? ranks[index] : index + 1;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      // Ranking Medal
                                      if (_selectedChallengeType != null)
                                        _buildRankingMedal(rank),
                                      if (_selectedChallengeType != null)
                                        const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _truncateName(memberEmail),
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            if (_selectedChallengeType != null)
                                              const SizedBox(height: 6),
                                            if (_selectedChallengeType != null)
                                              _selectedChallengeType ==
                                                      'Log Streak'
                                                  ? _buildNutritionChip(
                                                      '$logStreak Days',
                                                      const Color(0xFF6366F1),
                                                    )
                                                  : Wrap(
                                                      spacing: 8,
                                                      runSpacing: 4,
                                                      children: [
                                                        _buildNutritionChip(
                                                          '${calories.toStringAsFixed(0)} cal',
                                                          Colors
                                                              .orange.shade600,
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
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () {
                                          _startChatWithMember(
                                              memberId, memberEmail);
                                        },
                                        icon: const Icon(
                                          Icons.chat_bubble_outline,
                                          color: Color(0xFF6366F1),
                                        ),
                                        tooltip: 'Chat',
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

          // Calculate log streak
          final logStreak = await _calculateLogStreak(memberId);

          memberData.add({
            'userId': memberId,
            'email': email,
            'consumed_calories': consumedCalories,
            'consumed_protein': consumedProtein,
            'consumed_carbs': consumedCarbs,
            'consumed_fats': consumedFats,
            'log_streak': logStreak,
          });
        } catch (e) {
          // Error fetching member data
        }
      }

      return memberData;
    });
  }

  List<Map<String, dynamic>> _sortMembersByChallenge(
      List<Map<String, dynamic>> members, String challengeType) {
    final sorted = List<Map<String, dynamic>>.from(members);

    switch (challengeType) {
      case 'Lowest Calories Consumed':
        sorted.sort((a, b) => (a['consumed_calories'] as double)
            .compareTo(b['consumed_calories'] as double));
        break;
      case 'Lowest Protein Consumed':
        sorted.sort((a, b) => (a['consumed_protein'] as double)
            .compareTo(b['consumed_protein'] as double));
        break;
      case 'Lowest Carbs Consumed':
        sorted.sort((a, b) => (a['consumed_carbs'] as double)
            .compareTo(b['consumed_carbs'] as double));
        break;
      case 'Lowest Fat Consumed':
        sorted.sort((a, b) => (a['consumed_fats'] as double)
            .compareTo(b['consumed_fats'] as double));
        break;
      case 'Highest Calories Consumed':
        sorted.sort((a, b) => (b['consumed_calories'] as double)
            .compareTo(a['consumed_calories'] as double));
        break;
      case 'Highest Protein Consumed':
        sorted.sort((a, b) => (b['consumed_protein'] as double)
            .compareTo(a['consumed_protein'] as double));
        break;
      case 'Highest Carbs Consumed':
        sorted.sort((a, b) => (b['consumed_carbs'] as double)
            .compareTo(a['consumed_carbs'] as double));
        break;
      case 'Highest Fat Consumed':
        sorted.sort((a, b) => (b['consumed_fats'] as double)
            .compareTo(a['consumed_fats'] as double));
        break;
      case 'Log Streak':
        // Sort by log streak descending (highest first)
        sorted.sort((a, b) =>
            (b['log_streak'] as int).compareTo(a['log_streak'] as int));
        break;
    }

    return sorted;
  }

  List<int> _calculateRanksWithTies(
      List<Map<String, dynamic>> sortedMembers, String challengeType) {
    if (sortedMembers.isEmpty) return [];

    List<int> ranks = [];
    int currentRank = 1;

    // Get the value to compare for the challenge type
    num _getChallengeValue(Map<String, dynamic> member) {
      switch (challengeType) {
        case 'Lowest Calories Consumed':
        case 'Highest Calories Consumed':
          return member['consumed_calories'] as double;
        case 'Lowest Protein Consumed':
        case 'Highest Protein Consumed':
          return member['consumed_protein'] as double;
        case 'Lowest Carbs Consumed':
        case 'Highest Carbs Consumed':
          return member['consumed_carbs'] as double;
        case 'Lowest Fat Consumed':
        case 'Highest Fat Consumed':
          return member['consumed_fats'] as double;
        case 'Log Streak':
          return member['log_streak'] as int;
        default:
          return 0;
      }
    }

    num? previousValue;

    for (int i = 0; i < sortedMembers.length; i++) {
      final currentValue = _getChallengeValue(sortedMembers[i]);

      if (previousValue != null && currentValue != previousValue) {
        // Value changed, increment rank by 1 (dense ranking)
        currentRank++;
      }

      ranks.add(currentRank);
      previousValue = currentValue;
    }

    return ranks;
  }

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<int> _calculateLogStreak(String userId) async {
    try {
      int streak = 0;
      final today = DateTime.now();
      DateTime checkDate = DateTime(today.year, today.month, today.day);

      // Check consecutive days backwards from today
      while (true) {
        final key = _dateKey(checkDate);
        final docSnapshot = await FirebaseFirestore.instance
            .collection('daily_logs')
            .doc('${userId}_$key')
            .get();

        if (!docSnapshot.exists) {
          // No log for this day, streak ends
          break;
        }

        final data = docSnapshot.data();
        final finished = data?['finished'] as bool? ?? false;

        if (!finished) {
          // Day not finished, streak ends
          break;
        }

        // Day is finished, increment streak
        streak++;

        // Move to previous day
        checkDate = checkDate.subtract(const Duration(days: 1));

        // Prevent infinite loop - max 365 days
        if (streak >= 365) break;
      }

      return streak;
    } catch (e) {
      return 0;
    }
  }

  Widget _buildRankingMedal(int rank) {
    Color medalColor;

    switch (rank) {
      case 1:
        medalColor = const Color(0xFFFFD700); // Gold
        break;
      case 2:
        medalColor = const Color(0xFFC0C0C0); // Silver
        break;
      case 3:
        medalColor = const Color(0xFFCD7F32); // Bronze
        break;
      default:
        medalColor = const Color(0xFF6366F1); // Blue
        break;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: medalColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          rank.toString(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildNutritionChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}
