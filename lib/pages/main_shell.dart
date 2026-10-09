import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:namer_app/pages/auth_page.dart';
import 'package:namer_app/pages/friends_page.dart';
import 'package:namer_app/pages/hiscores_page.dart';
import 'package:namer_app/pages/home_page.dart';
import 'package:namer_app/pages/menu_page.dart';
import 'package:namer_app/pages/messages_page.dart';
import 'package:namer_app/pages/recipes_page.dart';
import 'package:namer_app/pages/statement_page.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/today_panel.dart';

/// Top-level destinations of the signed-in app.
enum ShellTab { card, recipes, friends, hiscores, statement, chat, profile }

class _TabSpec {
  final ShellTab tab;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool onPhone;

  const _TabSpec(
    this.tab,
    this.label,
    this.icon,
    this.selectedIcon, {
    this.onPhone = true,
  });
}

const _tabs = <_TabSpec>[
  _TabSpec(ShellTab.card, 'Card', Icons.credit_card_outlined,
      Icons.credit_card),
  _TabSpec(ShellTab.recipes, 'Recipes', Icons.restaurant_outlined,
      Icons.restaurant),
  _TabSpec(ShellTab.friends, 'Friends', Icons.people_outline, Icons.people),
  _TabSpec(ShellTab.hiscores, 'Hiscores', Icons.emoji_events_outlined,
      Icons.emoji_events,
      onPhone: false),
  _TabSpec(ShellTab.statement, 'Statement', Icons.receipt_long_outlined,
      Icons.receipt_long,
      onPhone: false),
  _TabSpec(ShellTab.chat, 'Chat', Icons.chat_bubble_outline,
      Icons.chat_bubble),
  _TabSpec(ShellTab.profile, 'Profile', Icons.person_outline, Icons.person),
];

/// Signed-in layout.
///
/// * Phone: page + bottom navigation bar (Card, Recipes, Friends, Chat,
///   Profile). Hiscores lives inside Friends, Statement inside Profile.
/// * Tablet / desktop: navigation sidebar, the page in a centred column and,
///   on wide screens, a live "Today" panel on the right.
///
/// Every tab has its own navigator, so opening a page (a chat, settings, a
/// friend's card) keeps the sidebar or bottom bar in place.
class MainShell extends StatefulWidget {
  /// Legacy index kept for existing callers:
  /// 0 = profile, 1 = card, 2 = recipes, 3 = chat.
  final int initialIndex;

  const MainShell({super.key, this.initialIndex = 1});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late ShellTab _current;
  final Set<ShellTab> _visited = {};
  final Map<ShellTab, GlobalKey<NavigatorState>> _navKeys = {
    for (final t in ShellTab.values) t: GlobalKey<NavigatorState>(),
  };

  @override
  void initState() {
    super.initState();
    // Wake the lookup server early (it sleeps when idle).
    ProxyClient.warmUp();
    _current = switch (widget.initialIndex) {
      0 => ShellTab.profile,
      2 => ShellTab.recipes,
      3 => ShellTab.chat,
      _ => ShellTab.card,
    };
    _visited.add(_current);
    // Tell the outer frame a shell is on screen. Done after the frame:
    // ancestors can't be rebuilt while this widget is mounting/unmounting.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ShellPresence.mounted.value = ShellPresence.mounted.value + 1;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final next = ShellPresence.mounted.value - 1;
      ShellPresence.mounted.value = next < 0 ? 0 : next;
    });
    super.dispose();
  }

  void _select(ShellTab tab) {
    if (tab == _current) {
      // Tapping the active tab again returns to its first page.
      _navKeys[tab]?.currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() {
      _current = tab;
      _visited.add(tab);
    });
  }

  Widget _rootPageFor(ShellTab tab) {
    switch (tab) {
      case ShellTab.card:
        return const HomePage();
      case ShellTab.recipes:
        return const RecipesPage();
      case ShellTab.friends:
        return const FriendsPage();
      case ShellTab.hiscores:
        return const HiscoresPage();
      case ShellTab.statement:
        return const StatementPage();
      case ShellTab.chat:
        return const MessagesPage();
      case ShellTab.profile:
        return MenuPage(
          onOpenStatement: () => _openFromProfile(const StatementPage()),
          onOpenHiscores: () => _openFromProfile(const HiscoresPage()),
        );
    }
  }

  void _openFromProfile(Widget page) {
    _navKeys[ShellTab.profile]
        ?.currentState
        ?.push(MaterialPageRoute(builder: (_) => page));
  }

  Widget _buildTabNavigator(ShellTab tab) {
    if (!_visited.contains(tab)) return const SizedBox.shrink();
    return HeroControllerScope.none(
      child: Navigator(
        key: _navKeys[tab],
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: settings,
          builder: (_) => _rootPageFor(tab),
        ),
      ),
    );
  }

  Widget _buildPages() {
    final children = [for (final t in ShellTab.values) _buildTabNavigator(t)];
    return NavigatorPopHandler(
      onPopWithResult: (_) => _navKeys[_current]?.currentState?.maybePop(),
      child: IndexedStack(
        index: ShellTab.values.indexOf(_current),
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final width = MediaQuery.sizeOf(context).width;

    return _BadgeCounts(
      userId: uid,
      builder: (context, pendingRequests, unreadMessages) {
        int badgeFor(ShellTab t) => switch (t) {
              ShellTab.friends => pendingRequests,
              ShellTab.chat => unreadMessages,
              _ => 0,
            };

        if (width < Breakpoints.tablet) {
          return _PhoneLayout(
            current: _current,
            badgeFor: badgeFor,
            onSelect: _select,
            body: _buildPages(),
          );
        }

        return _DesktopLayout(
          current: _current,
          badgeFor: badgeFor,
          onSelect: _select,
          extended: width >= Breakpoints.desktop,
          showTodayPanel: width >= Breakpoints.wide,
          userId: uid,
          body: _buildPages(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Phone
// ---------------------------------------------------------------------------

class _PhoneLayout extends StatelessWidget {
  final ShellTab current;
  final int Function(ShellTab) badgeFor;
  final ValueChanged<ShellTab> onSelect;
  final Widget body;

  const _PhoneLayout({
    required this.current,
    required this.badgeFor,
    required this.onSelect,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final phoneTabs = _tabs.where((t) => t.onPhone).toList();
    // Desktop-only tabs highlight the phone tab that contains them.
    final highlighted = switch (current) {
      ShellTab.hiscores => ShellTab.friends,
      ShellTab.statement => ShellTab.profile,
      _ => current,
    };
    final found = phoneTabs.indexWhere((t) => t.tab == highlighted);
    final selectedIndex = found < 0 ? 0 : found;

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        height: 64,
        selectedIndex: selectedIndex,
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => onSelect(phoneTabs[i].tab),
        destinations: [
          for (final t in phoneTabs)
            NavigationDestination(
              icon: _BadgedIcon(icon: t.icon, count: badgeFor(t.tab)),
              selectedIcon: _BadgedIcon(
                icon: t.selectedIcon,
                count: badgeFor(t.tab),
                color: AppColors.primary,
              ),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tablet / desktop
// ---------------------------------------------------------------------------

class _DesktopLayout extends StatelessWidget {
  final ShellTab current;
  final int Function(ShellTab) badgeFor;
  final ValueChanged<ShellTab> onSelect;
  final bool extended;
  final bool showTodayPanel;
  final String userId;
  final Widget body;

  const _DesktopLayout({
    required this.current,
    required this.badgeFor,
    required this.onSelect,
    required this.extended,
    required this.showTodayPanel,
    required this.userId,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(
            current: current,
            badgeFor: badgeFor,
            onSelect: onSelect,
            extended: extended,
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: Breakpoints.contentMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 20),
                  child: Material(
                    color: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: LocalMediaQuery(child: body),
                  ),
                ),
              ),
            ),
          ),
          if (showTodayPanel)
            SizedBox(
              width: 360,
              child: TodayPanel(
                userId: userId,
                onOpenStatement: () => onSelect(ShellTab.statement),
              ),
            ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final ShellTab current;
  final int Function(ShellTab) badgeFor;
  final ValueChanged<ShellTab> onSelect;
  final bool extended;

  const _Sidebar({
    required this.current,
    required this.badgeFor,
    required this.onSelect,
    required this.extended,
  });

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final name = email.contains('@') ? email.split('@').first : email;

    return Container(
      width: extended ? 248 : 84,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(extended ? 20 : 0, 24, 12, 24),
            child: Row(
              mainAxisAlignment:
                  extended ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.credit_card,
                      color: Colors.white, size: 22),
                ),
                if (extended) ...[
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'The Calorie Card',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final t in _tabs)
                  _SidebarItem(
                    spec: t,
                    selected: t.tab == current,
                    badge: badgeFor(t.tab),
                    extended: extended,
                    onTap: () => onSelect(t.tab),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment:
                  extended ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: Text(
                    name.isEmpty ? '?' : name[0].toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (extended) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sign out',
                    icon: const Icon(Icons.logout, size: 20),
                    color: AppColors.muted,
                    onPressed: () => _logout(context),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final _TabSpec spec;
  final bool selected;
  final int badge;
  final bool extended;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.spec,
    required this.selected,
    required this.badge,
    required this.extended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.muted;
    final icon = _BadgedIcon(
      icon: selected ? spec.selectedIcon : spec.icon,
      count: badge,
      color: color,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: extended ? '' : spec.label,
        child: Material(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              height: 46,
              child: extended
                  ? Row(
                      children: [
                        const SizedBox(width: 14),
                        icon,
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            spec.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected ? AppColors.ink : AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(child: icon),
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgedIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color? color;

  const _BadgedIcon({required this.icon, required this.count, this.color});

  @override
  Widget build(BuildContext context) {
    final i = Icon(icon, color: color, size: 23);
    if (count <= 0) return i;
    return Badge(
      label: Text(count > 99 ? '99+' : '$count'),
      backgroundColor: AppColors.red,
      child: i,
    );
  }
}

/// Listens for pending friend requests and unread chat messages.
class _BadgeCounts extends StatefulWidget {
  final String userId;
  final Widget Function(BuildContext, int pendingRequests, int unread)
      builder;

  const _BadgeCounts({required this.userId, required this.builder});

  @override
  State<_BadgeCounts> createState() => _BadgeCountsState();
}

class _BadgeCountsState extends State<_BadgeCounts> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _requests;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _conversations;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _BadgeCounts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _subscribe();
  }

  void _subscribe() {
    final db = FirebaseFirestore.instance;
    _requests = db
        .collection('friend_requests')
        .where('to_user_id', isEqualTo: widget.userId)
        .where('status', isEqualTo: 'pending')
        .snapshots();
    _conversations = db
        .collection('conversations')
        .where('participant_ids', arrayContains: widget.userId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _requests,
      builder: (context, requests) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _conversations,
          builder: (context, convos) {
            var unread = 0;
            final docs = convos.data?.docs ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            for (final doc in docs) {
              final map = doc.data()['unread_count'];
              if (map is Map) {
                final v = map[widget.userId];
                if (v is num) unread += v.toInt();
              }
            }
            return widget.builder(
                context, requests.data?.docs.length ?? 0, unread);
          },
        );
      },
    );
  }
}
