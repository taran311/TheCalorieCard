import 'package:flutter/material.dart';
import 'package:namer_app/pages/messages_page.dart' show confirmClearChat;
import 'package:namer_app/services/chat_service.dart';
import 'package:namer_app/services/group_service.dart';
import 'package:namer_app/ui/responsive.dart';

/// Clear chat, Leave and Delete for a friend group: from a swipe or ⋮ on
/// the Friends page, and from the group's own ⋮. Leaving and deleting
/// always ask first (neither can be undone).

String _leaveBody(LeaveOutcome outcome) => switch (outcome) {
      LeaveOutcome.left =>
        "You'll stop seeing the group's day and its group chat.",
      LeaveOutcome.handedOver =>
        "You'll stop seeing the group's day and its group chat. You made "
            'it, so the next person in it will look after it.',
      LeaveOutcome.deleted =>
        "You're the last one in it, so the group will be deleted.",
    };

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: TextButton.styleFrom(foregroundColor: AppText.red600),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Asks, then leaves. True once left.
Future<bool> leaveGroupWithConfirm(
  BuildContext context, {
  required String uid,
  required String groupId,
  required String groupName,
  required Map<String, dynamic>? groupData,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final outcome = GroupService.outcomeFor(groupData, uid);
  final ok = await _confirm(
    context,
    title: 'Leave $groupName?',
    body: _leaveBody(outcome),
    action: 'Leave',
  );
  if (!ok) return false;
  try {
    final done = await GroupService.leave(uid, groupId);
    messenger.showSnackBar(SnackBar(
        content: Text(done == LeaveOutcome.deleted
            ? '$groupName deleted'
            : 'You left $groupName')));
    return true;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Something went wrong. Please try again.')));
    return false;
  }
}

/// Asks, then deletes for everyone. True once deleted.
Future<bool> deleteGroupWithConfirm(
  BuildContext context, {
  required String groupId,
  required String groupName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await _confirm(
    context,
    title: 'Delete $groupName?',
    body: 'This removes the group for everyone.',
    action: 'Delete',
  );
  if (!ok) return false;
  try {
    await GroupService.delete(groupId);
    messenger.showSnackBar(const SnackBar(content: Text('Group deleted')));
    return true;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Something went wrong. Please try again.')));
    return false;
  }
}

/// Asks, then hides the group chat's messages so far, for [uid] only.
Future<void> clearGroupChatWithConfirm(
  BuildContext context, {
  required String uid,
  required String groupId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await confirmClearChat(context)) return;
  try {
    await ChatService.clearForMe(uid, 'group_$groupId');
    messenger.showSnackBar(const SnackBar(content: Text('Chat cleared')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text("Couldn't clear the chat. Please try again.")));
  }
}

/// The options for one group, as a sheet: Clear chat, Leave group, and
/// Delete group for whoever looks after it.
Future<void> showGroupActions(
  BuildContext context, {
  required String uid,
  required String groupId,
  required String groupName,
  required Map<String, dynamic>? groupData,
}) async {
  final isCreator = groupData?['creator_id'] == uid;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              groupName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Clear chat'),
            subtitle: const Text('Hides the messages so far, just for you'),
            onTap: () => Navigator.pop(sheetContext, 'clear'),
          ),
          ListTile(
            leading: Icon(Icons.logout, color: AppText.red600),
            title: Text('Leave group', style: TextStyle(color: AppText.red600)),
            onTap: () => Navigator.pop(sheetContext, 'leave'),
          ),
          if (isCreator)
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppText.red600),
              title:
                  Text('Delete group', style: TextStyle(color: AppText.red600)),
              subtitle: const Text('Removes it for everyone'),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'clear':
      await clearGroupChatWithConfirm(context, uid: uid, groupId: groupId);
    case 'leave':
      await leaveGroupWithConfirm(context,
          uid: uid, groupId: groupId, groupName: groupName, groupData: groupData);
    case 'delete':
      await deleteGroupWithConfirm(context,
          groupId: groupId, groupName: groupName);
  }
}
