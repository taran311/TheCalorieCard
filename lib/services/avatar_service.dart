import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:namer_app/services/balance_service.dart';

/// One of the ready-made avatars: an emoji on a colour.
class AvatarPreset {
  final String id;
  final String emoji;
  final Color color;
  const AvatarPreset(this.id, this.emoji, this.color);
}

/// Profile pictures, shown to friends in Friends and Chat.
///
/// Stored on `users/{uid}.avatar` as either `{preset: 'avocado'}` or
/// `{photo: <small JPEG, base64>}`. No `avatar` means the original
/// initial-letter avatar, which stays the default.
class Avatars {
  Avatars._();

  static const presets = [
    AvatarPreset('sprout', '🌱', Color(0xFFDCFCE7)),
    AvatarPreset('avocado', '🥑', Color(0xFFECFCCB)),
    AvatarPreset('strawberry', '🍓', Color(0xFFFFE4E6)),
    AvatarPreset('broccoli', '🥦', Color(0xFFD1FAE5)),
    AvatarPreset('lemon', '🍋', Color(0xFFFEF9C3)),
    AvatarPreset('watermelon', '🍉', Color(0xFFFCE7F3)),
    AvatarPreset('carrot', '🥕', Color(0xFFFFEDD5)),
    AvatarPreset('grapes', '🍇', Color(0xFFEDE9FE)),
    AvatarPreset('pineapple', '🍍', Color(0xFFFEF3C7)),
    AvatarPreset('chilli', '🌶️', Color(0xFFFEE2E2)),
    AvatarPreset('fox', '🦊', Color(0xFFFFEDD5)),
    AvatarPreset('panda', '🐼', Color(0xFFF1F5F9)),
    AvatarPreset('rocket', '🚀', Color(0xFFE0E7FF)),
    AvatarPreset('star', '⭐', Color(0xFFFEF9C3)),
    AvatarPreset('flex', '💪', Color(0xFFDBEAFE)),
    AvatarPreset('sun', '🌞', Color(0xFFFFF7ED)),
  ];

  /// Biggest photo we'll store (it's resized to 256px first, so real
  /// photos come in well under this).
  static const maxPhotoBytes = 150 * 1024;

  static AvatarPreset? presetById(Object? id) {
    for (final p in presets) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The `avatar` map from a `users/{uid}` doc, or null for the default.
  static Map<String, dynamic>? fromUser(Map<String, dynamic>? user) {
    final a = user?['avatar'];
    if (a is! Map) return null;
    final preset = a['preset'];
    final photo = a['photo'];
    if (preset is String && presetById(preset) != null) {
      return {'preset': preset};
    }
    if (photo is String && photo.isNotEmpty) return {'photo': photo};
    return null;
  }

  // ---------------------------------------------------------------- reads

  static final Map<String, Future<Map<String, dynamic>?>> _cache = {};

  /// Bumped whenever an avatar changes here, so pictures on screen redraw.
  static final ValueNotifier<int> changed = ValueNotifier(0);

  /// [uid]'s avatar, read once per session.
  static Future<Map<String, dynamic>?> forUid(String uid) {
    if (uid.isEmpty) return Future.value(null);
    return _cache.putIfAbsent(uid, () async {
      try {
        final doc = await BalanceService.db.collection('users').doc(uid).get();
        return fromUser(doc.data());
      } catch (_) {
        _cache.remove(uid);
        return null;
      }
    });
  }

  /// Saves a read we already have (e.g. a friend's doc), so it isn't read
  /// again.
  static void remember(String uid, Map<String, dynamic>? user) {
    if (uid.isEmpty || user == null) return;
    final next = fromUser(user);
    final had = _cache.containsKey(uid);
    _cache[uid] = Future.value(next);
    if (had) changed.value++;
  }

  static final Map<String, MemoryImage> _images = {};

  /// The decoded picture for a stored photo, kept so it isn't decoded on
  /// every rebuild.
  static MemoryImage? imageFor(String photo) {
    final cached = _images[photo];
    if (cached != null) return cached;
    try {
      final image = MemoryImage(base64Decode(photo));
      if (_images.length > 200) _images.clear();
      _images[photo] = image;
      return image;
    } catch (_) {
      return null;
    }
  }

  // --------------------------------------------------------------- writes

  static Future<void> _save(String uid, Object value) async {
    await BalanceService.db
        .collection('users')
        .doc(uid)
        .update({'avatar': value});
    _cache[uid] =
        Future.value(value is Map<String, dynamic> ? value : null);
    changed.value++;
  }

  static Future<void> setPreset(String uid, String presetId) async {
    // Clear the old one first: an avatar is a preset or a photo, never
    // both.
    await _save(uid, FieldValue.delete());
    await _save(uid, <String, dynamic>{'preset': presetId});
  }

  /// [jpeg] should already be small (see [maxPhotoBytes]).
  static Future<void> setPhoto(String uid, Uint8List jpeg) {
    if (jpeg.length > maxPhotoBytes) {
      throw const AvatarTooBig();
    }
    return _save(uid, FieldValue.delete()).then(
        (_) => _save(uid, <String, dynamic>{'photo': base64Encode(jpeg)}));
  }

  /// Back to the initial-letter avatar.
  static Future<void> useInitials(String uid) =>
      _save(uid, FieldValue.delete());
}

class AvatarTooBig implements Exception {
  const AvatarTooBig();
}
