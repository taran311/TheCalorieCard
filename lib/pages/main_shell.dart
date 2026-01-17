import 'package:flutter/material.dart';
import 'package:namer_app/pages/home_page.dart';
import 'package:namer_app/pages/menu_page.dart';
import 'package:namer_app/pages/recipes_page.dart';

class MainShell extends StatefulWidget {
  final int initialIndex;

  const MainShell({super.key, this.initialIndex = 1});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _currentIndex;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 2);
    _pages = const [
      MenuPage(hideNav: true),
      HomePage(hideNav: true),
      RecipesPage(hideNav: true),
    ];
  }

  void _onTap(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        height: 56,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onTap(0),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: Colors.grey.shade200, width: 1),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.person,
                      size: 24,
                      color: _currentIndex == 0
                          ? const Color(0xFF6366F1)
                          : Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onTap(1),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: Colors.grey.shade200, width: 1),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.credit_card,
                      size: 24,
                      color: _currentIndex == 1
                          ? const Color(0xFF6366F1)
                          : Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onTap(2),
                child: Container(
                  child: Center(
                    child: Icon(
                      Icons.restaurant,
                      size: 24,
                      color: _currentIndex == 2
                          ? const Color(0xFF6366F1)
                          : Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
