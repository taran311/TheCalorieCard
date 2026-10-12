import 'package:flutter/material.dart';
import 'package:namer_app/services/avatar_service.dart';

/// Someone's chosen avatar (a photo or a ready-made one), or [fallback]
/// (the usual initial-letter circle) if they haven't picked one.
class UserAvatar extends StatelessWidget {
  /// From [Avatars.fromUser]; null shows [fallback].
  final Map<String, dynamic>? avatar;
  final double size;
  final Widget fallback;

  const UserAvatar({
    super.key,
    required this.avatar,
    required this.size,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final a = avatar;
    final photo = a?['photo'];
    if (photo is String) {
      final image = Avatars.imageFor(photo);
      if (image != null) {
        return ClipOval(
          child: SizedBox(
            width: size,
            height: size,
            child: Image(
              image: image,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => fallback,
            ),
          ),
        );
      }
    }
    final preset = Avatars.presetById(a?['preset']);
    if (preset != null) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: preset.color, shape: BoxShape.circle),
        child: Text(
          preset.emoji,
          style: TextStyle(fontSize: size * 0.52, height: 1.1),
        ),
      );
    }
    return fallback;
  }
}

/// [UserAvatar] for someone you only have the id of: looks their avatar up
/// (once per session) and redraws when it changes.
class UidAvatar extends StatelessWidget {
  final String uid;
  final double size;
  final Widget fallback;

  const UidAvatar({
    super.key,
    required this.uid,
    required this.size,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Avatars.changed,
      builder: (context, _, __) =>
          FutureBuilder<Map<String, dynamic>?>(
        future: Avatars.forUid(uid),
        builder: (context, snap) => UserAvatar(
          avatar: snap.data,
          size: size,
          fallback: fallback,
        ),
      ),
    );
  }
}
