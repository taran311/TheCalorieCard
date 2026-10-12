import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/tutorials/tutorial_player.dart';
import 'package:namer_app/ui/tutorials/tutorial_scripts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tutorials button on the Card screen that opens the tutorials.
///
/// The first time someone sees it, it's a labelled pill with a pulsing
/// ring so it gets noticed; once they've opened it, it settles into a small
/// round button. Once they've finished a couple of tutorials it goes away
/// (they stay in Profile via [showTutorialsSheet]), so it stops covering
/// the list for people who already know their way round.
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
    TutorialProgress.load();
    TutorialProgress.changed.addListener(_onProgress);
  }

  void _onProgress() {
    if (mounted) setState(() {});
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
    TutorialProgress.changed.removeListener(_onProgress);
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    _markSeen();
    await showTutorialsSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    if (TutorialProgress.done.length >= TutorialProgress.hideButtonAfter) {
      return const SizedBox.shrink();
    }
    final button = Material(
      color: AppColors.surface,
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
              Icon(Icons.school_outlined,
                  color: AppText.primaryDark, size: 22),
              if (_fresh) ...[
                const SizedBox(width: 6),
                Text(
                  'Tutorials',
                  style: TextStyle(
                    color: AppText.primaryDark,
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

/// The list of tutorials. Public so other screens (e.g. the Profile menu)
/// can open it once the floating button has gone.
Future<void> showTutorialsSheet(BuildContext context) {
  TutorialProgress.load();
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
            Row(
              children: [
                Icon(Icons.school_outlined, color: AppText.primary),
                const SizedBox(width: 8),
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
            Text(
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
                    if (finished) TutorialProgress.markDone(t.id);
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Which tutorials have been finished (shown as ticks). Saved on this
/// device, so the floating button can stay hidden once you know the app.
class TutorialProgress {
  TutorialProgress._();

  /// Finished tutorials needed before the floating button hides.
  static const hideButtonAfter = 2;

  static final Set<String> done = {};

  /// Bumped when [done] changes (after loading or finishing one).
  static final ValueNotifier<int> changed = ValueNotifier<int>(0);

  static String? _loadedFor;

  static String _key(String uid) => 'tutorials_done_$uid';

  /// Reads the saved list once per signed-in account.
  static Future<void> load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _loadedFor == uid) return;
    _loadedFor = uid;
    // A different account: forget the last one's ticks.
    done.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_key(uid)) ?? const <String>[];
      done.addAll(saved);
      changed.value++;
    } catch (_) {
      // Storage blocked (private window): just this run, then.
    }
  }

  static Future<void> markDone(String id) async {
    if (!done.add(id)) return;
    changed.value++;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key(uid), done.toList());
    } catch (_) {}
  }
}

class _TutorialTile extends StatelessWidget {
  final Tutorial tutorial;
  final VoidCallback onTap;

  const _TutorialTile({required this.tutorial, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final finished = TutorialProgress.done.contains(tutorial.id);
    return Material(
      color: AppColors.surface,
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
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tutorial.subtitle} · ${tutorial.steps.length} steps',
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Icon(
                finished ? Icons.check_circle : Icons.play_circle_outline,
                color: finished ? AppText.emerald600 : AppText.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Help on each screen
// ============================================================================

/// The ⓘ on a screen: straight into its tutorial when there's just one,
/// otherwise a short list of only that screen's tutorials. [onDemo] adds a
/// "Show me here" demo on the screen itself (Add food, New recipe); null
/// [onDemo] with [demoUnavailable] shows why it can't run right now.
Future<void> showScreenHelp(
  BuildContext context, {
  required List<String> tutorialIds,
  VoidCallback? onDemo,
  String? demoUnavailable,
}) async {
  TutorialProgress.load();
  final list = [
    for (final id in tutorialIds)
      for (final t in tutorials)
        if (t.id == id) t
  ];
  final demo = onDemo;
  final hasDemo = demo != null || demoUnavailable != null;
  if (!hasDemo && list.length == 1) {
    final finished = await TutorialPlayer.open(context, list.single);
    if (finished) TutorialProgress.markDone(list.single.id);
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            'How this works',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Watch on a practice card. Your real card is never touched.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          if (hasDemo)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDecor.radius),
                  side: BorderSide(color: AppColors.border),
                ),
                leading: Icon(Icons.touch_app_outlined, color: AppText.primary),
                title: const Text('Show me here',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(demo != null
                    ? 'A quick demo on this screen'
                    : demoUnavailable ?? ''),
                enabled: demo != null,
                onTap: demo == null
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        demo();
                      },
              ),
            ),
          for (final t in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TutorialTile(
                tutorial: t,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final finished = await TutorialPlayer.open(context, t);
                  if (finished) TutorialProgress.markDone(t.id);
                },
              ),
            ),
        ],
      ),
    ),
  );
}

/// The ⓘ button for an app bar.
class ScreenHelpButton extends StatelessWidget {
  final List<String> tutorialIds;
  const ScreenHelpButton({super.key, required this.tutorialIds});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'How this works',
      icon: const Icon(Icons.help_outline),
      onPressed: () => showScreenHelp(context, tutorialIds: tutorialIds),
    );
  }
}

/// "New here? See how Friends works": shown the first time someone opens a
/// screen, and never again once they tap Show me or ✕ (or have already
/// finished one of its tutorials). Remembered on this device.
class FirstVisitHint extends StatefulWidget {
  /// Which screen ("friends"): one hint per screen.
  final String screen;

  /// "See how {label} works".
  final String label;

  /// Its tutorials: if any is already finished, no hint.
  final List<String> tutorialIds;

  final VoidCallback onShow;

  const FirstVisitHint({
    super.key,
    required this.screen,
    required this.label,
    required this.tutorialIds,
    required this.onShow,
  });

  @override
  State<FirstVisitHint> createState() => _FirstVisitHintState();
}

class _FirstVisitHintState extends State<FirstVisitHint> {
  /// Hidden until we know it hasn't been seen (no flash for regulars).
  bool _show = false;

  /// Seen this run (so a rebuild never brings it back).
  static final Set<String> _seenThisRun = {};

  String? get _key {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : 'hint_seen_${widget.screen}_$uid';
  }

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final key = _key;
    if (key == null || _seenThisRun.contains(key)) return;
    try {
      await TutorialProgress.load();
      if (widget.tutorialIds.any(TutorialProgress.done.contains)) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(key) == true) return;
      if (mounted) setState(() => _show = true);
    } catch (_) {
      // No storage: skip the hint rather than show it every time.
    }
  }

  Future<void> _dismiss() async {
    final key = _key;
    setState(() => _show = false);
    if (key == null) return;
    _seenThisRun.add(key);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
              AppColors.primary.withValues(alpha: AppColors.dark ? 0.16 : 0.07),
              AppColors.surface),
          borderRadius: BorderRadius.circular(AppDecor.radius),
          border: Border.all(
              color: AppColors.primary
                  .withValues(alpha: AppColors.dark ? 0.55 : 0.35)),
        ),
        child: Row(
          children: [
            const Text('👋', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'New here? See how ${widget.label} works.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                _dismiss();
                widget.onShow();
              },
              child: const Text('Show me'),
            ),
            IconButton(
              tooltip: 'No thanks',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 18, color: AppColors.gray600),
              onPressed: _dismiss,
            ),
          ],
        ),
      ),
    );
  }
}
