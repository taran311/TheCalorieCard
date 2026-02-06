import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

class MessagesPage extends StatelessWidget {
  final bool hideNav;

  const MessagesPage({Key? key, this.hideNav = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('conversations')
            .where('participant_ids', arrayContains: currentUserId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 64, color: Colors.red.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading conversations',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please check your connection',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No conversations yet',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start a chat from Friends or Groups',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            );
          }

          // Sort conversations by last_message_time
          final conversations = snapshot.data!.docs.toList();
          conversations.sort((a, b) {
            final aTime = (a.data()
                as Map<String, dynamic>)['last_message_time'] as Timestamp?;
            final bTime = (b.data()
                as Map<String, dynamic>)['last_message_time'] as Timestamp?;

            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;

            return bTime.compareTo(aTime); // Descending order
          });

          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              final data = conversation.data() as Map<String, dynamic>;

              final conversationName = data['conversation_name'] ?? 'Unknown';
              final lastMessage = data['last_message'] ?? '';
              final lastMessageTime = data['last_message_time'] as Timestamp?;
              final isGroup = data['is_group'] ?? false;
              final unreadCount = data['unread_count']?[currentUserId] ?? 0;
              var groupId = data['group_id'] as String?;

              // Extract group ID from conversation ID if not stored
              if (isGroup &&
                  groupId == null &&
                  conversation.id.startsWith('group_')) {
                groupId =
                    conversation.id.substring(6); // Remove 'group_' prefix
              }

              // For groups, fetch the actual group name from friend_groups
              if (isGroup && groupId != null) {
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('friend_groups')
                      .doc(groupId)
                      .get(),
                  builder: (context, groupSnapshot) {
                    String displayName = conversationName;
                    if (groupSnapshot.hasData && groupSnapshot.data != null) {
                      final groupData =
                          groupSnapshot.data!.data() as Map<String, dynamic>?;
                      displayName = groupData?['name'] ?? conversationName;
                    }

                    return _buildConversationTile(
                      context,
                      conversation.id,
                      displayName,
                      lastMessage,
                      lastMessageTime,
                      isGroup,
                      unreadCount,
                    );
                  },
                );
              }

              return _buildConversationTile(
                context,
                conversation.id,
                conversationName,
                lastMessage,
                lastMessageTime,
                isGroup,
                unreadCount,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewChatDialog(context, currentUserId),
        backgroundColor: const Color(0xFF6366F1),
        child: const Icon(Icons.add_comment, color: Colors.white),
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
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF6366F1),
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
              style: GoogleFonts.poppins(
                fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
          if (lastMessageTime != null)
            Text(
              timeago.format(lastMessageTime.toDate()),
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.grey.shade600,
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
                color: unreadCount > 0 ? Colors.black87 : Colors.grey.shade600,
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
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                unreadCount.toString(),
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
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailPage(
              conversationId: conversationId,
              conversationName: conversationName,
              isGroup: isGroup,
            ),
          ),
        );
      },
    );
  }

  void _showNewChatDialog(BuildContext context, String currentUserId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Start New Chat',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      TabBar(
                        labelColor: const Color(0xFF6366F1),
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: const Color(0xFF6366F1),
                        tabs: const [
                          Tab(text: 'Friends'),
                          Tab(text: 'Groups'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildFriendsList(context, currentUserId),
                            _buildGroupsList(context, currentUserId),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendsList(BuildContext context, String currentUserId) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>?;
        final friendsList =
            (userData?['friends'] as List?)?.cast<String>() ?? [];

        if (friendsList.isEmpty) {
          return Center(
            child: Text(
              'No friends yet',
              style: GoogleFonts.poppins(color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          itemCount: friendsList.length,
          itemBuilder: (context, index) {
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(friendsList[index])
                  .get(),
              builder: (context, friendSnapshot) {
                if (!friendSnapshot.hasData) return const SizedBox.shrink();

                final friendData =
                    friendSnapshot.data!.data() as Map<String, dynamic>?;
                final friendEmail = friendData?['email'] ?? 'Unknown';
                final friendName = friendEmail.split('@')[0];

                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF6366F1),
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(
                    friendName,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _startChatWithFriend(
                        context, currentUserId, friendsList[index], friendName);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildGroupsList(BuildContext context, String currentUserId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('friend_groups')
          .where('members', arrayContains: currentUserId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              'No groups yet',
              style: GoogleFonts.poppins(color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final group = snapshot.data!.docs[index];
            final groupData = group.data() as Map<String, dynamic>;
            final groupName = groupData['name'] ?? 'Unknown Group';
            final memberIds =
                (groupData['members'] as List?)?.cast<String>() ?? [];

            return ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF6366F1),
                child: Icon(Icons.group, color: Colors.white),
              ),
              title: Text(
                groupName,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                '${memberIds.length} members',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _startGroupChat(context, group.id, memberIds, groupName);
              },
            );
          },
        );
      },
    );
  }

  Future<void> _startChatWithFriend(BuildContext context, String currentUserId,
      String friendId, String friendName) async {
    final conversationId = currentUserId.compareTo(friendId) < 0
        ? '${currentUserId}_$friendId'
        : '${friendId}_$currentUserId';

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

    if (context.mounted) {
      Navigator.push(
        context,
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
      final data = conversationDoc.data() as Map<String, dynamic>?;
      if (data?['group_id'] == null) {
        await conversationRef.update({
          'group_id': groupId,
          'conversation_name': groupName,
        });
      }
    }

    if (context.mounted) {
      Navigator.push(
        context,
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

  @override
  void initState() {
    super.initState();
    _markAsRead();
    _markMessagesAsDelivered();
  }

  Future<void> _markMessagesAsDelivered() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final messagesSnapshot = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .collection('messages')
          .where('sender_id', isNotEqualTo: currentUserId)
          .where('status', isEqualTo: 'sent')
          .get();

      for (final doc in messagesSnapshot.docs) {
        if (widget.isGroup) {
          await doc.reference.update({
            'delivered_to': FieldValue.arrayUnion([currentUserId]),
          });
        } else {
          await doc.reference.update({'status': 'delivered'});
        }
      }
    } catch (e) {
      print('Error marking as delivered: $e');
    }
  }

  Future<void> _markAsRead() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .update({
        'unread_count.$currentUserId': 0,
      });

      // Mark all messages as read
      final messagesSnapshot = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .collection('messages')
          .where('sender_id', isNotEqualTo: currentUserId)
          .get();

      for (final doc in messagesSnapshot.docs) {
        if (widget.isGroup) {
          await doc.reference.update({
            'read_by': FieldValue.arrayUnion([currentUserId]),
          });
        } else {
          await doc.reference.update({'status': 'read'});
        }
      }
    } catch (e) {
      print('Error marking as read: $e');
    }
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final currentUserEmail = currentUser.email ?? 'Unknown';
    final username = currentUserEmail.split('@')[0];

    _messageController.clear();

    try {
      // Get participant_ids first
      final conversationDoc = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .get();

      final participantIds =
          List<String>.from(conversationDoc.data()?['participant_ids'] ?? []);

      // Add message to messages subcollection
      final messageData = {
        'sender_id': currentUser.uid,
        'sender_name': username,
        'message': messageText,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
      };

      if (widget.isGroup) {
        messageData['delivered_to'] = [];
        messageData['read_by'] = [];
      }

      final messageRef = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .collection('messages')
          .add(messageData);

      // Build unread count map (increment for all except sender)
      Map<String, dynamic> unreadCountUpdate = {};
      for (final participantId in participantIds) {
        if (participantId != currentUser.uid) {
          unreadCountUpdate['unread_count.$participantId'] =
              FieldValue.increment(1);
        }
      }

      // Update conversation with last message info
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .update({
        'last_message': messageText,
        'last_message_time': FieldValue.serverTimestamp(),
        'last_sender_id': currentUser.uid,
        ...unreadCountUpdate,
      });

      // Scroll to bottom
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      print('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending message: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              widget.isGroup ? Icons.group : Icons.person,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.conversationName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('conversations')
                  .doc(widget.conversationId)
                  .snapshots(),
              builder: (context, conversationSnapshot) {
                if (!conversationSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final conversationData =
                    conversationSnapshot.data!.data() as Map<String, dynamic>?;
                final participantIds = List<String>.from(
                    conversationData?['participant_ids'] ?? []);

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('conversations')
                      .doc(widget.conversationId)
                      .collection('messages')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Text(
                          'No messages yet. Say hi! 👋',
                          style: GoogleFonts.poppins(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        final message = snapshot.data!.docs[index];
                        final data = message.data() as Map<String, dynamic>;

                        final senderId = data['sender_id'];
                        final senderName = data['sender_name'] ?? 'Unknown';
                        final messageText = data['message'] ?? '';
                        final timestamp = data['timestamp'] as Timestamp?;
                        final status = data['status'] ?? 'sent';
                        final deliveredTo =
                            data['delivered_to'] as List<dynamic>? ?? [];
                        final readBy = data['read_by'] as List<dynamic>? ?? [];

                        final isMe = senderId == currentUserId;

                        return Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.7,
                            ),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? const Color(0xFF6366F1)
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (widget.isGroup && !isMe)
                                  Text(
                                    senderName,
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isMe
                                          ? Colors.white70
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                Text(
                                  messageText,
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: isMe ? Colors.white : Colors.black87,
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (timestamp != null)
                                      Text(
                                        timeago.format(timestamp.toDate()),
                                        style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          color: isMe
                                              ? Colors.white70
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                    if (isMe)
                                      ..._buildMessageStatus(
                                          status,
                                          deliveredTo,
                                          readBy,
                                          participantIds.length),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send),
                  color: const Color(0xFF6366F1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMessageStatus(String status, List<dynamic> deliveredTo,
      List<dynamic> readBy, int totalParticipants) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (widget.isGroup) {
      // For groups: check if all other participants have read/delivered
      final otherParticipantsCount = totalParticipants - 1; // Exclude sender
      final allRead = readBy.length >= otherParticipantsCount;
      final allDelivered = deliveredTo.length >= otherParticipantsCount;

      if (allRead) {
        // Green double tick
        return [
          const SizedBox(width: 4),
          Icon(
            Icons.done_all,
            size: 14,
            color: Colors.lightGreenAccent.shade400,
          ),
        ];
      } else if (allDelivered) {
        // Gray double tick
        return [
          const SizedBox(width: 4),
          const Icon(
            Icons.done_all,
            size: 14,
            color: Colors.white70,
          ),
        ];
      } else {
        // Gray single tick
        return [
          const SizedBox(width: 4),
          const Icon(
            Icons.done,
            size: 14,
            color: Colors.white70,
          ),
        ];
      }
    } else {
      // For 1:1 chats
      if (status == 'read') {
        // Green double tick
        return [
          const SizedBox(width: 4),
          Icon(
            Icons.done_all,
            size: 14,
            color: Colors.lightGreenAccent.shade400,
          ),
        ];
      } else if (status == 'delivered') {
        // Gray double tick
        return [
          const SizedBox(width: 4),
          const Icon(
            Icons.done_all,
            size: 14,
            color: Colors.white70,
          ),
        ];
      } else {
        // Gray single tick (sent)
        return [
          const SizedBox(width: 4),
          const Icon(
            Icons.done,
            size: 14,
            color: Colors.white70,
          ),
        ];
      }
    }
  }
}
