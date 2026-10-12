import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:namer_app/services/avatar_service.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/text_utils.dart';
import 'package:namer_app/ui/user_avatar.dart';

/// "Choose your avatar": your initial (the default), a ready-made one, or
/// a photo from your camera roll (phone) or files (computer).
Future<void> showAvatarPicker(
  BuildContext context, {
  required String uid,
  required String name,
  required Map<String, dynamic>? current,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AvatarPicker(uid: uid, name: name, current: current),
  );
}

class _AvatarPicker extends StatefulWidget {
  final String uid;
  final String name;
  final Map<String, dynamic>? current;

  const _AvatarPicker({
    required this.uid,
    required this.name,
    required this.current,
  });

  @override
  State<_AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<_AvatarPicker> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() save) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await save();
      if (mounted) Navigator.pop(context);
    } on AvatarTooBig {
      _fail("That picture is too big. Try another one.");
    } catch (_) {
      _fail("Couldn't save that. Please try again.");
    }
  }

  void _fail(String message) {
    if (mounted) {
      setState(() {
        _busy = false;
        _error = message;
      });
    }
  }

  Future<void> _pickPhoto() async {
    if (_busy) return;
    XFile? file;
    try {
      // Phones open the camera roll; computers open a file picker.
      file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 75,
      );
    } catch (_) {
      _fail("Couldn't open your photos.");
      return;
    }
    if (file == null) return; // cancelled
    final picked = file;
    await _run(() async =>
        Avatars.setPhoto(widget.uid, await picked.readAsBytes()));
  }

  Widget _initialCircle(double size) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        child: Text(
          widget.name.initial.toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  Widget _option({
    required bool selected,
    required Widget child,
    required VoidCallback onTap,
    required String label,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 3,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.current;
    const size = 52.0;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: UserAvatar(
                avatar: current,
                size: 88,
                fallback: _initialCircle(88),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your avatar',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Friends see it in Friends and Chat.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.gray600),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _pickPhoto,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Use a photo'),
            ),
            const SizedBox(height: 20),
            Text(
              'Or pick one',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.gray700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _option(
                  selected: current == null,
                  label: 'Your initial',
                  onTap: () => _run(() => Avatars.useInitials(widget.uid)),
                  child: _initialCircle(size),
                ),
                for (final p in Avatars.presets)
                  _option(
                    selected: current?['preset'] == p.id,
                    label: p.id,
                    onTap: () => _run(() => Avatars.setPreset(widget.uid, p.id)),
                    child: UserAvatar(
                      avatar: {'preset': p.id},
                      size: size,
                      fallback: const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppText.red600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
