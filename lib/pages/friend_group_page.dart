import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/text_utils.dart';
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
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  /// Created once: building it in build() would re-subscribe every rebuild.
  late final DocumentReference<Map<String, dynamic>> _groupRef =
      FirebaseFirestore.instance.collection('friend_groups').doc(widget.groupId);
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _groupStream =
      _groupRef.snapshots();

  /// Today's food for the members, cached until the member list changes.
  Stream<List<Map<String, dynamic>>>? _consumption;
  String? _consumptionKey;

  /// Members' emails, fetched once each.
  final Map<String, String> _emails = {};

  bool _busy = false;

  Stream<List<Map<String, dynamic>>> _consumptionFor(List<String> memberIds) {
    final key = memberIds.join(',');
    if (_consumption == null || key != _consumptionKey) {
      _consumptionKey = key;
      _consumption = _getMemberConsumptionStream(memberIds);
    }
    return _consumption!;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _openChat(String conversationId, String name, bool isGroup) {
    if (!mounted) return;
    chatNavigator(context).push(
      MaterialPageRoute(
        builder: (_) => ChatDetailPage(
          conversationId: conversationId,
          conversationName: name,
          isGroup: isGroup,
        ),
      ),
    );
  }

  Future<void> _startGroupChat(List<String> memberIds, String groupName) async {
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
          'conversation_name': groupName,
          'is_group': true,
          'group_id': widget.groupId,
          'created_at': FieldValue.serverTimestamp(),
          'last_message': '',
          'last_message_time': FieldValue.serverTimestamp(),
          'unread_count': unreadCount,
        });
      }

      _openChat(conversationId, groupName, true);
    } catch (_) {
      _snack("Couldn't open the chat. Please try again.");
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

      _openChat(conversationId, memberEmail.split('@')[0], false);
    } catch (_) {
      _snack("Couldn't open the chat. Please try again.");
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red600),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Takes you out of the group and its group chat.
  Future<void> _leaveGroup(String groupName) async {
    if (_busy || _uid.isEmpty) return;
    final ok = await _confirm(
      title: 'Leave $groupName?',
      body: "You'll stop seeing the group's day and its group chat.",
      action: 'Leave',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _groupRef.update({
        'members': FieldValue.arrayRemove([_uid]),
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      _snack('Something went wrong. Please try again.');
      return;
    }
    // The group chat may not exist yet; that's fine.
    try {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc('group_${widget.groupId}')
          .update({
        'participant_ids': FieldValue.arrayRemove([_uid]),
      });
    } catch (_) {}
    if (!mounted) return;
    _snack('You left $groupName');
    Navigator.of(context).maybePop();
  }

  /// Deletes the group for everyone (creator only).
  Future<void> _deleteGroup(String groupName) async {
    if (_busy) return;
    final ok = await _confirm(
      title: 'Delete $groupName?',
      body: 'This removes the group for everyone.',
      action: 'Delete',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _groupRef.delete();
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      _snack('Something went wrong. Please try again.');
      return;
    }
    if (!mounted) return;
    _snack('Group deleted');
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _groupStream,
      builder: (context, snapshot) {
        final groupData = snapshot.data?.data();
        final rawName = groupData?['name'];
        final groupName = rawName is String && rawName.isNotEmpty
            ? rawName
            : widget.groupName;
        final memberIds = [
          for (final id in (groupData?['members'] as List?) ?? const [])
            id.toString()
        ];
        final isCreator =
            _uid.isNotEmpty && groupData?['creator_id'] == _uid;
        final exists = snapshot.data?.exists == true;

        // Start over if the group stream drops out, so the food stream
        // (which can only be listened to once) is made fresh next time.
        if (!exists) {
          _consumption = null;
          _consumptionKey = null;
        }

        Widget body;
        if (snapshot.hasError) {
          body = const _Note("Couldn't load this. Check your connection.");
        } else if (!snapshot.hasData) {
          body = const Center(child: CircularProgressIndicator());
        } else if (!exists) {
          body = const _Note("This group doesn't exist any more.");
        } else if (memberIds.isEmpty) {
          body = const _Note('No one is in this group yet.');
        } else {
          body = _membersList(memberIds);
        }

        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(
            title: Text(
              groupName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (exists)
                IconButton(
                  onPressed: memberIds.isEmpty
                      ? null
                      : () => _startGroupChat(memberIds, groupName),
                  icon: const Icon(Icons.chat_bubble_outline),
                  tooltip: 'Group chat',
                ),
              if (exists)
                PopupMenuButton<String>(
                  tooltip: 'More',
                  enabled: !_busy,
                  onSelected: (value) {
                    if (value == 'leave') _leaveGroup(groupName);
                    if (value == 'delete') _deleteGroup(groupName);
                  },
                  itemBuilder: (_) => [
                    if (memberIds.contains(_uid))
                      const PopupMenuItem(
                        value: 'leave',
                        child: Text('Leave group'),
                      ),
                    if (isCreator)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete group',
                          style: TextStyle(color: AppColors.red600),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          body: body,
        );
      },
    );
  }

  Widget _membersList(List<String> memberIds) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _consumptionFor(memberIds),
      builder: (context, consumptionSnapshot) {
        if (consumptionSnapshot.hasError) {
          return const _Note("Couldn't load this. Check your connection.");
        }
        if (!consumptionSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final members = consumptionSnapshot.data!;

        return ListView.builder(
          // Room at the bottom for the Coach button.
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: members.length,
          itemBuilder: (context, index) => _memberCard(members[index]),
        );
      },
    );
  }

  Widget _memberCard(Map<String, dynamic> memberData) {
    final memberId = memberData['userId'] as String;
    final memberEmail = memberData['email'] as String;
    final name = FriendsService.displayName(memberEmail);
    final calories = memberData['consumed_calories'] as double;
    final protein = memberData['consumed_protein'] as double;
    final carbs = memberData['consumed_carbs'] as double;
    final fats = memberData['consumed_fats'] as double;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppDecor.card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    gradient: AppColors.brandGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      memberEmail.initial.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.gray800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Eaten today',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.gray600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Nutrition Info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: AppDecor.inset,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildNutritionChip(
                    '${calories.toStringAsFixed(0)} kcal',
                    AppColors.primaryDark,
                  ),
                  _buildNutritionChip(
                    '${protein.toStringAsFixed(0)}g protein',
                    AppColors.proteinText,
                  ),
                  _buildNutritionChip(
                    '${carbs.toStringAsFixed(0)}g carbs',
                    AppColors.carbsText,
                  ),
                  _buildNutritionChip(
                    '${fats.toStringAsFixed(0)}g fat',
                    AppColors.fatText,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HomePage(
                          readOnly: true,
                          userIdOverride: memberId,
                          showBanner: true,
                          bannerTitle: memberEmail,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.credit_card, size: 20),
                  label: const Text('View card'),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AchievementsPage(
                          userIdOverride: memberId,
                          titleOverride: "$name's achievements",
                        ),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.emoji_events_outlined,
                    color: AppColors.violet600,
                  ),
                  tooltip: 'Achievements',
                ),
                if (memberId != _uid)
                  IconButton(
                    onPressed: () =>
                        _startChatWithMember(memberId, memberEmail),
                    icon: const Icon(
                      Icons.chat_bubble_outline,
                      color: AppColors.primary,
                    ),
                    tooltip: 'Chat',
                  ),
              ],
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

    // Listen to today's food for all members (not their whole history).
    final dayStart = BalanceService.startOfDay(BalanceService.now());
    return BalanceService.entrySnapshotsBetween(memberIds.take(30).toList(),
            dayStart, BalanceService.addDays(dayStart, 1))
        .asyncMap((snapshot) async {
      final today = BalanceService.now();
      final startOfDay = BalanceService.startOfDay(today);
      final endOfDay = BalanceService.addDays(startOfDay, 1);

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

          // Only food eaten today (recipe ingredient rows aren't eaten)
          if (BalanceService.isLogEntry(data) &&
              docDate != null &&
              !docDate.isBefore(startOfDay) &&
              docDate.isBefore(endOfDay)) {
            userFoodMap.putIfAbsent(userId, () => []).add(doc);
          }
        }
      }

      // Fetch any emails we don't have yet, all at once.
      final missing = memberIds.where((id) => !_emails.containsKey(id));
      await Future.wait(missing.map((id) async {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(id)
              .get();
          final email = userDoc.data()?['email'];
          _emails[id] = email is String ? email : 'Unknown';
        } catch (_) {
          // Shown as "Unknown" this time; tried again on the next update.
        }
      }).toList());

      // Build member data list
      final List<Map<String, dynamic>> memberData = [];

      for (final memberId in memberIds) {
        // Calculate consumed values from today's food items
        double consumedCalories = 0;
        double consumedProtein = 0;
        double consumedCarbs = 0;
        double consumedFats = 0;

        final userFoodDocs = userFoodMap[memberId] ?? [];
        for (final doc in userFoodDocs) {
          final data = doc.data() as Map<String, dynamic>;
          consumedCalories += (data['food_calories'] as num?)?.toDouble() ?? 0;
          consumedProtein += (data['food_protein'] as num?)?.toDouble() ?? 0;
          consumedCarbs += (data['food_carbs'] as num?)?.toDouble() ?? 0;
          consumedFats += (data['food_fat'] as num?)?.toDouble() ?? 0;
        }

        memberData.add({
          'userId': memberId,
          'email': _emails[memberId] ?? 'Unknown',
          'consumed_calories': consumedCalories,
          'consumed_protein': consumedProtein,
          'consumed_carbs': consumedCarbs,
          'consumed_fats': consumedFats,
        });
      }

      return memberData;
    });
  }

  Widget _buildNutritionChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// A short muted message in the middle of the page.
class _Note extends StatelessWidget {
  final String text;

  const _Note(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
      ),
    );
  }
}
