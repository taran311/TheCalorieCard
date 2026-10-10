import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/pages/messages_page.dart';
import 'package:namer_app/ui/responsive.dart';

/// Chat icon (with an unread count) for the Friends page's app bar.
class MessagesButton extends StatefulWidget {
  const MessagesButton({super.key});

  @override
  State<MessagesButton> createState() => _MessagesButtonState();
}

class _MessagesButtonState extends State<MessagesButton> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _conversations =
      FirebaseFirestore.instance
          .collection('conversations')
          .where('participant_ids', arrayContains: _uid)
          .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _conversations,
      builder: (context, snapshot) {
        var unread = 0;
        for (final doc in snapshot.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
          final counts = doc.data()['unread_count'];
          if (counts is Map) {
            final v = counts[_uid];
            if (v is num) unread += v.toInt();
          }
        }
        const icon = Icon(Icons.chat_bubble_outline);
        return IconButton(
          tooltip: 'Messages',
          color: Colors.white,
          splashRadius: 20,
          // On phones this opens over the bottom bar, like the chats it leads to.
          onPressed: () => chatNavigator(context).push(
            MaterialPageRoute(builder: (_) => const MessagesPage()),
          ),
          icon: unread <= 0
              ? icon
              : Badge(
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  backgroundColor: AppColors.red,
                  child: icon,
                ),
        );
      },
    );
  }
}
