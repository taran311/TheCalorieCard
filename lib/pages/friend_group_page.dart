import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/friend_activity.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/ui/friend_today.dart';
import 'package:namer_app/ui/responsive.dart';
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

  /// Today's food for the members, cached until the member list or the
  /// day changes. (The query covers one day: kept past midnight, it would
  /// show everyone at zero.)
  Stream<List<Map<String, dynamic>>>? _consumption;
  String? _consumptionKey;

  /// Members' names, fetched once each.
  final Map<String, String> _names = {};

  bool _busy = false;
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    _midnight = FriendActivity.atMidnight(() {
      if (!mounted) return;
      // build() sees the new date and starts a fresh stream for today.
      setState(() {});
      _scheduleMidnight();
    });
  }

  @override
  void dispose() {
    _midnight?.cancel();
    super.dispose();
  }

  Stream<List<Map<String, dynamic>>> _consumptionFor(List<String> memberIds) {
    final key = '${BalanceService.dateKey(BalanceService.now())}|'
        '${memberIds.join(',')}';
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

  Future<void> _startChatWithMember(String memberId, String name) async {
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
          'conversation_name': name,
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

      _openChat(conversationId, name, false);
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
            style: TextButton.styleFrom(foregroundColor: AppText.red600),
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
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete group',
                          style: TextStyle(color: AppText.red600),
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
    final name = memberData['name'] as String;
    final calories = memberData['consumed_calories'] as double;
    final protein = memberData['consumed_protein'] as double;
    final carbs = memberData['consumed_carbs'] as double;
    final fats = memberData['consumed_fats'] as double;
    final isMe = memberId == _uid;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppDecor.card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: FriendTodayBuilder(
          userId: memberId,
          builder: (context, logged) {
            // Spending comes from the live food stream; budget and
            // "finished" from their day's history (or their goal).
            final day = logged == null
                ? null
                : FriendDay(
                    finished: logged.finished,
                    spent: calories,
                    budget: logged.budget,
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ProgressAvatar(name: name, day: day, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMe ? '$name (you)' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.gray800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _statusLine(day),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Macros are a side note: the card is about the budget.
                Text(
                  '${protein.round()}g protein · ${carbs.round()}g carbs · '
                  '${fats.round()}g fat',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
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
                              bannerTitle: name,
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
                      icon: Icon(
                        Icons.emoji_events_outlined,
                        color: AppText.violet600,
                      ),
                      tooltip: 'Achievements',
                    ),
                    if (!isMe)
                      IconButton(
                        onPressed: () => _startChatWithMember(memberId, name),
                        icon: Icon(
                          Icons.chat_bubble_outline,
                          color: AppText.primary,
                        ),
                        tooltip: 'Chat',
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// "62% of budget spent · on track", or "Finished ✓ · on budget".
  Widget _statusLine(FriendDay? day) {
    if (day == null) return const SizedBox(height: 16);
    final Color color;
    if (day.onTrack == false) {
      color = AppText.amber700;
    } else if (day.finished) {
      color = AppText.emerald700;
    } else {
      color = AppColors.gray600;
    }
    final text = Text(
      day.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
    );
    if (!day.finished) return text;
    return Tooltip(
      message: "They've closed their day on the Card",
      child: text,
    );
  }

  Stream<List<Map<String, dynamic>>> _getMemberConsumptionStream(
      List<String> memberIds) {
    if (memberIds.isEmpty) {
      return Stream.value([]);
    }

    // Listen to today's food for all members (not their whole history),
    // 30 people per query, so big groups aren't cut short.
    final dayStart = BalanceService.startOfDay(BalanceService.now());
    final dayEnd = BalanceService.addDays(dayStart, 1);
    return FriendActivity.foodBetween(memberIds, dayStart, dayEnd)
        .asyncMap((docs) async {
      // Group food items by user: only food eaten that day (recipe
      // ingredient rows aren't eaten; a fallback query returns more).
      final userFoodMap = <String, List<Map<String, dynamic>>>{};
      for (final doc in docs) {
        final data = doc.data();
        final userId = data['user_id'] as String?;
        final docDate = BalanceService.entryDate(data);
        if (userId != null &&
            BalanceService.isLogEntry(data) &&
            docDate != null &&
            !docDate.isBefore(dayStart) &&
            docDate.isBefore(dayEnd)) {
          userFoodMap.putIfAbsent(userId, () => []).add(data);
        }
      }

      // Fetch any names we don't have yet, all at once.
      final missing = memberIds.where((id) => !_names.containsKey(id));
      await Future.wait(missing.map((id) async {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(id)
              .get();
          _names[id] = FriendsService.nameFromUser(userDoc.data());
        } catch (_) {
          // Shown as "Unknown" this time; tried again on the next update.
        }
      }).toList());

      return [
        for (final memberId in memberIds)
          () {
            final total =
                BalanceService.totalOf(userFoodMap[memberId] ?? const []);
            return <String, dynamic>{
              'userId': memberId,
              'name': _names[memberId] ?? 'Unknown',
              'consumed_calories': total.calories,
              'consumed_protein': total.protein,
              'consumed_carbs': total.carbs,
              'consumed_fats': total.fat,
            };
          }(),
      ];
    });
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
          style: TextStyle(color: AppColors.muted),
        ),
      ),
    );
  }
}
