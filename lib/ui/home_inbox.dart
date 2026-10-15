import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:namer_app/pages/budgets_page.dart';
import 'package:namer_app/pages/games_hub_page.dart';
import 'package:namer_app/pages/messages_page.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/budget_service.dart';
import 'package:namer_app/services/direct_debit_service.dart';
import 'package:namer_app/services/games_service.dart';
import 'package:namer_app/services/late_close.dart';
import 'package:namer_app/services/notification_service.dart';
import 'package:namer_app/services/premium_service.dart';
import 'package:namer_app/pages/premium_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:namer_app/services/split_service.dart';
import 'package:namer_app/ui/responsive.dart';

/// The Card screen's inbox, like a banking app's notification strip:
/// split-the-bill requests, direct debits due today, balance alerts, the
/// evening "finish your day" nudge, this week's pot and today's Calorie
/// Quiz.
///
/// Shows one item at a time (swipe for more) so the card stays the hero.
class HomeInbox extends StatefulWidget {
  final String userId;
  final bool isDayFinished;
  final bool hasFoodToday;
  final VoidCallback onFinishDay;

  /// Called after something here changed the balance without logging food
  /// (moving the pot onto the card).
  final VoidCallback onBalanceChanged;

  const HomeInbox({
    super.key,
    required this.userId,
    required this.isDayFinished,
    required this.hasFoodToday,
    required this.onFinishDay,
    required this.onBalanceChanged,
  });

  @override
  State<HomeInbox> createState() => _HomeInboxState();
}

class _HomeInboxState extends State<HomeInbox> {
  StreamSubscription<List<BillSplit>>? _splitSub;
  StreamSubscription<List<DirectDebit>>? _debitSub;
  StreamSubscription<dynamic>? _profileSub;

  List<BillSplit> _splits = const [];
  List<DirectDebit> _debits = const [];
  Map<String, dynamic>? _profile;
  final Set<String> _busy = {};
  final PageController _pages = PageController();
  int _page = 0;

  /// Rebuilds every minute so time-based items (the evening nudge, debits
  /// due after midnight) appear without waiting for another update.
  Timer? _clock;

  /// Offer the evening reminder (once, until they answer).
  bool _offerReminder = false;

  Future<void> _checkReminderOffer() async {
    if (!NotificationService.supported) return;
    try {
      final r = await NotificationService.load();
      if (mounted && !r.enabled && !r.prompted) {
        setState(() => _offerReminder = true);
      }
    } catch (_) {}
  }

  /// Yesterday, if food was logged but it was never closed (it can be
  /// closed until midnight). Checked when the inbox opens and as the
  /// date changes.
  DateTime? _openYesterday;
  String? _yesterdayCheckedOn;

  Future<void> _checkYesterday() async {
    final today = BalanceService.dateKey(BalanceService.now());
    if (_yesterdayCheckedOn == today) return;
    _yesterdayCheckedOn = today;
    try {
      final day = await LateClose.openYesterday(widget.userId);
      if (mounted) setState(() => _openYesterday = day);
    } catch (_) {
      _yesterdayCheckedOn = null; // try again on the next tick
    }
  }

  Future<Object?> _closeYesterday() async {
    final day = _openYesterday;
    if (day == null) return null;
    final ok = await LateClose.closeYesterday(widget.userId, day);
    if (!mounted) return null;
    setState(() => _openYesterday = null);
    if (!ok) return false;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Yesterday closed ✓ It counts towards your streak.')));
    return null;
  }

  /// Chats with unread messages, for "Sam sent you a message".
  StreamSubscription<dynamic>? _chatSub;
  List<_UnreadChat> _unreadChats = const [];

  /// Names for one-to-one chats (the other person's), looked up once.
  final Map<String, String> _chatNames = {};

  void _onChats(Iterable<({String id, Map<String, dynamic> data})> docs) {
    final uid = widget.userId;
    final chats = <_UnreadChat>[];
    for (final d in docs) {
      final counts = d.data['unread_count'];
      final n = counts is Map ? counts[uid] : null;
      if (n is! num || n <= 0) continue;
      final isGroup = d.data['is_group'] == true;
      String? otherId;
      if (!isGroup) {
        for (final p in (d.data['participant_ids'] as List? ?? const [])) {
          if (p is String && p != uid) otherId = p;
        }
        if (otherId != null && !_chatNames.containsKey(otherId)) {
          _chatNames[otherId] = '';
          final id = otherId;
          FriendsService.nameFor(id).then((name) {
            if (mounted) setState(() => _chatNames[id] = name);
          }, onError: (_) {});
        }
      }
      chats.add(_UnreadChat(
        id: d.id,
        count: n.toInt(),
        isGroup: isGroup,
        groupName: '${d.data['conversation_name'] ?? 'Your group'}',
        otherId: otherId,
      ));
    }
    if (mounted) setState(() => _unreadChats = chats);
  }

  String _chatName(_UnreadChat c) {
    if (c.isGroup) return c.groupName;
    final name = _chatNames[c.otherId];
    return name == null || name.isEmpty ? 'A friend' : name;
  }

  void _openChats() {
    final chats = _unreadChats;
    final nav = chatNavigator(context);
    if (chats.length == 1) {
      final c = chats.single;
      nav.push(MaterialPageRoute(
        builder: (_) => ChatDetailPage(
          conversationId: c.id,
          conversationName: _chatName(c),
          isGroup: c.isGroup,
        ),
      ));
    } else {
      nav.push(MaterialPageRoute(builder: (_) => const MessagesPage()));
    }
  }

  /// Games progress, for "Today's Calorie Quiz".
  StreamSubscription<GamesProgress>? _gamesSub;
  GamesProgress? _games;

  /// Cards hidden for the rest of today on this device ("Not today",
  /// "Later", "Not now"), by card: the date they were hidden on.
  final Map<String, String?> _hiddenOn = {};

  static const _hideable = ['quiz', 'finish_day', 'late_close'];

  String _hiddenKey(String card) => card == 'quiz'
      ? 'quiz_card_hidden_${widget.userId}'
      : '${card}_card_hidden_${widget.userId}';

  bool _hiddenToday(String card) =>
      _hiddenOn[card] == GamesService.dayKey();

  Future<void> _loadHidden() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        for (final card in _hideable) {
          _hiddenOn[card] = prefs.getString(_hiddenKey(card));
        }
      });
    } catch (_) {}
  }

  /// Hides [card] until tomorrow.
  Future<void> _hideToday(String card) async {
    final day = GamesService.dayKey();
    setState(() => _hiddenOn[card] = day);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_hiddenKey(card), day);
    } catch (_) {}
  }

  Future<void> _hideQuiz() => _hideToday('quiz');

  void _openQuiz() {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => const SoloGamePage(kind: SoloKind.daily)),
    );
  }

  /// "Your trial has ended" was dismissed on this device.
  bool _trialEndSeen = true;

  String get _trialSeenKey => 'trial_end_seen_${widget.userId}';

  Future<void> _loadTrialSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() => _trialEndSeen = prefs.getBool(_trialSeenKey) ?? false);
      }
    } catch (_) {}
  }

  Future<void> _dismissTrialEnded() async {
    setState(() => _trialEndSeen = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_trialSeenKey, true);
    } catch (_) {}
  }

  /// Meal and category budgets, for the 80% / 100% heads-ups.
  List<BudgetProgress> _budgets = const [];

  /// Budget alerts dismissed on this device ([BudgetProgress.alertId]s).
  Set<String> _budgetSeen = {};
  Timer? _budgetDebounce;
  int _budgetToken = 0;

  String get _budgetSeenKey => 'budget_alerts_seen_${widget.userId}';

  Future<void> _loadBudgetSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getStringList(_budgetSeenKey) ?? const <String>[];
      if (mounted) setState(() => _budgetSeen = {..._budgetSeen, ...seen});
    } catch (_) {}
  }

  /// Re-checks budgets shortly after the card changes (food logged or
  /// removed, or budgets edited), batching quick changes into one read.
  void _scheduleBudgetCheck() {
    _budgetDebounce?.cancel();
    _budgetDebounce = Timer(const Duration(milliseconds: 800), _checkBudgets);
  }

  Future<void> _checkBudgets() async {
    final token = ++_budgetToken;
    final settings = BudgetSettings.fromProfile(_profile);
    try {
      final progress =
          await BudgetService.loadProgress(widget.userId, settings);
      if (!mounted || token != _budgetToken) return;
      setState(() => _budgets = progress);
    } catch (_) {
      // Budgets are a nice-to-have: keep the last figures.
    }
  }

  /// Hides one budget alert for good (each shows once per day / week).
  Future<void> _dismissBudget(String id) async {
    setState(() => _budgetSeen = {..._budgetSeen, id});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_budgetSeenKey,
          BudgetService.pruneSeen(_budgetSeen, BalanceService.now()));
    } catch (_) {}
  }

  void _openBudgets() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BudgetsPage()),
    );
  }

  void _onPremiumChanged() {
    if (mounted) setState(() {});
  }

  void _openPremium() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PremiumPage()),
    );
  }

  @override
  void initState() {
    super.initState();
    _checkReminderOffer();
    _loadTrialSeen();
    _loadBudgetSeen();
    _loadHidden();
    _checkYesterday();
    _gamesSub = GamesService.watch(widget.userId).listen(
      (g) {
        if (mounted) setState(() => _games = g);
      },
      onError: (_) {},
    );
    Premium.notifier.addListener(_onPremiumChanged);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _checkYesterday(); // only does anything once the date changes
    });
    _splitSub = SplitService.pendingFor(widget.userId).listen(
      (v) => setState(() => _splits = v),
      onError: (_) {},
    );
    _debitSub = DirectDebitService.forUser(widget.userId).listen(
      (v) => setState(() => _debits = v),
      onError: (_) {},
    );
    _chatSub = BalanceService.db
        .collection('conversations')
        .where('participant_ids', arrayContains: widget.userId)
        .snapshots()
        .listen(
      (snap) => _onChats([
        for (final d in snap.docs) (id: d.id, data: d.data()),
      ]),
      onError: (_) {},
    );
    _profileSub = BalanceService.db
        .collection('user_data')
        .where('user_id', isEqualTo: widget.userId)
        .limit(1)
        .snapshots()
        .listen(
      (snap) {
        setState(() =>
            _profile = snap.docs.isEmpty ? null : snap.docs.first.data());
        _scheduleBudgetCheck();
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    Premium.notifier.removeListener(_onPremiumChanged);
    _splitSub?.cancel();
    _debitSub?.cancel();
    _profileSub?.cancel();
    _gamesSub?.cancel();
    _chatSub?.cancel();
    _clock?.cancel();
    _budgetDebounce?.cancel();
    _pages.dispose();
    super.dispose();
  }

  /// Runs an inbox action. If it returns false, it had already been
  /// handled (e.g. on another device), so say that instead of [done].
  Future<void> _run(String key, Future<Object?> Function() action,
      {String? done}) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      final result = await action();
      if (!mounted) return;
      final message = result == false ? 'Already done on another device' : done;
      if (message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  /// Inbox items. On [narrow] screens, cards with two buttons put the
  /// buttons on their own row under the text.
  List<_InboxCard> _items({bool narrow = false}) {
    final items = <_InboxCard>[];
    final uid = widget.userId;

    // First: it can only be done until midnight.
    if (_openYesterday != null && !_hiddenToday('late_close')) {
      items.add(_InboxCard(
        icon: Icons.event_available,
        color: AppColors.amber700,
        title: "Yesterday's still open",
        subtitle: 'You logged food but didn\'t close the day. Close it now '
            'so it counts towards your streak.',
        busy: _busy.contains('late_close'),
        actions: [
          _InboxAction('Not now', () => _hideToday('late_close')),
          _InboxAction(
              'Close yesterday', () => _run('late_close', _closeYesterday),
              primary: true),
        ],
        stacked: narrow,
      ));
    }

    // Unread messages: a friend's waiting for a reply. Gone once read.
    if (_unreadChats.isNotEmpty) {
      final total = _unreadChats.fold<int>(0, (s, c) => s + c.count);
      final names = [for (final c in _unreadChats) _chatName(c)];
      final from = names.length == 1
          ? names.single
          : names.length == 2
              ? '${names[0]} and ${names[1]}'
              : '${names[0]}, ${names[1]} and ${names.length - 2} more';
      final single = _unreadChats.length == 1 && !_unreadChats.single.isGroup;
      items.add(_InboxCard(
        icon: Icons.chat_bubble,
        color: AppColors.primary,
        title: single
            ? (total == 1
                ? '$from sent you a message'
                : '$from sent you $total messages')
            : '$total unread message${total == 1 ? '' : 's'}',
        subtitle: single ? 'Tap to read and reply.' : 'From $from.',
        actions: [
          _InboxAction(
              _unreadChats.length == 1 ? 'Open chat' : 'Open messages',
              _openChats,
              primary: true),
        ],
        stacked: narrow,
      ));
    }

    for (final split in _splits) {
      final key = 'split:${split.id}';
      items.add(_InboxCard(
        icon: Icons.receipt_long,
        color: AppColors.violet600,
        title: '${split.fromName} split ${split.title}',
        subtitle: 'Your share: ${split.calories.round()} kcal · ${split.meal}',
        busy: _busy.contains(key),
        actions: [
          _InboxAction('Decline', () => _run(key,
              () => SplitService.decline(uid, split))),
          _InboxAction('Accept', () => _run(key,
              () => SplitService.accept(uid, split),
              done: 'Added your share to ${split.meal}'), primary: true),
        ],
        stacked: narrow,
      ));
    }

    for (final debit in _debits.where((d) => d.isDueToday)) {
      final key = 'debit:${debit.id}';
      items.add(_InboxCard(
        icon: Icons.autorenew,
        color: AppColors.sky,
        title: 'Direct debit: ${debit.name}',
        subtitle: '${debit.macros.calories.round()} kcal · ${debit.meal}',
        busy: _busy.contains(key),
        actions: [
          _InboxAction('Skip today',
              () => _run(key, () => DirectDebitService.skipToday(debit))),
          _InboxAction(
              'Pay',
              () => _run(key, () => DirectDebitService.pay(uid, debit),
                  done: 'Logged ${debit.name}'),
              primary: true),
        ],
        stacked: narrow,
      ));
    }

    final profile = _profile;
    if (profile != null &&
        profile['balance_date'] == BalanceService.dateKey(BalanceService.now())) {
      final left = BalanceService.number(profile['calories']) ?? 0;
      final goal = BalanceService.calorieGoalFrom(profile) ?? 0;
      // Going over is handled by the Coach note under the card.
      if (left >= 0 && goal > 0 && left <= goal * 0.1 && widget.hasFoodToday) {
        items.add(_InboxCard(
          icon: Icons.battery_alert,
          color: AppColors.amber700,
          title: 'Low balance: ${left.round()} kcal left',
          subtitle: 'Nearly at your limit for today.',
        ));
      }

      final pot = BalanceService.potFrom(profile);
      if (pot > 0) {
        items.add(_InboxCard(
          icon: Icons.savings_outlined,
          color: AppColors.emerald600,
          title: 'Pot: ${pot.round()} kcal saved this week',
          subtitle: 'Move it onto today\'s card for a treat.',
          busy: _busy.contains('pot'),
          actions: [
            _InboxAction('Move to card', () => _run('pot', () async {
                  await BalanceService.spendPot(uid);
                  widget.onBalanceChanged();
                }, done: 'Pot moved onto your card'), primary: true),
          ],
        ));
      }
    }

    // Gentle budget heads-ups at 80% and 100%, once each per period.
    for (final a in BudgetService.alerts(
        _budgets, _budgetSeen, BalanceService.now())) {
      final id = a.progress.alertId(a.level);
      items.add(_InboxCard(
        icon: Icons.pie_chart_outline,
        color: a.level >= 100 ? AppColors.violet600 : AppColors.amber700,
        title: '${a.progress.budget.name} budget',
        subtitle: a.progress.alertMessage(a.level),
        actions: [
          _InboxAction('OK', () => _dismissBudget(id)),
          _InboxAction('Budgets', _openBudgets, primary: true),
        ],
        stacked: narrow,
      ));
    }

    final premium = Premium.current;
    if (premium.loaded && premium.inTrial && premium.trialDaysLeft <= 3) {
      final days = premium.trialDaysLeft;
      items.add(_InboxCard(
        icon: Icons.auto_awesome_rounded,
        color: AppColors.violet600,
        title: 'Premium trial: $days day${days == 1 ? '' : 's'} left',
        subtitle: Premium.sellsHere
            ? 'Choose a plan to keep it and unlock the Aurora card. '
                'Logging stays free.'
            : 'Logging, streaks and friends stay free after it ends.',
        actions: [
          if (Premium.sellsHere)
            _InboxAction('See plans', _openPremium, primary: true),
        ],
      ));
    } else if (premium.trialEnded && !_trialEndSeen) {
      items.add(_InboxCard(
        icon: Icons.auto_awesome_rounded,
        color: AppColors.violet600,
        title: 'Your Premium trial has ended',
        subtitle: 'You keep logging, streaks and friends, free.',
        actions: [
          _InboxAction('OK', _dismissTrialEnded, primary: !Premium.sellsHere),
          if (Premium.sellsHere)
            _InboxAction('See plans', _openPremium, primary: true),
        ],
        stacked: narrow,
      ));
    }

    if (_offerReminder) {
      items.add(_InboxCard(
        icon: Icons.notifications_active_outlined,
        color: AppColors.amber700,
        title: 'Want a nudge at ${NotificationService.hourLabel(NotificationService.defaultHour)}?',
        subtitle: "Only if you haven't logged anything by then.",
        busy: _busy.contains('reminder'),
        actions: [
          _InboxAction('No thanks', () => _run('reminder', () async {
                await NotificationService.dismissOffer();
                if (mounted) setState(() => _offerReminder = false);
              })),
          _InboxAction('Turn on', () => _run('reminder', () async {
                final error = await NotificationService.enable();
                if (!mounted) return null;
                if (error != null) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error)));
                  return null;
                }
                setState(() => _offerReminder = false);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Reminder on. Change it any time in '
                        'Profile → Evening reminder.')));
                return null;
              }), primary: true),
        ],
        stacked: narrow,
      ));
    }

    if (BalanceService.now().hour >= 20 &&
        !widget.isDayFinished &&
        widget.hasFoodToday &&
        !_hiddenToday('finish_day')) {
      items.add(_InboxCard(
        icon: Icons.nightlight_round,
        color: AppColors.indigo700,
        title: 'Finish your day?',
        subtitle: 'Finished days count towards streaks and challenges.',
        actions: [
          _InboxAction('Later', () => _hideToday('finish_day')),
          _InboxAction('Finish day', widget.onFinishDay, primary: true),
        ],
        stacked: narrow,
      ));
    }

    // Last, so anything that needs doing comes first. Gone once played
    // (or for the rest of the day after "Not today").
    final today = GamesService.dayKey();
    final games = _games;
    if (games != null &&
        !games.dailyDoneOn(today) &&
        !_hiddenToday('quiz')) {
      final started = games.dailyGuessesOn(today).length;
      items.add(_InboxCard(
        icon: Icons.sports_esports,
        color: AppColors.primary,
        title: started > 0
            ? "Finish today's Calorie Quiz"
            : "Today's Calorie Quiz",
        subtitle: started > 0
            ? '$started of ${GamesService.dailyRounds} guessed. Pick up '
                'where you left off.'
            : '${GamesService.dailyRounds} foods, about a minute. How close '
                'can you get?',
        actions: [
          _InboxAction('Not today', _hideQuiz),
          _InboxAction('Play', _openQuiz, primary: true),
        ],
        stacked: narrow,
      ));
    }
    return items;
  }

  /// Moves to inbox item [i] (dots and arrows; swiping still works).
  void _goTo(int i, int count) {
    if (i < 0 || i >= count || !_pages.hasClients) return;
    if (MediaQuery.of(context).disableAnimations) {
      _pages.jumpToPage(i);
    } else {
      _pages.animateToPage(i,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  /// True on a tablet/desktop-sized window, where swiping with a mouse
  /// isn't obvious. Uses the real window width (the page column is
  /// narrower than the window on desktop).
  bool get _wideWindow {
    final view = View.of(context);
    return view.physicalSize.width / view.devicePixelRatio >=
        Breakpoints.tablet;
  }

  @override
  Widget build(BuildContext context) {
    if (_items().isEmpty) return const SizedBox.shrink();
    // Grow with the text size so nothing is clipped.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final textHeight = 50 * scale;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 340;
        final items = _items(narrow: narrow);
        if (items.isEmpty) return const SizedBox.shrink();
        final page = _page.clamp(0, items.length - 1);
        final anyStacked = items.any((c) => c.stacked && c.actions.length > 1);
        final height = anyStacked
            ? 72 + textHeight
            : math.max(78.0, 22 + textHeight);

        return Column(
          children: [
            SizedBox(
              height: height,
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: items,
              ),
            ),
            if (items.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_wideWindow)
                      IconButton(
                        tooltip: 'Previous',
                        visualDensity: VisualDensity.compact,
                        iconSize: 20,
                        color: AppText.primary,
                        disabledColor: AppColors.gray300,
                        onPressed: page > 0
                            ? () => _goTo(page - 1, items.length)
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                    for (var i = 0; i < items.length; i++)
                      Semantics(
                        button: true,
                        selected: i == page,
                        label: 'Item ${i + 1} of ${items.length}',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _goTo(i, items.length),
                          child: Padding(
                            // A bigger tap area than the dot itself.
                            padding: const EdgeInsets.symmetric(
                                horizontal: 3, vertical: 9),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: i == page ? 16 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: i == page
                                    ? AppColors.primary
                                    : AppColors.gray300,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_wideWindow)
                      IconButton(
                        tooltip: 'Next',
                        visualDensity: VisualDensity.compact,
                        iconSize: 20,
                        color: AppText.primary,
                        disabledColor: AppColors.gray300,
                        onPressed: page < items.length - 1
                            ? () => _goTo(page + 1, items.length)
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InboxAction {
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  const _InboxAction(this.label, this.onPressed, {this.primary = false});
}

class _InboxCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final List<_InboxAction> actions;
  final bool busy;

  /// Buttons on their own row under the text (narrow screens).
  final bool stacked;

  const _InboxCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    this.busy = false,
    this.stacked = false,
  });

  /// A fill dark enough for white button text: the lighter accents
  /// (sky, emerald) are fine for the icon but not behind 14 px text.
  static Color _buttonFill(Color c) {
    if (c == AppColors.sky) return const Color(0xFF0369A1);
    if (c == AppColors.emerald600 || c == AppColors.green) {
      return AppColors.emerald700;
    }
    if (c == AppColors.primary) return AppColors.primaryDark;
    return c;
  }

  Widget _button(_InboxAction a) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: a.primary
          ? FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _buttonFill(color),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: a.onPressed,
              child: Text(a.label),
            )
          : TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: a.onPressed,
              child: Text(a.label),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const spinner = Padding(
      padding: EdgeInsets.all(10),
      child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2)),
    );
    final text = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: AppColors.ink),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
    final iconBadge = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      // Lighter in dark mode so the icon reads on the dark card.
      child: Icon(icon,
          color: AppColors.dark ? Color.lerp(color, Colors.white, 0.45) : color,
          size: 20),
    );

    final Widget body;
    if (stacked && actions.length > 1) {
      body = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              iconBadge,
              const SizedBox(width: 10),
              Expanded(child: text),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (busy) spinner else for (final a in actions) _button(a),
            ],
          ),
        ],
      );
    } else {
      body = Row(
        children: [
          iconBadge,
          const SizedBox(width: 10),
          Expanded(child: text),
          if (busy) spinner else for (final a in actions) _button(a),
        ],
      );
    }

    // A soft tint and edge in the item's own colour, so inbox items read
    // as "something for you" and never blend in with the meal cards.
    final dark = AppColors.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: AppDecor.card.copyWith(
        color: Color.alphaBlend(
            color.withValues(alpha: dark ? 0.16 : 0.07), AppColors.surface),
        border: Border.all(
            color: color.withValues(alpha: dark ? 0.55 : 0.35), width: 1.2),
      ),
      child: body,
    );
  }
}

class _UnreadChat {
  final String id;
  final int count;
  final bool isGroup;
  final String groupName;
  final String? otherId;

  const _UnreadChat({
    required this.id,
    required this.count,
    required this.isGroup,
    required this.groupName,
    required this.otherId,
  });
}
