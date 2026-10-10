import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';

/// Sends messages into one-to-one chats from outside the chat screen
/// (e.g. sharing your monthly Wrapped). Uses the same conversation ids and
/// fields as the Chat tab.
class ChatService {
  ChatService._();

  static String conversationId(String a, String b) =>
      a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  /// Message fields that callers can't override with `extra` (they'd break
  /// the chat or its unread counts).
  static const _reserved = {
    'sender_id',
    'sender_name',
    'message',
    'timestamp',
    'status',
    'delivered_to',
    'read_by',
  };

  /// [extra] is stored on the message too, e.g. `{'type': 'game',
  /// 'game_id': id}` so the chat can show it as a tappable card. [text] is
  /// always saved as well, so older app versions still show something.
  static Future<void> sendToFriend({
    required String uid,
    required String myName,
    required String friendId,
    required String friendName,
    required String text,
    Map<String, dynamic>? extra,
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
      ..._clean(extra),
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

  /// Sends [text] into a friend group's chat (`conversations/group_{id}`),
  /// starting the chat if nobody has yet. Same fields as the Chat tab.
  static Future<void> sendToGroup({
    required String uid,
    required String myName,
    required String groupId,
    required String groupName,
    required List<String> memberIds,
    required String text,
    Map<String, dynamic>? extra,
  }) async {
    final db = BalanceService.db;
    final ref = db.collection('conversations').doc('group_$groupId');

    final existing = await ref.get();
    var participants = memberIds;
    if (!existing.exists) {
      await ref.set({
        'participant_ids': memberIds,
        'conversation_name': groupName,
        'is_group': true,
        'group_id': groupId,
        'last_message': '',
        'last_message_time': FieldValue.serverTimestamp(),
        'unread_count': {for (final m in memberIds) m: 0},
      });
    } else {
      final stored = existing.data()?['participant_ids'];
      if (stored is List) participants = [for (final p in stored) '$p'];
    }

    final batch = db.batch();
    batch.set(ref.collection('messages').doc(), {
      ..._clean(extra),
      'sender_id': uid,
      'sender_name': myName,
      'message': text,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent',
      'delivered_to': <String>[],
      'read_by': <String>[],
    });
    batch.update(ref, {
      'last_message': text,
      'last_message_time': FieldValue.serverTimestamp(),
      'last_sender_id': uid,
      for (final p in participants)
        if (p != uid) 'unread_count.$p': FieldValue.increment(1),
    });
    await batch.commit();
  }

  static Map<String, dynamic> _clean(Map<String, dynamic>? extra) => {
        if (extra != null)
          for (final e in extra.entries)
            if (!_reserved.contains(e.key)) e.key: e.value,
      };
}
