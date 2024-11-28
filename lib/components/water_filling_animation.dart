import 'package:flutter/material.dart';

class WaterFillingAnimation extends StatefulWidget {
  final double fillPercentage; // From 0.0 to 1.0 (empty to full)

  const WaterFillingAnimation({Key? key, required this.fillPercentage})
      : super(key: key);

  @override
  State<WaterFillingAnimation> createState() => _WaterFillingAnimationState();
}

class _WaterFillingAnimationState extends State<WaterFillingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    // Initialize AnimationController
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3), // Duration for filling
    );

    // Define the animation
    _animation = Tween<double>(
      begin: 0.0, // Start empty
      end: widget.fillPercentage.clamp(0.0, 1.0), // Clamp to valid range
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    // Start the animation
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant WaterFillingAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Restart the animation if fillPercentage changes
    if (oldWidget.fillPercentage != widget.fillPercentage) {
      _animation = Tween<double>(
        begin: _animation.value,
        end: widget.fillPercentage.clamp(0.0, 1.0), // Clamp to valid range
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ));
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        // Glass Outline
        Container(
          width: 100,
          height: 200,
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.blue,
              width: 4,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        // Water Filling Animation
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Container(
              width: 92, // Slightly smaller than the glass container
              height: 192 * _animation.value, // Fill based on animation value
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.5),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(8),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
