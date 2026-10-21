import 'package:flutter/material.dart';
import 'package:namer_app/ui/auth_ui.dart';
import 'package:namer_app/ui/responsive.dart';

/// Three quick screens before sign-up that say what the app is: a digital
/// card you spend calories from, fast logging, and friends. Swipe through
/// or go straight to "Create my card".
class IntroPage extends StatefulWidget {
  final VoidCallback onCreate;
  final VoidCallback onSignIn;

  const IntroPage({super.key, required this.onCreate, required this.onSignIn});

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  final _pages = PageController();
  int _index = 0;

  static const _slides = [
    (
      title: 'Your calories, as a bank card',
      body: 'A digital card in the app, with nothing to post. Everything you '
          'eat is spent from it, and what\'s left is your balance for the '
          'day.',
    ),
    (
      title: 'Log food in seconds',
      body: 'Type what you had, scan the barcode or just say it. We work out '
          'the calories and macros for you.',
    ),
    (
      title: 'Better with friends',
      body: 'See how each other\'s day is going, cheer each other on, keep '
          'your streaks going and play calorie games together.',
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_index >= _slides.length - 1) {
      widget.onCreate();
      return;
    }
    _pages.nextPage(
      duration: MediaQuery.of(context).disableAnimations
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _picture(int i) => switch (i) {
        0 => ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: const CalorieCardPreview(cardholder: 'YOUR NAME'),
          ),
        1 => const _LoggingPicture(),
        _ => const _FriendsPicture(),
      };

  @override
  Widget build(BuildContext context) {
    final last = _index == _slides.length - 1;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Row(
                  children: [
                    const Icon(Icons.credit_card, color: Colors.white),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'The Calorie Card',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (!last)
                      TextButton(
                        onPressed: () => _pages.jumpToPage(_slides.length - 1),
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.white),
                        child: const Text('Skip'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Shrinks on short phones rather than
                            // pushing the words off the screen.
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: SizedBox(width: 320, child: _picture(i)),
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              _slides[i].title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _slides[i].body,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 16,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Semantics(
                label: 'Page ${_index + 1} of ${_slides.length}',
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _slides.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _index ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white
                                .withValues(alpha: i == _index ? 1 : 0.4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primaryDark,
                      ),
                      onPressed: _next,
                      child: Text(
                        last ? 'Create my card' : 'Next',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextButton(
                  onPressed: widget.onSignIn,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('I already have an account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A food box with what was typed, the ways in, and the results.
class _LoggingPicture extends StatelessWidget {
  const _LoggingPicture();

  @override
  Widget build(BuildContext context) {
    Widget row(String name, String kcal) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937))),
                ),
                Text(kcal,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF4F46E5))),
              ],
            ),
          ),
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFA5B4FC), width: 2),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Text(
                    '2 crumpets, 150g baked beans',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Color(0xFF374151)),
                  ),
                ),
                Icon(Icons.mic_none, color: Color(0xFF6366F1)),
                SizedBox(width: 8),
                Icon(Icons.qr_code_scanner, color: Color(0xFF6B7280)),
                SizedBox(width: 8),
                Icon(Icons.photo_camera_outlined, color: Color(0xFF6B7280)),
              ],
            ),
          ),
          row('2 crumpets', '228 kcal'),
          row('150g baked beans', '122 kcal'),
        ],
      ),
    );
  }
}

/// Friends with progress rings and a little activity.
class _FriendsPicture extends StatelessWidget {
  const _FriendsPicture();

  @override
  Widget build(BuildContext context) {
    Widget friend(String initial, String name, double progress) => Column(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 5,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Text(initial,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF4F46E5))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(name,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        );
    Widget chip(String text) => Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(text,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            friend('S', 'Sam', 0.7),
            const SizedBox(width: 18),
            friend('P', 'Priya', 0.45),
            const SizedBox(width: 18),
            friend('A', 'Alex', 0.9),
          ],
        ),
        const SizedBox(height: 8),
        chip('👏 Priya cheered your day'),
        chip('🔥 Sam is on a 12-day streak'),
      ],
    );
  }
}
