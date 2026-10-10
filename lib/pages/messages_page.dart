import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/ui/shell_back.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/pages/calorie_game_page.dart';
import 'package:timeago/timeago.dart' as timeago;

/// The navigator chat screens open on.
///
/// On phones a chat goes on the root navigator, so it covers the bottom bar
/// and the Coach button can't sit on top of the message box. On wider
/// screens it stays inside the current tab. Uses the window width, not
/// MediaQuery (which is narrowed to the page column on desktop).
NavigatorState chatNavigator(BuildContext context) {
  final view = View.of(context);
  final width = view.physicalSize.width / view.devicePixelRatio;
  return Navigator.of(context, rootNavigator: width < Breakpoints.tablet);
}

/// Display names for the other person in direct chats, fetched once each.
final Map<String, Future<String?>> _personNames = {};

Future<String?> _personName(String uid) {
  return _personNames.putIfAbsent(uid, () async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      if (data == null) return null;
      final name = FriendsService.nameFromUser(data);
      return name == 'Unknown' ? null : name;
    } catch (_) {
      _personNames.remove(uid);
      return null;
    }
  });
}

/// Group names, fetched once each per session.
final Map<String, Future<String?>> _groupNames = {};

Future<String?> _groupName(String groupId) {
  return _groupNames.putIfAbsent(groupId, () async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('friend_groups')
          .doc(groupId)
          .get();
      final name = doc.data()?['name'];
      return name is String && name.isNotEmpty ? name : null;
    } catch (_) {
      _groupNames.remove(groupId);
      return null;
    }
  });
}

/// The other participant in a one-to-one chat (null if unknown).
String? _otherParticipant(Map<String, dynamic> data, String myUid) {
  final ids = data['participant_ids'];
  if (ids is! List) return null;
  for (final id in ids) {
    if (id is String && id != myUid) return id;
  }
  return null;
}

class MessagesPage extends StatefulWidget {
  const MessagesPage({Key? key}) : super(key: key);

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  /// Created once: building it in build() would re-subscribe (and flash
  /// the spinner) on every rebuild.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _conversations =
      FirebaseFirestore.instance
          .collection('conversations')
          .where('participant_ids', arrayContains: _uid ?? '')
          .snapshots();

  @override
  Widget build(BuildContext context) {
    final currentUserId = _uid;
    if (currentUserId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Messages')),
        body: const Center(child: Text('Sign in to see your messages.')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: ShellBack.button(context),
        title: const Text('Messages'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _conversations,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        size: 64, color: AppColors.red400),
                    SizedBox(height: 16),
                    Text(
                      "Couldn't load your messages",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.gray600,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Check your connection and try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.data!.docs.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline,
                        size: 64, color: AppColors.gray400),
                    SizedBox(height: 16),
                    Text(
                      'No conversations yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.gray600,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Start a chat from Friends or Groups',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Sort conversations by last_message_time
          final conversations = snapshot.data!.docs.toList();
          conversations.sort((a, b) {
            final aTime = a.data()['last_message_time'] as Timestamp?;
            final bTime = b.data()['last_message_time'] as Timestamp?;

            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;

            return bTime.compareTo(aTime); // Descending order
          });

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              final data = conversation.data();

              final conversationName =
                  (data['conversation_name'] ?? 'Unknown').toString();
              final lastMessage = (data['last_message'] ?? '').toString();
              final lastMessageTime = data['last_message_time'] as Timestamp?;
              final isGroup = data['is_group'] == true;
              final rawUnread = data['unread_count'] is Map
                  ? (data['unread_count'] as Map)[currentUserId]
                  : null;
              final unreadCount = rawUnread is num ? rawUnread.toInt() : 0;
              var groupId = data['group_id'] as String?;

              // Extract group ID from conversation ID if not stored
              if (isGroup &&
                  groupId == null &&
                  conversation.id.startsWith('group_')) {
                groupId =
                    conversation.id.substring(6); // Remove 'group_' prefix
              }

              // Groups: the group's current name. Direct chats: the other
              // person's name (the stored name is the creator's view).
              final Future<String?>? nameFuture;
              if (isGroup) {
                nameFuture = groupId == null ? null : _groupName(groupId);
              } else {
                final otherId = _otherParticipant(data, currentUserId);
                nameFuture = otherId == null ? null : _personName(otherId);
              }

              if (nameFuture == null) {
                return _buildConversationTile(
                  context,
                  conversation.id,
                  conversationName,
                  lastMessage,
                  lastMessageTime,
                  isGroup,
                  unreadCount,
                );
              }

              return FutureBuilder<String?>(
                future: nameFuture,
                builder: (context, nameSnapshot) {
                  return _buildConversationTile(
                    context,
                    conversation.id,
                    nameSnapshot.data ?? conversationName,
                    lastMessage,
                    lastMessageTime,
                    isGroup,
                    unreadCount,
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'messages-new-chat',
        tooltip: 'New chat',
        onPressed: () => _showNewChatDialog(context, currentUserId),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_comment),
      ),
    );
  }

  Widget _buildConversationTile(
    BuildContext context,
    String conversationId,
    String conversationName,
    String lastMessage,
    Timestamp? lastMessageTime,
    bool isGroup,
    int unreadCount,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary,
          child: Icon(
            isGroup ? Icons.group : Icons.person,
            color: Colors.white,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                conversationName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight:
                      unreadCount > 0 ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
            if (lastMessageTime != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  timeago.format(lastMessageTime.toDate()),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.gray600,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                lastMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight:
                      unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                  color: unreadCount > 0 ? AppColors.ink : AppColors.gray600,
                ),
              ),
            ),
            if (unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : unreadCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        onTap: () {
          chatNavigator(context).push(
            MaterialPageRoute(
              builder: (_) => ChatDetailPage(
                conversationId: conversationId,
                conversationName: conversationName,
                isGroup: isGroup,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showNewChatDialog(BuildContext context, String currentUserId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // Keep `context` = the Messages page: the chat is opened from it after
      // the sheet closes (the sheet's own context is gone by then).
      builder: (sheetContext) => _NewChatSheet(
        uid: currentUserId,
        onFriend: (friendId, friendName) async {
          Navigator.pop(sheetContext);
          await _startChatWithFriend(
              context, currentUserId, friendId, friendName);
        },
        onGroup: (groupId, memberIds, groupName) async {
          Navigator.pop(sheetContext);
          await _startGroupChat(context, groupId, memberIds, groupName);
        },
      ),
    );
  }

  static void _chatFailed(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
          content: Text("Couldn't open the chat. Please try again.")),
    );
  }

  Future<void> _startChatWithFriend(BuildContext context, String currentUserId,
      String friendId, String friendName) async {
    final conversationId = currentUserId.compareTo(friendId) < 0
        ? '${currentUserId}_$friendId'
        : '${friendId}_$currentUserId';

    try {
      final conversationRef = FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId);

      final conversationDoc = await conversationRef.get();
      if (!conversationDoc.exists) {
        await conversationRef.set({
          'participant_ids': [currentUserId, friendId],
          'conversation_name': friendName,
          'is_group': false,
          'last_message': '',
          'last_message_time': FieldValue.serverTimestamp(),
          'unread_count': {currentUserId: 0, friendId: 0},
        });
      }
    } catch (_) {
      _chatFailed(context);
      return;
    }

    if (context.mounted) {
      chatNavigator(context).push(
        MaterialPageRoute(
          builder: (_) => ChatDetailPage(
            conversationId: conversationId,
            conversationName: friendName,
            isGroup: false,
          ),
        ),
      );
    }
  }

  Future<void> _startGroupChat(BuildContext context, String groupId,
      List<String> memberIds, String groupName) async {
    final conversationId = 'group_$groupId';

    try {
      final conversationRef = FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId);

      final conversationDoc = await conversationRef.get();
      if (!conversationDoc.exists) {
        Map<String, int> unreadCount = {};
        for (final memberId in memberIds) {
          unreadCount[memberId] = 0;
        }

        await conversationRef.set({
          'participant_ids': memberIds,
          'conversation_name': groupName,
          'is_group': true,
          'group_id': groupId,
          'last_message': '',
          'last_message_time': FieldValue.serverTimestamp(),
          'unread_count': unreadCount,
        });
      } else {
        // Update existing conversation with group_id if missing
        final data = conversationDoc.data();
        if (data?['group_id'] == null) {
          await conversationRef.update({
            'group_id': groupId,
            'conversation_name': groupName,
          });
        }
      }
    } catch (_) {
      _chatFailed(context);
      return;
    }

    if (context.mounted) {
      chatNavigator(context).push(
        MaterialPageRoute(
          builder: (_) => ChatDetailPage(
            conversationId: conversationId,
            conversationName: groupName,
            isGroup: true,
          ),
        ),
      );
    }
  }
}

/// "New chat": your friends and groups, in two tabs. Its streams are made
/// once, not on every rebuild of the sheet.
class _NewChatSheet extends StatefulWidget {
  final String uid;
  final void Function(String friendId, String friendName) onFriend;
  final void Function(String groupId, List<String> memberIds, String name)
      onGroup;

  const _NewChatSheet({
    required this.uid,
    required this.onFriend,
    required this.onGroup,
  });

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userDoc =
      FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _groups =
      FirebaseFirestore.instance
          .collection('friend_groups')
          .where('members', arrayContains: widget.uid)
          .snapshots();

  static Widget _loadError() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          "Couldn't load this. Check your connection.",
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'New chat',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.ink,
              ),
            ),
          ),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    labelColor: AppText.primaryDark,
                    unselectedLabelColor: AppColors.muted,
                    indicatorColor: AppColors.primary,
                    tabs: const [
                      Tab(text: 'Friends'),
                      Tab(text: 'Groups'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _friendsList(),
                        _groupsList(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _friendsList() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDoc,
      builder: (_, snapshot) {
        if (snapshot.hasError) return _loadError();
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final userData = snapshot.data!.data();
        final friendsList = [
          for (final id in (userData?['friends'] as List?) ?? const [])
            id.toString()
        ];

        if (friendsList.isEmpty) {
          return Center(
            child: Text(
              'No friends yet',
              style: TextStyle(color: AppColors.muted),
            ),
          );
        }

        return ListView.builder(
          itemCount: friendsList.length,
          itemBuilder: (_, index) {
            final friendId = friendsList[index];
            return FutureBuilder<String?>(
              future: _personName(friendId),
              builder: (_, friendSnapshot) {
                if (friendSnapshot.connectionState != ConnectionState.done) {
                  return const SizedBox.shrink();
                }
                final friendName = friendSnapshot.data ?? 'Unknown';

                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(
                    friendName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  onTap: () => widget.onFriend(friendId, friendName),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _groupsList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _groups,
      builder: (_, snapshot) {
        if (snapshot.hasError) return _loadError();
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text(
              'No groups yet',
              style: TextStyle(color: AppColors.muted),
            ),
          );
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (_, index) {
            final group = docs[index];
            final groupData = group.data();
            final rawName = groupData['name'];
            final groupName = rawName is String && rawName.isNotEmpty
                ? rawName
                : 'Unnamed group';
            final memberIds = [
              for (final id in (groupData['members'] as List?) ?? const [])
                id.toString()
            ];

            return ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.group, color: Colors.white),
              ),
              title: Text(
                groupName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                '${memberIds.length} ${memberIds.length == 1 ? 'member' : 'members'}',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              onTap: () => widget.onGroup(group.id, memberIds, groupName),
            );
          },
        );
      },
    );
  }
}

class ChatDetailPage extends StatefulWidget {
  final String conversationId;
  final String conversationName;
  final bool isGroup;

  const ChatDetailPage({
    Key? key,
    required this.conversationId,
    required this.conversationName,
    required this.isGroup,
  }) : super(key: key);

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  late final DocumentReference<Map<String, dynamic>> _conversationRef;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _conversationStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream;

  bool _marking = false;
  bool _sharingCard = false;

  /// For direct chats: the other person's name, looked up from their
  /// account (the stored conversation name is the creator's view).
  Future<String?>? _otherName;

  /// Only the most recent messages are loaded; older ones aren't needed to
  /// chat and loading everything gets slower as a conversation grows.
  static const _messageLimit = 200;

  @override
  void initState() {
    super.initState();
    _conversationRef = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId);
    _conversationStream = _conversationRef.snapshots();
    _messagesStream = _conversationRef
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(_messageLimit)
        .snapshots();
    if (!widget.isGroup) _otherName = _lookUpOtherName();
    _resetUnreadCount();
  }

  Future<String?> _lookUpOtherName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final doc = await _conversationRef.get();
      final data = doc.data();
      if (data == null) return null;
      final otherId = _otherParticipant(data, uid);
      return otherId == null ? null : await _personName(otherId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _resetUnreadCount() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _conversationRef.update({'unread_count.$uid': 0});
    } catch (_) {}
  }

  /// Marks incoming messages as read, in a single batched write, and only
  /// for messages that aren't already marked.
  Future<void> _markIncomingRead(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _marking) return;

    final batch = FirebaseFirestore.instance.batch();
    var count = 0;
    for (final doc in docs) {
      final data = doc.data();
      if (data['sender_id'] == uid) continue;
      if (widget.isGroup) {
        final readBy = (data['read_by'] as List?) ?? const [];
        if (readBy.contains(uid)) continue;
        batch.update(doc.reference, {
          'read_by': FieldValue.arrayUnion([uid]),
          'delivered_to': FieldValue.arrayUnion([uid]),
        });
      } else {
        if (data['status'] == 'read') continue;
        batch.update(doc.reference, {'status': 'read'});
      }
      if (++count >= 450) break; // Firestore batch limit is 500.
    }
    if (count == 0) return;

    batch.update(_conversationRef, {'unread_count.$uid': 0});
    _marking = true;
    try {
      await batch.commit();
    } catch (_) {
      // Not critical; we'll try again on the next update.
    } finally {
      _marking = false;
    }
  }

  bool _hasUnreadIncoming(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String? uid) {
    for (final doc in docs) {
      final data = doc.data();
      if (data['sender_id'] == uid) continue;
      if (widget.isGroup) {
        final readBy = (data['read_by'] as List?) ?? const [];
        if (!readBy.contains(uid)) return true;
      } else if (data['status'] != 'read') {
        return true;
      }
    }
    return false;
  }

  Future<void> _sendMessage({
    String? overrideText,
    Map<String, dynamic>? card,
  }) async {
    final messageText = (overrideText ?? _messageController.text).trim();
    if (messageText.isEmpty) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;


    if (overrideText == null) {
      _messageController.clear();
      // On desktop browsers the Enter key can land after we clear; tidy up.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_messageController.text.trim().isEmpty) {
          _messageController.clear();
        }
      });
    }

    try {
      // Your display name if you set one (looked up once, then cached).
      final username = await FriendsService.nameFor(currentUser.uid,
          email: currentUser.email);
      final conversationDoc = await _conversationRef.get();
      final participantIds =
          List<String>.from(conversationDoc.data()?['participant_ids'] ?? []);

      final messageData = <String, dynamic>{
        'sender_id': currentUser.uid,
        'sender_name': username,
        'message': messageText,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
        if (card != null) 'type': 'card',
        if (card != null) 'card': card,
      };
      if (widget.isGroup) {
        messageData['delivered_to'] = [];
        messageData['read_by'] = [];
      }

      final unreadCountUpdate = <String, dynamic>{
        for (final id in participantIds)
          if (id != currentUser.uid)
            'unread_count.$id': FieldValue.increment(1),
      };

      // Message + conversation preview are written together.
      final batch = FirebaseFirestore.instance.batch();
      batch.set(_conversationRef.collection('messages').doc(), messageData);
      batch.update(_conversationRef, {
        'last_message': messageText,
        'last_message_time': FieldValue.serverTimestamp(),
        'last_sender_id': currentUser.uid,
        ...unreadCountUpdate,
      });
      await batch.commit();

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (_) {
      // Keep what they typed so they can send it again.
      if (mounted &&
          overrideText == null &&
          _messageController.text.trim().isEmpty) {
        _messageController.text = messageText;
        _messageController.selection =
            TextSelection.collapsed(offset: messageText.length);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Message not sent. Check your connection and try again.')),
        );
      }
    }
  }

  /// Posts today's card balance into the chat.
  Future<void> _shareCard() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _sharingCard) return;
    setState(() => _sharingCard = true);
    try {
      final doc = await BalanceService.userDataDoc(uid);
      final data = doc?.data();
      if (data == null) return;
      double n(dynamic v) => v is num ? v.toDouble() : 0;
      final card = <String, dynamic>{
        'calories_left': n(data['calories']).round(),
        'calorie_goal': (BalanceService.calorieGoalFrom(data) ?? 0).round(),
        'protein_left': n(data['protein_balance']).round(),
        'carbs_left': n(data['carbs_balance']).round(),
        'fat_left': n(data['fats_balance']).round(),
      };
      final kcal = card['calories_left'] as int;
      final text = kcal >= 0
          ? '💳 My card: $kcal kcal left today · P ${card['protein_left']}g · C ${card['carbs_left']}g · F ${card['fat_left']}g'
          : '💳 My card: ${-kcal} kcal over today';
      await _sendMessage(overrideText: text, card: card);
    } finally {
      if (mounted) setState(() => _sharingCard = false);
    }
  }

  KeyEventResult _onInputKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _sendMessage();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    if (_sameDay(d, now)) return 'Today';
    if (_sameDay(d, BalanceService.addDays(now, -1))) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              child: Icon(
                widget.isGroup ? Icons.group : Icons.person,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _otherName == null
                  ? Text(
                      widget.conversationName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : FutureBuilder<String?>(
                      future: _otherName,
                      builder: (context, nameSnapshot) => Text(
                        nameSnapshot.data ?? widget.conversationName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _conversationStream,
              builder: (context, conversationSnapshot) {
                final participantIds = List<String>.from(
                    conversationSnapshot.data?.data()?['participant_ids'] ??
                        []);

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _messagesStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            "Couldn't load this. Check your connection.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.muted),
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data!.docs;

                    if (docs.isEmpty) {
                      return Center(
                        child: Text(
                          'No messages yet. Say hi! 👋',
                          style: TextStyle(color: AppColors.gray600),
                        ),
                      );
                    }

                    if (_hasUnreadIncoming(docs, currentUserId)) {
                      WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _markIncomingRead(docs));
                    }

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final maxBubble = constraints.maxWidth * 0.72;
                        return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final data = docs[index].data();
                            final senderId = data['sender_id'];
                            final isMe = senderId == currentUserId;
                            final time =
                                (data['timestamp'] as Timestamp?)?.toDate() ??
                                    DateTime.now();

                            // The list is newest-first and drawn bottom-up,
                            // so index + 1 is the message *above* this one.
                            final older = index + 1 < docs.length
                                ? docs[index + 1].data()
                                : null;
                            final olderTime =
                                (older?['timestamp'] as Timestamp?)?.toDate();
                            final newDay = olderTime == null ||
                                !_sameDay(olderTime, time);
                            final continued = olderTime != null &&
                                !newDay &&
                                older?['sender_id'] == senderId &&
                                time.difference(olderTime).inMinutes < 5;

                            return Column(
                              children: [
                                if (newDay) _DaySeparator(label: _dayLabel(time)),
                                _MessageBubble(
                                  data: data,
                                  isMe: isMe,
                                  isGroup: widget.isGroup,
                                  continued: continued,
                                  maxWidth: maxBubble,
                                  timeLabel: _clock(time),
                                  status: isMe
                                      ? _buildMessageStatus(
                                          (data['status'] ?? 'sent')
                                              .toString(),
                                          (data['delivered_to'] as List?) ??
                                              const [],
                                          (data['read_by'] as List?) ??
                                              const [],
                                          participantIds.length,
                                        )
                                      : const [],
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Share my card',
                    onPressed: _sharingCard ? null : _shareCard,
                    icon: _sharingCard
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.credit_card),
                    color: AppText.primary,
                  ),
                  Expanded(
                    child: Focus(
                      onKeyEvent: _onInputKey,
                      child: TextField(
                        controller: _messageController,
                        focusNode: _inputFocus,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: 'Message',
                          filled: true,
                          fillColor: AppColors.gray100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _messageController,
                    builder: (context, value, _) {
                      final canSend = value.text.trim().isNotEmpty;
                      return IconButton.filled(
                        tooltip: 'Send',
                        onPressed: canSend ? () => _sendMessage() : null,
                        icon: const Icon(Icons.send_rounded, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The ticks after your own messages. Each has a label for screen
  /// readers, since the difference is otherwise only colour and shape.
  List<Widget> _buildMessageStatus(String status, List<dynamic> deliveredTo,
      List<dynamic> readBy, int totalParticipants) {
    final String state;
    if (widget.isGroup) {
      // For groups: have all other participants read/received it?
      final others = totalParticipants - 1; // Exclude sender
      state = readBy.length >= others
          ? 'read'
          : deliveredTo.length >= others
              ? 'delivered'
              : 'sent';
    } else {
      state = status == 'read' || status == 'delivered' ? status : 'sent';
    }
    return [
      const SizedBox(width: 4),
      switch (state) {
        'read' => const Icon(Icons.done_all,
            size: 14, color: AppColors.emerald300, semanticLabel: 'Read'),
        'delivered' => const Icon(Icons.done_all,
            size: 14, color: Colors.white, semanticLabel: 'Delivered'),
        _ => const Icon(Icons.done,
            size: 14, color: Colors.white, semanticLabel: 'Sent'),
      },
    ];
  }
}

class _DaySeparator extends StatelessWidget {
  final String label;

  const _DaySeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMe;
  final bool isGroup;
  final bool continued;
  final double maxWidth;
  final String timeLabel;
  final List<Widget> status;

  const _MessageBubble({
    required this.data,
    required this.isMe,
    required this.isGroup,
    required this.continued,
    required this.maxWidth,
    required this.timeLabel,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final isCard = data['type'] == 'card' && data['card'] is Map;
    final gameId = data['type'] == 'game' ? data['game_id'] : null;
    final radius = Radius.circular(18);
    final tight = Radius.circular(continued ? 18 : 6);

    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeLabel,
          style: TextStyle(
            fontSize: 11,
            // Pure white on your own (indigo) bubbles: white70 was too faint.
            color: isMe ? Colors.white : AppColors.gray600,
          ),
        ),
        ...status,
      ],
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(top: continued ? 2 : 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        constraints: BoxConstraints(maxWidth: maxWidth),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: radius,
            topRight: radius,
            bottomLeft: isMe ? radius : tight,
            bottomRight: isMe ? tight : radius,
          ),
          border: isMe ? null : Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isGroup && !isMe && !continued)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    (data['sender_name'] ?? 'Unknown').toString(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppText.primary,
                    ),
                  ),
                ),
              ),
            if (isCard)
              _SharedCard(card: Map<String, dynamic>.from(data['card'] as Map))
            else if (gameId is String && gameId.isNotEmpty)
              _GameMessage(
                text: (data['message'] ?? '').toString(),
                gameId: gameId,
                isMe: isMe,
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  (data['message'] ?? '').toString(),
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.3,
                    color: isMe ? Colors.white : AppColors.ink,
                  ),
                ),
              ),
            const SizedBox(height: 2),
            meta,
          ],
        ),
      ),
    );
  }
}

/// A calorie card shared into a chat.
class _SharedCard extends StatelessWidget {
  final Map<String, dynamic> card;

  const _SharedCard({required this.card});

  @override
  Widget build(BuildContext context) {
    int n(String k) => (card[k] is num) ? (card[k] as num).round() : 0;
    final left = n('calories_left');
    final goal = n('calorie_goal');
    final over = left < 0;
    final spent = goal - left;
    final progress = goal <= 0 ? 0.0 : (spent / goal).clamp(0.0, 1.0);

    return Container(
      width: 230,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        // Always dark (white text on it), in light and dark mode.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2937), Color(0xFF111827)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.credit_card, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(
                over ? 'OVER BUDGET' : 'BALANCE TODAY',
                style: TextStyle(
                  color: over ? AppColors.red300 : Colors.white70,
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${left.abs()} kcal',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.toDouble(),
              minHeight: 5,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(
                over ? AppText.red : AppText.green,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Left: ${n('protein_left')}g protein · ${n('carbs_left')}g carbs · ${n('fat_left')}g fat',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// A Guess the Calories message: tap it to open the game.
class _GameMessage extends StatelessWidget {
  final String text;
  final String gameId;
  final bool isMe;

  const _GameMessage({
    required this.text,
    required this.gameId,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isMe ? Colors.white : AppColors.ink;
    final link = isMe ? Colors.white : AppText.primary;
    return Semantics(
      button: true,
      label: '$text. Open the game',
      excludeSemantics: true,
      child: Material(
        color: isMe
            ? Colors.white.withValues(alpha: 0.14)
            : AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CalorieGamePage(gameId: gameId)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text,
                    style: TextStyle(fontSize: 15, height: 1.3, color: fg),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Open the game',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: link,
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 18, color: link),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
