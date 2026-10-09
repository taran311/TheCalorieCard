import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';

/// Sends messages into one-to-one chats from outside the chat screen
/// (e.g. sharing your monthly Wrapped). Uses the same conversation ids and
/// fields as the Chat tab.
class ChatService {
  ChatService._();

  static String conversationId(String a, String b) =>
      a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  static Future<void> sendToFriend({
    required String uid,
    required String myName,
    required String friendId,
    required String friendName,
    required String text,
  }) async {
    final db = BalanceService.db;
    final ref = db
        .collection('conversations')
        .doc(conversationId(uid, friendId));

    final existing = await ref.get();
    if (!existing.exists) {
      await ref.set({
        'participant_ids': [uid, friendId],
        'conversation_name': friendName,
        'is_group': false,
        'last_message': '',
        'last_message_time': FieldValue.serverTimestamp(),
        'unread_count': {uid: 0, friendId: 0},
      });
    }

    final batch = db.batch();
    batch.set(ref.collection('messages').doc(), {
      'sender_id': uid,
      'sender_name': myName,
      'message': text,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent',
    });
    batch.update(ref, {
      'last_message': text,
      'last_message_time': FieldValue.serverTimestamp(),
      'last_sender_id': uid,
      'unread_count.$friendId': FieldValue.increment(1),
    });
    await batch.commit();
  }
}
