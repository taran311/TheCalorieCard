import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/coach_actions.dart';
import 'package:namer_app/services/coach_service.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/coach_glyph.dart';
import 'package:namer_app/ui/responsive.dart';

/// Calorie Coach: a friendly chat about your day, with ready-made
/// questions that change with how the day's going. Coach can also propose
/// changes (add food, log a recipe, remove something, save a recipe); each
/// shows as a card with Accept / Reject and nothing changes until accepted.
class CoachPage extends StatefulWidget {
  /// Sent straight away when the page opens (e.g. from "I went over").
  final String? initialQuestion;

  const CoachPage({super.key, this.initialQuestion});

  /// Bumped when Coach is opened from the bottom bar, so it picks up your
  /// latest numbers (it stays alive between visits).
  static final refresh = ValueNotifier<int>(0);

  @override
  State<CoachPage> createState() => _CoachPageState();
}

enum _ProposalState { preparing, failed, ready, applying, done, rejected }

/// A change Coach proposed, from "working it out" to accepted or rejected.
class _Proposal extends ChangeNotifier {
  final CoachAction action;
  _ProposalState state = _ProposalState.preparing;
  PreparedAction? prepared;
  String? message;
  bool _disposed = false;

  _Proposal(this.action);

  void update(void Function() change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// One thing in the chat: a message or a proposal card.
class _Item {
  final CoachMessage? message;
  final _Proposal? proposal;

  const _Item.message(CoachMessage this.message) : proposal = null;
  const _Item.proposal(_Proposal this.proposal) : message = null;
}

class _CoachPageState extends State<CoachPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// What's shown.
  final List<_Item> _items = [];

  /// What Coach remembers (messages, plus notes on accepted/rejected
  /// changes so it knows what happened).
  final List<CoachMessage> _history = [];

  CoachContext? _context;
  bool _loadingContext = true;
  bool _thinking = false;
  String? _error;

  late final String _name = () {
    final full = cardholderFromEmail(
        FirebaseAuth.instance.currentUser?.email ?? '');
    return full.split(' ').first;
  }();

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    CoachPage.refresh.addListener(_reloadContext);
    _loadContext();
  }

  @override
  void dispose() {
    CoachPage.refresh.removeListener(_reloadContext);
    if (_thinking) CoachService.stopThinking();
    for (final item in _items) {
      item.proposal?.dispose();
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    final uid = _uid;
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

  Future<void> _reloadContext() async {
    final uid = _uid;
    if (uid == null || _loadingContext) return;
    try {
      final c = await CoachContext.load(uid);
      if (mounted) setState(() => _context = c);
    } catch (_) {}
  }

  Future<void> _send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _thinking) return;
    _input.clear();
    final message = CoachMessage.user(question);
    setState(() {
      _items.add(_Item.message(message));
      _history.add(message);
      _error = null;
    });
    await _ask();
  }

  void _setThinking(bool value) {
    if (value == _thinking) return;
    _thinking = value;
    if (value) {
      CoachService.startThinking();
    } else {
      CoachService.stopThinking();
    }
  }

  Future<void> _ask() async {
    setState(() => _setThinking(true));
    _scrollToEnd();
    try {
      final reply =
          await CoachService.ask(history: _history, context: _context);
      if (!mounted) return;
      final answer = CoachMessage.coach(reply.text);
      final proposals = [for (final a in reply.actions) _Proposal(a)];
      setState(() {
        _items.add(_Item.message(answer));
        _history.add(answer);
        for (final p in proposals) {
          _items.add(_Item.proposal(p));
        }
      });
      _scrollToEnd();
      // Keep the waves going while the numbers are looked up.
      await Future.wait(proposals.map(_prepare));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is CoachException
            ? e.message
            : "Couldn't reach Coach. Check your connection and try again.";
      });
    } finally {
      if (mounted) {
        setState(() => _setThinking(false));
      } else if (_thinking) {
        _thinking = false;
        CoachService.stopThinking();
      }
      _scrollToEnd();
    }
  }

  Future<void> _prepare(_Proposal p) async {
    final uid = _uid;
    if (uid == null) {
      p.update(() {
        p.state = _ProposalState.failed;
        p.message = 'Please sign in again.';
      });
      return;
    }
    try {
      final prepared = await CoachActions.prepare(p.action, uid);
      p.update(() {
        p.prepared = prepared;
        p.state = _ProposalState.ready;
      });
    } catch (e) {
      p.update(() {
        p.state = _ProposalState.failed;
        p.message = e is CoachActionException
            ? e.message
            : "I couldn't work that out just now. Try asking again?";
      });
    }
    _scrollToEnd();
  }

  Future<void> _accept(_Proposal p) async {
    final prepared = p.prepared;
    if (prepared == null || p.state != _ProposalState.ready) return;
    p.update(() => p.state = _ProposalState.applying);
    try {
      String done;
      try {
        done = await prepared.apply().timeout(const Duration(seconds: 15));
      } on TimeoutException {
        // Saved on this device; Firestore sends it when back online.
        done = "Saved. It'll sync when you're back online.";
      }
      p.update(() {
        p.state = _ProposalState.done;
        p.message = done;
      });
      _history.add(CoachMessage.coach(
          '[App note: the user accepted, so I did it: ${prepared.summary}.]'));
      await _reloadContext();
    } catch (e) {
      p.update(() => p.state = _ProposalState.ready);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't make that change. Please try again."),
        ));
      }
    }
  }

  void _reject(_Proposal p) {
    final prepared = p.prepared;
    if (p.state != _ProposalState.ready) return;
    p.update(() => p.state = _ProposalState.rejected);
    if (prepared != null) {
      _history.add(CoachMessage.coach(
          '[App note: the user rejected this, nothing changed: '
          '${prepared.summary}.]'));
    }
  }

  Future<void> _retry() async {
    if (_thinking) return;
    setState(() => _error = null);
    await _ask();
  }

  void _newChat() {
    setState(() {
      for (final item in _items) {
        item.proposal?.dispose();
      }
      _items.clear();
      _history.clear();
      _error = null;
    });
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
    final started = _items.isNotEmpty;
    final lastIsUser =
        _items.isNotEmpty && _items.last.message?.fromUser == true;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.brandGradient,
              ),
              child: CoachGlyph(size: 20, thinking: _thinking),
            ),
            const SizedBox(width: 10),
            const Text('Calorie Coach',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          if (started)
            IconButton(
              tooltip: 'New chat',
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: _thinking ? null : _newChat,
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
                          for (final item in _items)
                            if (item.message != null)
                              _Bubble(
                                text: item.message!.text,
                                fromUser: item.message!.fromUser,
                              )
                            else
                              _ProposalCard(
                                proposal: item.proposal!,
                                onAccept: _accept,
                                onReject: _reject,
                              ),
                          if (_thinking && (_items.isEmpty || lastIsUser))
                            const _Thinking(),
                          if (_error != null)
                            _ErrorBubble(message: _error!, onRetry: _retry),
                          const SizedBox(height: 8),
                          const Text(
                            'Coach gives general tips, not medical advice. '
                            'Nothing changes until you tap Accept.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(fontSize: 11, color: AppColors.muted),
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

/// A proposed change with its exact numbers and Accept / Reject.
class _ProposalCard extends StatelessWidget {
  final _Proposal proposal;
  final ValueChanged<_Proposal> onAccept;
  final ValueChanged<_Proposal> onReject;

  const _ProposalCard({
    required this.proposal,
    required this.onAccept,
    required this.onReject,
  });

  static String _signedKcal(double v) =>
      v < 0 ? '${(-v).round()} kcal back' : '+${v.round()} kcal';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: proposal,
      builder: (context, _) {
        final p = proposal;
        final prepared = p.prepared;
        final done = p.state == _ProposalState.done;
        final rejected = p.state == _ProposalState.rejected;

        return AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: rejected ? 0.6 : 1,
          child: Container(
            margin: const EdgeInsets.only(top: 4, bottom: 8, right: 24),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: done
                    ? AppColors.emerald600.withValues(alpha: 0.5)
                    : AppColors.indigo100,
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (p.state == _ProposalState.preparing)
                  const Row(
                    children: [
                      CoachGlyph(
                          size: 22, thinking: true, color: AppColors.primary),
                      SizedBox(width: 10),
                      Text('Looking up the numbers…',
                          style: TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w600)),
                    ],
                  )
                else if (p.state == _ProposalState.failed)
                  Text(p.message ?? "Couldn't work that out.",
                      style: const TextStyle(color: AppColors.amber700))
                else if (prepared != null) ...[
                  Row(
                    children: [
                      Text(prepared.icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          prepared.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final line in prepared.lines) _ProposalLineRow(line),
                  if (prepared.total != null) ...[
                    const Divider(height: 16),
                    Row(
                      children: [
                        Text(
                          _signedKcal(prepared.total!.calories),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: prepared.total!.calories < 0
                                ? AppColors.emerald600
                                : AppColors.ink,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${prepared.total!.protein.abs().round()}g protein · '
                            '${prepared.total!.carbs.abs().round()}g carbs · '
                            '${prepared.total!.fat.abs().round()}g fat',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.muted),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (prepared.note != null) ...[
                    const SizedBox(height: 6),
                    Text(prepared.note!,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  ],
                  const SizedBox(height: 10),
                  if (p.state == _ProposalState.ready)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => onReject(p),
                            child: const Text('Reject'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => onAccept(p),
                            style: FilledButton.styleFrom(
                              backgroundColor: prepared.destructive
                                  ? AppColors.red600
                                  : AppColors.emerald600,
                            ),
                            child: Text(prepared.acceptLabel),
                          ),
                        ),
                      ],
                    )
                  else if (p.state == _ProposalState.applying)
                    const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Icon(
                          done
                              ? Icons.check_circle
                              : Icons.do_not_disturb_on_outlined,
                          size: 18,
                          color: done ? AppColors.emerald600 : AppColors.muted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            done
                                ? (p.message ?? 'Done')
                                : 'Rejected. Nothing changed.',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color:
                                  done ? AppColors.emerald600 : AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProposalLineRow extends StatelessWidget {
  final ProposalLine line;

  const _ProposalLineRow(this.line);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              line.skipped ? Icons.warning_amber_rounded : Icons.circle,
              size: line.skipped ? 15 : 7,
              color: line.skipped ? AppColors.amber700 : AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: line.skipped ? AppColors.muted : AppColors.ink,
                    decoration:
                        line.skipped ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (line.detail.isNotEmpty)
                  Text(
                    '${line.estimate ? '~ ' : ''}${line.detail}',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          line.skipped ? AppColors.amber700 : AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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
    final width = MediaQuery.sizeOf(context).width * 0.8;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: width > 560 ? 560 : width),
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

/// Coach's "thinking" bubble: the spark turned into flowing waves.
class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CoachGlyph(size: 28, thinking: true, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Thinking…',
                style: TextStyle(
                    color: AppColors.muted, fontWeight: FontWeight.w600)),
          ],
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
    // Pages can be drawn with a narrowed MediaQuery on desktop, so use the
    // real window width to tell whether the phone bottom bar is showing.
    final view = View.of(context);
    final windowWidth = view.physicalSize.width / view.devicePixelRatio;
    final onPhone = windowWidth < Breakpoints.tablet;
    return SafeArea(
      top: false,
      child: Padding(
        // On phones, extra room at the bottom for the Coach button that
        // sits over the bottom bar.
        padding: EdgeInsets.fromLTRB(12, 8, 12, onPhone ? 30 : 12),
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
                  hintText: 'Ask anything, or "add 2 eggs to brekkie"',
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
