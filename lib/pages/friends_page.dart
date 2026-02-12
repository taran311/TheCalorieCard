import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/pages/home_page.dart';
import 'package:namer_app/pages/achievements_page.dart';
import 'package:namer_app/pages/friend_group_page.dart';
import 'package:namer_app/pages/messages_page.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({Key? key}) : super(key: key);

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final TextEditingController _emailController = TextEditingController();
  bool _showAddFriendForm = false;
  bool _isSubmitting = false;
  bool _isDeleteMode = false;
  String? _errorMessage;

  // Friend group creation
  bool _showAddGroupModal = false;
  final TextEditingController _groupNameController = TextEditingController();
  Set<String> _selectedFriendIds = {};
  bool _isCreatingGroup = false;

  @override
  void initState() {
    super.initState();
    _initializeUserDocument();
  }

  Future<void> _initializeUserDocument() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        // Create user document if it doesn't exist
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .set({
          'email': currentUser.email,
          'friends': [],
        });
      }
    } catch (e) {
      // Silently fail - not critical
    }
  }

  Future<void> _submitFriendRequest() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter an email address';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Find user by email
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        setState(() {
          _errorMessage = 'User not found';
          _isSubmitting = false;
        });
        return;
      }

      final targetUserId = userQuery.docs.first.id;

      // Prevent self-requests
      if (targetUserId == currentUser.uid) {
        setState(() {
          _errorMessage = 'You cannot add yourself';
          _isSubmitting = false;
        });
        return;
      }

      // Check if already friends
      final currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      final friends =
          (currentUserDoc.data()?['friends'] as List?)?.cast<String>() ?? [];
      if (friends.contains(targetUserId)) {
        setState(() {
          _errorMessage = 'Already friends with this user';
          _isSubmitting = false;
        });
        return;
      }

      // Check if request already pending
      final existingRequest = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('from_user_id', isEqualTo: currentUser.uid)
          .where('to_user_id', isEqualTo: targetUserId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (existingRequest.docs.isNotEmpty) {
        setState(() {
          _errorMessage = 'Friend request already sent';
          _isSubmitting = false;
        });
        return;
      }

      // Create friend request
      await FirebaseFirestore.instance.collection('friend_requests').add({
        'from_user_id': currentUser.uid,
        'from_email': currentUser.email ?? '',
        'to_user_id': targetUserId,
        'to_email': email,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      _emailController.clear();
      setState(() {
        _showAddFriendForm = false;
        _isSubmitting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request sent!')),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _isSubmitting = false;
      });
    }
  }

  Future<void> _acceptFriendRequest(
      String requestId, String fromUserId, String fromEmail) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // Update friend request status
        transaction.update(
          FirebaseFirestore.instance
              .collection('friend_requests')
              .doc(requestId),
          {'status': 'accepted'},
        );

        // Add to current user's friends
        transaction.update(
          FirebaseFirestore.instance.collection('users').doc(currentUser.uid),
          {
            'friends': FieldValue.arrayUnion([fromUserId]),
          },
        );

        // Add to other user's friends
        transaction.update(
          FirebaseFirestore.instance.collection('users').doc(fromUserId),
          {
            'friends': FieldValue.arrayUnion([currentUser.uid]),
          },
        );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You are now friends with $fromEmail')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _rejectFriendRequest(String requestId) async {
    try {
      await FirebaseFirestore.instance
          .collection('friend_requests')
          .doc(requestId)
          .update({'status': 'rejected'});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request rejected')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _deleteFriends(List<String> friendIds) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        for (final friendId in friendIds) {
          // Remove from current user's friends
          transaction.update(
            FirebaseFirestore.instance.collection('users').doc(currentUser.uid),
            {
              'friends': FieldValue.arrayRemove([friendId]),
            },
          );

          // Remove from friend's friends list
          transaction.update(
            FirebaseFirestore.instance.collection('users').doc(friendId),
            {
              'friends': FieldValue.arrayRemove([currentUser.uid]),
            },
          );
        }
      });

      setState(() {
        _isDeleteMode = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friends deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _startChatWithFriend(String friendId, String friendEmail) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      // Create a sorted list to ensure consistent conversation ID
      final participantIds = [currentUserId, friendId]..sort();
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
          'conversation_name': friendEmail.split('@')[0],
          'is_group': false,
          'created_at': FieldValue.serverTimestamp(),
          'last_message': '',
          'last_message_time': FieldValue.serverTimestamp(),
          'unread_count': {
            currentUserId: 0,
            friendId: 0,
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
              conversationName: friendEmail.split('@')[0],
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

  Future<void> _startGroupChat(
      String groupId, String groupName, List<String> memberIds) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      final conversationId = 'group_$groupId';

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
          'group_id': groupId,
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
              conversationName: groupName,
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

  Future<void> _createFriendGroup() async {
    final groupName = _groupNameController.text.trim();

    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }

    if (_selectedFriendIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one friend')),
      );
      return;
    }

    setState(() {
      _isCreatingGroup = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Add creator to the members list
      final allMembers = [currentUser.uid, ..._selectedFriendIds];

      await FirebaseFirestore.instance.collection('friend_groups').add({
        'name': groupName,
        'creator_id': currentUser.uid,
        'members': allMembers,
        'created_at': FieldValue.serverTimestamp(),
      });

      _groupNameController.clear();
      setState(() {
        _showAddGroupModal = false;
        _selectedFriendIds.clear();
        _isCreatingGroup = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend group created!')),
        );
      }
    } catch (e) {
      setState(() {
        _isCreatingGroup = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  void _showGroupCreationModal(List<String> friendIds) {
    final groupNameSuggestions = [
      'SoberGophers',
      'CleanMachines',
      'KetoGang',
      'TeamVegan',
      'FatBurnersUnited',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Create Friend Group',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _selectedFriendIds.clear();
                          _groupNameController.clear();
                        });
                      },
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Group Name',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _groupNameController,
                        decoration: InputDecoration(
                          hintText: 'Enter group name',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Suggested Names',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: groupNameSuggestions.map((name) {
                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                _groupNameController.text = name;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color:
                                      const Color(0xFF6366F1).withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF6366F1),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Select Friends',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...friendIds.map((friendId) {
                        return FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('users')
                              .doc(friendId)
                              .get(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const SizedBox.shrink();
                            }

                            final friendEmail =
                                snapshot.data?.get('email') ?? 'Unknown';

                            return CheckboxListTile(
                              value: _selectedFriendIds.contains(friendId),
                              onChanged: (bool? value) {
                                setModalState(() {
                                  if (value == true) {
                                    _selectedFriendIds.add(friendId);
                                  } else {
                                    _selectedFriendIds.remove(friendId);
                                  }
                                });
                                setState(() {});
                              },
                              title: Text(
                                friendEmail,
                                style: TextStyle(fontSize: 14),
                              ),
                              activeColor: const Color(0xFF6366F1),
                            );
                          },
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
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
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isCreatingGroup
                        ? null
                        : () {
                            Navigator.pop(context);
                            _createFriendGroup();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isCreatingGroup
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Create Group',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: currentUser == null
          ? const Center(child: Text('Not logged in'))
          : SafeArea(
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
                        const Expanded(
                          child: Center(
                            child: Text(
                              'Friends',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Friend Requests Section
                            Text(
                              'Friend Requests',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('friend_requests')
                                  .where('to_user_id',
                                      isEqualTo: currentUser.uid)
                                  .where('status', isEqualTo: 'pending')
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                if (!snapshot.hasData ||
                                    snapshot.data!.docs.isEmpty) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 24),
                                    alignment: Alignment.center,
                                    child: Text(
                                      'No pending friend requests',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  );
                                }

                                return ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: snapshot.data!.docs.length,
                                  itemBuilder: (context, index) {
                                    final doc = snapshot.data!.docs[index];
                                    final fromEmail =
                                        doc['from_email'] as String?;
                                    final fromUserId =
                                        doc['from_user_id'] as String?;

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            fromEmail ?? 'Unknown',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: ElevatedButton(
                                                  onPressed: () {
                                                    _acceptFriendRequest(
                                                      doc.id,
                                                      fromUserId ?? '',
                                                      fromEmail ?? '',
                                                    );
                                                  },
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        const Color(0xFF6366F1),
                                                  ),
                                                  child: const Text(
                                                    'Accept',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: ElevatedButton(
                                                  onPressed: () {
                                                    _rejectFriendRequest(
                                                        doc.id);
                                                  },
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.grey,
                                                  ),
                                                  child: const Text(
                                                    'Reject',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: 24),

                            // Friends List Section
                            Text(
                              'Your Friends',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            StreamBuilder<DocumentSnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(currentUser.uid)
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                if (!snapshot.hasData) {
                                  return const SizedBox.shrink();
                                }

                                final friendIds =
                                    (snapshot.data?.get('friends') as List?)
                                            ?.cast<String>() ??
                                        [];

                                if (friendIds.isEmpty) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 24),
                                    alignment: Alignment.center,
                                    child: Text(
                                      'No friends yet',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  );
                                }

                                return ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: friendIds.length,
                                  itemBuilder: (context, index) {
                                    final friendId = friendIds[index];

                                    return FutureBuilder<DocumentSnapshot>(
                                      future: FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(friendId)
                                          .get(),
                                      builder: (context, snapshot) {
                                        if (!snapshot.hasData) {
                                          return const SizedBox.shrink();
                                        }

                                        final friendEmail =
                                            snapshot.data?.get('email') ??
                                                'Unknown';

                                        return GestureDetector(
                                          onTap: null,
                                          child: Container(
                                            margin: const EdgeInsets.only(
                                                bottom: 12),
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: _isDeleteMode
                                                  ? Colors.grey.shade200
                                                  : Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    friendEmail,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                IconButton(
                                                  onPressed: () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            HomePage(
                                                          readOnly: true,
                                                          hideNav: true,
                                                          userIdOverride:
                                                              friendId,
                                                          showBanner: true,
                                                          bannerTitle:
                                                              friendEmail,
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
                                                        builder: (_) =>
                                                            AchievementsPage(
                                                          userIdOverride:
                                                              friendId,
                                                          titleOverride:
                                                              '${friendEmail}\'s Achievements',
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
                                                IconButton(
                                                  onPressed: () {
                                                    _startChatWithFriend(
                                                        friendId, friendEmail);
                                                  },
                                                  icon: const Icon(
                                                    Icons.chat_bubble_outline,
                                                    color: Color(0xFF6366F1),
                                                  ),
                                                  tooltip: 'Chat',
                                                ),
                                                if (_isDeleteMode)
                                                  IconButton(
                                                    onPressed: () {
                                                      _deleteFriends(
                                                          [friendId]);
                                                    },
                                                    icon: Icon(
                                                      Icons.delete_outline,
                                                      color:
                                                          Colors.red.shade400,
                                                    ),
                                                    tooltip: 'Delete',
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
                            const SizedBox(height: 24),

                            // Friend Groups Section
                            Text(
                              'Friend Groups',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('friend_groups')
                                  .where('creator_id',
                                      isEqualTo: currentUser.uid)
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                if (!snapshot.hasData ||
                                    snapshot.data!.docs.isEmpty) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 24),
                                    alignment: Alignment.center,
                                    child: Text(
                                      'No friend groups yet',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  );
                                }

                                return ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: snapshot.data!.docs.length,
                                  itemBuilder: (context, index) {
                                    final doc = snapshot.data!.docs[index];
                                    final groupName = doc['name'] as String? ??
                                        'Unnamed Group';
                                    final memberIds = (doc['members'] as List?)
                                            ?.cast<String>() ??
                                        [];

                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => FriendGroupPage(
                                              groupId: doc.id,
                                              groupName: groupName,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 12),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.indigo.shade50,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                            color: const Color(0xFF6366F1)
                                                .withOpacity(0.3),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.group,
                                              color: const Color(0xFF6366F1),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    groupName,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${memberIds.length} ${memberIds.length == 1 ? 'member' : 'members'}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          Colors.grey.shade600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () {
                                                _startGroupChat(doc.id,
                                                    groupName, memberIds);
                                              },
                                              icon: const Icon(
                                                Icons.chat_bubble_outline,
                                                color: Color(0xFF6366F1),
                                              ),
                                              tooltip: 'Group Chat',
                                            ),
                                            const Icon(
                                              Icons.arrow_forward_ios,
                                              size: 16,
                                              color: Colors.grey,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                            if (_showAddFriendForm) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  labelText: 'Friend Email',
                                  hintText: 'name@example.com',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _isSubmitting
                                          ? null
                                          : _submitFriendRequest,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF10B981),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: _isSubmitting
                                          ? const SizedBox(
                                              height: 16,
                                              width: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(Colors.white),
                                              ),
                                            )
                                          : const Text('Send Request'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        setState(() {
                                          _showAddFriendForm = false;
                                          _errorMessage = null;
                                          _emailController.clear();
                                        });
                                      },
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 200),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: currentUser == null
          ? null
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUser.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final friendIds =
                    (snapshot.data?.get('friends') as List?)?.cast<String>() ??
                        [];
                final hasFriends = friendIds.isNotEmpty;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (hasFriends)
                      FloatingActionButton(
                        heroTag: 'friends-group',
                        onPressed: () {
                          _showGroupCreationModal(friendIds);
                        },
                        backgroundColor: const Color(0xFF6366F1),
                        child: const Icon(Icons.group_add),
                      ),
                    if (hasFriends) const SizedBox(height: 12),
                    FloatingActionButton(
                      heroTag: 'friends-add',
                      onPressed: () {
                        setState(() {
                          _showAddFriendForm = !_showAddFriendForm;
                          _errorMessage = null;
                        });
                      },
                      backgroundColor: Colors.green.shade400,
                      child: Icon(
                        _showAddFriendForm ? Icons.close : Icons.person_add,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton(
                      heroTag: 'friends-delete',
                      onPressed: () {
                        setState(() {
                          _isDeleteMode = !_isDeleteMode;
                        });
                      },
                      backgroundColor: _isDeleteMode
                          ? Colors.red.shade600
                          : Colors.red.shade400,
                      child: Icon(
                        _isDeleteMode ? Icons.close : Icons.delete_outline,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
