import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:namer_app/pages/home_page.dart';
import 'package:namer_app/pages/achievements_page.dart';

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
                              style: GoogleFonts.poppins(
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
                                      style: GoogleFonts.poppins(
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
                                            style: GoogleFonts.poppins(
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
                              style: GoogleFonts.poppins(
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
                                      style: GoogleFonts.poppins(
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
                                                    style: GoogleFonts.poppins(
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
                                                          builder: (_) => HomePage(
                                                            readOnly: true,
                                                            hideNav: true,
                                                            userIdOverride: friendId,
                                                            showBanner: true,
                                                            bannerTitle: friendEmail,
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
                                                            userIdOverride: friendId,
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
                                                if (_isDeleteMode)
                                                  IconButton(
                                                    onPressed: () {
                                                      _deleteFriends([friendId]);
                                                    },
                                                    icon: Icon(
                                                      Icons.delete_outline,
                                                      color: Colors.red.shade400,
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
                                      onPressed:
                                          _isSubmitting ? null : _submitFriendRequest,
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
                                                    AlwaysStoppedAnimation<Color>(
                                                        Colors.white),
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
                            const SizedBox(height: 24),
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
          : Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
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
                  backgroundColor:
                      _isDeleteMode ? Colors.red.shade600 : Colors.red.shade400,
                  child: Icon(
                    _isDeleteMode ? Icons.close : Icons.delete_outline,
                  ),
                ),
              ],
            ),
    );
  }
}
