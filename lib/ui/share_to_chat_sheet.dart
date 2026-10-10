import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/chat_service.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/ui/responsive.dart';

/// Somewhere to send a message: a friend or one of your groups.
class ChatTarget {
  final String id;
  final String name;
  final bool isGroup;
  final List<String> memberIds; // groups only

  const ChatTarget.friend(this.id, this.name)
      : isGroup = false,
        memberIds = const [];

  const ChatTarget.group(this.id, this.name, this.memberIds) : isGroup = true;
}

/// Your friends and groups, friends first. Either list failing to load
/// just leaves it out.
Future<List<ChatTarget>> loadChatTargets(String uid) async {
  final friendsFuture =
      FriendsService.load(uid).catchError((_) => <Friend>[]);
  final groupsFuture = BalanceService.db
      .collection('friend_groups')
      .where('members', arrayContains: uid)
      .get()
      .then<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        (s) => s.docs,
        onError: (Object _) =>
            <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );
  final friends = await friendsFuture;
  final groups = await groupsFuture;
  final groupTargets = <ChatTarget>[
    for (final g in groups)
      ChatTarget.group(
        g.id,
        '${g.data()['name'] ?? ''}'.trim().isEmpty
            ? 'Unnamed group'
            : '${g.data()['name']}'.trim(),
        [for (final m in (g.data()['members'] as List? ?? const [])) '$m'],
      )
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return [
    for (final f in friends) ChatTarget.friend(f.id, f.name),
    ...groupTargets,
  ];
}

/// Lets you pick a friend or group and sends [text] to their chat. Shows
/// a snackbar either way. Returns true if it was sent.
Future<bool> shareToChat(BuildContext context,
    {required String text,
    String title = 'Share to a friend or group',
    Map<String, dynamic>? extra}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  final messenger = ScaffoldMessenger.of(context);
  final target = await showModalBottomSheet<ChatTarget>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ShareSheet(uid: user.uid, title: title),
  );
  if (target == null) return false;
  try {
    final myName = await FriendsService.nameFor(user.uid, email: user.email);
    if (target.isGroup) {
      await ChatService.sendToGroup(
        uid: user.uid,
        myName: myName,
        groupId: target.id,
        groupName: target.name,
        memberIds: target.memberIds,
        text: text,
        extra: extra,
      );
    } else {
      await ChatService.sendToFriend(
        uid: user.uid,
        myName: myName,
        friendId: target.id,
        friendName: target.name,
        text: text,
        extra: extra,
      );
    }
    messenger.showSnackBar(SnackBar(content: Text('Sent to ${target.name}')));
    return true;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Message not sent. Check your connection and try again.')));
    return false;
  }
}

class _ShareSheet extends StatefulWidget {
  final String uid;
  final String title;

  const _ShareSheet({required this.uid, required this.title});

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late Future<List<ChatTarget>> _targets = loadChatTargets(widget.uid);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
            Flexible(
              child: FutureBuilder<List<ChatTarget>>(
                future: _targets,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text("Couldn't load your friends.",
                                style: TextStyle(color: AppColors.muted)),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _targets = loadChatTargets(widget.uid);
                            }),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final targets = snap.data!;
                  if (targets.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Add a friend first, then you can share with them.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final t in targets)
                        ListTile(
                          leading: Icon(
                            t.isGroup
                                ? Icons.group_outlined
                                : Icons.person_outline,
                            color: AppText.primary,
                          ),
                          title: Text(
                            t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: t.isGroup ? const Text('Group chat') : null,
                          onTap: () => Navigator.pop(context, t),
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
}
