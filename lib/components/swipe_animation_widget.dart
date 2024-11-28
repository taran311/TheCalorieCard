import 'package:flutter/material.dart';

class SwipeAnimationWidget extends StatefulWidget {
  final VoidCallback onAnimationComplete;

  const SwipeAnimationWidget({
    Key? key,
    required this.onAnimationComplete,
  }) : super(key: key);

  @override
  _SwipeAnimationWidgetState createState() => _SwipeAnimationWidgetState();
}

class _SwipeAnimationWidgetState extends State<SwipeAnimationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _swipeAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    // Set up the AnimationController with a duration of 3 seconds
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3), // 3-second animation
    );

    // Define the slide-in animation from left to center
    _swipeAnimation = Tween<Offset>(
      begin: Offset(-1.0, 0.0), // Start off-screen on the left
      end: Offset(0.0, 0.0), // Move to the center
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    // Define the fade-in animation
    _opacityAnimation = Tween<double>(
      begin: 0.0, // Fully transparent
      end: 1.0, // Fully visible
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    ));

    // Start the animation immediately
    _controller.forward().whenComplete(() {
      widget.onAnimationComplete(); // Notify when the animation completes
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _swipeAnimation,
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: Align(
          alignment: Alignment
              .center, // Align in the center horizontally and vertically
          child: Container(
            width: 200,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

class CardReaderAnimationWidget extends StatefulWidget {
  final VoidCallback onAnimationComplete;

  const CardReaderAnimationWidget({
    Key? key,
    required this.onAnimationComplete,
  }) : super(key: key);

  @override
  _CardReaderAnimationWidgetState createState() =>
      _CardReaderAnimationWidgetState();
}

class _CardReaderAnimationWidgetState extends State<CardReaderAnimationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // Set up the AnimationController for sliding in from the right
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3), // 3-second animation
    );

    // Define the slide-in animation from right to center
    _slideAnimation = Tween<Offset>(
      begin: Offset(1.0, 0.0), // Off-screen on the right
      end: Offset(0.0, 0.0), // Center
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    // Start the animation immediately
    _controller.forward().whenComplete(() {
      widget.onAnimationComplete(); // Notify when the animation completes
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Align(
        alignment: Alignment.centerRight,
        child: Image.asset(
          'lib/images/card_reader.png',
          width: 200,
          height: 150,
        ),
      ),
    );
  }
}
