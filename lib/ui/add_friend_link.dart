import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/services/username_service.dart';
import 'package:namer_app/services/web_platform.dart' as web;
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/text_utils.dart';

/// Opens "Add Taz (@taz) as a friend?" for an invite link
/// (https://thecaloriecard.com/?add=taz, or ?add=<uid> for someone
/// without a username). Looks them up, then says plainly if it's you,
/// you're already friends, a request is already waiting, or nobody has
/// that name. Nothing is sent until they tap "Send friend request".
Future<void> handleAddFriendLink(
    BuildContext context, String handleOrUid) async {
  final raw = handleOrUid.trim();
  if (raw.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    messenger?.showSnackBar(
        const SnackBar(content: Text('Sign in to add friends.')));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _AddFriendLinkSheet(
      handleOrUid: raw,
      myUid: user.uid,
      myEmail: user.email,
      messenger: messenger,
    ),
  );
}

/// Shares your invite [link] through the phone's share sheet where there
/// is one, or copies it ("Link copied").
Future<void> shareInviteLink(
  BuildContext context, {
  required String link,
  String? username,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final text = username == null
      ? 'Add me as a friend on The Calorie Card.'
      : "Add me as a friend on The Calorie Card — I'm @$username.";
  var shared = false;
  try {
    shared = await web.shareText('Add me on The Calorie Card', text, link);
  } catch (_) {
    shared = false;
  }
  if (shared) return;
  try {
    await Clipboard.setData(ClipboardData(text: link));
    messenger?.showSnackBar(const SnackBar(content: Text('Link copied')));
  } catch (_) {
    messenger?.showSnackBar(
        SnackBar(content: Text("Couldn't copy it. Your link is $link")));
  }
}

/// Who the link points at, and where you stand with them.
class _LinkTarget {
  final FoundUser user;
  final FriendStatus status;

  const _LinkTarget(this.user, this.status);

  String get name => FriendsService.nameFromUser(user.data);
  String? get username => user.username;
}

class _AddFriendLinkSheet extends StatefulWidget {
  final String handleOrUid;
  final String myUid;
  final String? myEmail;
  final ScaffoldMessengerState? messenger;

  const _AddFriendLinkSheet({
    required this.handleOrUid,
    required this.myUid,
    required this.myEmail,
    required this.messenger,
  });

  @override
  State<_AddFriendLinkSheet> createState() => _AddFriendLinkSheetState();
}

class _AddFriendLinkSheetState extends State<_AddFriendLinkSheet> {
  late Future<_LinkTarget?> _target = _lookUp();

  /// Replaces [_target]'s status after a send that found things had
  /// changed (e.g. they'd just asked you).
  FriendStatus? _status;
  bool _busy = false;
  String? _error;

  Future<_LinkTarget?> _lookUp() async {
    final found = await UsernameService.resolve(widget.handleOrUid);
    if (found == null) return null;
    final status = await FriendsService.relationTo(widget.myUid, found.uid);
    return _LinkTarget(found, status);
  }

  void _retry() {
    setState(() {
      _status = null;
      _error = null;
      _target = _lookUp();
    });
  }

  void _done([String? message]) {
    if (mounted) Navigator.pop(context);
    if (message != null) {
      widget.messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _send(_LinkTarget t) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await FriendsService.sendRequest(
        myUid: widget.myUid,
        myEmail: widget.myEmail,
        toUid: t.user.uid,
        toEmail: '${t.user.data['email'] ?? ''}',
      );
      if (!mounted) return;
      if (status.relation == FriendRelation.none) {
        _done('Friend request sent to ${t.name}');
        return;
      }
      // Something changed since the sheet opened: show that instead.
      setState(() {
        _busy = false;
        _status = status;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't send the request. Check your connection and try "
            'again.';
      });
    }
  }

  Future<void> _accept(_LinkTarget t, String requestId) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FriendsService.acceptRequest(
        requestId: requestId,
        myUid: widget.myUid,
        fromUid: t.user.uid,
      );
      FriendsService.clearNameCache();
      if (mounted) _done("You're now friends with ${t.name}");
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't accept. Check your connection and try again.";
      });
    }
  }

  // ------------------------------------------------------------------ UI

  Widget _title(String text) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
      );

  Widget _body(String text) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.muted),
      );

  Widget _avatar(String name) => Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          gradient: AppColors.brandGradient,
          shape: BoxShape.circle,
        ),
        child: Text(
          name.initial.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  Widget _primary(String label, VoidCallback? onPressed) => FilledButton(
        onPressed: _busy ? null : onPressed,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: _busy
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      );

  Widget _secondary(String label) => TextButton(
        onPressed: _busy ? null : () => _done(),
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: Text(label),
      );

  /// What the link was for, as people would say it: "@taz", or "that
  /// person" for a plain uid link.
  String get _asked {
    final h = UsernameService.normalise(widget.handleOrUid);
    return UsernameService.validate(h) == null ? '@$h' : 'that person';
  }

  List<Widget> _notFound() => [
        Icon(Icons.person_search_rounded, size: 48, color: AppColors.muted),
        const SizedBox(height: 12),
        _title("We couldn't find $_asked"),
        const SizedBox(height: 6),
        _body('The link may be old, or they may have changed their '
            'username. Ask them to send it again.'),
        const SizedBox(height: 20),
        _secondary('OK'),
      ];

  List<Widget> _failed() => [
        _title("Couldn't look that up"),
        const SizedBox(height: 6),
        _body('Check your connection and try again.'),
        const SizedBox(height: 20),
        _primary('Try again', _retry),
        _secondary('Not now'),
      ];

  List<Widget> _found(_LinkTarget t) {
    final status = _status ?? t.status;
    final name = t.name;
    final handle = t.username;
    final who = handle == null ? name : '$name (@$handle)';

    var rest = const <Widget>[];
    switch (status.relation) {
      case FriendRelation.self:
        rest = [
          _title("That's your own link"),
          const SizedBox(height: 6),
          _body('Send it to friends so they can add you.'),
          const SizedBox(height: 20),
          _secondary('OK'),
        ];
      case FriendRelation.friends:
        rest = [
          _title("You're already friends with $name"),
          const SizedBox(height: 20),
          _secondary('OK'),
        ];
      case FriendRelation.requestSent:
        rest = [
          _title("You've already asked $name"),
          const SizedBox(height: 6),
          _body('Your friend request is waiting for them to accept.'),
          const SizedBox(height: 20),
          _secondary('OK'),
        ];
      case FriendRelation.requestReceived:
        final requestId = status.requestId;
        rest = [
          _title('$name has already asked to be your friend'),
          const SizedBox(height: 20),
          _primary(
            'Accept',
            requestId == null ? null : () => _accept(t, requestId),
          ),
          _secondary('Not now'),
        ];
      case FriendRelation.none:
        rest = [
          _title('Add $who as a friend?'),
          const SizedBox(height: 6),
          _body("We'll send them a friend request. Once they accept, "
              "you'll see each other's day."),
          const SizedBox(height: 20),
          _primary('Send friend request', () => _send(t)),
          _secondary('Not now'),
        ];
    }

    return [
      Center(child: _avatar(name)),
      const SizedBox(height: 10),
      Text(
        name,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.gray800,
        ),
      ),
      if (handle != null)
        Text(
          '@$handle',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
      const SizedBox(height: 16),
      ...rest,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: FutureBuilder<_LinkTarget?>(
          future: _target,
          builder: (context, snap) {
            final List<Widget> children;
            if (snap.connectionState != ConnectionState.done) {
              children = [
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 16),
                _body('Finding $_asked…'),
                const SizedBox(height: 24),
              ];
            } else if (snap.hasError) {
              children = _failed();
            } else if (snap.data == null) {
              children = _notFound();
            } else {
              children = _found(snap.data!);
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...children,
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppText.red600),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
