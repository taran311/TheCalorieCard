import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:namer_app/ui/skeleton.dart';
import 'package:namer_app/services/avatar_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/pages/calorie_game_page.dart';
import 'package:namer_app/pages/games_hub_page.dart';
import 'package:namer_app/services/calorie_game.dart';
import 'package:namer_app/services/chat_service.dart';
import 'package:namer_app/services/friend_activity.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/services/leaderboard_service.dart';
import 'package:namer_app/services/username_service.dart';
import 'package:namer_app/ui/add_friend_link.dart';
import 'package:namer_app/ui/friend_today.dart';
import 'package:namer_app/ui/group_actions.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/tutorials/tutorial_button.dart';
import 'package:namer_app/ui/text_utils.dart';
import 'package:namer_app/ui/username_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:namer_app/pages/challenges_page.dart';
import 'package:namer_app/pages/home_page.dart';
import 'package:namer_app/pages/friend_group_page.dart';
import 'package:namer_app/pages/messages_page.dart';
import 'package:namer_app/pages/hiscores_page.dart';
import 'package:namer_app/ui/messages_button.dart';
import 'package:namer_app/services/referrals.dart';
import 'package:namer_app/ui/referral_card.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({Key? key}) : super(key: key);

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  final TextEditingController _emailController = TextEditingController();
  final ValueNotifier<bool> _isSubmitting = ValueNotifier<bool>(false);

  /// The add-friend error, shown inside the add-friend sheet.
  final ValueNotifier<String?> _addError = ValueNotifier<String?>(null);

  // Created once: building them in build() would re-subscribe every rebuild.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _incomingRequests =
      FirebaseFirestore.instance
          .collection('friend_requests')
          .where('to_user_id', isEqualTo: _uid)
          .where('status', isEqualTo: 'pending')
          .snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _sentRequests =
      FirebaseFirestore.instance
          .collection('friend_requests')
          .where('from_user_id', isEqualTo: _uid)
          .where('status', isEqualTo: 'pending')
          .snapshots();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userDoc =
      FirebaseFirestore.instance.collection('users').doc(_uid).snapshots();

  /// Your own doc again, for your username: one listener (not a
  /// StreamBuilder) because both the page and the add-friend sheet need it.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _meSub;

  /// Unread messages per chat (conversation id → count), for the badges
  /// on each friend's and group's chat button. One listener for the page.
  final ValueNotifier<Map<String, int>> _unread = ValueNotifier(const {});
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _unreadSub;

  /// Your username (no @), once [_meKnown].
  String? _myUsername;
  bool _meKnown = false;

  /// Whether you have any friends, and the groups you're in (names), for
  /// putting Groups first when that's all you have, and for spotting a
  /// new group with the same name as one you're already in.
  bool _hasFriends = false;
  List<String> _groupNames = const [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _groupsSub;

  /// "You, Sam and Jess" per group, fetched once per member list.
  final Map<String, Future<String>> _memberLines = {};

  /// Whether "Pick a username" has been waved away on this device. Null
  /// until read, so the prompt doesn't flash up and vanish.
  bool? _usernamePromptDismissed;

  String get _promptKey => 'username_prompt_dismissed_$_uid';
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _groups =
      FirebaseFirestore.instance
          .collection('friend_groups')
          .where('members', arrayContains: _uid)
          .snapshots();

  late final Stream<List<CalorieGame>> _games =
      CalorieGameService.forUser(_uid);

  /// Friends' user docs, fetched once each. A failed read isn't kept, so
  /// the next rebuild tries again (e.g. once a request is accepted).
  final Map<String, Future<DocumentSnapshot<Map<String, dynamic>>>>
      _friendDocs = {};

  Future<DocumentSnapshot<Map<String, dynamic>>> _friendDoc(String id) =>
      _friendDocs.putIfAbsent(id, () {
        final read =
            FirebaseFirestore.instance.collection('users').doc(id).get();
        read.then<void>(
          // Their avatar comes with it, so it isn't read twice.
          (doc) => Avatars.remember(id, doc.data()),
          onError: (Object _) {
            _friendDocs.remove(id);
          },
        );
        return read;
      });

  @override
  void initState() {
    super.initState();
    _initializeUserDocument();
    _loadPromptDismissed();
    // Invites: a new friend may have just earned you both a free month.
    Referrals.check();
    if (_uid.isNotEmpty) {
      _unreadSub = FirebaseFirestore.instance
          .collection('conversations')
          .where('participant_ids', arrayContains: _uid)
          .snapshots()
          .listen((snap) {
        final counts = <String, int>{};
        for (final doc in snap.docs) {
          final c = doc.data()['unread_count'];
          final v = c is Map ? c[_uid] : null;
          if (v is num && v > 0) counts[doc.id] = v.toInt();
        }
        _unread.value = counts;
      }, onError: (Object _) {});
      _meSub = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .snapshots()
          .listen((doc) {
        if (!mounted) return;
        setState(() {
          _myUsername = UsernameService.usernameFrom(doc.data());
          _meKnown = true;
          _hasFriends =
              ((doc.data()?['friends'] as List?) ?? const []).isNotEmpty;
        });
      }, onError: (Object _) {
        if (mounted) setState(() => _meKnown = true);
      });
      _groupsSub = FirebaseFirestore.instance
          .collection('friend_groups')
          .where('members', arrayContains: _uid)
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        setState(() => _groupNames = [
              for (final d in snap.docs)
                if (d.data()['name'] is String) d.data()['name'] as String
            ]);
      }, onError: (Object _) {});
    }
  }

  Future<void> _loadPromptDismissed() async {
    var dismissed = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      dismissed = prefs.getBool(_promptKey) ?? false;
    } catch (_) {}
    if (mounted) setState(() => _usernamePromptDismissed = dismissed);
  }

  /// "Not now" on the username prompt: it's only offered once.
  Future<void> _dismissUsernamePrompt() async {
    setState(() => _usernamePromptDismissed = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_promptKey, true);
    } catch (_) {}
  }

  /// Opens the username picker; true if they saved one.
  Future<bool> _pickUsername() async {
    final picked = await showUsernameSheet(context);
    if (!mounted || picked == null || picked == usernameSkipped) return false;
    _snack('Saved. Friends can add you as @$picked.');
    return true;
  }

  /// [_shareMyLink] for buttons: uses the username already loaded (so the
  /// share sheet opens straight from the tap), or reads it if it isn't yet.
  Future<void> _onShareMyLink() async {
    if (_meKnown) return _shareMyLink(_myUsername);
    String? username;
    try {
      username = await UsernameService.usernameOf(_uid);
    } catch (_) {}
    if (!mounted) return;
    await _shareMyLink(username);
  }

  /// Shares https://thecaloriecard.com/?add=<username>. With no username
  /// yet, asks for one first (a plain link with your account id works
  /// too, but reads badly).
  Future<void> _shareMyLink(String? username) async {
    if (username != null) {
      await shareInviteLink(
        context,
        link: UsernameService.inviteLink(username),
        username: username,
      );
      return;
    }
    final picked = await showUsernameSheet(
      context,
      intro: 'Pick a username first. Your link will read '
          '${UsernameService.siteHost}/?add=yourname, and friends can find '
          'you by it.',
      skipLabel: 'Share a plain link instead',
    );
    if (!mounted || picked == null) return;
    if (picked == usernameSkipped) {
      await shareInviteLink(context, link: UsernameService.inviteLink(_uid));
    } else {
      await shareInviteLink(
        context,
        link: UsernameService.inviteLink(picked),
        username: picked,
      );
    }
  }

  @override
  void dispose() {
    _meSub?.cancel();
    _unreadSub?.cancel();
    _unread.dispose();
    _groupsSub?.cancel();
    _isSubmitting.dispose();
    _addError.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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

  /// Shows [message] in the add-friend sheet and re-enables the button.
  void _fail(String message) {
    _addError.value = message;
    _isSubmitting.value = false;
  }

  Future<void> _submitFriendRequest(VoidCallback closeSheet) async {
    if (_isSubmitting.value) return;
    final input = _emailController.text.trim();

    if (input.isEmpty) {
      _fail("Enter your friend's username or email.");
      return;
    }

    // "sam@x.com" is an email; "@taz" or "taz" is a username.
    final byEmail = UsernameService.looksLikeEmail(input);
    final handle = UsernameService.normalise(input);
    // (Reserved names pass here: they're looked up, and simply not found.)
    if (!byEmail &&
        UsernameService.validate(handle) != null &&
        !UsernameService.reserved.contains(handle)) {
      _fail("That doesn't look like a username or an email. Usernames are "
          'letters, numbers and _, like @taz.');
      return;
    }

    _isSubmitting.value = true;
    _addError.value = null;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _fail('Please sign in again.');
        return;
      }

      final String targetUserId;
      final String toEmail;
      if (byEmail) {
        final email = input;
        // Find user by email (as typed, then lower-case: sign-up emails are
        // usually stored lower-case, but people type "Sam@Gmail.com").
        var userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (userQuery.docs.isEmpty && email.toLowerCase() != email) {
          userQuery = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: email.toLowerCase())
              .limit(1)
              .get();
        }

        if (userQuery.docs.isEmpty) {
          _fail("We couldn't find anyone with that email. Check it, or ask "
              'them to sign up first.');
          return;
        }
        targetUserId = userQuery.docs.first.id;
        toEmail = email;
      } else {
        final uid = await UsernameService.lookup(handle);
        if (uid == null) {
          _fail("We couldn't find @$handle. Check the spelling, or try "
              'their email.');
          return;
        }
        targetUserId = uid;
        // Same request doc as the email flow, so fill in their email.
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        toEmail = '${doc.data()?['email'] ?? ''}';
      }

      final status = await FriendsService.sendRequest(
        myUid: currentUser.uid,
        myEmail: currentUser.email,
        toUid: targetUserId,
        toEmail: toEmail,
      );

      switch (status.relation) {
        case FriendRelation.self:
          _fail(byEmail
              ? "That's your own email."
              : "That's your own username.");
          return;
        case FriendRelation.friends:
          _fail("You're already friends.");
          return;
        case FriendRelation.requestSent:
          _fail("You've already sent them a request.");
          return;
        case FriendRelation.requestReceived:
          // They already asked to be your friend? Accept that instead of
          // sending a second request the other way.
          _emailController.clear();
          _isSubmitting.value = false;
          closeSheet();
          final requestId = status.requestId;
          if (requestId != null) {
            await _acceptFriendRequest(
              requestId,
              targetUserId,
              status.requestFromEmail ?? toEmail,
            );
          }
          return;
        case FriendRelation.none:
          break;
      }

      _emailController.clear();
      _isSubmitting.value = false;
      closeSheet();
      _snack('Request sent');
    } catch (_) {
      _fail("Couldn't send the request. Check your connection and try again.");
    }
  }

  void _showAddFriendSheet() {
    _emailController.clear();
    _addError.value = null;
    _isSubmitting.value = false;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        void close() {
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Add a friend',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Add them by username or email. We'll send them a "
                    'friend request.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<String?>(
                    valueListenable: _addError,
                    builder: (context, error, _) => TextField(
                      controller: _emailController,
                      autofocus: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      // The email keyboard has @ to hand for both.
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submitFriendRequest(close),
                      onChanged: (_) {
                        if (_addError.value != null) _addError.value = null;
                      },
                      decoration: InputDecoration(
                        labelText: 'Username or email',
                        hintText: '@taz or name@example.com',
                        errorText: error,
                        errorMaxLines: 3,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<bool>(
                    valueListenable: _isSubmitting,
                    builder: (context, busy, _) => FilledButton(
                      onPressed: busy ? null : () => _submitFriendRequest(close),
                      child: busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Send request'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Easier than typing for a friend who's not signed up.
                  TextButton.icon(
                    onPressed: () {
                      close();
                      _onShareMyLink();
                    },
                    icon: const Icon(Icons.ios_share_rounded, size: 20),
                    label: const Text('Or share your link'),
                  ),
                  TextButton(
                    onPressed: close,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _cancelFriendRequest(String requestId) async {
    try {
      await FirebaseFirestore.instance
          .collection('friend_requests')
          .doc(requestId)
          .delete();
      _snack('Request cancelled');
    } catch (_) {
      _snack('Something went wrong. Please try again.');
    }
  }

  Future<void> _acceptFriendRequest(
      String requestId, String fromUserId, String fromEmail) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await FriendsService.acceptRequest(
        requestId: requestId,
        myUid: currentUser.uid,
        fromUid: fromUserId,
      );

      _snack("You're now friends with ${FriendsService.displayName(fromEmail)}");
    } catch (_) {
      _snack('Something went wrong. Please try again.');
    }
  }

  Future<void> _rejectFriendRequest(String requestId) async {
    try {
      await FirebaseFirestore.instance
          .collection('friend_requests')
          .doc(requestId)
          .update({'status': 'rejected'});
      _snack('Request declined');
    } catch (_) {
      _snack('Something went wrong. Please try again.');
    }
  }

  Future<void> _confirmRemoveFriend(String friendId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove $name?'),
        content: const Text(
            "You'll stop seeing each other's cards and high scores, and "
            "they'll be taken out of any groups you made."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppText.red600),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await _removeFriend(friendId);
  }

  Future<void> _removeFriend(String friendId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // Groups first, while you're still friends (in case the rules want
    // that). Groups someone else made can only be changed by them.
    List<String>? sharedGroups;
    try {
      sharedGroups =
          await FriendsService.removeFromMyGroups(currentUser.uid, friendId);
    } catch (_) {
      sharedGroups = null; // Couldn't check: say so honestly below.
    }

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
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
      });

      if (sharedGroups == null) {
        _snack("Friend removed. They'll still see you in groups you share "
            '— leave or edit the group to stop that.');
      } else if (sharedGroups.isNotEmpty) {
        final names = sharedGroups.join(', ');
        final it = sharedGroups.length == 1 ? 'it' : 'them';
        _snack("Friend removed. You're both still in $names, made by someone "
            'else — leave $it to stop seeing each other there.');
      } else {
        _snack('Friend removed');
      }
    } catch (_) {
      _snack('Something went wrong. Please try again.');
    }
  }

  void _openFriendCard(String friendId, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HomePage(
          readOnly: true,
          userIdOverride: friendId,
          showBanner: true,
          bannerTitle: name,
        ),
      ),
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

  Future<void> _startChatWithFriend(String friendId, String name) async {
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
          'conversation_name': name,
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

      _openChat(conversationId, name, false);
    } catch (_) {
      _snack("Couldn't open the chat. Please try again.");
    }
  }

  /// Sends a quick cheer into your chat with a friend, then opens the chat.
  Future<void> _sendCheer(String friendId, String name) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await ChatService.sendToFriend(
        uid: user.uid,
        myName: await FriendsService.nameFor(user.uid, email: user.email),
        friendId: friendId,
        friendName: name,
        text: '👏 Keep it up!',
      );
      _openChat(
        ChatService.conversationId(user.uid, friendId),
        name,
        false,
      );
    } catch (_) {
      _snack('Message not sent. Check your connection and try again.');
    }
  }

  /// A friendly "have you logged today?" in your chat with them, at most
  /// once a day per friend. Returns true once they've been nudged today
  /// (now or earlier), false if it couldn't be sent.
  Future<bool> _sendNudge(String friendId, String name) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final sent = await FriendActivity.nudge(
        uid: user.uid,
        myName: await FriendsService.nameFor(user.uid, email: user.email),
        friendId: friendId,
        friendName: name,
      );
      _snack(sent
          ? 'Nudge sent to $name'
          : "You've already nudged $name today");
      return true;
    } catch (_) {
      _snack('Nudge not sent. Check your connection and try again.');
      return false;
    }
  }

  /// Today at a glance for one friend, with Cheer and Nudge.
  void _showFriendSheet(String friendId, String name) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _FriendDaySheet(
        friendId: friendId,
        name: name,
        onCheer: () {
          Navigator.pop(sheetContext);
          _sendCheer(friendId, name);
        },
        onNudge: () => _sendNudge(friendId, name),
        onViewCard: () {
          Navigator.pop(sheetContext);
          _openFriendCard(friendId, name);
        },
      ),
    );
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

      _openChat(conversationId, groupName, true);
    } catch (_) {
      _snack("Couldn't open the chat. Please try again.");
    }
  }

  Future<void> _showNewGroupSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _NewGroupSheet(uid: _uid, existingNames: _groupNames),
    );
    if (created == true) _snack('Group created');
  }

  // ---------------------------------------------------------------- UI bits

  static TextStyle get _sectionStyle => TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  static TextStyle get _nameStyle => TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.gray800,
  );

  static TextStyle get _subStyle => TextStyle(fontSize: 12, color: AppColors.gray600);

  Widget _emptyNote(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: AppDecor.card,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: AppColors.muted),
      ),
    );
  }

  /// No friends yet: what they're for, and the two ways to add one, right
  /// here rather than in a corner of the screen.
  Widget _noFriendsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: AppDecor.card,
      child: Column(
        children: [
          Text(
            'No friends added yet. Add people to compare high scores, send '
            'challenges and cheer each other on.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _showAddFriendSheet,
                icon: const Icon(Icons.person_add, size: 20),
                label: const Text('Add a friend'),
              ),
              OutlinedButton.icon(
                onPressed: _onShareMyLink,
                icon: const Icon(Icons.ios_share_rounded, size: 20),
                label: const Text('Share my link'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _loadError() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          "Couldn't load this. Check your connection.",
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
      ),
    );
  }

  Widget _loading() {
    return const SkeletonList(rows: 4, roundLeading: true);
  }

  /// The chat button's icon, with a red count when there are unread
  /// messages in [conversationId].
  Widget _chatIcon(String conversationId) {
    final icon = Icon(
      Icons.chat_bubble_outline,
      color: AppText.primary,
      size: 22,
    );
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: _unread,
      builder: (context, unread, _) {
        final n = unread[conversationId] ?? 0;
        if (n <= 0) return icon;
        return Badge(
          label: Text(n > 99 ? '99+' : '$n'),
          backgroundColor: AppColors.red,
          child: icon,
        );
      },
    );
  }

  Widget _avatar(String text, {Color color = AppColors.primary}) {
    return CircleAvatar(
      radius: 22,
      backgroundColor: color,
      child: Text(
        text.initial.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// A white, bordered, tappable card. [wrap] goes round the card itself
  /// (inside the gap below it), e.g. to make it swipeable.
  Widget _tappableCard({
    required VoidCallback onTap,
    required Widget child,
    Widget Function(Widget card)? wrap,
  }) {
    final card = Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppDecor.radius)),
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: child),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: wrap == null ? card : wrap(card),
    );
  }

  /// High scores, Challenges and Games as one row of small tiles, at the top
  /// of the page: they work whether or not you've added friends yet.
  Widget _shortcutTiles() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _ShortcutTile(
                label: 'High scores',
                icon: Icon(Icons.leaderboard,
                    color: AppText.primary, size: 24),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const HiscoresPage(fromFriends: true),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ShortcutTile(
                label: 'Challenges',
                icon: Icon(Icons.emoji_events_outlined,
                    color: AppText.primary, size: 24),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChallengesPage()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StreamBuilder<List<CalorieGame>>(
                stream: _games,
                builder: (context, snap) {
                  final waiting = snap.hasData
                      ? CalorieGameService.waitingOn(_uid, snap.data!)
                      : 0;
                  const target = Text('🎯', style: TextStyle(fontSize: 22));
                  return _ShortcutTile(
                    label: 'Games',
                    note: waiting == 0
                        ? null
                        : waiting == 1
                            ? '1 waiting for you'
                            : '$waiting waiting for you',
                    icon: waiting == 0
                        ? target
                        : Badge(
                            label: Text(waiting > 9 ? '9+' : '$waiting'),
                            backgroundColor: AppColors.red,
                            child: target,
                          ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const GamesHubPage()),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Incoming requests, highlighted at the top. Nothing at all when there
  /// aren't any (or while loading), so the page leads with your friends.
  Widget _incomingRequestsSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _incomingRequests,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 2),
          decoration: BoxDecoration(
            color: AppColors.indigo50,
            borderRadius: BorderRadius.circular(AppDecor.radius + 4),
            border: Border.all(color: AppColors.indigo300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  docs.length == 1
                      ? 'Friend request'
                      : 'Friend requests (${docs.length})',
                  style: _sectionStyle,
                ),
              ),
              for (final doc in docs) _incomingRequestCard(doc),
            ],
          ),
        );
      },
    );
  }

  Widget _incomingRequestCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final fromEmail = data['from_email'] as String?;
    final fromUserId = data['from_user_id'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AppDecor.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _avatar(fromEmail ?? 'U', color: AppColors.emerald600),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _requestName(fromUserId, fromEmail),
                    const SizedBox(height: 2),
                    Text('wants to be your friend', style: _subStyle),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _acceptFriendRequest(
                    doc.id,
                    fromUserId ?? '',
                    fromEmail ?? '',
                  ),
                  icon: const Icon(Icons.check, size: 20),
                  label: const Text('Accept'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _rejectFriendRequest(doc.id),
                  icon: const Icon(Icons.close, size: 20),
                  label: const Text('Decline'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The name on a friend request: the name they chose if their profile
  /// can be read, otherwise the start of their email. Their @username
  /// goes underneath when they have one.
  Widget _requestName(String? userId, String? email) {
    final fallback = FriendsService.displayName(email);
    Widget text(String name, [String? username]) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: _nameStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (username != null) _usernameLine(username),
          ],
        );
    if (userId == null || userId.isEmpty) return text(fallback);
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _friendDoc(userId),
      builder: (context, snap) {
        final data = snap.hasError ? null : snap.data?.data();
        return text(
          data == null ? fallback : FriendsService.nameFromUser(data),
          UsernameService.usernameFrom(data),
        );
      },
    );
  }

  /// "@taz", small, under a name.
  Widget _usernameLine(String username) => Text(
        '@$username',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: AppColors.muted),
      );

  Widget _sentRequestsSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _sentRequests,
      builder: (context, snapshot) {
        // Sent requests are a side note: stay quiet while loading or failing.
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text('Sent requests', style: _sectionStyle),
            const SizedBox(height: 12),
            for (final doc in snapshot.data!.docs) _sentRequestCard(doc),
          ],
        );
      },
    );
  }

  Widget _sentRequestCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final toEmail = doc.data()['to_email'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: AppDecor.card,
      child: Row(
        children: [
          _avatar(toEmail ?? 'U', color: AppColors.indigo400),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _requestName(doc.data()['to_user_id'] as String?, toEmail),
                const SizedBox(height: 2),
                Text('Waiting for them to accept', style: _subStyle),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _cancelFriendRequest(doc.id),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _friendsSection() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDoc,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _loadError();
        if (!snapshot.hasData) return _loading();

        final friendIds = [
          for (final id in (snapshot.data!.data()?['friends'] as List?) ??
              const [])
            id.toString()
        ];

        if (friendIds.isEmpty) return _noFriendsCard();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // One list: each friend's ring shows how their day's going
            // (it used to be a separate strip above the same people).
            for (final friendId in friendIds)
              FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                key: ValueKey(friendId),
                future: _friendDoc(friendId),
                builder: (context, friendSnapshot) {
                  if (!friendSnapshot.hasData) {
                    return const SizedBox.shrink();
                  }
                  final data = friendSnapshot.data!.data();
                  return _friendRow(
                    friendId,
                    FriendsService.nameFromUser(data),
                    username: UsernameService.usernameFrom(data),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _friendRow(String friendId, String name, {String? username}) {
    // On the narrowest phones the game button goes (it's in ⋮ too), so
    // the name and status keep enough room.
    final roomy = MediaQuery.sizeOf(context).width >= 360;
    return _tappableCard(
      onTap: () => _openFriendCard(friendId, name),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        child: Row(
          children: [
            // Their day as a ring round their photo (✓ once finished). Tap
            // it for Cheer and Nudge.
            FriendTodayBuilder(
              userId: friendId,
              builder: (context, day) => Semantics(
                button: true,
                label: day == null ? name : '$name: ${day.label}',
                excludeSemantics: true,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _showFriendSheet(friendId, name),
                  child: ProgressAvatar(
                      name: name, day: day, size: 46, uid: friendId),
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
                    style: _nameStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (username != null) _usernameLine(username),
                  const SizedBox(height: 3),
                  FriendTodayStatus(friendId: friendId),
                ],
              ),
            ),
            if (roomy)
              IconButton(
                onPressed: () => startCalorieGame(context,
                    friendId: friendId, friendName: name, confirm: true),
                icon: Icon(
                  Icons.videogame_asset_outlined,
                  color: AppText.primary,
                  size: 22,
                ),
                tooltip: 'Play a game',
              ),
            IconButton(
              onPressed: () => _startChatWithFriend(friendId, name),
              icon: _chatIcon(ChatService.conversationId(_uid, friendId)),
              tooltip: 'Chat',
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(Icons.more_vert, color: AppColors.gray600),
              onSelected: (value) {
                switch (value) {
                  case 'card':
                    _openFriendCard(friendId, name);
                  case 'cheer':
                    _sendCheer(friendId, name);
                  case 'nudge':
                    _sendNudge(friendId, name);
                  case 'game':
                    startCalorieGame(context,
                        friendId: friendId, friendName: name, confirm: true);
                  case 'remove':
                    _confirmRemoveFriend(friendId, name);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'card', child: Text('View card')),
                PopupMenuItem(value: 'cheer', child: Text('Send a cheer 👏')),
                PopupMenuItem(value: 'nudge', child: Text('Nudge to log 👋')),
                PopupMenuItem(
                    value: 'game', child: Text('Play a game 🎯')),
                PopupMenuItem(
                  value: 'remove',
                  child: Text(
                    'Remove friend',
                    style: TextStyle(color: AppText.red600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// "Your friends" with Share my link and Add friend, and, once, a
  /// friendly nudge to pick a username if you haven't.
  Widget _friendsHeader() {
    final showPrompt = _meKnown &&
        _myUsername == null &&
        _usernamePromptDismissed == false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Your friends', style: _sectionStyle)),
            IconButton(
              onPressed: _onShareMyLink,
              icon: Icon(Icons.ios_share_rounded,
                  size: 22, color: AppText.primary),
              tooltip: 'Share my link',
            ),
            const SizedBox(width: 4),
            FilledButton.tonalIcon(
              onPressed: _showAddFriendSheet,
              icon: const Icon(Icons.person_add, size: 20),
              label: const Text('Add friend'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        if (_myUsername != null) _myUsernameLine(_myUsername!),
        if (showPrompt) ...[
          const SizedBox(height: 8),
          _usernamePrompt(),
        ],
      ],
    );
  }

  /// "You're @taran", so you know what to tell friends: tap to copy, or
  /// change it.
  Widget _myUsernameLine(String username) {
    return Row(
      children: [
        Flexible(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: '@$username'));
              _snack('Copied @$username');
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: "You're ",
                    style: TextStyle(color: AppColors.gray600),
                  ),
                  TextSpan(
                    text: '@$username',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppText.primaryDark,
                    ),
                  ),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(Icons.copy_rounded,
                          size: 15, color: AppColors.gray400),
                    ),
                  ),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        TextButton(
          onPressed: () async {
            final picked =
                await showUsernameSheet(context, current: username);
            if (!mounted || picked == null || picked == usernameSkipped) {
              return;
            }
            _snack('Saved. Friends can add you as @$picked.');
          },
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          child: const Text('Change'),
        ),
      ],
    );
  }

  Widget _usernamePrompt() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.indigo50,
        borderRadius: BorderRadius.circular(AppDecor.radius),
        border: Border.all(color: AppColors.indigo300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'Pick a username',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'Friends can add you as @yourname instead of typing your '
              'email, and your invite link is easier to share.',
              style: TextStyle(fontSize: 13.5, color: AppColors.gray700),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                TextButton(
                  onPressed: _dismissUsernamePrompt,
                  child: const Text('Not now'),
                ),
                TextButton(
                  onPressed: _pickUsername,
                  child: const Text('Pick a username'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupsSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _groups,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _loadError();
        if (!snapshot.hasData) return _loading();

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return _emptyNote(
              "No groups yet. Make one to see each other's day together.");
        }

        return Column(
          children: [
            for (final doc in docs) _groupCard(doc),
          ],
        );
      },
    );
  }

  static const _groupColors = [
    AppColors.primaryDark,
    AppColors.violet600,
    AppColors.emerald600,
    AppColors.amber700,
    AppColors.rose600,
    AppColors.indigo800,
  ];

  /// The same colour for a group every time (picked from its id).
  static Color _groupColor(String groupId) {
    var h = 0;
    for (final c in groupId.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _groupColors[h % _groupColors.length];
  }

  /// "Lunch Club" → "LC", "SoberGophers" → "SG", "Family" → "F".
  static String _groupInitials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.length >= 2) {
      return (words.first.initial + words.elementAt(1).initial).toUpperCase();
    }
    final word = words.isEmpty ? '?' : words.first;
    final caps = RegExp('[A-Z]').allMatches(word).map((m) => m[0]!).toList();
    if (caps.length >= 2) return caps.take(2).join();
    return word.initial.toUpperCase();
  }

  /// "You, Sam and Jess" or "You, Sam, Jess and 2 more".
  Future<String> _memberLine(String groupId, List<String> memberIds) {
    return _memberLines.putIfAbsent('$groupId|${memberIds.join(',')}',
        () async {
      final others = memberIds.where((id) => id != _uid).toList();
      final shown = others.take(3).toList();
      final names = <String>[];
      for (final id in shown) {
        try {
          names.add(FriendsService.nameFromUser((await _friendDoc(id)).data()));
        } catch (_) {}
      }
      final rest = others.length - names.length;
      final all = [
        if (memberIds.contains(_uid)) 'You',
        ...names,
        if (rest > 0) '$rest more',
      ];
      if (all.length <= 1) return all.join();
      return '${all.sublist(0, all.length - 1).join(', ')} and ${all.last}';
    });
  }

  Widget _groupCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final rawName = data['name'];
    final groupName =
        rawName is String && rawName.isNotEmpty ? rawName : 'Unnamed group';
    final memberIds = [
      for (final id in (data['members'] as List?) ?? const []) id.toString()
    ];

    void actions() => showGroupActions(context,
        uid: _uid, groupId: doc.id, groupName: groupName, groupData: data);

    return _tappableCard(
      // Swipe left (like removing a food) for Clear chat and Leave. It
      // opens the options rather than acting, since leaving can't be undone.
      wrap: (card) => Dismissible(
        key: ValueKey('group-${doc.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          actions();
          return false;
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(AppDecor.radius),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.more_horiz, color: Colors.white),
              SizedBox(width: 6),
              Text('Options',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        child: card,
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FriendGroupPage(
            groupId: doc.id,
            groupName: groupName,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            // Its own colour and initials, so two groups with the same
            // name still look different.
            CircleAvatar(
              radius: 22,
              backgroundColor: _groupColor(doc.id),
              child: Text(
                _groupInitials(groupName),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    groupName,
                    style: _nameStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  FutureBuilder<String>(
                    future: _memberLine(doc.id, memberIds),
                    builder: (context, snap) => Text(
                      snap.data ??
                          '${memberIds.length} ${memberIds.length == 1 ? 'member' : 'members'}',
                      style: _subStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _startGroupChat(doc.id, groupName, memberIds),
              icon: _chatIcon('group_${doc.id}'),
              tooltip: 'Group chat',
            ),
            IconButton(
              onPressed: actions,
              icon: Icon(Icons.more_vert, color: AppColors.gray600),
              tooltip: 'More',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Friends')),
        body: const Center(child: Text('Sign in to see your friends.')),
      );
    }

    // Keyed, so each keeps its state when the order swaps.
    final friends = KeyedSubtree(
      key: const ValueKey('friends'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _friendsHeader(),
          const SizedBox(height: 12),
          ReferralCard(onShare: _onShareMyLink),
          const SizedBox(height: 12),
          _friendsSection(),
          _sentRequestsSection(),
        ],
      ),
    );
    final groups = KeyedSubtree(
      key: const ValueKey('groups'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Groups', style: _sectionStyle)),
              TextButton.icon(
                onPressed: _showNewGroupSheet,
                icon: const Icon(Icons.group_add),
                label: const Text('New group'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _groupsSection(),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Friends'),
        actions: const [
          ScreenHelpButton(tutorialIds: ['friends', 'chat', 'calorie_game']),
          MessagesButton(),
        ],
      ),
      // A plain scroll view (not a lazy list) so the sections' streams stay
      // subscribed while scrolled off screen.
      body: SingleChildScrollView(
        // Room at the bottom for the Coach button.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FirstVisitHint(
            screen: 'friends',
            label: 'Friends',
            tutorialIds: const ['friends', 'chat', 'calorie_game'],
            onShow: () => showScreenHelp(context,
                tutorialIds: const ['friends', 'chat', 'calorie_game']),
          ),
          _incomingRequestsSection(),
          _shortcutTiles(),
          const SizedBox(height: 12),
          // Groups first when they're all you have so far.
          if (_meKnown && !_hasFriends && _groupNames.isNotEmpty) ...[
            groups,
            const SizedBox(height: 12),
            friends,
          ] else ...[
            friends,
            const SizedBox(height: 12),
            groups,
          ],
        ],
        ),
      ),
    );
  }
}

/// Sheet for making a friend group: a name and at least one friend.
class _NewGroupSheet extends StatefulWidget {
  final String uid;

  /// Names of the groups you're already in.
  final List<String> existingNames;

  const _NewGroupSheet({required this.uid, this.existingNames = const []});

  @override
  State<_NewGroupSheet> createState() => _NewGroupSheetState();
}

class _NewGroupSheetState extends State<_NewGroupSheet> {
  static const _suggestions = [
    'Lunch Club',
    'Gym Buddies',
    'Family',
    'Weekday Warriors',
    'Step Squad',
  ];

  final TextEditingController _name = TextEditingController();
  final Set<String> _chosen = {};
  late Future<List<Friend>> _friends = FriendsService.load(widget.uid);
  bool _saving = false;
  String? _error;

  bool get _sameName {
    final name = _name.text.trim().toLowerCase();
    return name.isNotEmpty &&
        widget.existingNames.any((n) => n.trim().toLowerCase() == name);
  }

  bool get _canCreate =>
      !_saving && _name.text.trim().isNotEmpty && _chosen.isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_canCreate) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await FirebaseFirestore.instance.collection('friend_groups').add({
        'name': _name.text.trim(),
        'creator_id': widget.uid,
        // The creator is a member too.
        'members': [widget.uid, ..._chosen],
        'created_at': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't create the group. Please try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'New group',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Group name',
                          hintText: 'e.g. Lunch Club',
                          border: const OutlineInputBorder(),
                          // Allowed, but easy to mix up.
                          helperText: _sameName
                              ? "You're already in a group called this. A "
                                  'different name keeps them apart.'
                              : null,
                          helperMaxLines: 2,
                          helperStyle: TextStyle(color: AppText.amber700),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Ideas',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.gray700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final idea in _suggestions)
                            ActionChip(
                              label: Text(idea),
                              onPressed: () => setState(() {
                                _name.text = idea;
                                _name.selection = TextSelection.collapsed(
                                    offset: idea.length);
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Who's in?",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.gray700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FutureBuilder<List<Friend>>(
                        future: _friends,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      "Couldn't load your friends.",
                                      style: TextStyle(color: AppColors.muted),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _friends =
                                          FriendsService.load(widget.uid);
                                    }),
                                    child: const Text('Try again'),
                                  ),
                                ],
                              ),
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final friends = snapshot.data!;
                          if (friends.isEmpty) {
                            return Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Add a friend first, then you can make a group.',
                                style: TextStyle(color: AppColors.muted),
                              ),
                            );
                          }
                          return Column(
                            children: [
                              for (final f in friends)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  value: _chosen.contains(f.id),
                                  title: Text(
                                    f.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onChanged: (v) => setState(() {
                                    if (v == true) {
                                      _chosen.add(f.id);
                                    } else {
                                      _chosen.remove(f.id);
                                    }
                                  }),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(color: AppText.red600),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _canCreate ? _create : null,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Create group'),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A friend's day in one line ("62% of budget spent · on track",
/// "Finished ✓ · on budget"). Live: it updates as they log, and moves on
/// at midnight.
class FriendTodayStatus extends StatelessWidget {
  final String friendId;

  const FriendTodayStatus({super.key, required this.friendId});

  @override
  Widget build(BuildContext context) {
    return FriendTodayBuilder(
      userId: friendId,
      builder: (context, day) {
        // Same height while loading, so rows don't jump.
        if (day == null) return const SizedBox(height: 16);
        final Color color;
        if (day.finished) {
          color = day.onTrack == false ? AppText.amber700 : AppText.emerald700;
        } else if (day.onTrack == false) {
          color = AppText.amber700;
        } else {
          color = AppColors.muted;
        }
        final row = Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                day.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: color),
              ),
            ),
          ],
        );
        if (!day.finished) return row;
        return Tooltip(
          message: "They've closed their day on the Card",
          child: row,
        );
      },
    );
  }
}

/// A small tile in the row under your friends (High scores and so on).
class _ShortcutTile extends StatelessWidget {
  final String label;
  final Widget icon;
  final String? note;
  final bool highlighted;
  final VoidCallback onTap;

  const _ShortcutTile({
    required this.label,
    required this.icon,
    required this.onTap,
    this.note,
    // ignore: unused_element_parameter
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = highlighted ? Colors.white : AppColors.ink;
    return Semantics(
      button: true,
      label: note == null ? label : '$label, $note',
      excludeSemantics: true,
      child: Material(
        color: highlighted ? Colors.transparent : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDecor.radius),
          side: highlighted
              ? BorderSide.none
              : BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: highlighted
              ? const BoxDecoration(gradient: AppColors.brandGradient)
              : null,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 88),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: 28, child: Center(child: icon)),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                    if (note != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        note!,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppText.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A friend's day, from the activity strip: progress, streak, and quick
/// ways to encourage them.
class _FriendDaySheet extends StatefulWidget {
  final String friendId;
  final String name;
  final VoidCallback onCheer;
  final Future<bool> Function() onNudge;
  final VoidCallback onViewCard;

  const _FriendDaySheet({
    required this.friendId,
    required this.name,
    required this.onCheer,
    required this.onNudge,
    required this.onViewCard,
  });

  @override
  State<_FriendDaySheet> createState() => _FriendDaySheetState();
}

class _FriendDaySheetState extends State<_FriendDaySheet> {
  /// Their streak, worked out once when the sheet opens (it reads a few
  /// weeks of history, so it isn't on the strip itself).
  late final Future<int> _streak = LeaderboardService.streakFor(widget.friendId)
      .then((r) => r.current)
      .catchError((_) => 0);
  late final Future<bool> _nudgedAlready =
      FriendActivity.nudgedToday(widget.friendId);
  bool _nudging = false;
  bool _nudged = false;

  Future<void> _nudge() async {
    setState(() => _nudging = true);
    final sent = await widget.onNudge();
    if (!mounted) return;
    setState(() {
      _nudging = false;
      // Nudged now or earlier today: nothing more to send. (A failed send
      // shows its own message and can be tried again.)
      _nudged = sent || _nudged;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: FriendTodayBuilder(
          userId: widget.friendId,
          builder: (context, day) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ProgressAvatar(
                      name: widget.name,
                      day: day,
                      size: 60,
                      uid: widget.friendId),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          day?.label ?? ' ',
                          style:
                              TextStyle(fontSize: 13, color: AppColors.gray700),
                        ),
                        FutureBuilder<int>(
                          future: _streak,
                          builder: (context, snap) {
                            final streak = snap.data ?? 0;
                            if (streak <= 0) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '🔥 $streak-day streak',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppText.amber700,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.onCheer,
                      child: const Text('Cheer 👏'),
                    ),
                  ),
                  // No point nudging someone who's already finished.
                  if (day?.finished != true) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: FutureBuilder<bool>(
                        future: _nudgedAlready,
                        builder: (context, snap) {
                          final done = _nudged || snap.data == true;
                          return OutlinedButton(
                            onPressed:
                                done || _nudging || !snap.hasData ? null : _nudge,
                            child: Text(done ? 'Nudged today' : 'Nudge to log'),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: widget.onViewCard,
                child: Text('View ${widget.name}\'s card'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
