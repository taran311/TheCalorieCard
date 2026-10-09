import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/coach_service.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/responsive.dart';

/// Calorie Coach: a friendly chat about your day, with ready-made
/// questions that change with how the day's going.
class CoachPage extends StatefulWidget {
  /// Sent straight away when the page opens (e.g. from "I went over").
  final String? initialQuestion;

  const CoachPage({super.key, this.initialQuestion});

  @override
  State<CoachPage> createState() => _CoachPageState();
}

class _CoachPageState extends State<CoachPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<CoachMessage> _messages = [];

  CoachContext? _context;
  bool _loadingContext = true;
  bool _thinking = false;
  String? _error;

  late final String _name = () {
    final full = cardholderFromEmail(
        FirebaseAuth.instance.currentUser?.email ?? '');
    return full.split(' ').first;
  }();

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final c = await CoachContext.load(uid);
        if (mounted) setState(() => _context = c);
      } catch (_) {
        // Coach still works, just without your numbers.
      }
    }
    if (!mounted) return;
    setState(() => _loadingContext = false);
    final first = widget.initialQuestion;
    if (first != null && first.trim().isNotEmpty) _send(first);
  }

  Future<void> _send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _thinking) return;
    _input.clear();
    setState(() {
      _messages.add(CoachMessage.user(question));
      _thinking = true;
      _error = null;
    });
    _scrollToEnd();
    await _ask();
  }

  Future<void> _ask() async {
    try {
      final reply =
          await CoachService.ask(history: _messages, context: _context);
      if (!mounted) return;
      setState(() {
        _messages.add(CoachMessage.coach(reply));
        _thinking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _thinking = false;
        _error = e is CoachException
            ? e.message
            : "Couldn't reach Coach. Check your connection and try again.";
      });
    }
    _scrollToEnd();
  }

  Future<void> _retry() async {
    if (_thinking) return;
    setState(() {
      _thinking = true;
      _error = null;
    });
    _scrollToEnd();
    await _ask();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final prompts = CoachService.promptsFor(_context);
    final started = _messages.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('💬 ', style: TextStyle(fontSize: 20)),
            Text('Calorie Coach',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          if (started)
            IconButton(
              tooltip: 'New chat',
              icon: const Icon(Icons.refresh),
              onPressed: _thinking
                  ? null
                  : () => setState(() {
                        _messages.clear();
                        _error = null;
                      }),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: Breakpoints.contentMaxWidth),
          child: Column(
            children: [
              if (_context != null) _TodayStrip(context: _context!),
              Expanded(
                child: _loadingContext
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        children: [
                          _Bubble(
                            text: CoachService.greeting(_context, name: _name),
                            fromUser: false,
                          ),
                          if (!started) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final p in prompts)
                                  _PromptChip(
                                      prompt: p, onTap: () => _send(p.question)),
                              ],
                            ),
                          ],
                          for (final m in _messages)
                            _Bubble(text: m.text, fromUser: m.fromUser),
                          if (_thinking) const _Thinking(),
                          if (_error != null)
                            _ErrorBubble(message: _error!, onRetry: _retry),
                          const SizedBox(height: 8),
                          const Text(
                            'Coach gives general tips, not medical advice.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(fontSize: 11, color: AppColors.gray400),
                          ),
                        ],
                      ),
              ),
              if (started && !_thinking)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final p in prompts.take(6))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _PromptChip(
                              prompt: p, onTap: () => _send(p.question)),
                        ),
                    ],
                  ),
                ),
              _InputBar(
                controller: _input,
                enabled: !_thinking && !_loadingContext,
                onSend: () => _send(_input.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "820 kcal left · 40g protein to go" under the app bar.
class _TodayStrip extends StatelessWidget {
  final CoachContext context;

  const _TodayStrip({required this.context});

  @override
  Widget build(BuildContext buildContext) {
    final c = context;
    final left = c.caloriesLeft.round();
    final over = left < 0;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(
            over ? '${-left} kcal over' : '$left kcal left',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const Spacer(),
          if (c.proteinLeft > 0)
            Text(
              '${c.proteinLeft.round()}g protein to go',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  final CoachPrompt prompt;
  final VoidCallback onTap;

  const _PromptChip({required this.prompt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Text(prompt.emoji),
      label: Text(prompt.label),
      onPressed: onTap,
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppColors.indigo100),
      labelStyle: const TextStyle(
          color: AppColors.primaryDark, fontWeight: FontWeight.w600),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool fromUser;

  const _Bubble({required this.text, required this.fromUser});

  @override
  Widget build(BuildContext context) {
    final colour = fromUser ? Colors.white : AppColors.ink;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8 > 560
                ? 560
                : MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: fromUser ? AppColors.primaryDark : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(fromUser ? 18 : 4),
            bottomRight: Radius.circular(fromUser ? 4 : 18),
          ),
          border: fromUser ? null : Border.all(color: AppColors.border),
        ),
        child: _FormattedText(text: text, colour: colour),
      ),
    );
  }
}

/// Shows **bold** and "- " bullet lines from Coach's replies nicely.
class _FormattedText extends StatelessWidget {
  final String text;
  final Color colour;

  const _FormattedText({required this.text, required this.colour});

  List<TextSpan> _spans(String line) {
    final spans = <TextSpan>[];
    final bold = RegExp(r'\*\*(.+?)\*\*');
    var last = 0;
    for (final m in bold.allMatches(line)) {
      if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start)));
      spans.add(TextSpan(
          text: m.group(1),
          style: const TextStyle(fontWeight: FontWeight.w800)));
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: colour, fontSize: 14.5, height: 1.35);
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final raw in lines)
          if (raw.trim().isEmpty)
            const SizedBox(height: 6)
          else if (RegExp(r'^\s*([-*•]|\d+\.)\s+').hasMatch(raw))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: style),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                          style: style,
                          children: _spans(raw.replaceFirst(
                              RegExp(r'^\s*([-*•]|\d+\.)\s+'), ''))),
                    ),
                  ),
                ],
              ),
            )
          else
            Text.rich(TextSpan(style: style, children: _spans(raw))),
      ],
    );
  }
}

class _Thinking extends StatefulWidget {
  const _Thinking();

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dots = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: AnimatedBuilder(
          animation: _dots,
          builder: (context, _) {
            final active = (_dots.value * 3).floor();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i == active ? AppColors.primary : AppColors.gray300,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ErrorBubble extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBubble({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.amber50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(message,
                style: const TextStyle(color: AppColors.amber700)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                maxLength: 500,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Ask Coach anything about food or your day…',
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: enabled ? onSend : null,
              style: IconButton.styleFrom(
                  backgroundColor: AppColors.primaryDark),
              icon: const Icon(Icons.send_rounded),
              tooltip: 'Send',
            ),
          ],
        ),
      ),
    );
  }
}

/// A slim "Ask Coach" button for the Card screen.
class CoachEntry extends StatelessWidget {
  const CoachEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CoachPage()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.indigo100),
          ),
          child: const Row(
            children: [
              Text('💬', style: TextStyle(fontSize: 20)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ask Coach: meal ideas, a pep talk, or help if you\'re over',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryDark,
                      fontSize: 13),
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
