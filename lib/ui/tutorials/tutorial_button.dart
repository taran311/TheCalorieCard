import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/tutorials/tutorial_player.dart';
import 'package:namer_app/ui/tutorials/tutorial_scripts.dart';

/// Headphones button on the Card screen that opens the tutorials.
///
/// The first time someone sees it, it's a labelled pill with a pulsing
/// ring so it gets noticed; once they've opened it, it settles into a small
/// round button. (The only thing it saves is that one "seen it" flag.)
class TutorialButton extends StatefulWidget {
  const TutorialButton({super.key});

  @override
  State<TutorialButton> createState() => _TutorialButtonState();
}

class _TutorialButtonState extends State<TutorialButton>
    with SingleTickerProviderStateMixin {
  static const _flag = 'tutorials_button_seen';

  /// Remembered for this run of the app (so it doesn't flash again before
  /// the save lands).
  static final Set<String> _seenBy = {};

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool _fresh = false;

  @override
  void initState() {
    super.initState();
    _checkSeen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  void _syncPulse() {
    final still = MediaQuery.of(context).disableAnimations;
    if (_fresh && !still) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
  }

  Future<void> _checkSeen() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || _seenBy.contains(uid)) return;
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!mounted) return;
      if (doc.data()?[_flag] == true) {
        _seenBy.add(uid);
        return;
      }
      setState(() => _fresh = true);
      _syncPulse();
    } catch (_) {
      // Offline: just show the quiet version.
    }
  }

  Future<void> _markSeen() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _seenBy.add(uid);
    if (_fresh) {
      setState(() => _fresh = false);
      _pulse.stop();
    }
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({_flag: true}, SetOptions(merge: true));
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    _markSeen();
    await showTutorialsSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: _fresh ? AppColors.primary : AppColors.border,
          width: _fresh ? 1.5 : 1,
        ),
      ),
      elevation: 2,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _open,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: _fresh ? 14 : 10, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.headphones_rounded,
                  color: AppColors.primaryDark, size: 22),
              if (_fresh) ...[
                const SizedBox(width: 6),
                const Text(
                  'Tutorials',
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Tooltip(
      message: 'Tutorials',
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          if (!_fresh) return child!;
          final t = Curves.easeOut.transform(_pulse.value);
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Transform.scale(
                  scale: 1 + 0.35 * t,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: AppColors.primary
                              .withValues(alpha: 0.6 * (1 - t)),
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child: button,
      ),
    );
  }
}

/// The list of tutorials.
Future<void> showTutorialsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Row(
              children: [
                Icon(Icons.headphones_rounded, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  'Tutorials',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Watch how things work on a practice card. Your real card, '
              'diary and friends are never touched.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            for (final t in tutorials)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TutorialTile(
                  tutorial: t,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    final finished = await TutorialPlayer.open(context, t);
                    if (finished) TutorialProgress.done.add(t.id);
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Which tutorials were finished in this run of the app (shown as ticks).
class TutorialProgress {
  TutorialProgress._();
  static final Set<String> done = {};
}

class _TutorialTile extends StatelessWidget {
  final Tutorial tutorial;
  final VoidCallback onTap;

  const _TutorialTile({required this.tutorial, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final finished = TutorialProgress.done.contains(tutorial.id);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppDecor.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDecor.radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDecor.radius),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.indigo50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(tutorial.emoji,
                    style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tutorial.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tutorial.subtitle} · ${tutorial.steps.length} steps',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Icon(
                finished ? Icons.check_circle : Icons.play_circle_outline,
                color: finished ? AppColors.emerald600 : AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
